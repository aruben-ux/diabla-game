extends StaticBody3D

## Breakable pot that shatters when hit by an attack.
## Optionally drops gold on break. Synced via RPC.

var _health := 1.0
var _broken := false
var _drop_gold := false
var _gold_amount := 0
var _floor_level := 1


func setup(floor_lvl: int, drops_gold: bool, gold_amt: int) -> void:
	_floor_level = floor_lvl
	_drop_gold = drops_gold
	_gold_amount = gold_amt


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if _broken:
		return
	_health -= amount
	if _health <= 0.0:
		_broken = true
		_sync_break.rpc()
		# Server spawns gold drop
		if _drop_gold and _gold_amount > 0 and attacker and attacker.has_method("rpc_spawn_gold"):
			attacker.rpc_spawn_gold(_gold_amount, global_position + Vector3(0, 0.3, 0))


@rpc("authority", "call_local", "reliable")
func _sync_break() -> void:
	_broken = true
	# Hide pot meshes and disable collision
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	_spawn_debris()
	get_tree().create_timer(2.0).timeout.connect(_cleanup)


func _cleanup() -> void:
	if is_instance_valid(self):
		queue_free()


func _spawn_debris() -> void:
	var parent := get_parent()
	if not parent:
		return

	var debris_mat := StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.55, 0.35, 0.18)
	debris_mat.roughness = 0.9

	for i in range(6):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var s := randf_range(0.04, 0.1)
		mesh.size = Vector3(s, s * 0.7, s)
		piece.mesh = mesh
		piece.material_override = debris_mat
		piece.position = global_position + Vector3(0, 0.25, 0)
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		parent.add_child(piece)

		# Arc outward from pot center
		var angle := TAU * float(i) / 6.0
		var dist := randf_range(0.4, 0.8)
		var peak := piece.position + Vector3(cos(angle) * dist * 0.5, 0.3, sin(angle) * dist * 0.5)
		var landing := Vector3(
			global_position.x + cos(angle) * dist,
			0.02,
			global_position.z + sin(angle) * dist,
		)
		var tween := piece.create_tween()
		tween.tween_property(piece, "position", peak, 0.12).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, "position", landing, 0.22).set_ease(Tween.EASE_IN)
		# Fade away
		get_tree().create_timer(1.5).timeout.connect(piece.queue_free)
