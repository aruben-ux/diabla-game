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


func _ready() -> void:
	respawn_button.pressed.connect(_on_respawn_pressed)
	_build_target_panel()


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

	_target_name_label = Label.new()
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_target_name_label)

	_target_health_bar = ProgressBar.new()
	_target_health_bar.custom_minimum_size = Vector2(260, 16)
	_target_health_bar.show_percentage = false
	vbox.add_child(_target_health_bar)

	_target_health_label = Label.new()
	_target_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_health_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_target_health_label)

	_target_info_label = Label.new()
	_target_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_info_label.add_theme_font_size_override("font_size", 12)
	_target_info_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(_target_info_label)

	_target_panel.add_child(vbox)
	add_child(_target_panel)
	_target_panel.visible = false


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
