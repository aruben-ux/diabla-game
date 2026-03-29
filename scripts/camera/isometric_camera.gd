extends Camera3D

## Isometric-style camera that follows a target node.
## Positioned at a fixed angle looking down at the player.
## Handles building occlusion — hides roofs when player is inside,
## and fades walls near the camera-to-player line via shader.

@export var target: Node3D
@export var offset := Vector3(-8, 12, 8)
@export var follow_speed := 12.0
@export var zoom_speed := 2.0
@export var min_zoom := 0.6
@export var max_zoom := 1.4

var zoom_level := 1.0
var _shake_intensity := 0.0
var _shake_timer := 0.0

# Occlusion state
var _hidden_roofs: Array[MeshInstance3D] = []
var _occludable_meshes: Array[MeshInstance3D] = []
var _occludable_ready := false


func _ready() -> void:
	pass


func snap_to_target() -> void:
	if not target:
		return
	var height := 12.0 * zoom_level
	var ground_dist := 7.0 * zoom_level
	var cam_offset := Vector3(ground_dist, height, ground_dist)
	global_position = target.global_position + cam_offset
	look_at(target.global_position + Vector3(0, 1, 0), Vector3.UP)


func _process(delta: float) -> void:
	if not target:
		return

	var height := 12.0 * zoom_level
	var ground_dist := 7.0 * zoom_level
	var cam_offset := Vector3(ground_dist, height, ground_dist)
	var desired_position := target.global_position + cam_offset

	# Snap instantly if the target jumped far (floor transition / teleport)
	var dist_sq := global_position.distance_squared_to(desired_position)
	if dist_sq > 400.0:  # > 20 units away
		global_position = desired_position
	else:
		global_position = global_position.lerp(desired_position, follow_speed * delta)

	look_at(target.global_position + Vector3(0, 1, 0), Vector3.UP)

	# Screen shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var shake_offset := Vector3(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity),
			0.0
		)
		global_position += shake_offset
		_shake_intensity *= 0.85

	# Building occlusion
	_update_occlusion()


func shake(intensity: float = 0.15, duration: float = 0.15) -> void:
	_shake_intensity = intensity
	_shake_timer = duration


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clampf(zoom_level - zoom_speed * 0.1, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clampf(zoom_level + zoom_speed * 0.1, min_zoom, max_zoom)


# --- Building Occlusion ---

func _gather_occludable_meshes() -> void:
	_occludable_meshes.clear()
	for node in get_tree().get_nodes_in_group("occludable"):
		if node is MeshInstance3D:
			_occludable_meshes.append(node)
	_occludable_ready = true


func _update_occlusion() -> void:
	if not target:
		return

	var player_pos := target.global_position

	# 1) Hide roofs when player is inside
	_update_roof_visibility(player_pos)

	# 2) Update wall occlusion shader with camera-to-player line
	_update_wall_shader(player_pos)


func _update_roof_visibility(player_pos: Vector3) -> void:
	for roof in _hidden_roofs:
		if is_instance_valid(roof):
			roof.visible = true
	_hidden_roofs.clear()

	var roofs := get_tree().get_nodes_in_group("building_roofs")
	for node in roofs:
		var roof := node as MeshInstance3D
		if not roof or not roof.has_meta("building_min"):
			continue
		var bmin: Vector3 = roof.get_meta("building_min")
		var bmax: Vector3 = roof.get_meta("building_max")
		if player_pos.x >= bmin.x and player_pos.x <= bmax.x and player_pos.z >= bmin.z and player_pos.z <= bmax.z:
			roof.visible = false
			_hidden_roofs.append(roof)


func _update_wall_shader(player_pos: Vector3) -> void:
	if not _occludable_ready:
		_gather_occludable_meshes()

	var cam_pos := global_position

	for mi in _occludable_meshes:
		if not is_instance_valid(mi):
			continue
		var mat := mi.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("camera_pos", cam_pos)
			mat.set_shader_parameter("player_pos", player_pos)
