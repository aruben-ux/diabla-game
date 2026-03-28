extends Camera3D

## Isometric-style camera that follows a target node.
## Positioned at a fixed angle looking down at the player.

@export var target: Node3D
@export var offset := Vector3(-8, 12, 8)
@export var follow_speed := 12.0
@export var zoom_speed := 2.0
@export var min_zoom := 0.6
@export var max_zoom := 1.4

var zoom_level := 1.0
var _shake_intensity := 0.0
var _shake_timer := 0.0


func _ready() -> void:
	pass


func snap_to_target() -> void:
	## Instantly position the camera at the correct offset — no lerp.
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
		_shake_intensity *= 0.85  # Decay


func shake(intensity: float = 0.15, duration: float = 0.15) -> void:
	_shake_intensity = intensity
	_shake_timer = duration


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clampf(zoom_level - zoom_speed * 0.1, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clampf(zoom_level + zoom_speed * 0.1, min_zoom, max_zoom)
