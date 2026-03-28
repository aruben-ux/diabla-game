extends Camera3D

## Isometric-style camera that follows a target node.
## Positioned at a fixed angle looking down at the player.
## Handles building occlusion — hides roofs when player is inside,
## and fades walls/geometry between camera and player.

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
var _faded_geometry: Dictionary = {}  # MeshInstance3D -> original material
const FADE_ALPHA := 0.2


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

func _update_occlusion() -> void:
	if not target:
		return

	var player_pos := target.global_position

	# 1) Hide roofs when player is inside the building
	_update_roof_visibility(player_pos)

	# 2) Fade geometry between camera and player
	_update_wall_transparency(player_pos)


func _update_roof_visibility(player_pos: Vector3) -> void:
	# Restore previously hidden roofs
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
		# Check if player is within X/Z bounds of this building
		if player_pos.x >= bmin.x and player_pos.x <= bmax.x and player_pos.z >= bmin.z and player_pos.z <= bmax.z:
			roof.visible = false
			_hidden_roofs.append(roof)


func _update_wall_transparency(player_pos: Vector3) -> void:
	var cam_pos := global_position
	var to_player := player_pos - cam_pos
	var ray_len := to_player.length()
	if ray_len < 0.1:
		return
	var ray_dir := to_player / ray_len

	# Find geometry nodes whose AABB the camera-to-player ray passes through
	var currently_occluding: Array[MeshInstance3D] = []
	var all_geometry := get_tree().get_nodes_in_group("building_geometry")

	for node in all_geometry:
		var mi := node as MeshInstance3D
		if not mi or not mi.visible:
			continue
		var aabb := mi.get_aabb()
		var global_aabb := AABB(aabb.position + mi.global_position, aabb.size)
		# Expand slightly for better detection
		global_aabb = global_aabb.grow(0.5)
		if _ray_intersects_aabb(cam_pos, ray_dir, ray_len, global_aabb):
			currently_occluding.append(mi)

	# Restore geometry that is no longer occluding
	var to_restore: Array[MeshInstance3D] = []
	for mi in _faded_geometry:
		if not currently_occluding.has(mi):
			to_restore.append(mi)

	for mi in to_restore:
		if is_instance_valid(mi):
			mi.material_override = _faded_geometry[mi]
		_faded_geometry.erase(mi)

	# Fade newly occluding geometry
	for mi in currently_occluding:
		if _faded_geometry.has(mi):
			continue  # Already faded
		# Store original material and apply transparent copy
		var orig_mat: Material = mi.material_override
		_faded_geometry[mi] = orig_mat
		if orig_mat is StandardMaterial3D:
			var fade_mat: StandardMaterial3D = orig_mat.duplicate()
			fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fade_mat.albedo_color.a = FADE_ALPHA
			mi.material_override = fade_mat


func _ray_intersects_aabb(origin: Vector3, dir: Vector3, length: float, aabb: AABB) -> bool:
	## Slab method for ray-AABB intersection
	var tmin := 0.0
	var tmax := length

	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var bmin_a: float = aabb.position[axis]
		var bmax_a: float = aabb.position[axis] + aabb.size[axis]

		if absf(d) < 0.0001:
			# Ray is parallel to this slab
			if o < bmin_a or o > bmax_a:
				return false
		else:
			var t1 := (bmin_a - o) / d
			var t2 := (bmax_a - o) / d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false

	return true
