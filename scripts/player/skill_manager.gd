extends Node
class_name SkillManager

## Manages a player's active skills, cooldowns, and execution.

signal skill_used(slot: int, skill: SkillData)
signal cooldown_updated(slot: int, remaining: float, total: float)

var skills: Array = [null, null, null, null]  # 4 skill slots
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var player: Node


func setup(p: Node) -> void:
	player = p
	# Assign default skills
	skills[0] = _create_fireball()
	skills[1] = _create_heal()
	skills[2] = _create_whirlwind()
	skills[3] = _create_frost_nova()


func _process(delta: float) -> void:
	for i in 4:
		if cooldowns[i] > 0.0:
			cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
			if skills[i]:
				cooldown_updated.emit(i, cooldowns[i], skills[i].cooldown)


func try_use_skill(slot: int, target_pos: Vector3) -> bool:
	if slot < 0 or slot >= 4:
		return false
	var skill: SkillData = skills[slot]
	if not skill:
		return false
	if cooldowns[slot] > 0.0:
		return false
	if not player or not player.get("stats"):
		return false

	# Server or owning client validates and consumes mana
	if player.is_multiplayer_authority() or multiplayer.is_server():
		var stats: PlayerStats = player.stats
		if not stats.use_mana(skill.mana_cost):
			if player.is_multiplayer_authority():
				EventBus.show_floating_text.emit(
					player.global_position + Vector3(0, 2.5, 0),
					"No Mana!",
					Color.DODGER_BLUE
				)
			return false

	cooldowns[slot] = skill.cooldown
	skill_used.emit(slot, skill)
	_execute_skill(skill, target_pos)
	return true


func _execute_skill(skill: SkillData, target_pos: Vector3) -> void:
	match skill.id:
		"fireball":
			_cast_fireball(skill, target_pos)
		"heal":
			_cast_heal(skill)
		"whirlwind":
			_cast_whirlwind(skill)
		"frost_nova":
			_cast_frost_nova(skill)


func _cast_fireball(skill: SkillData, target_pos: Vector3) -> void:
	EventBus.show_floating_text.emit(
		target_pos + Vector3(0, 1, 0),
		"FIREBALL",
		Color.ORANGE_RED
	)
	# Damage enemies near target position
	if not multiplayer.is_server():
		return
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(target_pos) <= skill.radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(skill.damage + player.stats.intelligence * 0.5, player)


func _cast_heal(skill: SkillData) -> void:
	if multiplayer.is_server():
		player.stats.heal(skill.damage + player.stats.intelligence * 0.3)
	EventBus.show_floating_text.emit(
		player.global_position + Vector3(0, 2.5, 0),
		"+%d HP" % int(skill.damage),
		Color.GREEN
	)


func _cast_whirlwind(skill: SkillData) -> void:
	EventBus.show_floating_text.emit(
		player.global_position + Vector3(0, 2, 0),
		"WHIRLWIND",
		Color.LIGHT_BLUE
	)
	if not multiplayer.is_server():
		return
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(player.global_position) <= skill.radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(skill.damage + player.stats.strength * 0.5, player)


func _cast_frost_nova(skill: SkillData) -> void:
	EventBus.show_floating_text.emit(
		player.global_position + Vector3(0, 2, 0),
		"FROST NOVA",
		Color.CYAN
	)
	if not multiplayer.is_server():
		return
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(player.global_position) <= skill.radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(skill.damage + player.stats.intelligence * 0.4, player)


func _create_fireball() -> SkillData:
	var s := SkillData.new()
	s.id = "fireball"
	s.display_name = "Fireball"
	s.description = "Hurl a ball of fire at a target area."
	s.target_type = SkillData.TargetType.POINT
	s.cooldown = 1.8
	s.mana_cost = 10.0
	s.damage = 28.0
	s.radius = 4.0
	s.range_dist = 12.0
	s.icon_color = Color.ORANGE_RED
	return s


func _create_heal() -> SkillData:
	var s := SkillData.new()
	s.id = "heal"
	s.display_name = "Heal"
	s.description = "Restore health."
	s.target_type = SkillData.TargetType.SELF
	s.cooldown = 5.0
	s.mana_cost = 12.0
	s.damage = 45.0  # Heal amount
	s.icon_color = Color.GREEN
	return s


func _create_whirlwind() -> SkillData:
	var s := SkillData.new()
	s.id = "whirlwind"
	s.display_name = "Whirlwind"
	s.description = "Spin and damage all nearby enemies."
	s.target_type = SkillData.TargetType.SELF
	s.cooldown = 2.5
	s.mana_cost = 8.0
	s.damage = 22.0
	s.radius = 4.5
	s.icon_color = Color.LIGHT_BLUE
	return s


func _create_frost_nova() -> SkillData:
	var s := SkillData.new()
	s.id = "frost_nova"
	s.display_name = "Frost Nova"
	s.description = "Blast frost in an area around you."
	s.target_type = SkillData.TargetType.SELF
	s.cooldown = 3.0
	s.mana_cost = 11.0
	s.damage = 26.0
	s.radius = 5.5
	s.icon_color = Color.CYAN
	return s
