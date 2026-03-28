extends Node

## Manages multiplayer connections using ENet.
## Supports both LAN (offline) and dedicated server (online) modes.
## In online mode, sends a game_token after connecting for server validation.

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal player_authenticated(peer_id: int, character_data: Dictionary)

const DEFAULT_PORT := 9999
const MAX_CLIENTS := 8

var peer: ENetMultiplayerPeer

## Online mode: set before joining a game
var game_token: String = ""
var game_id: int = -1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		printerr("Failed to create server: ", error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Server started on port ", port)

	# Register the host as a player (offline/LAN mode only)
	if not GameManager.is_dedicated_server:
		GameManager.register_player(1, {"name": "Host"})
		player_connected.emit(1)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		printerr("Failed to create client: ", error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", address, ":", port)
	return OK


func disconnect_game() -> void:
	if peer:
		multiplayer.multiplayer_peer = null
		peer = null
	GameManager.players.clear()
	game_token = ""
	game_id = -1
	print("Disconnected from game")


func is_server() -> bool:
	return multiplayer.is_server()


func get_unique_id() -> int:
	return multiplayer.get_unique_id()


func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	if not GameManager.is_online_mode:
		# Offline/LAN: register immediately
		GameManager.register_player(id, {"name": "Player_%d" % id})
		player_connected.emit(id)
	# In online mode, the dedicated server waits for the player to
	# send their game_token via _send_game_token RPC before registering.


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	GameManager.unregister_player(id)
	GameManager.online_players.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("Connected to server! My ID: ", multiplayer.get_unique_id())
	var my_id := multiplayer.get_unique_id()

	if GameManager.is_online_mode and game_token != "":
		# Send our game token to the server for validation
		_send_game_token.rpc_id(1, game_token)
	else:
		# Offline/LAN mode
		GameManager.register_player(my_id, {"name": "Player_%d" % my_id})

	connection_succeeded.emit()


func _on_connection_failed() -> void:
	printerr("Connection to server failed")
	multiplayer.multiplayer_peer = null
	peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	printerr("Server disconnected")
	multiplayer.multiplayer_peer = null
	peer = null
	GameManager.players.clear()
	server_disconnected.emit()


## Called by a client to authenticate with the dedicated game server.
@rpc("any_peer", "call_remote", "reliable")
func _send_game_token(token: String) -> void:
	if not multiplayer.is_server():
		return
	if not GameManager.is_dedicated_server:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	# The headless game server will validate this token with the lobby server.
	# This is handled in the game_server_main.gd script.
	print("[Server] Received game token from peer ", sender_id)
	EventBus.game_token_received.emit(sender_id, token)


## Called by the dedicated server after validating a player's token.
## Broadcasts to all peers that this player is authenticated and ready.
@rpc("authority", "call_local", "reliable")
func _confirm_player_authenticated(peer_id: int, char_data: Dictionary) -> void:
	var char_name: String = char_data.get("character_name", "Player_%d" % peer_id)
	GameManager.register_player(peer_id, {"name": char_name})
	GameManager.online_players[peer_id] = char_data
	player_connected.emit(peer_id)
	player_authenticated.emit(peer_id, char_data)
