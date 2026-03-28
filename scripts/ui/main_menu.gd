extends Control

## Main menu with Online / Offline choice.
## Online → Login screen → Lobby (Battle.net style)
## Offline → Original host/join LAN flow

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var online_button: Button = $VBoxContainer/OnlineButton
@onready var offline_button: Button = $VBoxContainer/OfflineButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

# Offline LAN controls (hidden by default, shown when Offline is picked)
@onready var offline_panel: VBoxContainer = $VBoxContainer/OfflinePanel
@onready var host_button: Button = $VBoxContainer/OfflinePanel/HostButton
@onready var join_button: Button = $VBoxContainer/OfflinePanel/JoinButton
@onready var address_input: LineEdit = $VBoxContainer/OfflinePanel/AddressInput
@onready var back_button: Button = $VBoxContainer/OfflinePanel/BackButton


func _ready() -> void:
	online_button.pressed.connect(_on_online_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	status_label.text = ""
	offline_panel.visible = false
	GameManager.is_online_mode = false


func _on_online_pressed() -> void:
	GameManager.is_online_mode = true
	get_tree().change_scene_to_file("res://scenes/ui/login_screen.tscn")


func _on_offline_pressed() -> void:
	GameManager.is_online_mode = false
	_show_offline_panel()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_offline_panel() -> void:
	online_button.visible = false
	offline_button.visible = false
	quit_button.visible = false
	offline_panel.visible = true
	status_label.text = "Offline Mode — LAN Play"


func _on_back_pressed() -> void:
	offline_panel.visible = false
	online_button.visible = true
	offline_button.visible = true
	quit_button.visible = true
	status_label.text = ""


func _on_host_pressed() -> void:
	var error := NetworkManager.host_game()
	if error == OK:
		status_label.text = "Hosting game..."
		get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")
	else:
		status_label.text = "Failed to host game!"


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var error := NetworkManager.join_game(address)
	if error == OK:
		status_label.text = "Connecting to %s..." % address
	else:
		status_label.text = "Failed to connect!"


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Try again."
