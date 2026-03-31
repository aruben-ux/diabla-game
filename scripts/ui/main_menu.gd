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

# Language selector (built in code)
var _lang_button: Button
var _lang_panel: PanelContainer
var _lang_buttons: Array[Button] = []


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
	_build_language_selector()


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
	status_label.text = tr("Offline Mode — LAN Play")


func _on_back_pressed() -> void:
	offline_panel.visible = false
	online_button.visible = true
	offline_button.visible = true
	quit_button.visible = true
	status_label.text = ""


func _on_host_pressed() -> void:
	var error := NetworkManager.host_game()
	if error == OK:
		status_label.text = tr("Hosting game...")
		get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")
	else:
		status_label.text = tr("Failed to host game!")


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var error := NetworkManager.join_game(address)
	if error == OK:
		status_label.text = tr("Connecting to %s...") % address
	else:
		status_label.text = tr("Failed to connect!")


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")


func _on_connection_failed() -> void:
	status_label.text = tr("Connection failed. Try again.")


func _build_language_selector() -> void:
	# "Language" button in bottom-right corner
	_lang_button = Button.new()
	_lang_button.text = tr("Language") + ": " + TranslationManager.LANGUAGE_NAMES.get(TranslationManager.get_language(), "English")
	_lang_button.custom_minimum_size = Vector2(160, 36)
	_lang_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lang_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lang_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lang_button.offset_left = -176
	_lang_button.offset_top = -52
	_lang_button.offset_right = -16
	_lang_button.offset_bottom = -16
	_lang_button.pressed.connect(_toggle_lang_panel)
	add_child(_lang_button)

	# Popup panel with language options
	_lang_panel = PanelContainer.new()
	_lang_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lang_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_lang_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lang_panel.offset_left = -176
	_lang_panel.offset_top = -170
	_lang_panel.offset_right = -16
	_lang_panel.offset_bottom = -56

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.4, 0.3, 0.7)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_lang_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_lang_panel.add_child(vbox)

	for locale in TranslationManager.LANGUAGES:
		var btn := Button.new()
		btn.text = TranslationManager.LANGUAGE_NAMES[locale]
		btn.custom_minimum_size = Vector2(140, 30)
		btn.pressed.connect(_on_language_selected.bind(locale))
		vbox.add_child(btn)
		_lang_buttons.append(btn)

	add_child(_lang_panel)
	_lang_panel.visible = false
	_update_lang_highlight()


func _toggle_lang_panel() -> void:
	_lang_panel.visible = not _lang_panel.visible


func _on_language_selected(locale: String) -> void:
	TranslationManager.set_language(locale)
	_lang_panel.visible = false
	# Reload the scene to refresh all translated text
	get_tree().reload_current_scene()


func _update_lang_highlight() -> void:
	var current := TranslationManager.get_language()
	for i in TranslationManager.LANGUAGES.size():
		var locale: String = TranslationManager.LANGUAGES[i]
		if i < _lang_buttons.size():
			_lang_buttons[i].modulate = Color.GOLD if locale == current else Color.WHITE
