extends Node3D

## Town portal: a glowing blue 3D oval with a live camera preview of the
## destination rendered via SubViewport. Created by a player in the dungeon;
## matching exit portal appears in town. When the creator enters the town-side
## portal, both portals are destroyed.

var owner_peer_id: int = 0
var source_floor: int = 0
var source_position := Vector3.ZERO
var is_town_side := false
var destination_pos := Vector3.ZERO  # Where the other end is (world-space)
var owner_name: String = "Player"
var portal_color := Color(0.3, 0.5, 0.85)

## Interactable interface
var display_name: String = "Town Portal"
var interact_hint: String = "Click to enter portal"

var _time := 0.0
var _viewport: SubViewport
var _cam: Camera3D
var _portal_surface: MeshInstance3D
var _frame_ring: Node3D
var _ground_light: OmniLight3D
var _sparks: Array[MeshInstance3D] = []
var _label: Label3D

const PORTAL_WIDTH := 1.4
const PORTAL_HEIGHT := 2.6
const FRAME_SEGMENTS := 32
const FRAME_THICKNESS := 0.08
const SPARK_COUNT := 16

## Visibility layer for portal meshes — layers 1+2 so always visible to the main
## camera, but the SubViewport camera (cull_mask=1) won't render them.
const PORTAL_VIS_LAYER := 3  # 1 | 2

## Derived colors computed from portal_color in _ready
var _base_color: Color
var _light_color: Color
var _white_color: Color


func _ready() -> void:
	_base_color = portal_color
	_light_color = portal_color.lightened(0.35)
	_white_color = portal_color.lightened(0.6)
	add_to_group("interactables")
	_build_subviewport()
	_build_portal_surface()
	_build_frame()
	_build_ground_glow()
	_build_ground_light()
	_build_sparks()
	_build_collision()
	_build_label()


# ── SubViewport + Camera that looks at the destination ──

func _build_subviewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 256)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.name = "PortalViewport"
	add_child(_viewport)

	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.cull_mask = 1  # Only render layer 1 — excludes portal meshes
	_cam.name = "PortalCam"
	_viewport.add_child(_cam)
	_position_camera()


func _position_camera() -> void:
	# Place camera at destination looking at it from ~10 units at the isometric angle
	var look_at_pos := destination_pos + Vector3(0, 1.0, 0)
	_cam.global_position = destination_pos + Vector3(6, 8, 6)
	_cam.look_at(look_at_pos)


# ── Portal surface: oval quad showing the live viewport texture ──

func _build_portal_surface() -> void:
	# Create an oval by using a PlaneMesh and masking with vertex shader?
	# Simpler: build a procedural oval mesh via SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 48
	var half_w := PORTAL_WIDTH * 0.5
	var half_h := PORTAL_HEIGHT * 0.5
	var center_y := PORTAL_HEIGHT * 0.5 + 0.1

	# Fan of triangles from center
	for i in segments:
		var a0 := float(i) / segments * TAU
		var a1 := float(i + 1) / segments * TAU

		# Center vertex
		st.set_uv(Vector2(0.5, 0.5))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(0, center_y, 0))

		# Edge vertex i
		var x0 := cos(a0) * half_w
		var y0 := sin(a0) * half_h + center_y
		st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 - sin(a0) * 0.5))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(x0, y0, 0))

		# Edge vertex i+1
		var x1 := cos(a1) * half_w
		var y1 := sin(a1) * half_h + center_y
		st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 - sin(a1) * 0.5))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(x1, y1, 0))

	var mesh := st.commit()

	_portal_surface = MeshInstance3D.new()
	_portal_surface.mesh = mesh
	_portal_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_portal_surface.layers = PORTAL_VIS_LAYER
	_portal_surface.name = "PortalSurface"

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.emission_enabled = true
	mat.emission = _base_color
	mat.emission_energy_multiplier = 1.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_portal_surface.material_override = mat
	add_child(_portal_surface)

	# Back face (same mesh mirrored) so portal looks good from both sides
	var back := MeshInstance3D.new()
	back.mesh = mesh
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.layers = PORTAL_VIS_LAYER
	back.scale.z = -1.0
	back.name = "PortalSurfaceBack"
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_texture = _viewport.get_texture()
	back_mat.emission_enabled = true
	back_mat.emission = _base_color
	back_mat.emission_energy_multiplier = 1.2
	back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.material_override = back_mat
	add_child(back)


# ── 3D frame: torus of small cylinders around the oval edge ──

func _build_frame() -> void:
	_frame_ring = Node3D.new()
	_frame_ring.name = "Frame"
	add_child(_frame_ring)

	var half_w := PORTAL_WIDTH * 0.5 + FRAME_THICKNESS
	var half_h := PORTAL_HEIGHT * 0.5 + FRAME_THICKNESS
	var center_y := PORTAL_HEIGHT * 0.5 + 0.1

	for i in FRAME_SEGMENTS:
		var angle := float(i) / FRAME_SEGMENTS * TAU
		var next_angle := float(i + 1) / FRAME_SEGMENTS * TAU

		var x := cos(angle) * half_w
		var y := sin(angle) * half_h + center_y

		var nx := cos(next_angle) * half_w
		var ny := sin(next_angle) * half_h + center_y

		# Small sphere at each point for a beaded frame look
		var bead := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = FRAME_THICKNESS
		sphere.height = FRAME_THICKNESS * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		bead.mesh = sphere
		bead.position = Vector3(x, y, 0)
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bead.layers = PORTAL_VIS_LAYER

		var mat := StandardMaterial3D.new()
		mat.albedo_color = _light_color
		mat.emission_enabled = true
		mat.emission = _light_color
		mat.emission_energy_multiplier = 3.0
		mat.metallic = 0.8
		mat.roughness = 0.2
		bead.material_override = mat
		_frame_ring.add_child(bead)


# ── Ground glow: flat circle on the floor ──

func _build_ground_glow() -> void:
	var glow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = PORTAL_WIDTH * 0.8
	disc.bottom_radius = PORTAL_WIDTH * 0.8
	disc.height = 0.02
	disc.radial_segments = 24
	disc.rings = 1
	glow.mesh = disc
	glow.position.y = 0.02
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.layers = PORTAL_VIS_LAYER
	glow.name = "GroundGlow"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(_base_color.r, _base_color.g, _base_color.b, 0.4)
	mat.emission_enabled = true
	mat.emission = _base_color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.material_override = mat
	add_child(glow)


# ── OmniLight for ambient blue glow ──

func _build_ground_light() -> void:
	_ground_light = OmniLight3D.new()
	_ground_light.light_color = _light_color
	_ground_light.light_energy = 2.0
	_ground_light.omni_range = 5.0
	_ground_light.omni_attenuation = 1.5
	_ground_light.position.y = PORTAL_HEIGHT * 0.5
	_ground_light.shadow_enabled = false
	_ground_light.name = "PortalLight"
	add_child(_ground_light)


# ── Floating spark particles (small glowing spheres that drift upward) ──

func _build_sparks() -> void:
	for i in SPARK_COUNT:
		var spark := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		sphere.height = 0.08
		sphere.radial_segments = 6
		sphere.rings = 3
		spark.mesh = sphere
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.layers = PORTAL_VIS_LAYER
		spark.name = "Spark_%d" % i

		var mat := StandardMaterial3D.new()
		mat.albedo_color = _white_color
		mat.emission_enabled = true
		mat.emission = _white_color
		mat.emission_energy_multiplier = 5.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = mat
		add_child(spark)
		_sparks.append(spark)


# ── Collision body for click interaction ──

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 128  # Layer 8 = interactable
	body.collision_mask = 0
	body.name = "PortalBody"
	add_child(body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(PORTAL_WIDTH, PORTAL_HEIGHT, 1.2)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = PORTAL_HEIGHT * 0.5 + 0.1
	body.add_child(col)


func interact(player: Node) -> void:
	if not player or not is_instance_valid(player):
		return
	if not multiplayer.is_server():
		return
	var peer_id := player.get_multiplayer_authority()
	var main_game := _get_main_game()
	if not main_game:
		return
	main_game.use_town_portal(peer_id, self)


func _build_label() -> void:
	_label = Label3D.new()
	var dest_text := "Town" if not is_town_side else "Floor %d" % source_floor
	_label.text = "%s's Portal\n→ %s" % [owner_name, dest_text]
	display_name = "%s's Portal → %s" % [owner_name, dest_text]
	interact_hint = "Click to enter"
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.position.y = PORTAL_HEIGHT + 0.4
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(1, 1, 1, 0.9)
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.layers = PORTAL_VIS_LAYER
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.name = "PortalLabel"
	add_child(_label)


# ── Animation ──

func _process(delta: float) -> void:
	_time += delta

	# Billboard: rotate portal to face the main camera
	var camera := get_viewport().get_camera_3d()
	if camera:
		var cam_pos := camera.global_position
		var my_pos := global_position
		var dir := Vector3(cam_pos.x - my_pos.x, 0.0, cam_pos.z - my_pos.z).normalized()
		if dir.length_squared() > 0.001:
			rotation.y = atan2(dir.x, dir.z)

	# Pulse portal surface
	if _portal_surface:
		var pulse := 0.97 + sin(_time * 2.5) * 0.03
		_portal_surface.scale = Vector3(pulse, pulse, 1.0)

	# Rotate frame beads gently around the oval path
	if _frame_ring:
		var half_w := PORTAL_WIDTH * 0.5 + FRAME_THICKNESS
		var half_h := PORTAL_HEIGHT * 0.5 + FRAME_THICKNESS
		var center_y := PORTAL_HEIGHT * 0.5 + 0.1
		var offset := _time * 0.3  # Slow rotation
		var idx := 0
		for child in _frame_ring.get_children():
			var angle := float(idx) / FRAME_SEGMENTS * TAU + offset
			var x := cos(angle) * half_w
			var y := sin(angle) * half_h + center_y
			child.position = Vector3(x, y, 0)
			# Pulsing brightness per bead
			var brightness := 2.5 + sin(_time * 4.0 + float(idx) * 0.5) * 1.0
			if child.material_override:
				child.material_override.emission_energy_multiplier = brightness
			idx += 1

	# Animate sparks — each floats on a unique orbit
	for i in _sparks.size():
		var spark: MeshInstance3D = _sparks[i]
		var seed_f := float(i) * 1.618  # Golden ratio offset
		var orbit_speed := 0.8 + fmod(seed_f, 0.6)
		var angle := _time * orbit_speed + seed_f * TAU
		var radius := PORTAL_WIDTH * 0.35 + sin(_time * 1.3 + seed_f) * 0.2
		var height_offset := fmod((_time * 0.5 + seed_f) * 0.7, PORTAL_HEIGHT)
		var x := cos(angle) * radius
		var z := sin(angle) * 0.15  # Slight depth wobble
		spark.position = Vector3(x, height_offset + 0.1, z)
		# Fade sparks near top and bottom
		var fade: float = 1.0 - absf(height_offset / PORTAL_HEIGHT - 0.5) * 2.0
		fade = clampf(fade, 0.1, 1.0)
		if spark.material_override:
			spark.material_override.albedo_color.a = fade * 0.8

	# Pulse ground light
	if _ground_light:
		_ground_light.light_energy = 1.5 + sin(_time * 2.0) * 0.5

	# Ground glow pulsing
	var glow := get_node_or_null("GroundGlow") as MeshInstance3D
	if glow and glow.material_override:
		glow.material_override.albedo_color.a = 0.3 + sin(_time * 1.5) * 0.1


func _get_main_game() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("use_town_portal"):
			return node
		node = node.get_parent()
	return null
