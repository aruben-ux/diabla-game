extends Area3D

## A loot drop in the world. Players walk into it to pick up.

@export var item: ItemData
@export var bob_speed := 2.0
@export var bob_height := 0.3

var _base_y: float
var _time: float = 0.0


func _ready() -> void:
	_base_y = global_position.y + 0.5
	body_entered.connect(_on_body_entered)


func setup(item_data: ItemData) -> void:
	item = item_data
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


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players") or not item:
		return

	if multiplayer.is_server():
		# Server detects collision directly
		var peer_id := body.get_multiplayer_authority()
		_sync_pickup.rpc(peer_id, item.to_dict())
	elif body.is_multiplayer_authority():
		# Client: request pickup from server (server collision may miss teleported bodies)
		_request_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	if not multiplayer.is_server():
		return
	if not item:
		return
	var requester := multiplayer.get_remote_sender_id()
	# Verify the requester's player exists and is reasonably close
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == requester:
			if global_position.distance_to(player.global_position) < 6.0:
				_sync_pickup.rpc(requester, item.to_dict())
			break


@rpc("authority", "call_local", "reliable")
func _sync_pickup(peer_id: int, item_dict: Dictionary) -> void:
	# Prevent double-pickup
	item = null
	# Find the player with this peer_id and give them the item
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
