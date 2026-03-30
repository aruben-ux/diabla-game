extends Control

## Full-screen character creation screen.
## Shows three class cards with 3D previews and customization options.

signal character_created

# --- Class definitions ---
const CLASS_INFO := {
	CharacterData.CharacterClass.WARRIOR: {
		"name": "Warrior",
		"desc": "A stalwart champion clad in heavy armor. Excels in melee combat with devastating attacks and high defense. Wields a sword and shield.",
		"color": Color(0.9, 0.35, 0.25),
		"color_presets": [
			{"name": "Crimson",   "armor": Color(0.7, 0.15, 0.1),  "accent": Color(0.9, 0.35, 0.15)},
			{"name": "Azure",     "armor": Color(0.2, 0.35, 0.75), "accent": Color(0.3, 0.5, 0.9)},
			{"name": "Gold",      "armor": Color(0.65, 0.55, 0.15),"accent": Color(0.85, 0.75, 0.25)},
			{"name": "Obsidian",  "armor": Color(0.2, 0.2, 0.25),  "accent": Color(0.5, 0.5, 0.55)},
		],
		"body_presets": [
			{"name": "Stocky", "scale_mult": Vector3(1.1, 0.95, 1.1)},
			{"name": "Athletic", "scale_mult": Vector3(1.0, 1.0, 1.0)},
			{"name": "Towering", "scale_mult": Vector3(0.95, 1.1, 0.95)},
		],
	},
	CharacterData.CharacterClass.MAGE: {
		"name": "Mage",
		"desc": "A master of the arcane arts. Calls upon devastating spell power to obliterate foes from range. Wields a staff tipped with a glowing orb.",
		"color": Color(0.3, 0.5, 1.0),
		"color_presets": [
			{"name": "Arcane",    "armor": Color(0.25, 0.1, 0.5),  "accent": Color(0.6, 0.2, 1.0)},
			{"name": "Frost",     "armor": Color(0.15, 0.3, 0.55), "accent": Color(0.4, 0.7, 1.0)},
			{"name": "Ember",     "armor": Color(0.45, 0.1, 0.1),  "accent": Color(1.0, 0.4, 0.15)},
			{"name": "Nature",    "armor": Color(0.1, 0.35, 0.15), "accent": Color(0.3, 0.85, 0.4)},
		],
		"body_presets": [
			{"name": "Slender", "scale_mult": Vector3(0.9, 1.05, 0.9)},
			{"name": "Average", "scale_mult": Vector3(1.0, 1.0, 1.0)},
			{"name": "Broad",   "scale_mult": Vector3(1.1, 0.95, 1.1)},
		],
	},
	CharacterData.CharacterClass.ROGUE: {
		"name": "Rogue",
		"desc": "A swift and cunning fighter striking from the shadows. Relies on speed and precision with dual daggers. Nimble movement and fast attacks.",
		"color": Color(0.2, 0.85, 0.4),
		"color_presets": [
			{"name": "Shadow",    "armor": Color(0.15, 0.15, 0.2), "accent": Color(0.3, 0.3, 0.4)},
			{"name": "Forest",    "armor": Color(0.15, 0.35, 0.15),"accent": Color(0.25, 0.6, 0.3)},
			{"name": "Blood",     "armor": Color(0.45, 0.1, 0.1),  "accent": Color(0.7, 0.15, 0.15)},
			{"name": "Sand",      "armor": Color(0.55, 0.45, 0.3), "accent": Color(0.7, 0.6, 0.4)},
		],
		"body_presets": [
			{"name": "Lithe", "scale_mult": Vector3(0.9, 1.0, 0.9)},
			{"name": "Balanced", "scale_mult": Vector3(1.0, 1.0, 1.0)},
			{"name": "Muscular", "scale_mult": Vector3(1.1, 1.0, 1.1)},
		],
	},
}

const SIZE_PRESETS := [
	{"name": "Small",  "mult": 0.85},
	{"name": "Medium", "mult": 1.0},
	{"name": "Large",  "mult": 1.15},
]

# --- State ---
var _selected_class: CharacterData.CharacterClass = CharacterData.CharacterClass.WARRIOR
var _color_index: int = 0
var _body_index: int = 1
var _size_index: int = 1

# --- Node refs (built in code) ---
var _name_input: LineEdit
var _class_cards: Array[Button] = []
var _desc_label: RichTextLabel
var _color_option: OptionButton
var _body_option: OptionButton
var _size_option: OptionButton
var _create_btn: Button
var _back_btn: Button
var _preview_viewport: SubViewport
var _preview_model: Node3D
var _is_online: bool = false


func _ready() -> void:
	_is_online = GameManager.is_online_mode
	_build_ui()
	_select_class(CharacterData.CharacterClass.WARRIOR)


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.09)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Title
	var title := Label.new()
	title.text = "Create Character"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	title.offset_top = 20
	title.offset_bottom = 60
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)

	# --- Left column: class cards ---
	var left_panel := VBoxContainer.new()
	left_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	left_panel.anchor_left = 0.03
	left_panel.anchor_top = 0.1
	left_panel.anchor_right = 0.28
	left_panel.anchor_bottom = 0.88
	left_panel.add_theme_constant_override("separation", 10)
	add_child(left_panel)

	var cards_label := Label.new()
	cards_label.text = "Choose Class"
	cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_label.add_theme_font_size_override("font_size", 20)
	left_panel.add_child(cards_label)

	for cls in [CharacterData.CharacterClass.WARRIOR, CharacterData.CharacterClass.MAGE, CharacterData.CharacterClass.ROGUE]:
		var info: Dictionary = CLASS_INFO[cls]
		var card := Button.new()
		card.text = info["name"]
		card.custom_minimum_size.y = 60
		card.add_theme_font_size_override("font_size", 18)
		var cls_color: Color = info["color"]
		card.add_theme_color_override("font_color", cls_color)
		card.add_theme_color_override("font_hover_color", cls_color.lightened(0.3))
		card.pressed.connect(_select_class.bind(cls))
		left_panel.add_child(card)
		_class_cards.append(card)

	# Description below cards
	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.scroll_active = false
	left_panel.add_child(_desc_label)

	# --- Center: 3D preview ---
	var center_panel := PanelContainer.new()
	center_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center_panel.anchor_left = 0.3
	center_panel.anchor_top = 0.1
	center_panel.anchor_right = 0.7
	center_panel.anchor_bottom = 0.85
	add_child(center_panel)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(400, 500)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.msaa_3d = Viewport.MSAA_2X

	# Camera for preview
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 3.5)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 30
	_preview_viewport.add_child(cam)

	# Light for preview
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.2
	_preview_viewport.add_child(light)

	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.6
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.06, 0.12)
	ambient.environment = env
	_preview_viewport.add_child(ambient)

	# Model placeholder
	var model_script := preload("res://scripts/visuals/model_builder.gd")
	_preview_model = Node3D.new()
	_preview_model.set_script(model_script)
	_preview_model.position = Vector3(0, 0, 0)
	_preview_viewport.add_child(_preview_model)

	var svp_container := SubViewportContainer.new()
	svp_container.stretch = true
	svp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svp_container.add_child(_preview_viewport)
	center_panel.add_child(svp_container)

	# --- Right column: customization ---
	var right_panel := VBoxContainer.new()
	right_panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	right_panel.anchor_left = 0.72
	right_panel.anchor_top = 0.1
	right_panel.anchor_right = 0.97
	right_panel.anchor_bottom = 0.88
	right_panel.add_theme_constant_override("separation", 10)
	add_child(right_panel)

	var custom_label := Label.new()
	custom_label.text = "Customize"
	custom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_label.add_theme_font_size_override("font_size", 20)
	right_panel.add_child(custom_label)

	# Name
	var name_label := Label.new()
	name_label.text = "Name"
	right_panel.add_child(name_label)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Enter character name"
	_name_input.max_length = 20
	right_panel.add_child(_name_input)

	right_panel.add_child(HSeparator.new())

	# Color theme
	var color_label := Label.new()
	color_label.text = "Color Theme"
	right_panel.add_child(color_label)

	_color_option = OptionButton.new()
	_color_option.item_selected.connect(_on_color_selected)
	right_panel.add_child(_color_option)

	# Body shape
	var body_label := Label.new()
	body_label.text = "Body Shape"
	right_panel.add_child(body_label)

	_body_option = OptionButton.new()
	_body_option.item_selected.connect(_on_body_selected)
	right_panel.add_child(_body_option)

	# Size
	var size_label := Label.new()
	size_label.text = "Size"
	right_panel.add_child(size_label)

	_size_option = OptionButton.new()
	for i in SIZE_PRESETS.size():
		_size_option.add_item(SIZE_PRESETS[i]["name"], i)
	_size_option.selected = _size_index
	_size_option.item_selected.connect(_on_size_selected)
	right_panel.add_child(_size_option)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(spacer)

	# Create button
	_create_btn = Button.new()
	_create_btn.text = "Create Character"
	_create_btn.custom_minimum_size.y = 50
	_create_btn.add_theme_font_size_override("font_size", 18)
	_create_btn.pressed.connect(_on_create_pressed)
	right_panel.add_child(_create_btn)

	# --- Bottom bar ---
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bottom.anchor_top = 0.9
	bottom.anchor_bottom = 0.97
	bottom.anchor_left = 0.35
	bottom.anchor_right = 0.65
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(180, 0)
	_back_btn.pressed.connect(_on_back_pressed)
	bottom.add_child(_back_btn)


func _select_class(cls: CharacterData.CharacterClass) -> void:
	_selected_class = cls
	_color_index = 0
	_body_index = 1

	var info: Dictionary = CLASS_INFO[cls]

	# Update card highlight
	var classes := [CharacterData.CharacterClass.WARRIOR, CharacterData.CharacterClass.MAGE, CharacterData.CharacterClass.ROGUE]
	for i in classes.size():
		_class_cards[i].modulate = Color.WHITE if classes[i] == cls else Color(0.5, 0.5, 0.5)

	# Update description
	_desc_label.text = "[color=#%s][b]%s[/b][/color]\n\n%s" % [
		info["color"].to_html(false), info["name"], info["desc"]
	]

	# Rebuild color options
	_color_option.clear()
	var presets: Array = info["color_presets"]
	for i in presets.size():
		_color_option.add_item(presets[i]["name"], i)
	_color_option.selected = 0

	# Rebuild body options
	_body_option.clear()
	var bodies: Array = info["body_presets"]
	for i in bodies.size():
		_body_option.add_item(bodies[i]["name"], i)
	_body_option.selected = _body_index

	_refresh_preview()


func _on_color_selected(idx: int) -> void:
	_color_index = idx
	_refresh_preview()


func _on_body_selected(idx: int) -> void:
	_body_index = idx
	_refresh_preview()


func _on_size_selected(idx: int) -> void:
	_size_index = idx
	_refresh_preview()


func _get_appearance() -> Dictionary:
	var info: Dictionary = CLASS_INFO[_selected_class]
	var color_preset: Dictionary = info["color_presets"][_color_index]
	var body_preset: Dictionary = info["body_presets"][_body_index]
	var size_preset: Dictionary = SIZE_PRESETS[_size_index]

	return {
		"character_class": _selected_class as int,
		"color_index": _color_index,
		"body_index": _body_index,
		"size_index": _size_index,
		"armor_color": [color_preset["armor"].r, color_preset["armor"].g, color_preset["armor"].b],
		"accent_color": [color_preset["accent"].r, color_preset["accent"].g, color_preset["accent"].b],
		"body_scale": [body_preset["scale_mult"].x, body_preset["scale_mult"].y, body_preset["scale_mult"].z],
		"size_mult": size_preset["mult"],
	}


func _refresh_preview() -> void:
	if not _preview_model:
		return
	var appearance := _get_appearance()
	_preview_model.build_class_model(appearance)


func _on_create_pressed() -> void:
	var char_name := _name_input.text.strip_edges()
	if char_name.is_empty():
		char_name = "Hero"

	var appearance := _get_appearance()

	if _is_online:
		OnlineManager.create_character(char_name, _selected_class as int, appearance)
	else:
		var slot := CharacterManager.get_next_free_slot()
		var data := CharacterData.create_new(char_name, _selected_class)
		data.save_slot = slot
		data.appearance = appearance
		CharacterManager.save_character(data)

	character_created.emit()
	_go_back()


func _on_back_pressed() -> void:
	_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_select.tscn")
