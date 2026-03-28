extends Node

## Manages communication with the lobby server (HTTP + WebSocket).
## Handles authentication, character CRUD, game listing, and lobby chat.
## This is the Godot client's interface to the online backend.

signal login_succeeded(username: String, account_id: int)
signal login_failed(reason: String)
signal register_succeeded(username: String, account_id: int)
signal register_failed(reason: String)
signal characters_loaded(characters: Array)
signal character_created(character: Dictionary)
signal character_deleted()
signal games_loaded(games: Array)
signal game_created(game_info: Dictionary)
signal game_joined(game_info: Dictionary)
signal chat_message(sender: String, text: String, timestamp: String)
signal system_message(text: String)
signal user_list_updated(users: Array)
signal lobby_connected
signal lobby_disconnected
signal game_list_updated(games: Array)

const DEFAULT_LOBBY_URL := "http://5.78.206.166:8080"

var lobby_url: String = DEFAULT_LOBBY_URL
var access_token: String = ""
var username: String = ""
var account_id: int = -1
var is_online: bool = false
var selected_character_id: int = -1
var selected_character_data: Dictionary = {}

var _ws: WebSocketPeer = null
var _ws_connected: bool = false
var _http: HTTPRequest = null


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_connected:
			_ws_connected = true
			lobby_connected.emit()
		while _ws.get_available_packet_count() > 0:
			var text := _ws.get_packet().get_string_from_utf8()
			_handle_ws_message(text)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _ws_connected:
			_ws_connected = false
			lobby_disconnected.emit()
		_ws = null


# --- Authentication ---

func login(user: String, password: String) -> void:
	var body := JSON.stringify({"username": user, "password": password})
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 200:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				var data: Dictionary = json.data
				access_token = data.get("access_token", "")
				username = data.get("username", "")
				account_id = data.get("account_id", -1)
				is_online = true
				login_succeeded.emit(username, account_id)
			else:
				var reason := _parse_error(body_bytes, "Login failed")
				login_failed.emit(reason),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/auth/login", _json_headers(), HTTPClient.METHOD_POST, body)


func register(user: String, password: String, email: String) -> void:
	var body := JSON.stringify({"username": user, "password": password, "email": email})
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 201:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				var data: Dictionary = json.data
				access_token = data.get("access_token", "")
				username = data.get("username", "")
				account_id = data.get("account_id", -1)
				is_online = true
				register_succeeded.emit(username, account_id)
			else:
				var reason := _parse_error(body_bytes, "Registration failed")
				register_failed.emit(reason),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/auth/register", _json_headers(), HTTPClient.METHOD_POST, body)


func logout() -> void:
	access_token = ""
	username = ""
	account_id = -1
	is_online = false
	selected_character_id = -1
	selected_character_data = {}
	disconnect_lobby()


# --- Characters ---

func fetch_characters() -> void:
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 200:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				characters_loaded.emit(json.data)
			else:
				characters_loaded.emit([]),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/characters/", _auth_headers(), HTTPClient.METHOD_GET)


func create_character(char_name: String, char_class: int) -> void:
	var body := JSON.stringify({"character_name": char_name, "character_class": char_class})
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 201:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				character_created.emit(json.data)
			else:
				character_created.emit({}),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/characters/", _auth_json_headers(), HTTPClient.METHOD_POST, body)


func delete_character(character_id: int) -> void:
	_http.request_completed.connect(
		func(_result: int, _code: int, _headers: PackedStringArray, _body_bytes: PackedByteArray):
			character_deleted.emit(),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/characters/%d" % character_id, _auth_headers(), HTTPClient.METHOD_DELETE)


func select_character(char_data: Dictionary) -> void:
	selected_character_id = char_data.get("id", -1)
	selected_character_data = char_data


# --- Games ---

func fetch_games() -> void:
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 200:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				games_loaded.emit(json.data)
			else:
				games_loaded.emit([]),
		CONNECT_ONE_SHOT)
	_http.request(lobby_url + "/games/", [], HTTPClient.METHOD_GET)


func create_game(game_name: String, max_players: int = 8, difficulty: String = "normal") -> void:
	var body := JSON.stringify({"name": game_name, "max_players": max_players, "difficulty": difficulty})
	var url := lobby_url + "/games/?character_id=%d" % selected_character_id
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 201:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				game_created.emit(json.data)
			else:
				var reason := _parse_error(body_bytes, "Failed to create game")
				game_created.emit({"error": reason}),
		CONNECT_ONE_SHOT)
	_http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST, body)


func join_game(game_id: int) -> void:
	var url := lobby_url + "/games/%d/join?character_id=%d" % [game_id, selected_character_id]
	_http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			if code == 200:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				game_joined.emit(json.data)
			else:
				var reason := _parse_error(body_bytes, "Failed to join game")
				game_joined.emit({"error": reason}),
		CONNECT_ONE_SHOT)
	_http.request(url, _auth_json_headers(), HTTPClient.METHOD_POST)


# --- WebSocket Lobby ---

func connect_lobby() -> void:
	if _ws != null:
		return
	var ws_url := lobby_url.replace("http://", "ws://").replace("https://", "wss://")
	ws_url += "/ws/lobby?token=%s" % access_token
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(ws_url)
	_ws_connected = false


func disconnect_lobby() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
		_ws_connected = false


func send_chat(text: String) -> void:
	if _ws == null or not _ws_connected:
		return
	var msg := JSON.stringify({"type": "chat", "text": text})
	_ws.send_text(msg)


func _handle_ws_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data: Dictionary = json.data
	var msg_type: String = data.get("type", "")
	match msg_type:
		"chat":
			chat_message.emit(data.get("sender", "???"), data.get("text", ""), data.get("timestamp", ""))
		"system":
			system_message.emit(data.get("text", ""))
		"user_list":
			user_list_updated.emit(data.get("users", []))
		"game_list":
			game_list_updated.emit(data.get("games", []))
		"pong":
			pass  # Keepalive


# --- Helpers ---

func _json_headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json"])


func _auth_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer %s" % access_token])


func _auth_json_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % access_token,
	])


func _parse_error(body_bytes: PackedByteArray, fallback: String) -> String:
	var json := JSON.new()
	if json.parse(body_bytes.get_string_from_utf8()) == OK:
		var data: Dictionary = json.data
		return data.get("detail", fallback)
	return fallback
