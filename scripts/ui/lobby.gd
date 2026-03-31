extends Control

## Online lobby screen — Battle.net style.
## Shows chat, character info, game browser, and create/join game controls.

# Character panel (left)
@onready var char_name_label: Label = $HSplitContainer/LeftPanel/CharPanel/CharNameLabel
@onready var char_info_label: Label = $HSplitContainer/LeftPanel/CharPanel/CharInfoLabel
@onready var change_char_button: Button = $HSplitContainer/LeftPanel/CharPanel/ChangeCharButton

# Chat panel (left bottom)
@onready var chat_log: RichTextLabel = $HSplitContainer/LeftPanel/ChatPanel/ChatLog
@onready var chat_input: LineEdit = $HSplitContainer/LeftPanel/ChatPanel/ChatInput
@onready var user_list: ItemList = $HSplitContainer/LeftPanel/ChatPanel/UserList

# Game browser (right)
@onready var game_list: ItemList = $HSplitContainer/RightPanel/GameBrowser/GameList
@onready var refresh_button: Button = $HSplitContainer/RightPanel/GameBrowser/RefreshButton
@onready var join_button: Button = $HSplitContainer/RightPanel/GameBrowser/JoinButton
@onready var create_game_button: Button = $HSplitContainer/RightPanel/GameBrowser/CreateGameButton

# Create game dialog
@onready var create_dialog: PanelContainer = $CreateGameDialog
@onready var game_name_input: LineEdit = $CreateGameDialog/VBox/GameNameInput
@onready var difficulty_option: OptionButton = $CreateGameDialog/VBox/DifficultyOption
@onready var confirm_create_button: Button = $CreateGameDialog/VBox/ConfirmButton
@onready var cancel_create_button: Button = $CreateGameDialog/VBox/CancelButton

@onready var logout_button: Button = $LogoutButton
@onready var status_label: Label = $StatusLabel

var _games: Array = []
var _selected_game_index: int = -1
var _connect_retries := 0
var _connect_info: Dictionary = {}
const MAX_CONNECT_RETRIES := 20
const CONNECT_RETRY_DELAY := 1.5

const CLASS_NAMES := ["Warrior", "Mage", "Rogue"]


func _ready() -> void:
	# Connect UI signals
	change_char_button.pressed.connect(_on_change_char)
	chat_input.text_submitted.connect(_on_chat_submitted)
	refresh_button.pressed.connect(_refresh_games)
	join_button.pressed.connect(_on_join_pressed)
	create_game_button.pressed.connect(_show_create_dialog)
	confirm_create_button.pressed.connect(_on_confirm_create)
	cancel_create_button.pressed.connect(func(): create_dialog.visible = false)
	logout_button.pressed.connect(_on_logout)
	game_list.item_selected.connect(_on_game_selected)

	# Connect OnlineManager signals
	OnlineManager.chat_message.connect(_on_chat_message)
	OnlineManager.system_message.connect(_on_system_message)
	OnlineManager.user_list_updated.connect(_on_user_list_updated)
	OnlineManager.game_list_updated.connect(_on_game_list_updated)
	OnlineManager.games_loaded.connect(_on_games_loaded)
	OnlineManager.game_created.connect(_on_game_created)
	OnlineManager.game_joined.connect(_on_game_joined)
	OnlineManager.lobby_connected.connect(func(): _add_system_msg(tr("Connected to lobby.")))
	OnlineManager.lobby_disconnected.connect(func(): _add_system_msg(tr("Disconnected from lobby.")))

	create_dialog.visible = false
	join_button.disabled = true
	status_label.text = tr("Welcome, %s!") % OnlineManager.username

	# Difficulty options
	difficulty_option.clear()
	difficulty_option.add_item(tr("Normal"), 0)
	difficulty_option.add_item(tr("Nightmare"), 1)
	difficulty_option.add_item(tr("Hell"), 2)

	# Connect to lobby WebSocket
	OnlineManager.connect_lobby()

	# Check if a character is selected; if not, go to character select
	if OnlineManager.selected_character_id < 0:
		get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")
		return

	_update_char_display()
	_refresh_games()


func _update_char_display() -> void:
	var cd: Dictionary = OnlineManager.selected_character_data
	if cd.is_empty():
		char_name_label.text = tr("No character selected")
		char_info_label.text = ""
		return
	var cls_name: String = CLASS_NAMES[cd.get("character_class", 0)] if cd.get("character_class", 0) < CLASS_NAMES.size() else tr("Unknown")
	char_name_label.text = cd.get("character_name", "???")
	char_info_label.text = tr("Lv.%d %s | Gold: %d") % [cd.get("level", 1), cls_name, cd.get("gold", 0)]


# --- Chat ---

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	OnlineManager.send_chat(text)
	chat_input.text = ""


func _on_chat_message(sender: String, text: String, _timestamp: String) -> void:
	chat_log.append_text("[b]%s:[/b] %s\n" % [sender, text])


func _on_system_message(text: String) -> void:
	_add_system_msg(text)


func _add_system_msg(text: String) -> void:
	chat_log.append_text("[color=gray]* %s[/color]\n" % text)


func _on_user_list_updated(users: Array) -> void:
	user_list.clear()
	for u in users:
		user_list.add_item(u)


# --- Game Browser ---

func _refresh_games() -> void:
	OnlineManager.fetch_games()


func _on_games_loaded(games: Array) -> void:
	_update_game_list(games)


func _on_game_list_updated(games: Array) -> void:
	_update_game_list(games)


func _update_game_list(games: Array) -> void:
	_games = games
	game_list.clear()
	_selected_game_index = -1
	join_button.disabled = true
	for g in games:
		var label := "%s  |  %s  |  %d/%d  |  %s" % [
			g.get("name", "???"),
			g.get("host_username", "???"),
			g.get("current_players", 0),
			g.get("max_players", 8),
			g.get("difficulty", "normal"),
		]
		game_list.add_item(label)


func _on_game_selected(index: int) -> void:
	_selected_game_index = index
	join_button.disabled = false


# --- Create Game ---

func _show_create_dialog() -> void:
	if OnlineManager.selected_character_id < 0:
		status_label.text = tr("Select a character first!")
		return
	game_name_input.text = tr("%s's Game") % OnlineManager.username
	create_dialog.visible = true


func _on_confirm_create() -> void:
	var gname := game_name_input.text.strip_edges()
	if gname.is_empty():
		return
	var diff_idx := difficulty_option.selected
	var difficulty: String = ["normal", "nightmare", "hell"][diff_idx]
	create_dialog.visible = false
	status_label.text = tr("Creating game...")
	OnlineManager.create_game(gname, 8, difficulty)


func _on_game_created(info: Dictionary) -> void:
	if info.has("error"):
		status_label.text = info["error"]
		return
	_connect_to_game_server(info)


# --- Join Game ---

func _on_join_pressed() -> void:
	if _selected_game_index < 0 or _selected_game_index >= _games.size():
		return
	if OnlineManager.selected_character_id < 0:
		status_label.text = tr("Select a character first!")
		return
	var game_id: int = _games[_selected_game_index].get("id", -1)
	status_label.text = tr("Joining game...")
	OnlineManager.join_game(game_id)


func _on_game_joined(info: Dictionary) -> void:
	if info.has("error"):
		status_label.text = info["error"]
		return
	_connect_to_game_server(info)


func _connect_to_game_server(info: Dictionary) -> void:
	var game_token: String = info.get("game_token", "")

	# Store the game token so NetworkManager can send it after connecting
	NetworkManager.game_token = game_token
	NetworkManager.game_id = info.get("game_id", -1)

	_connect_info = info
	_connect_retries = 0
	# Poll the lobby until the game server reports ready, then ENet connect
	_poll_server_ready()


func _poll_server_ready() -> void:
	_connect_retries += 1
	if _connect_retries > MAX_CONNECT_RETRIES:
		status_label.text = tr("Game server did not become ready in time.")
		OnlineManager.connect_lobby()
		return

	status_label.text = tr("Waiting for game server... (%d/%d)") % [_connect_retries, MAX_CONNECT_RETRIES]

	var game_id: int = _connect_info.get("game_id", -1)
	var url := OnlineManager.lobby_url + "/games/%d/status" % game_id
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(
		func(_result: int, code: int, _h: PackedStringArray, body_bytes: PackedByteArray):
			http.queue_free()
			if code == 200:
				var json := JSON.new()
				json.parse(body_bytes.get_string_from_utf8())
				var server_status: String = json.data.get("status", "waiting") if json.data is Dictionary else "waiting"
				if server_status in ["ready", "in_progress"]:
					# Server is ready — now connect via ENet
					_do_enet_connect()
					return
			# Not ready yet — retry after delay
			if _connect_retries < MAX_CONNECT_RETRIES:
				get_tree().create_timer(CONNECT_RETRY_DELAY).timeout.connect(_poll_server_ready)
			else:
				status_label.text = tr("Game server did not become ready in time.")
				OnlineManager.connect_lobby(),
		CONNECT_ONE_SHOT)
	http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)


func _do_enet_connect() -> void:
	var host: String = _connect_info.get("host", "127.0.0.1")
	var port: int = _connect_info.get("port", 9000)

	# Disconnect lobby WebSocket now that we know the server is ready
	OnlineManager.disconnect_lobby()

	status_label.text = tr("Connecting to game server...")
	var error := NetworkManager.join_game(host, port)
	if error == OK:
		NetworkManager.connection_succeeded.connect(_on_game_connection_ok, CONNECT_ONE_SHOT)
		NetworkManager.connection_failed.connect(_on_game_connection_fail, CONNECT_ONE_SHOT)
	else:
		status_label.text = tr("Failed to connect!")
		OnlineManager.connect_lobby()


func _on_game_connection_ok() -> void:
	# Load character data into CharacterManager for the game scenes to use
	var cd: Dictionary = OnlineManager.selected_character_data
	var char_data := CharacterData.from_dict(cd)
	CharacterManager.select_character(char_data)
	GameManager.change_state(GameManager.GameState.PLAYING)
	get_tree().change_scene_to_file("res://scenes/game/main_game.tscn")


func _on_game_connection_fail() -> void:
	status_label.text = tr("Connection to game server failed.")
	OnlineManager.connect_lobby()


# --- Navigation ---

func _on_change_char() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")


func _on_logout() -> void:
	OnlineManager.logout()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
