extends Node3D

## Town portal: a blue shimmering oval that teleports players.
## Created by a player in the dungeon; matching exit portal in town.
## When the creator enters the town-side portal, both portals are destroyed.

var owner_peer_id: int = 0
var source_floor: int = 0
var source_position := Vector3.ZERO  # Position of the dungeon-side portal
var is_town_side := false             # true = this is the exit portal in town

var _area: Area3D
var _mesh: MeshInstance3D
var _time := 0.0

const PORTAL_COLOR := Color(0.15, 0.35, 1.0, 0.8)
const PORTAL_INNER := Color(0.4, 0.6, 1.0, 0.5)
const PORTAL_WIDTH := 1.2
const PORTAL_HEIGHT := 2.4


func _ready() -> void:
	_build_visual()
	_build_collision()


func _build_visual() -> void:
	# Outer oval ring - a torus-like shape using two ovals
	# Use a QuadMesh for the portal surface (flat oval)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(PORTAL_WIDTH, PORTAL_HEIGHT)

	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.position.y = PORTAL_HEIGHT * 0.5 + 0.1
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.albedo_color = PORTAL_COLOR
	mat.emission_enabled = true
	mat.emission = PORTAL_COLOR
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_mesh.material_override = mat
	add_child(_mesh)

	# Inner glow - slightly smaller, brighter
	var inner_mesh := QuadMesh.new()
	inner_mesh.size = Vector2(PORTAL_WIDTH * 0.7, PORTAL_HEIGHT * 0.7)
	var inner := MeshInstance3D.new()
	inner.mesh = inner_mesh
	inner.position.y = PORTAL_HEIGHT * 0.5 + 0.1
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = PORTAL_INNER
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(0.5, 0.7, 1.0)
	inner_mat.emission_energy_multiplier = 3.0
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	inner_mat.no_depth_test = true
	inner.material_override = inner_mat
	inner.name = "InnerGlow"
	add_child(inner)

	# Portal frame - ring of particles via small spheres around the oval edge
	_build_frame_dots()


func _build_frame_dots() -> void:
	var dot_count := 24
	for i in dot_count:
		var angle := float(i) / dot_count * TAU
		var x := cos(angle) * PORTAL_WIDTH * 0.5
		var y := sin(angle) * PORTAL_HEIGHT * 0.5 + PORTAL_HEIGHT * 0.5 + 0.1
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		sphere.radial_segments = 6
		sphere.rings = 3
		dot.mesh = sphere
		dot.position = Vector3(x, y, 0)
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.8, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.8, 1.0)
		mat.emission_energy_multiplier = 4.0
		dot.material_override = mat
		dot.name = "FrameDot_%d" % i
		add_child(dot)


func _build_collision() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2  # Detect players (layer 2)
	_area.name = "PortalArea"
	add_child(_area)

	var shape := BoxShape3D.new()
	shape.size = Vector3(PORTAL_WIDTH, PORTAL_HEIGHT, 1.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = PORTAL_HEIGHT * 0.5 + 0.1
	_area.add_child(col)

	_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return
	# Only the server processes portal travel
	if not multiplayer.is_server():
		return
	var peer_id := body.get_multiplayer_authority()
	var main_game := _get_main_game()
	if not main_game:
		return
	main_game.use_town_portal(peer_id, self)


func _process(delta: float) -> void:
	_time += delta
	# Gentle pulsing and rotation for the portal surface
	if _mesh:
		var pulse := 0.9 + sin(_time * 3.0) * 0.1
		_mesh.scale = Vector3(pulse, pulse, 1.0)
	var inner := get_node_or_null("InnerGlow") as MeshInstance3D
	if inner:
		var inner_pulse := 0.85 + sin(_time * 4.0 + 1.0) * 0.15
		inner.scale = Vector3(inner_pulse, inner_pulse, 1.0)
	# Rotate frame dots subtly
	for i in 24:
		var dot := get_node_or_null("FrameDot_%d" % i) as MeshInstance3D
		if dot:
			var base_angle := float(i) / 24.0 * TAU + _time * 0.5
			var x := cos(base_angle) * PORTAL_WIDTH * 0.5
			var y := sin(base_angle) * PORTAL_HEIGHT * 0.5 + PORTAL_HEIGHT * 0.5 + 0.1
			dot.position = Vector3(x, y, 0)


func _get_main_game() -> Node:
	## Walk up the tree to find the main_game node.
	var node := get_parent()
	while node:
		if node.has_method("use_town_portal"):
			return node
		node = node.get_parent()
	return null
