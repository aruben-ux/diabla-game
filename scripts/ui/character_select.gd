extends Control

## Character selection screen.
## In offline mode: loads characters from local disk.
## In online mode: fetches characters from server via OnlineManager.

@onready var slot_list: VBoxContainer = $CharacterList/ScrollContainer/SlotList
@onready var create_button: Button = $BottomBar/CreateButton
@onready var play_button: Button = $BottomBar/PlayButton
@onready var delete_button: Button = $BottomBar/DeleteButton
@onready var back_button: Button = $BottomBar/BackButton

var _selected_index: int = -1
## In offline mode: Array[CharacterData]. In online mode: Array[Dictionary].
var _characters: Array = []
var _is_online: bool = false

const CLASS_COLORS := {
	CharacterData.CharacterClass.WARRIOR: Color(0.9, 0.35, 0.25),
	CharacterData.CharacterClass.MAGE: Color(0.3, 0.5, 1.0),
	CharacterData.CharacterClass.ROGUE: Color(0.2, 0.85, 0.4),
}

const CLASS_NAMES := ["Warrior", "Mage", "Rogue"]


func _ready() -> void:
	_is_online = GameManager.is_online_mode

	create_button.pressed.connect(_on_create_pressed)
	play_button.pressed.connect(_on_play_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)

	if _is_online:
		OnlineManager.characters_loaded.connect(_on_server_characters_loaded)
		OnlineManager.character_created.connect(_on_server_character_created)
		OnlineManager.character_deleted.connect(_on_server_character_deleted)

	_refresh_character_list()


func _refresh_character_list() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	_characters = []
	_selected_index = -1
	play_button.disabled = true
	delete_button.disabled = true

	if _is_online:
		OnlineManager.fetch_characters()
	else:
		_characters.assign(CharacterManager.get_all_characters())
		_rebuild_slot_ui()


func _on_server_characters_loaded(chars: Array) -> void:
	_characters = chars
	_rebuild_slot_ui()


func _rebuild_slot_ui() -> void:
	for child in slot_list.get_children():
		child.queue_free()

	if _characters.is_empty():
		var label := Label.new()
		label.text = "No characters yet — create one!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		slot_list.add_child(label)
		return

	for i in _characters.size():
		if _is_online:
			_add_online_slot(i, _characters[i])
		else:
			_add_character_slot(i, _characters[i])


func _add_character_slot(index: int, data: CharacterData) -> void:
	var btn := Button.new()
	btn.custom_minimum_size.y = 60
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var class_name_str := CharacterData.class_name_from_enum(data.character_class)
	var play_hours := int(data.play_time_seconds / 3600.0)
	var play_mins := int(fmod(data.play_time_seconds, 3600.0) / 60.0)
	var time_str := "%dh %dm" % [play_hours, play_mins] if play_hours > 0 else "%dm" % play_mins

	btn.text = "  %s  —  Lv.%d %s  |  Time: %s" % [
		data.character_name, data.level, class_name_str, time_str
	]

	var cls_color: Color = CLASS_COLORS.get(data.character_class, Color.WHITE)
	btn.add_theme_color_override("font_color", cls_color)
	btn.add_theme_color_override("font_hover_color", cls_color.lightened(0.3))
	btn.pressed.connect(_on_slot_pressed.bind(index))
	slot_list.add_child(btn)


func _add_online_slot(index: int, data: Dictionary) -> void:
	var btn := Button.new()
	btn.custom_minimum_size.y = 60
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var cls: int = data.get("character_class", 0)
	var cls_name: String = CLASS_NAMES[cls] if cls < CLASS_NAMES.size() else "Unknown"
	var play_secs: float = data.get("play_time_seconds", 0.0)
	var play_hours := int(play_secs / 3600.0)
	var play_mins := int(fmod(play_secs, 3600.0) / 60.0)
	var time_str := "%dh %dm" % [play_hours, play_mins] if play_hours > 0 else "%dm" % play_mins

	btn.text = "  %s  —  Lv.%d %s  |  Time: %s" % [
		data.get("character_name", "???"), data.get("level", 1), cls_name, time_str
	]

	var cls_enum := cls as CharacterData.CharacterClass
	var cls_color: Color = CLASS_COLORS.get(cls_enum, Color.WHITE)
	btn.add_theme_color_override("font_color", cls_color)
	btn.add_theme_color_override("font_hover_color", cls_color.lightened(0.3))
	btn.pressed.connect(_on_slot_pressed.bind(index))
	slot_list.add_child(btn)


func _on_slot_pressed(index: int) -> void:
	_selected_index = index
	play_button.disabled = false
	delete_button.disabled = false

	for i in slot_list.get_child_count():
		var child := slot_list.get_child(i)
		if child is Button:
			child.modulate = Color(0.7, 0.7, 0.7) if i != index else Color.WHITE


func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_creator.tscn")


func _on_server_character_created(_data: Dictionary) -> void:
	_refresh_character_list()


func _on_server_character_deleted() -> void:
	_refresh_character_list()


func _on_play_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _characters.size():
		return

	if _is_online:
		var char_dict: Dictionary = _characters[_selected_index]
		OnlineManager.select_character(char_dict)
		# Go to lobby
		get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
	else:
		var data: CharacterData = _characters[_selected_index]
		CharacterManager.select_character(data)

		var my_id := multiplayer.get_unique_id()
		var class_str := CharacterData.class_name_from_enum(data.character_class)
		GameManager.register_player(my_id, {
			"name": data.character_name,
			"class": class_str,
			"level": data.level,
		})

		GameManager.change_state(GameManager.GameState.PLAYING)
		get_tree().change_scene_to_file("res://scenes/game/main_game.tscn")


func _on_delete_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _characters.size():
		return

	if _is_online:
		var char_dict: Dictionary = _characters[_selected_index]
		var char_id: int = char_dict.get("id", -1)
		if char_id > 0:
			OnlineManager.delete_character(char_id)
	else:
		var data: CharacterData = _characters[_selected_index]
		CharacterManager.delete_character(data.save_slot)
		_refresh_character_list()


func _on_back_pressed() -> void:
	if _is_online:
		get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn") if OnlineManager.access_token != "" else get_tree().change_scene_to_file("res://scenes/ui/login_screen.tscn")
	else:
		NetworkManager.disconnect_game()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
