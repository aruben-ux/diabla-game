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


func _ready() -> void:
	respawn_button.pressed.connect(_on_respawn_pressed)
	_build_target_panel()
	_build_dialog_panel()
	_style_potion_panel(health_potion_panel, Color(0.8, 0.15, 0.15, 0.7))
	_style_potion_panel(mana_potion_panel, Color(0.15, 0.3, 0.8, 0.7))
	EventBus.npc_dialog_opened.connect(_on_npc_dialog_opened)
	EventBus.npc_dialog_closed.connect(_on_npc_dialog_closed)


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
	_dialog_continue_btn.text = "Continue"
	_dialog_continue_btn.custom_minimum_size = Vector2(100, 32)
	_dialog_continue_btn.pressed.connect(_on_dialog_continue)
	btn_row.add_child(_dialog_continue_btn)

	_dialog_close_btn = Button.new()
	_dialog_close_btn.text = "Close"
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
		for i in 4:
			var skill: SkillData = player.skill_manager.skills[i]
			if skill and skill_slots[i]:
				skill_slots[i].get_node("Label").text = skill.display_name.left(4)


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

	level_label.text = "Level %d" % stats.level

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
			respawn_button.text = "Respawn (%d)" % ceili(_respawn_timer)
			respawn_button.disabled = true
		else:
			respawn_button.text = "Respawn"
			respawn_button.disabled = false

	# Update target info
	_update_target_display()


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
		_target_name_label.text = type_key.capitalize()
		_target_health_bar.visible = true
		_target_health_bar.max_value = enemy.max_health
		_target_health_bar.value = enemy.health
		_target_health_label.visible = true
		_target_health_label.text = "%d / %d" % [int(enemy.health), int(enemy.max_health)]
		_target_info_label.text = "Level %d" % enemy.floor_level
	elif target_node.is_in_group("players"):
		var p_name: String = target_node.get("player_name") if target_node.get("player_name") else "Player"
		_target_name_label.text = p_name
		var p_stats: PlayerStats = target_node.stats
		_target_health_bar.visible = true
		_target_health_bar.max_value = p_stats.max_health
		_target_health_bar.value = p_stats.health
		_target_health_label.visible = true
		_target_health_label.text = "%d / %d" % [int(p_stats.health), int(p_stats.max_health)]
		_target_info_label.text = "Level %d" % p_stats.level
	elif target_node.is_in_group("interactables"):
		_target_name_label.text = target_node.get("display_name") if target_node.get("display_name") else "Object"
		_target_health_bar.visible = false
		_target_health_label.visible = false
		var hint: String = target_node.get("interact_hint") if target_node.get("interact_hint") else ""
		_target_info_label.text = hint


func _show_death_screen() -> void:
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	respawn_button.disabled = true
	respawn_button.text = "Respawn (%d)" % ceili(RESPAWN_DELAY)
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
