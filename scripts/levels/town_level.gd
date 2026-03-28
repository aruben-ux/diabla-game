extends Node3D

## Town level controller. Safe hub area where the player spawns.
## Contains buildings (future shops/vendors), quest givers, and
## stairs leading down to the dungeon.

signal level_ready(spawn_position: Vector3)
signal enter_dungeon(body: Node3D)

@onready var generator = $TownGenerator

var spawn_position := Vector3.ZERO
var stairs_position := Vector3.ZERO
var _stairs_area: Area3D
var sun: DirectionalLight3D


func _ready() -> void:
	generator.town_generated.connect(_on_town_generated)
	generator.generate.call_deferred()


func _on_town_generated(spawn_pos: Vector3, stairs_pos: Vector3) -> void:
	spawn_position = spawn_pos
	stairs_position = stairs_pos

	# Create trigger area at the dungeon stairs
	_create_stairs_trigger()

	# Ambient skylight
	_setup_environment()

	level_ready.emit(spawn_position)


func _create_stairs_trigger() -> void:
	_stairs_area = Area3D.new()
	_stairs_area.collision_layer = 0
	_stairs_area.collision_mask = 6  # Player (2) + Enemy (4) layers — we only care about player
	_stairs_area.name = "StairsTrigger"
	add_child(_stairs_area)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 4.0)
	col.shape = box
	col.position = stairs_position + Vector3(0, 1.0, 1.5)
	_stairs_area.add_child(col)

	_stairs_area.body_entered.connect(_on_stairs_body_entered)

	# Visual marker — glowing portal frame
	var frame := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 2.0
	torus.rings = 16
	torus.ring_segments = 16
	frame.mesh = torus
	frame.position = stairs_position + Vector3(0, 2.0, 0)
	frame.rotation.x = PI * 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.4, 1.0)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frame.material_override = mat
	add_child(frame)

	# "Enter Dungeon" label
	var label := Label3D.new()
	label.text = "Enter Dungeon"
	label.position = stairs_position + Vector3(0, 3.8, 0)
	label.pixel_size = 0.012
	label.font_size = 40
	label.modulate = Color(0.7, 0.85, 1.0)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _on_stairs_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		enter_dungeon.emit(body)


func _setup_environment() -> void:
	# Warm directional sunlight — angled down from above like afternoon sun
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)  # 55° down from horizon, rotated 30° around Y
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	add_child(sun)


func get_town_grid() -> Array:
	return generator.grid


func get_grid_dimensions() -> Vector2i:
	return Vector2i(generator.TOWN_WIDTH, generator.TOWN_HEIGHT)


func get_tile_size() -> float:
	return generator.TILE_SIZE
