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
	OnlineManager.lobby_connected.connect(func(): _add_system_msg("Connected to lobby."))
	OnlineManager.lobby_disconnected.connect(func(): _add_system_msg("Disconnected from lobby."))

	create_dialog.visible = false
	join_button.disabled = true
	status_label.text = "Welcome, %s!" % OnlineManager.username

	# Difficulty options
	difficulty_option.clear()
	difficulty_option.add_item("Normal", 0)
	difficulty_option.add_item("Nightmare", 1)
	difficulty_option.add_item("Hell", 2)

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
		char_name_label.text = "No character selected"
		char_info_label.text = ""
		return
	var cls_name: String = CLASS_NAMES[cd.get("character_class", 0)] if cd.get("character_class", 0) < CLASS_NAMES.size() else "Unknown"
	char_name_label.text = cd.get("character_name", "???")
	char_info_label.text = "Lv.%d %s | Gold: %d" % [cd.get("level", 1), cls_name, cd.get("gold", 0)]


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
		status_label.text = "Select a character first!"
		return
	game_name_input.text = "%s's Game" % OnlineManager.username
	create_dialog.visible = true


func _on_confirm_create() -> void:
	var gname := game_name_input.text.strip_edges()
	if gname.is_empty():
		return
	var diff_idx := difficulty_option.selected
	var difficulty: String = ["normal", "nightmare", "hell"][diff_idx]
	create_dialog.visible = false
	status_label.text = "Creating game..."
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
		status_label.text = "Select a character first!"
		return
	var game_id: int = _games[_selected_game_index].get("id", -1)
	status_label.text = "Joining game..."
	OnlineManager.join_game(game_id)


func _on_game_joined(info: Dictionary) -> void:
	if info.has("error"):
		status_label.text = info["error"]
		return
	_connect_to_game_server(info)


func _connect_to_game_server(info: Dictionary) -> void:
	var host: String = info.get("host", "127.0.0.1")
	var port: int = info.get("port", 9000)
	var game_token: String = info.get("game_token", "")

	# Store the game token so NetworkManager can send it after connecting
	NetworkManager.game_token = game_token
	NetworkManager.game_id = info.get("game_id", -1)

	# Disconnect lobby WebSocket (we're entering a game)
	OnlineManager.disconnect_lobby()

	# Connect to the dedicated game server via ENet
	var error := NetworkManager.join_game(host, port)
	if error == OK:
		status_label.text = "Connecting to game server..."
		# Wait for connection_succeeded to transition
		NetworkManager.connection_succeeded.connect(_on_game_connection_ok, CONNECT_ONE_SHOT)
		NetworkManager.connection_failed.connect(_on_game_connection_fail, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to connect!"


func _on_game_connection_ok() -> void:
	# Load character data into CharacterManager for the game scenes to use
	var cd: Dictionary = OnlineManager.selected_character_data
	var char_data := CharacterData.from_dict(cd)
	CharacterManager.select_character(char_data)
	GameManager.change_state(GameManager.GameState.PLAYING)
	get_tree().change_scene_to_file("res://scenes/game/main_game.tscn")


func _on_game_connection_fail() -> void:
	status_label.text = "Connection to game server failed."
	OnlineManager.connect_lobby()


# --- Navigation ---

func _on_change_char() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")


func _on_logout() -> void:
	OnlineManager.logout()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
