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


func _ready() -> void:
	respawn_button.pressed.connect(_on_respawn_pressed)


func set_player(player: Node) -> void:
	tracked_player = player
	_is_dead = false
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

	# Death detection
	if stats.health <= 0.0 and not _is_dead:
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


func _show_death_screen() -> void:
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	respawn_button.disabled = true
	respawn_button.text = "Respawn (%d)" % ceili(RESPAWN_DELAY)
	death_overlay.visible = true


func _on_respawn_pressed() -> void:
	if _respawn_timer > 0.0:
		return
	_is_dead = false
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
