extends Control

## In-game HUD: health bar, mana bar, XP bar, skill slots, level display, death screen.

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var mana_bar: ProgressBar = $MarginContainer/VBoxContainer/ManaBar
@onready var xp_bar: ProgressBar = $MarginContainer/VBoxContainer/XPBar
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/Label
@onready var mana_label: Label = $MarginContainer/VBoxContainer/ManaBar/Label
@onready var skill_slots: Array[Node] = [
	$SkillBar/Skill1, $SkillBar/Skill2, $SkillBar/Skill3, $SkillBar/Skill4
]
@onready var health_potion_panel: Panel = $SkillBar/HealthPotion
@onready var mana_potion_panel: Panel = $SkillBar/ManaPotion
@onready var hp_potion_label: Label = $SkillBar/HealthPotion/Label
@onready var mp_potion_label: Label = $SkillBar/ManaPotion/Label
@onready var death_overlay: ColorRect = $DeathOverlay
@onready var respawn_button: Button = $DeathOverlay/VBox/RespawnButton

var tracked_player: Node = null

const RESPAWN_DELAY := 3.0
var _respawn_timer := 0.0
var _is_dead := false
var _waiting_for_respawn := false

# Target info panel (built in code)
var _target_panel: PanelContainer
var _target_name_label: Label
var _target_health_bar: ProgressBar
var _target_health_label: Label
var _target_info_label: Label

# NPC dialog panel (built in code)
var _dialog_panel: PanelContainer
var _dialog_name_label: Label
var _dialog_text_label: RichTextLabel
var _dialog_continue_btn: Button
var _dialog_close_btn: Button
var _dialog_lines: Array = []
var _dialog_index: int = 0

# Party panel (built in code, left side)
var _party_container: VBoxContainer
var _party_entries: Dictionary = {}  # peer_id -> Dictionary of controls
const DUNGEON_X_THRESHOLD := 250.0
const FLOOR_SPACING := 200.0

# Character panel (stats window)
var _char_panel: Panel
var _char_stat_labels: Dictionary = {}  # stat_name -> Label

# Action buttons (lower-right)
var _inventory_btn: Button
var _character_btn: Button
var _quest_btn: Button

# Quest log panel
var _quest_panel: Panel
var _quest_content: VBoxContainer
var _quest_scroll: ScrollContainer

# Quest dialog (NPC offering quests)
var _quest_dialog_panel: PanelContainer
var _quest_dialog_vbox: VBoxContainer
var _quest_dialog_npc_id: String = ""

# Skill tree UI
var _skill_tree_ui: SkillTreeUI
var _skill_btn: Button

# Cast bar
var _cast_bar_panel: PanelContainer
var _cast_bar_progress: ProgressBar
var _cast_bar_label: Label


func _ready() -> void:
	respawn_button.pressed.connect(_on_respawn_pressed)
	_build_target_panel()
	_build_dialog_panel()
	_build_party_panel()
	_build_character_panel()
	_build_action_buttons()
	_build_quest_panel()
	_build_quest_dialog_panel()
	_style_potion_panel(health_potion_panel, Color(0.8, 0.15, 0.15, 0.7))
	_style_potion_panel(mana_potion_panel, Color(0.15, 0.3, 0.8, 0.7))
	EventBus.npc_dialog_opened.connect(_on_npc_dialog_opened)
	EventBus.npc_dialog_closed.connect(_on_npc_dialog_closed)
	EventBus.quest_updated.connect(_refresh_quest_panel)
	EventBus.quest_dialog_requested.connect(_on_quest_dialog_requested)
	_build_skill_tree_ui()
	_build_cast_bar()


func _build_target_panel() -> void:
	_target_panel = PanelContainer.new()
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.offset_left = -150
	_target_panel.offset_right = 150
	_target_panel.offset_top = 10
	_target_panel.offset_bottom = 80
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.4, 0.3, 0.6)
	_target_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_target_name_label = Label.new()
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override("font_size", 16)
	_target_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_target_name_label)

	_target_health_bar = ProgressBar.new()
	_target_health_bar.custom_minimum_size = Vector2(260, 16)
	_target_health_bar.show_percentage = false
	_target_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_target_health_bar)

	_target_health_label = Label.new()
	_target_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_health_label.add_theme_font_size_override("font_size", 12)
	_target_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_target_health_label)

	_target_info_label = Label.new()
	_target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_info_label.add_theme_font_size_override("font_size", 12)
	_target_info_label.modulate = Color(0.7, 0.7, 0.7)
	_target_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_target_info_label)

	_target_panel.add_child(vbox)
	add_child(_target_panel)
	_target_panel.visible = false


func _build_dialog_panel() -> void:
	_dialog_panel = PanelContainer.new()
	_dialog_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog_panel.offset_left = -250
	_dialog_panel.offset_right = 250
	_dialog_panel.offset_top = -200
	_dialog_panel.offset_bottom = -20
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.5, 0.3, 0.8)
	_dialog_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	_dialog_name_label = Label.new()
	_dialog_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_name_label.add_theme_font_size_override("font_size", 20)
	_dialog_name_label.modulate = Color(0.95, 0.85, 0.55)
	vbox.add_child(_dialog_name_label)

	var sep := HSeparator.new()
	sep.modulate = Color(0.5, 0.4, 0.3, 0.5)
	vbox.add_child(sep)

	_dialog_text_label = RichTextLabel.new()
	_dialog_text_label.bbcode_enabled = true
	_dialog_text_label.fit_content = true
	_dialog_text_label.custom_minimum_size = Vector2(0, 80)
	_dialog_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialog_text_label.add_theme_font_size_override("normal_font_size", 16)
	_dialog_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_dialog_text_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)

	_dialog_continue_btn = Button.new()
	_dialog_continue_btn.text = tr("Continue")
	_dialog_continue_btn.custom_minimum_size = Vector2(100, 32)
	_dialog_continue_btn.pressed.connect(_on_dialog_continue)
	btn_row.add_child(_dialog_continue_btn)

	_dialog_close_btn = Button.new()
	_dialog_close_btn.text = tr("Close")
	_dialog_close_btn.custom_minimum_size = Vector2(80, 32)
	_dialog_close_btn.pressed.connect(_on_dialog_close)
	btn_row.add_child(_dialog_close_btn)

	vbox.add_child(btn_row)
	_dialog_panel.add_child(vbox)
	add_child(_dialog_panel)
	_dialog_panel.visible = false


func _on_npc_dialog_opened(npc_name: String, lines: Array) -> void:
	_dialog_lines = lines
	_dialog_index = 0
	_dialog_name_label.text = npc_name
	_show_dialog_line()
	_dialog_panel.visible = true


func _on_npc_dialog_closed() -> void:
	_dialog_panel.visible = false
	_dialog_lines = []
	_dialog_index = 0


func _show_dialog_line() -> void:
	if _dialog_index < _dialog_lines.size():
		_dialog_text_label.text = str(_dialog_lines[_dialog_index])
		_dialog_continue_btn.visible = _dialog_index < _dialog_lines.size() - 1
	else:
		_on_dialog_close()


func _on_dialog_continue() -> void:
	_dialog_index += 1
	EventBus.npc_dialog_advance.emit()
	_show_dialog_line()


func _on_dialog_close() -> void:
	_dialog_panel.visible = false
	_dialog_lines = []
	_dialog_index = 0
	EventBus.npc_dialog_closed.emit()


func _build_party_panel() -> void:
	_party_container = VBoxContainer.new()
	_party_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_party_container.offset_left = 10
	_party_container.offset_top = 10
	_party_container.offset_right = 200
	_party_container.add_theme_constant_override("separation", 6)
	_party_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_party_container)


func _update_party_panel() -> void:
	if not _party_container:
		return

	var players := get_tree().get_nodes_in_group("players")
	var seen_ids: Array[int] = []

	for p in players:
		if not is_instance_valid(p) or p == tracked_player:
			continue
		var peer_id := p.get_multiplayer_authority()
		seen_ids.append(peer_id)

		if peer_id not in _party_entries:
			_create_party_entry(peer_id, p)

		var entry: Dictionary = _party_entries[peer_id]
		if not is_instance_valid(entry.get("panel")):
			_party_entries.erase(peer_id)
			continue

		var p_name: String = p.get("player_name") if p.get("player_name") else tr("Player")
		var stats: PlayerStats = p.stats if p.get("stats") else null

		entry["name_label"].text = p_name
		if stats:
			entry["hp_bar"].max_value = stats.max_health
			entry["hp_bar"].value = stats.health
			entry["hp_label"].text = "%d/%d" % [int(stats.health), int(stats.max_health)]
			entry["mp_bar"].max_value = stats.max_mana
			entry["mp_bar"].value = stats.mana
			entry["mp_label"].text = "%d/%d" % [int(stats.mana), int(stats.max_mana)]
			entry["level_label"].text = tr("Lv %d") % stats.level

		# Derive location from world position
		var loc_text := tr("Town")
		if p.global_position.x > DUNGEON_X_THRESHOLD:
			var dz: float = p.global_position.z
			var floor_num := int(round(dz / FLOOR_SPACING)) + 1
			if floor_num < 1:
				floor_num = 1
			loc_text = tr("Floor %d") % floor_num
		entry["loc_label"].text = loc_text

	# Remove entries for players who left
	var to_remove: Array[int] = []
	for pid in _party_entries:
		if pid not in seen_ids:
			to_remove.append(pid)
	for pid in to_remove:
		var entry: Dictionary = _party_entries[pid]
		if is_instance_valid(entry.get("panel")):
			entry["panel"].queue_free()
		_party_entries.erase(pid)


func _create_party_entry(peer_id: int, player_node: Node) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(185, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.8)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.35, 0.3, 0.5)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Portrait (class icon with player's armor color)
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(36, 36)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_style := StyleBoxFlat.new()
	# Use player's armor color as the portrait background
	var armor_col := Color(0.25, 0.2, 0.35)
	var cls_id := 0
	var appearance: Dictionary = player_node.get("cached_appearance") if player_node.get("cached_appearance") else {}
	if appearance.size() > 0:
		var ac: Array = appearance.get("armor_color", [0.25, 0.2, 0.35])
		armor_col = Color(ac[0], ac[1], ac[2])
		cls_id = appearance.get("character_class", 0)
	portrait_style.bg_color = Color(armor_col.r * 0.5, armor_col.g * 0.5, armor_col.b * 0.5, 0.9)
	portrait_style.corner_radius_top_left = 4
	portrait_style.corner_radius_top_right = 4
	portrait_style.corner_radius_bottom_left = 4
	portrait_style.corner_radius_bottom_right = 4
	portrait_style.border_width_left = 1
	portrait_style.border_width_right = 1
	portrait_style.border_width_top = 1
	portrait_style.border_width_bottom = 1
	portrait_style.border_color = Color(armor_col.r, armor_col.g, armor_col.b, 0.8)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	var portrait_label := Label.new()
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.add_theme_font_size_override("font_size", 18)
	portrait_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Class icon: ⚔ Warrior, ✦ Mage, ⚡ Rogue
	var class_icons := ["⚔", "✦", "⚡"]
	portrait_label.text = class_icons[cls_id] if cls_id < class_icons.size() else "?"
	portrait_label.add_theme_color_override("font_color", armor_col.lightened(0.3))
	portrait.add_child(portrait_label)
	hbox.add_child(portrait)

	# Info column
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 1)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Name + level row
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_name_str: String = player_node.get("player_name") if player_node.get("player_name") else tr("Player")
	name_label.text = p_name_str
	name_row.add_child(name_label)

	var level_label := Label.new()
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.modulate = Color(0.7, 0.7, 0.7)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.text = tr("Lv %d") % 1
	name_row.add_child(level_label)
	info_vbox.add_child(name_row)

	# HP bar
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(80, 10)
	hp_bar.show_percentage = false
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = Color(0.7, 0.15, 0.15, 0.9)
	hp_bar.add_theme_stylebox_override("fill", hp_style)
	hp_row.add_child(hp_bar)
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.custom_minimum_size = Vector2(55, 0)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_label)
	info_vbox.add_child(hp_row)

	# MP bar
	var mp_row := HBoxContainer.new()
	mp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mp_bar := ProgressBar.new()
	mp_bar.custom_minimum_size = Vector2(80, 10)
	mp_bar.show_percentage = false
	mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mp_style := StyleBoxFlat.new()
	mp_style.bg_color = Color(0.15, 0.25, 0.7, 0.9)
	mp_bar.add_theme_stylebox_override("fill", mp_style)
	mp_row.add_child(mp_bar)
	var mp_label := Label.new()
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.custom_minimum_size = Vector2(55, 0)
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_row.add_child(mp_label)
	info_vbox.add_child(mp_row)

	# Location
	var loc_label := Label.new()
	loc_label.add_theme_font_size_override("font_size", 10)
	loc_label.modulate = Color(0.6, 0.7, 0.6)
	loc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loc_label.text = tr("Town")
	info_vbox.add_child(loc_label)

	hbox.add_child(info_vbox)
	panel.add_child(hbox)
	_party_container.add_child(panel)

	_party_entries[peer_id] = {
		"panel": panel,
		"portrait_label": portrait_label,
		"name_label": name_label,
		"level_label": level_label,
		"hp_bar": hp_bar,
		"hp_label": hp_label,
		"mp_bar": mp_bar,
		"mp_label": mp_label,
		"loc_label": loc_label,
	}


func _build_cast_bar() -> void:
	_cast_bar_panel = PanelContainer.new()
	_cast_bar_panel.set_anchors_preset(Control.PRESET_CENTER)
	_cast_bar_panel.offset_left = -120
	_cast_bar_panel.offset_right = 120
	_cast_bar_panel.offset_top = 60
	_cast_bar_panel.offset_bottom = 100
	_cast_bar_panel.visible = false
	_cast_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	sb.border_color = Color(0.3, 0.5, 1.0, 0.8)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_cast_bar_panel.add_theme_stylebox_override("panel", sb)
	add_child(_cast_bar_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_bar_panel.add_child(vbox)

	_cast_bar_label = Label.new()
	_cast_bar_label.text = tr("Town Portal")
	_cast_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_bar_label.add_theme_font_size_override("font_size", 12)
	_cast_bar_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	_cast_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cast_bar_label)

	_cast_bar_progress = ProgressBar.new()
	_cast_bar_progress.min_value = 0.0
	_cast_bar_progress.max_value = 1.0
	_cast_bar_progress.value = 0.0
	_cast_bar_progress.custom_minimum_size = Vector2(220, 14)
	_cast_bar_progress.show_percentage = false
	_cast_bar_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Color(0.2, 0.4, 1.0, 0.9)
	fill_sb.corner_radius_top_left = 3
	fill_sb.corner_radius_top_right = 3
	fill_sb.corner_radius_bottom_left = 3
	fill_sb.corner_radius_bottom_right = 3
	_cast_bar_progress.add_theme_stylebox_override("fill", fill_sb)

	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	bg_sb.corner_radius_top_left = 3
	bg_sb.corner_radius_top_right = 3
	bg_sb.corner_radius_bottom_left = 3
	bg_sb.corner_radius_bottom_right = 3
	_cast_bar_progress.add_theme_stylebox_override("background", bg_sb)

	vbox.add_child(_cast_bar_progress)


func _update_cast_bar() -> void:
	if not tracked_player or not is_instance_valid(tracked_player):
		_cast_bar_panel.visible = false
		return
	if tracked_player._tp_casting:
		_cast_bar_panel.visible = true
		var elapsed: float = tracked_player.TP_CAST_TIME - tracked_player._tp_cast_timer
		_cast_bar_progress.value = elapsed / tracked_player.TP_CAST_TIME
	else:
		_cast_bar_panel.visible = false


func _style_potion_panel(panel: Panel, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)


func set_player(player: Node) -> void:
	tracked_player = player
	_is_dead = false
	_waiting_for_respawn = false
	death_overlay.visible = false
	if player and player.skill_manager:
		player.skill_manager.cooldown_updated.connect(_on_cooldown_updated)
		player.skill_manager.skill_tree_changed.connect(_refresh_skill_slots)
		_refresh_skill_slots()


func _process(delta: float) -> void:
	if not tracked_player or not is_instance_valid(tracked_player):
		return

	var stats: PlayerStats = tracked_player.stats
	if not stats:
		return

	health_bar.max_value = stats.max_health
	health_bar.value = stats.health
	health_label.text = "%d / %d" % [int(stats.health), int(stats.max_health)]

	mana_bar.max_value = stats.max_mana
	mana_bar.value = stats.mana
	mana_label.text = "%d / %d" % [int(stats.mana), int(stats.max_mana)]

	xp_bar.max_value = stats.experience_to_next_level
	xp_bar.value = stats.experience

	level_label.text = tr("Level %d") % stats.level

	# Update potion counts
	var inv: Inventory = tracked_player.inventory
	if inv:
		hp_potion_label.text = "Q\n%d" % inv.health_potions
		mp_potion_label.text = "E\n%d" % inv.mana_potions

	# Respawn completed — health restored by server
	if _is_dead and stats.health > 0.0:
		_is_dead = false
		_waiting_for_respawn = false
		death_overlay.visible = false

	# Death detection
	if stats.health <= 0.0 and not _is_dead and not _waiting_for_respawn:
		_show_death_screen()
	
	# Respawn countdown
	if _is_dead:
		_respawn_timer -= delta
		if _respawn_timer > 0.0:
			respawn_button.text = tr("Respawn (%d)") % ceili(_respawn_timer)
			respawn_button.disabled = true
		else:
			respawn_button.text = tr("Respawn")
			respawn_button.disabled = false

	# Update target info
	_update_target_display()
	_update_party_panel()
	_update_character_panel()
	_update_cast_bar()


func _update_target_display() -> void:
	if not tracked_player or not is_instance_valid(tracked_player):
		_target_panel.visible = false
		return

	var target_node = tracked_player.get("current_target")
	if target_node == null or not is_instance_valid(target_node):
		_target_panel.visible = false
		return

	_target_panel.visible = true

	if target_node is Enemy:
		var enemy: Enemy = target_node
		var type_key: String = Enemy.EnemyType.keys()[enemy.enemy_type]
		_target_name_label.text = tr(type_key.capitalize())
		_target_health_bar.visible = true
		_target_health_bar.max_value = enemy.max_health
		_target_health_bar.value = enemy.health
		_target_health_label.visible = true
		_target_health_label.text = "%d / %d" % [int(enemy.health), int(enemy.max_health)]
		_target_info_label.text = tr("Level %d") % enemy.floor_level
	elif target_node.is_in_group("players"):
		var p_name: String = target_node.get("player_name") if target_node.get("player_name") else tr("Player")
		_target_name_label.text = p_name
		var p_stats: PlayerStats = target_node.stats
		_target_health_bar.visible = true
		_target_health_bar.max_value = p_stats.max_health
		_target_health_bar.value = p_stats.health
		_target_health_label.visible = true
		_target_health_label.text = "%d / %d" % [int(p_stats.health), int(p_stats.max_health)]
		_target_info_label.text = tr("Level %d") % p_stats.level
	elif target_node.is_in_group("interactables"):
		_target_name_label.text = target_node.get("display_name") if target_node.get("display_name") else tr("Object")
		_target_health_bar.visible = false
		_target_health_label.visible = false
		var hint: String = target_node.get("interact_hint") if target_node.get("interact_hint") else ""
		_target_info_label.text = hint


func _show_death_screen() -> void:
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	respawn_button.disabled = true
	respawn_button.text = tr("Respawn (%d)") % ceili(RESPAWN_DELAY)
	death_overlay.visible = true


func _on_respawn_pressed() -> void:
	if _respawn_timer > 0.0:
		return
	_waiting_for_respawn = true
	death_overlay.visible = false
	if tracked_player and is_instance_valid(tracked_player):
		tracked_player.request_respawn()


func _on_cooldown_updated(slot: int, remaining: float, total: float) -> void:
	if slot < 0 or slot >= skill_slots.size():
		return
	var panel: Panel = skill_slots[slot]
	if not panel:
		return
	# Darken panel when on cooldown
	if remaining > 0.0:
		panel.modulate = Color(0.4, 0.4, 0.4)
	else:
		panel.modulate = Color.WHITE


## ─── CHARACTER PANEL ───

func _build_character_panel() -> void:
	_char_panel = Panel.new()
	_char_panel.name = "CharacterPanel"
	var panel_w := 280
	var panel_h := 420
	_char_panel.size = Vector2(panel_w, panel_h)
	_char_panel.position = Vector2(
		16,
		get_viewport_rect().size.y - panel_h - 60
	)
	_char_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_char_panel.z_index = 5

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.35, 0.2)
	_char_panel.add_theme_stylebox_override("panel", sb)
	add_child(_char_panel)

	# Title
	var title := Label.new()
	title.text = tr("Character")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 6)
	title.size = Vector2(panel_w, 20)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_char_panel.add_child(title)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(panel_w - 30, 4)
	close_btn.size = Vector2(24, 24)
	close_btn.pressed.connect(_toggle_character_panel)
	_char_panel.add_child(close_btn)

	# Stats list
	var y_offset := 34
	var line_h := 22
	var stats_list := [
		["name", "Name"],
		["class", "Class"],
		["level", "Level"],
		["experience", "Experience"],
		["sep1", ""],
		["health", "Health"],
		["mana", "Mana"],
		["sep2", ""],
		["strength", "Strength"],
		["dexterity", "Dexterity"],
		["intelligence", "Intelligence"],
		["vitality", "Vitality"],
		["sep3", ""],
		["attack_damage", "Attack Damage"],
		["attack_speed", "Attack Speed"],
		["defense", "Defense"],
		["move_speed", "Move Speed"],
	]

	for entry in stats_list:
		var key: String = entry[0]
		var label_text: String = entry[1]

		if key.begins_with("sep"):
			# Separator line
			var sep := HSeparator.new()
			sep.position = Vector2(12, y_offset + 4)
			sep.size = Vector2(panel_w - 24, 2)
			sep.modulate = Color(0.4, 0.35, 0.3, 0.5)
			_char_panel.add_child(sep)
			y_offset += 12
			continue

		# Label on the left
		var name_lbl := Label.new()
		name_lbl.text = tr(label_text)
		name_lbl.position = Vector2(16, y_offset)
		name_lbl.size = Vector2(140, line_h)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_char_panel.add_child(name_lbl)

		# Value on the right
		var val_lbl := Label.new()
		val_lbl.text = "—"
		val_lbl.position = Vector2(140, y_offset)
		val_lbl.size = Vector2(panel_w - 156, line_h)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_char_panel.add_child(val_lbl)
		_char_stat_labels[key] = val_lbl

		y_offset += line_h

	_char_panel.visible = false


func _update_character_panel() -> void:
	if not _char_panel or not _char_panel.visible:
		return
	if not tracked_player or not is_instance_valid(tracked_player):
		return

	var s: PlayerStats = tracked_player.stats
	if not s:
		return

	_set_stat("name", tracked_player.player_name)

	var char_class_name := tr("Unknown")
	if CharacterManager.active_character:
		var cc = CharacterManager.active_character.character_class
		char_class_name = tr(CharacterData.class_name_from_enum(cc))
	_set_stat("class", char_class_name)

	_set_stat("level", str(s.level))
	_set_stat("experience", "%d / %d" % [int(s.experience), int(s.experience_to_next_level)])
	_set_stat("health", "%d / %d" % [int(s.health), int(s.max_health)])
	_set_stat("mana", "%d / %d" % [int(s.mana), int(s.max_mana)])
	_set_stat("strength", str(s.strength))
	_set_stat("dexterity", str(s.dexterity))
	_set_stat("intelligence", str(s.intelligence))
	_set_stat("vitality", str(s.vitality))
	_set_stat("attack_damage", "%.1f" % s.attack_damage)
	_set_stat("attack_speed", "%.2f" % s.attack_speed)
	_set_stat("defense", "%.1f" % s.defense)
	_set_stat("move_speed", "%.1f" % s.move_speed)


func _set_stat(key: String, value: String) -> void:
	if key in _char_stat_labels:
		_char_stat_labels[key].text = value


func _toggle_character_panel() -> void:
	if _char_panel:
		_char_panel.visible = not _char_panel.visible


## ─── ACTION BUTTONS ───

func _build_action_buttons() -> void:
	var btn_container := HBoxContainer.new()
	btn_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn_container.offset_left = -350
	btn_container.offset_top = -52
	btn_container.offset_right = -16
	btn_container.offset_bottom = -16
	btn_container.add_theme_constant_override("separation", 8)
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	add_child(btn_container)

	_character_btn = _create_action_button(tr("Character") + "\n(C)", btn_container)
	_character_btn.pressed.connect(_toggle_character_panel)

	_skill_btn = _create_action_button(tr("Skills") + "\n(K)", btn_container)
	_skill_btn.pressed.connect(_toggle_skill_tree)

	_inventory_btn = _create_action_button(tr("Inventory") + "\n(I)", btn_container)
	_inventory_btn.pressed.connect(_on_inventory_btn_pressed)

	_quest_btn = _create_action_button(tr("Quests") + "\n(L)", btn_container)
	_quest_btn.pressed.connect(_toggle_quest_panel)


func _create_action_button(text: String, parent: Control) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(76, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.13, 0.18, 0.9)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.5, 0.4, 0.3, 0.7)
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb := sb.duplicate()
	hover_sb.bg_color = Color(0.22, 0.18, 0.26, 0.95)
	btn.add_theme_stylebox_override("hover", hover_sb)
	var pressed_sb := sb.duplicate()
	pressed_sb.bg_color = Color(0.1, 0.08, 0.12, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.add_theme_font_size_override("font_size", 12)
	parent.add_child(btn)
	return btn


func _on_inventory_btn_pressed() -> void:
	# Toggle inventory via the same input action
	var ev := InputEventAction.new()
	ev.action = "toggle_inventory"
	ev.pressed = true
	Input.parse_input_event(ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character"):
		_toggle_character_panel()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("toggle_quests"):
		_toggle_quest_panel()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		_toggle_skill_tree()
		get_viewport().set_input_as_handled()


## ─── QUEST LOG PANEL ───

func _build_quest_panel() -> void:
	_quest_panel = Panel.new()
	_quest_panel.name = "QuestPanel"
	var panel_w := 300
	var panel_h := 420
	_quest_panel.size = Vector2(panel_w, panel_h)
	_quest_panel.position = Vector2(
		16,
		get_viewport_rect().size.y - panel_h - 60
	)
	_quest_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_quest_panel.z_index = 5

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.35, 0.2)
	_quest_panel.add_theme_stylebox_override("panel", sb)
	add_child(_quest_panel)

	# Title
	var title := Label.new()
	title.text = tr("Quest Log")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 6)
	title.size = Vector2(panel_w, 20)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_quest_panel.add_child(title)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(panel_w - 30, 4)
	close_btn.size = Vector2(24, 24)
	close_btn.pressed.connect(_toggle_quest_panel)
	_quest_panel.add_child(close_btn)

	# Scrollable content area
	_quest_scroll = ScrollContainer.new()
	_quest_scroll.position = Vector2(8, 32)
	_quest_scroll.size = Vector2(panel_w - 16, panel_h - 40)
	_quest_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_quest_panel.add_child(_quest_scroll)

	_quest_content = VBoxContainer.new()
	_quest_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_content.add_theme_constant_override("separation", 8)
	_quest_scroll.add_child(_quest_content)

	_quest_panel.visible = false


func _toggle_quest_panel() -> void:
	if _quest_panel:
		_quest_panel.visible = not _quest_panel.visible
		if _quest_panel.visible:
			_refresh_quest_panel()


func _refresh_quest_panel() -> void:
	if not _quest_panel or not _quest_content:
		return
	# Clear existing entries
	for child in _quest_content.get_children():
		child.queue_free()

	var active := QuestManager.get_active_quests()
	var completed: Array[QuestData] = []
	for qid in QuestManager.quests:
		var q: QuestData = QuestManager.quests[qid]
		if q.status == QuestData.QuestStatus.COMPLETED:
			completed.append(q)

	if active.size() == 0 and completed.size() == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = tr("No active quests.\nTalk to NPCs in town to find quests.")
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_quest_content.add_child(empty_lbl)
		return

	for q in active:
		_add_quest_entry(q, Color(0.9, 0.85, 0.6))
	for q in completed:
		_add_quest_entry(q, Color(0.4, 0.9, 0.4))


func _add_quest_entry(q: QuestData, title_color: Color) -> void:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)

	var title_lbl := Label.new()
	title_lbl.text = tr(q.title)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", title_color)
	entry.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = tr(q.description)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	entry.add_child(desc_lbl)

	var progress_lbl := Label.new()
	if q.status == QuestData.QuestStatus.COMPLETED:
		progress_lbl.text = tr("COMPLETE — Return to NPC")
		progress_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	else:
		progress_lbl.text = tr("Progress: %d / %d") % [q.current_count, q.target_count]
		progress_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	progress_lbl.add_theme_font_size_override("font_size", 12)
	entry.add_child(progress_lbl)

	var reward_lbl := Label.new()
	reward_lbl.text = tr("Rewards: %d Gold, %d XP") % [q.reward_gold, int(q.reward_xp)]
	reward_lbl.add_theme_font_size_override("font_size", 11)
	reward_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	entry.add_child(reward_lbl)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.35, 0.3, 0.4)
	entry.add_child(sep)

	_quest_content.add_child(entry)


## ─── QUEST NPC DIALOG ───

func _build_quest_dialog_panel() -> void:
	_quest_dialog_panel = PanelContainer.new()
	_quest_dialog_panel.set_anchors_preset(Control.PRESET_CENTER)
	_quest_dialog_panel.offset_left = -220
	_quest_dialog_panel.offset_right = 220
	_quest_dialog_panel.offset_top = -180
	_quest_dialog_panel.offset_bottom = 180
	_quest_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_quest_dialog_panel.z_index = 20

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.5, 0.3, 0.8)
	_quest_dialog_panel.add_theme_stylebox_override("panel", style)

	_quest_dialog_vbox = VBoxContainer.new()
	_quest_dialog_vbox.add_theme_constant_override("separation", 8)
	_quest_dialog_panel.add_child(_quest_dialog_vbox)

	add_child(_quest_dialog_panel)
	_quest_dialog_panel.visible = false


func _on_quest_dialog_requested(npc_id: String) -> void:
	_quest_dialog_npc_id = npc_id
	_populate_quest_dialog(npc_id)


func _populate_quest_dialog(npc_id: String) -> void:
	# Clear old content
	for child in _quest_dialog_vbox.get_children():
		child.queue_free()

	var available := QuestManager.get_available_quests(npc_id)
	var turn_in := QuestManager.get_turn_in_quests(npc_id)

	if available.size() == 0 and turn_in.size() == 0:
		_quest_dialog_panel.visible = false
		return

	# Title
	var title := Label.new()
	title.text = tr("Quests")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_quest_dialog_vbox.add_child(title)

	# Turn-in quests first
	for q in turn_in:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)

		var q_title := Label.new()
		q_title.text = tr(q.title) + "  " + tr("[COMPLETE]")
		q_title.add_theme_font_size_override("font_size", 14)
		q_title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		entry.add_child(q_title)

		var reward := Label.new()
		reward.text = tr("Rewards: %d Gold, %d XP") % [q.reward_gold, int(q.reward_xp)]
		reward.add_theme_font_size_override("font_size", 12)
		reward.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
		entry.add_child(reward)

		var btn := Button.new()
		btn.text = tr("Turn In")
		btn.custom_minimum_size = Vector2(100, 28)
		var qid := q.quest_id
		btn.pressed.connect(_on_turn_in_pressed.bind(qid))
		entry.add_child(btn)

		var sep := HSeparator.new()
		sep.modulate = Color(0.4, 0.35, 0.3, 0.4)
		entry.add_child(sep)
		_quest_dialog_vbox.add_child(entry)

	# Available quests
	for q in available:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 4)

		var q_title := Label.new()
		q_title.text = tr(q.title)
		q_title.add_theme_font_size_override("font_size", 14)
		q_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		entry.add_child(q_title)

		var desc := Label.new()
		desc.text = tr(q.description)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		entry.add_child(desc)

		var reward := Label.new()
		reward.text = tr("Rewards: %d Gold, %d XP") % [q.reward_gold, int(q.reward_xp)]
		reward.add_theme_font_size_override("font_size", 12)
		reward.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
		entry.add_child(reward)

		var btn := Button.new()
		btn.text = tr("Accept")
		btn.custom_minimum_size = Vector2(100, 28)
		var qid := q.quest_id
		btn.pressed.connect(_on_accept_pressed.bind(qid))
		entry.add_child(btn)

		var sep := HSeparator.new()
		sep.modulate = Color(0.4, 0.35, 0.3, 0.4)
		entry.add_child(sep)
		_quest_dialog_vbox.add_child(entry)

	# Close button
	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.custom_minimum_size = Vector2(80, 28)
	close_btn.pressed.connect(func(): _quest_dialog_panel.visible = false)
	_quest_dialog_vbox.add_child(close_btn)

	_quest_dialog_panel.visible = true


func _on_accept_pressed(quest_id: String) -> void:
	QuestManager.accept_quest(quest_id)
	_sync_quests()
	# Refresh the dialog
	_populate_quest_dialog(_quest_dialog_npc_id)


func _on_turn_in_pressed(quest_id: String) -> void:
	var rewards := QuestManager.turn_in_quest(quest_id)
	if rewards.is_empty():
		return
	# Give rewards to player
	if tracked_player and is_instance_valid(tracked_player):
		tracked_player.inventory.gold += rewards["gold"]
		tracked_player.inventory.gold_changed.emit(tracked_player.inventory.gold)
		tracked_player.grant_xp(rewards["xp"])
		if tracked_player.has_method("sync_gold_to_server"):
			tracked_player.sync_gold_to_server()
		EventBus.show_floating_text.emit(
			tracked_player.global_position + Vector3(0, 2, 0),
			tr("Quest Complete! +%d Gold +%d XP") % [rewards["gold"], int(rewards["xp"])],
			Color.GOLD
		)
	# Refresh dialog — may close if no more quests
	_populate_quest_dialog(_quest_dialog_npc_id)
	_sync_quests()


func _sync_quests() -> void:
	if tracked_player and is_instance_valid(tracked_player):
		if tracked_player.has_method("sync_quests_to_server"):
			tracked_player.sync_quests_to_server()


## ─── SKILL TREE ───

func _build_skill_tree_ui() -> void:
	_skill_tree_ui = SkillTreeUI.new()
	_skill_tree_ui.z_index = 30
	add_child(_skill_tree_ui)


func _toggle_skill_tree() -> void:
	if not _skill_tree_ui:
		return
	if _skill_tree_ui.visible:
		_skill_tree_ui.close()
	else:
		if tracked_player and tracked_player.skill_manager:
			_skill_tree_ui.open(tracked_player.skill_manager)


func _refresh_skill_slots() -> void:
	if not tracked_player or not tracked_player.skill_manager:
		return
	for i in 4:
		var skill: SkillData = tracked_player.skill_manager.skills[i]
		if skill and i < skill_slots.size() and skill_slots[i]:
			skill_slots[i].get_node("Label").text = skill.display_name.left(4)
		elif i < skill_slots.size() and skill_slots[i]:
			skill_slots[i].get_node("Label").text = "—"
