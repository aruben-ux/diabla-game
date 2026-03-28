extends Control

## In-game HUD: health bar, mana bar, XP bar, skill slots, level display.

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var mana_bar: ProgressBar = $MarginContainer/VBoxContainer/ManaBar
@onready var xp_bar: ProgressBar = $MarginContainer/VBoxContainer/XPBar
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/Label
@onready var mana_label: Label = $MarginContainer/VBoxContainer/ManaBar/Label
@onready var skill_slots: Array[Node] = [
	$SkillBar/Skill1, $SkillBar/Skill2, $SkillBar/Skill3, $SkillBar/Skill4
]

var tracked_player: Node = null


func set_player(player: Node) -> void:
	tracked_player = player
	# Connect skill cooldown updates
	if player and player.skill_manager:
		player.skill_manager.cooldown_updated.connect(_on_cooldown_updated)
		# Set initial skill names
		for i in 4:
			var skill: SkillData = player.skill_manager.skills[i]
			if skill and skill_slots[i]:
				skill_slots[i].get_node("Label").text = skill.display_name.left(4)


func _process(_delta: float) -> void:
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
