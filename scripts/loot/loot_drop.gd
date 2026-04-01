extends Area3D

## A loot drop in the world. Potions auto-pickup on contact.
## Equipment must be clicked to pick up (walk-to-interact).

@export var item: ItemData
@export var bob_speed := 2.0
@export var bob_height := 0.3

var display_name: String = tr("Loot")
var interact_hint: String = tr("Click to pick up")

var _base_y: float
var _time: float = 0.0
var _is_auto_pickup: bool = false
var is_local_only: bool = false


func _ready() -> void:
	_base_y = global_position.y + 0.5
	body_entered.connect(_on_body_entered)
	add_to_group("loot_drops")


func setup(item_data: ItemData) -> void:
	item = item_data
	display_name = item.display_name
	_is_auto_pickup = item.item_type == ItemData.ItemType.POTION
	if _is_auto_pickup:
		interact_hint = ""
	else:
		add_to_group("interactables")
	# Potions: use colored sphere mesh instead of box
	var mesh_instance := $MeshInstance3D
	if mesh_instance and item.item_type == ItemData.ItemType.POTION:
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh_instance.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.RED if item.id == "health_potion" else Color.DODGER_BLUE
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 2.0
		mesh_instance.material_override = mat
	elif mesh_instance:
		# Equipment: color the mesh with glow shader to match rarity
		var glow_shader := load("res://assets/shaders/loot_glow.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = glow_shader
		var rarity_color := ItemData.get_rarity_color(item.rarity)
		mat.set_shader_parameter("base_color", rarity_color)
		mat.set_shader_parameter("glow_color", rarity_color)
		mat.set_shader_parameter("glow_strength", _glow_for_rarity(item.rarity))
		mat.set_shader_parameter("pulse_speed", 2.0)
		mesh_instance.material_override = mat


func _glow_for_rarity(rarity: int) -> float:
	match rarity:
		ItemData.Rarity.COMMON: return 0.3
		ItemData.Rarity.UNCOMMON: return 0.6
		ItemData.Rarity.RARE: return 1.0
		ItemData.Rarity.EPIC: return 1.5
		ItemData.Rarity.LEGENDARY: return 2.5
		_: return 0.5


func _process(delta: float) -> void:
	_time += delta
	# Loot-vs-loot separation (XZ only)
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("loot_drops"):
		if other == self or not is_instance_valid(other):
			continue
		var diff := global_position - other.global_position
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
			_base_y = global_position.y
	# Bob + spin
	var pos := global_position
	pos.y = _base_y + sin(_time * bob_speed) * bob_height
	global_position = pos
	rotation.y += delta * 2.0


## Auto-pickup (body contact) — only for potions
func _on_body_entered(body: Node3D) -> void:
	if not _is_auto_pickup:
		return
	if not body.is_in_group("players") or not item:
		return

	# Skip auto-pickup if at max potions
	if body.get("inventory") and not body.inventory.can_hold_potion(item.id):
		return

	if is_local_only:
		if body.is_multiplayer_authority():
			_local_pickup(body)
		return

	if multiplayer.is_server():
		var pickup_item := ItemData.from_dict(item.to_dict())
		if not body.pick_up_item(pickup_item):
			return  # Inventory full
		item = null
		_sync_pickup_visual.rpc()
	elif body.is_multiplayer_authority():
		_request_pickup.rpc_id(1)


## Click-to-pickup (interact call from player walk-to-interact)
func interact(player: Node) -> void:
	if _is_auto_pickup or not item:
		return
	if not player.is_in_group("players"):
		return

	if is_local_only:
		_local_pickup(player)
		return

	if multiplayer.is_server():
		# Server checks inventory space before broadcasting pickup
		var _peer_id := player.get_multiplayer_authority()
		var pickup_item := ItemData.from_dict(item.to_dict())
		if not player.pick_up_item(pickup_item):
			return  # Inventory full — keep the drop
		item = null
		_sync_pickup_visual.rpc()
	else:
		# Client: do nothing visual — server will broadcast result
		pass


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	if not multiplayer.is_server():
		return
	if not item:
		return
	var requester := multiplayer.get_remote_sender_id()
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == requester:
			if global_position.distance_to(player.global_position) < 6.0:
				var pickup_item := ItemData.from_dict(item.to_dict())
				if player.pick_up_item(pickup_item):
					item = null
					_sync_pickup_visual.rpc()
			break


@rpc("authority", "call_local", "reliable")
func _sync_pickup_visual() -> void:
	queue_free()


func _local_pickup(player: Node) -> void:
	## Direct local pickup for items dropped from inventory (not on server).
	var pickup_item := item
	if not player.pick_up_item(pickup_item):
		return  # Inventory full — keep the drop on the ground
	item = null
	queue_free()
