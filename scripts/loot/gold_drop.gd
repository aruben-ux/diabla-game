extends Area3D

## Gold coin drop. Picked up on contact, doesn't take inventory space.

var gold_amount: int = 0

var _base_y: float
var _time: float = 0.0


func _ready() -> void:
	_base_y = global_position.y + 0.3
	body_entered.connect(_on_body_entered)
	add_to_group("loot_drops")


func setup(amount: int) -> void:
	gold_amount = amount
	# Gold-colored glow
	var mesh_instance := $MeshInstance3D
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.65, 0.0)
		mat.emission_energy_multiplier = 1.5
		mat.metallic = 0.9
		mat.roughness = 0.3
		mesh_instance.material_override = mat


func _process(delta: float) -> void:
	_time += delta
	# Loot-vs-loot separation (XZ only)
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("loot_drops"):
		if other == self or not is_instance_valid(other):
			continue
		var diff: Vector3 = global_position - other.global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist < 1.2 and dist > 0.001:
			push += diff.normalized() * (1.2 - dist) * 4.0
		elif dist <= 0.001:
			push += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 2.0
	if push.length() > 0.01:
		var new_xz := global_position + push * delta
		# Wall collision check (layer 1)
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(global_position, new_xz, 1)
		var result := space.intersect_ray(query)
		if result.is_empty():
			global_position.x = new_xz.x
			global_position.z = new_xz.z
	# Bob + spin
	var pos := global_position
	pos.y = _base_y + sin(_time * 3.0) * 0.15
	global_position = pos
	rotation.y += delta * 4.0


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players") or gold_amount <= 0:
		return

	if multiplayer.is_server():
		var peer_id := body.get_multiplayer_authority()
		_sync_gold_pickup.rpc(peer_id)
	elif body.is_multiplayer_authority():
		_request_gold_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_gold_pickup() -> void:
	if not multiplayer.is_server():
		return
	if gold_amount <= 0:
		return
	var requester := multiplayer.get_remote_sender_id()
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == requester:
			if global_position.distance_to(player.global_position) < 6.0:
				_sync_gold_pickup.rpc(requester)
			break


@rpc("authority", "call_local", "reliable")
func _sync_gold_pickup(peer_id: int) -> void:
	var amount := gold_amount
	gold_amount = 0
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == peer_id:
			if player.has_method("add_gold"):
				player.add_gold(amount)
			break
	queue_free()
