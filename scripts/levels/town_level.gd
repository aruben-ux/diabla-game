extends Node3D

## Town level controller. Safe hub area where the player spawns.
## Contains buildings (future shops/vendors), quest givers, and
## stairs leading down to the dungeon.

signal level_ready(spawn_position: Vector3)
signal enter_dungeon(body: Node3D)

@onready var generator = $TownGenerator

var spawn_position := Vector3.ZERO
var stairs_position := Vector3.ZERO
var _stairs_area: Node3D
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
	# Clickable stairs — StaticBody3D with interactable layer
	var body := StaticBody3D.new()
	body.collision_layer = 128  # Layer 8 = interactable
	body.collision_mask = 0
	body.name = "StairsTrigger"
	body.add_to_group("interactables")
	body.set_meta("display_name", tr("Dungeon Entrance"))
	body.set_meta("interact_hint", tr("Click to enter dungeon"))
	body.set_meta("_town_level", self)
	body.set_script(_stairs_interact_script())
	body.position = stairs_position
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 4.0)
	col.shape = box
	col.position = Vector3(0, 1.0, 1.5)
	body.add_child(col)
	_stairs_area = body

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
	label.text = tr("Enter Dungeon")
	label.position = stairs_position + Vector3(0, 3.8, 0)
	label.pixel_size = 0.012
	label.font_size = 40
	label.modulate = Color(0.7, 0.85, 1.0)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _on_stairs_body_entered(_body: Node3D) -> void:
	pass  # Kept for compatibility, no longer used


func _stairs_interact_script() -> GDScript:
	## Returns a tiny inline script that makes the stairs interactable.
	var src := """extends StaticBody3D
var display_name: String = ""
var interact_hint: String = ""
func _ready() -> void:
	display_name = get_meta("display_name") if has_meta("display_name") else tr("Dungeon Entrance")
	interact_hint = get_meta("interact_hint") if has_meta("interact_hint") else tr("Click to enter dungeon")
func interact(player: Node) -> void:
	if not player or not is_instance_valid(player):
		return
	var town_lvl = get_meta("_town_level")
	if town_lvl and is_instance_valid(town_lvl):
		town_lvl.enter_dungeon.emit(player)
"""
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	return script


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
