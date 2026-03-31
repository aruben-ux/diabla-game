extends Control

## Login / Registration screen for online mode.
## Authenticates with the lobby server, then transitions to the lobby.

const SAVE_PATH := "user://login.cfg"

@onready var tab_container: TabContainer = $PanelContainer/TabContainer

# Login tab
@onready var login_username: LineEdit = $PanelContainer/TabContainer/Login/LoginVBox/UsernameInput
@onready var login_password: LineEdit = $PanelContainer/TabContainer/Login/LoginVBox/PasswordInput
@onready var login_button: Button = $PanelContainer/TabContainer/Login/LoginVBox/LoginButton
@onready var login_status: Label = $PanelContainer/TabContainer/Login/LoginVBox/StatusLabel
@onready var remember_check: CheckBox = $PanelContainer/TabContainer/Login/LoginVBox/RememberCheck

# Register tab
@onready var reg_username: LineEdit = $PanelContainer/TabContainer/Register/RegisterVBox/UsernameInput
@onready var reg_password: LineEdit = $PanelContainer/TabContainer/Register/RegisterVBox/PasswordInput
@onready var reg_email: LineEdit = $PanelContainer/TabContainer/Register/RegisterVBox/EmailInput
@onready var reg_button: Button = $PanelContainer/TabContainer/Register/RegisterVBox/RegisterButton
@onready var reg_status: Label = $PanelContainer/TabContainer/Register/RegisterVBox/StatusLabel

@onready var back_button: Button = $BackButton
@onready var server_input: LineEdit = $ServerInput


func _ready() -> void:
	login_button.pressed.connect(_on_login_pressed)
	reg_button.pressed.connect(_on_register_pressed)
	back_button.pressed.connect(_on_back_pressed)
	OnlineManager.login_succeeded.connect(_on_login_succeeded)
	OnlineManager.login_failed.connect(_on_login_failed)
	OnlineManager.register_succeeded.connect(_on_register_succeeded)
	OnlineManager.register_failed.connect(_on_register_failed)

	login_password.secret = true
	reg_password.secret = true

	if server_input:
		server_input.text = OnlineManager.lobby_url
		server_input.text_changed.connect(func(t: String): OnlineManager.lobby_url = t.strip_edges())

	_load_saved_credentials()


func _on_login_pressed() -> void:
	var user := login_username.text.strip_edges()
	var pw := login_password.text
	if user.is_empty() or pw.is_empty():
		login_status.text = tr("Enter username and password.")
		return
	login_button.disabled = true
	login_status.text = tr("Logging in...")
	if server_input:
		OnlineManager.lobby_url = server_input.text.strip_edges()
	OnlineManager.login(user, pw)


func _on_register_pressed() -> void:
	var user := reg_username.text.strip_edges()
	var pw := reg_password.text
	var email := reg_email.text.strip_edges()
	if user.is_empty() or pw.is_empty() or email.is_empty():
		reg_status.text = tr("Fill in all fields.")
		return
	if pw.length() < 6:
		reg_status.text = tr("Password must be at least 6 characters.")
		return
	reg_button.disabled = true
	reg_status.text = tr("Creating account...")
	if server_input:
		OnlineManager.lobby_url = server_input.text.strip_edges()
	OnlineManager.register(user, pw, email)


func _on_login_succeeded(_username: String, _account_id: int) -> void:
	_save_credentials()
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_login_failed(reason: String) -> void:
	login_status.text = reason
	login_button.disabled = false


func _on_register_succeeded(_username: String, _account_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_register_failed(reason: String) -> void:
	reg_status.text = reason
	reg_button.disabled = false


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _save_credentials() -> void:
	if not remember_check or not remember_check.button_pressed:
		# If unchecked, delete any saved credentials
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
		return
	var cfg := ConfigFile.new()
	cfg.set_value("login", "username", login_username.text.strip_edges())
	cfg.set_value("login", "password", login_password.text)
	cfg.set_value("login", "remember", true)
	cfg.save(SAVE_PATH)


func _load_saved_credentials() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	login_username.text = cfg.get_value("login", "username", "")
	login_password.text = cfg.get_value("login", "password", "")
	if remember_check:
		remember_check.button_pressed = cfg.get_value("login", "remember", false)
