extends Area3D

## A loot drop in the world. Potions auto-pickup on contact.
## Equipment must be clicked to pick up (walk-to-interact).

@export var item: ItemData
@export var bob_speed := 2.0
@export var bob_height := 0.3

var display_name: String = "Loot"
var interact_hint: String = "Click to pick up"

var _base_y: float
var _time: float = 0.0
var _is_auto_pickup: bool = false
var is_local_only: bool = false


func _ready() -> void:
	_base_y = global_position.y + 0.5
	body_entered.connect(_on_body_entered)


func setup(item_data: ItemData) -> void:
	item = item_data
	display_name = item.display_name
	_is_auto_pickup = item.item_type == ItemData.ItemType.POTION
	if _is_auto_pickup:
		interact_hint = ""
	else:
		add_to_group("interactables")
	# Color the mesh with glow shader to match rarity
	var mesh_instance := $MeshInstance3D
	if mesh_instance:
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
	var pos := global_position
	pos.y = _base_y + sin(_time * bob_speed) * bob_height
	global_position = pos
	# Spin
	rotation.y += delta * 2.0


## Auto-pickup (body contact) — only for potions
func _on_body_entered(body: Node3D) -> void:
	if not _is_auto_pickup:
		return
	if not body.is_in_group("players") or not item:
		return

	if is_local_only:
		if body.is_multiplayer_authority():
			_local_pickup(body)
		return

	if multiplayer.is_server():
		var peer_id := body.get_multiplayer_authority()
		_sync_pickup.rpc(peer_id, item.to_dict())
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
		# Server handles actual pickup
		var peer_id := player.get_multiplayer_authority()
		_sync_pickup.rpc(peer_id, item.to_dict())
	else:
		# Client hint — server will handle via _server_interact_intent
		visible = false


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
				_sync_pickup.rpc(requester, item.to_dict())
			break


@rpc("authority", "call_local", "reliable")
func _sync_pickup(peer_id: int, item_dict: Dictionary) -> void:
	item = null
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == peer_id:
			var pickup_item := ItemData.from_dict(item_dict)
			player.pick_up_item(pickup_item)
			EventBus.show_floating_text.emit(
				global_position + Vector3(0, 1.5, 0),
				pickup_item.display_name,
				ItemData.get_rarity_color(pickup_item.rarity)
			)
			break
	queue_free()


func _local_pickup(player: Node) -> void:
	## Direct local pickup for items dropped from inventory (not on server).
	var pickup_item := item
	if not player.pick_up_item(pickup_item):
		return  # Inventory full — keep the drop on the ground
	item = null
	queue_free()
