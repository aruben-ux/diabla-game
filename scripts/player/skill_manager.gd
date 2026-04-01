extends Node
class_name SkillManager

## Manages a player's skill tree, active skill slots, cooldowns, and execution.

signal skill_used(slot: int, skill: SkillData)
signal cooldown_updated(slot: int, remaining: float, total: float)
signal skill_tree_changed()

var skills: Array = [null, null, null, null]  # 4 skill slots
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var player: Node

# Skill tree state: node_id -> allocated rank
var allocated_points: Dictionary = {}
var skill_points: int = 0
var character_class: int = 0  # CharacterData.CharacterClass enum

static var _game_data: Dictionary = {}
static var _game_data_loaded := false


static func _load_game_data() -> void:
	if _game_data_loaded:
		return
	_game_data_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_game_data = json.data
		file.close()


func setup(p: Node) -> void:
	player = p
	# Load class + tree state from character data
	if player.get("character_class") != null:
		character_class = player.character_class
	_load_tree_from_character()
	_apply_passive_bonuses()
	_rebuild_skill_slots()


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
		var actual_cost := skill.mana_cost * (1.0 - stats.mana_cost_reduction_pct)
		if not stats.use_mana(actual_cost):
			if player.is_multiplayer_authority():
				EventBus.show_floating_text.emit(
					player.global_position + Vector3(0, 2.5, 0),
					tr("No Mana!"),
					Color.DODGER_BLUE
				)
			return false

	cooldowns[slot] = skill.cooldown
	skill_used.emit(slot, skill)
	_execute_skill(skill, target_pos)
	return true


func _execute_skill(skill: SkillData, target_pos: Vector3) -> void:
	var cast_pos: Vector3
	if skill.target_type == SkillData.TargetType.SELF:
		cast_pos = player.global_position
	else:
		cast_pos = target_pos

	# Show skill name
	EventBus.show_floating_text.emit(
		cast_pos + Vector3(0, 1.5, 0),
		tr(skill.display_name).to_upper(),
		skill.icon_color
	)

	var stats: PlayerStats = player.stats
	var is_server := multiplayer.is_server()

	match skill.id:
		# ── SHARED ──
		"heal":
			if is_server:
				stats.heal(skill.damage + stats.intelligence * 0.3)
			EventBus.show_floating_text.emit(
				player.global_position + Vector3(0, 2.5, 0),
				tr("+%d HP") % int(skill.damage + stats.intelligence * 0.3),
				Color.GREEN
			)

		"teleport", "shadow_step":
			if is_server:
				player.global_position = target_pos

		# ── WARRIOR: ARMS ──
		"cleave":
			# Wide arc attack — hits all enemies in a larger-than-normal cone
			if is_server:
				var dmg := skill.damage + stats.strength * 0.5
				_aoe_damage(cast_pos, skill.radius, dmg)

		"whirlwind":
			# Spinning AoE around player
			if is_server:
				var dmg := skill.damage + stats.strength * 0.5
				_aoe_damage(player.global_position, skill.radius, dmg)

		# ── WARRIOR: VALOR ──
		"shield_wall":
			# Block all damage for duration
			if is_server:
				player._buff_invulnerable = true
				player.add_buff("shield_wall", "Shield Wall", skill.duration, Color(0.7, 0.7, 0.8))

		"ground_slam":
			# AoE damage + slow enemies
			if is_server:
				var dmg := skill.damage + stats.strength * 0.5
				for enemy in player.get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(enemy):
						continue
					var dist: float = enemy.global_position.distance_to(player.global_position)
					if dist <= skill.radius and enemy.has_method("take_damage"):
						enemy.take_damage(dmg, player)
						# Slow enemy
						enemy.move_speed *= 0.5
						player.get_tree().create_timer(2.0).timeout.connect(func() -> void:
							if is_instance_valid(enemy):
								enemy.move_speed *= 2.0
						)

		# ── WARRIOR: WARCRY ──
		"war_cry":
			# Boost all nearby allied players' damage
			if is_server:
				player._buff_damage_mult += 0.3
				player.add_buff("war_cry", "War Cry", skill.duration, Color(1.0, 0.8, 0.2))
				# Also buff nearby players
				for p in player.get_tree().get_nodes_in_group("players"):
					if p != player and is_instance_valid(p) and p.global_position.distance_to(player.global_position) <= 10.0:
						p._buff_damage_mult += 0.3
						p.add_buff("war_cry", "War Cry", skill.duration, Color(1.0, 0.8, 0.2))

		"charge":
			# Rush to target + AoE damage on arrival
			if is_server:
				player.global_position = target_pos
				var dmg := skill.damage + stats.strength * 0.5
				_aoe_damage(target_pos, skill.radius, dmg)
				# Slow enemies hit
				for enemy in player.get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(enemy):
						continue
					if enemy.global_position.distance_to(target_pos) <= skill.radius:
						enemy.move_speed *= 0.4
						player.get_tree().create_timer(1.5).timeout.connect(func() -> void:
							if is_instance_valid(enemy):
								enemy.move_speed /= 0.4
						)

		"berserker_rage":
			# Massive self damage buff
			if is_server:
				player._buff_damage_mult += 0.5
				player.add_buff("berserker_rage", "Berserker Rage", skill.duration, Color(0.9, 0.2, 0.1))

		# ── MAGE: FIRE ──
		"fireball":
			if is_server:
				var dmg := skill.damage + stats.intelligence * 0.5
				dmg *= 1.0 + stats.spell_damage_pct
				_aoe_damage(cast_pos, skill.radius, dmg)

		"fire_wall":
			# Persistent damage zone — simplified as 3 quick ticks
			if is_server:
				var dmg := (skill.damage + stats.intelligence * 0.3) * (1.0 + stats.spell_damage_pct)
				for tick in range(5):
					player.get_tree().create_timer(float(tick) * 1.0).timeout.connect(func() -> void:
						if not is_instance_valid(player):
							return
						_aoe_damage(cast_pos, skill.radius, dmg * 0.4)
					)

		"meteor":
			# Delayed massive impact
			if is_server:
				var dmg := (skill.damage + stats.intelligence * 0.6) * (1.0 + stats.spell_damage_pct)
				# Impact after 0.6s delay
				player.get_tree().create_timer(0.6).timeout.connect(func() -> void:
					if not is_instance_valid(player):
						return
					_aoe_damage(cast_pos, skill.radius, dmg)
				)

		# ── MAGE: FROST ──
		"frost_nova":
			if is_server:
				var dmg := (skill.damage + stats.intelligence * 0.4) * (1.0 + stats.spell_damage_pct)
				for enemy in player.get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(enemy):
						continue
					var dist: float = enemy.global_position.distance_to(player.global_position)
					if dist <= skill.radius and enemy.has_method("take_damage"):
						enemy.take_damage(dmg, player)
						enemy.move_speed *= 0.4
						player.get_tree().create_timer(3.0).timeout.connect(func() -> void:
							if is_instance_valid(enemy):
								enemy.move_speed /= 0.4
						)

		"ice_barrier":
			# Absorb shield
			if is_server:
				var absorb_amount := 50.0 + stats.intelligence * 1.0
				player._buff_absorb = absorb_amount
				player.add_buff("ice_barrier", "Ice Barrier", skill.duration, Color(0.4, 0.7, 1.0))

		"blizzard":
			# Repeated AoE ticks over duration
			if is_server:
				var dmg := (skill.damage + stats.intelligence * 0.3) * (1.0 + stats.spell_damage_pct)
				for tick in range(6):
					player.get_tree().create_timer(float(tick) * 1.0).timeout.connect(func() -> void:
						if not is_instance_valid(player):
							return
						_aoe_damage(cast_pos, skill.radius, dmg * 0.3)
					)

		# ── MAGE: ARCANE ──
		"arcane_missiles":
			# 3 rapid hits
			if is_server:
				var dmg := (skill.damage + stats.intelligence * 0.4) * (1.0 + stats.spell_damage_pct)
				for volley in range(3):
					player.get_tree().create_timer(float(volley) * 0.2).timeout.connect(func() -> void:
						if not is_instance_valid(player):
							return
						_aoe_damage(cast_pos, skill.radius, dmg * 0.4)
					)

		"mana_shield":
			# Damage redirected to mana
			if is_server:
				player._buff_mana_shield = true
				player.add_buff("mana_shield", "Mana Shield", skill.duration, Color(0.5, 0.3, 0.9))

		# ── ROGUE: ASSASSINATION ──
		"backstab":
			# High single-target damage
			if is_server:
				var dmg := skill.damage + stats.dexterity * 0.7
				# Built-in 50% crit chance stacks with player crit
				var crit_chance := 0.5 + stats.crit_chance_pct
				if randf() < crit_chance:
					dmg *= 1.5 + stats.crit_damage_pct
				_aoe_damage(cast_pos, 2.5, dmg)  # Small radius = single target feel

		"poison_blade":
			# Buff: next 5 attacks apply DoT (simplified: buff adds flat damage)
			if is_server:
				player.add_buff("poison_blade", "Poison Blade", skill.duration, Color(0.3, 0.8, 0.2))

		"death_mark":
			# Mark nearest enemy to take 50% more damage
			if is_server:
				var nearest: Node3D = null
				var best_dist := 999.0
				for enemy in player.get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(enemy):
						continue
					var d: float = enemy.global_position.distance_to(cast_pos)
					if d < best_dist and d <= skill.range_dist:
						best_dist = d
						nearest = enemy
				if nearest and nearest.has_method("take_damage"):
					# Apply mark as metadata — 50% vulnerability
					nearest.set_meta(&"death_mark_mult", 1.5)
					player.get_tree().create_timer(skill.duration).timeout.connect(func() -> void:
						if is_instance_valid(nearest):
							nearest.remove_meta(&"death_mark_mult")
					)

		# ── ROGUE: SHADOW ──
		"vanish":
			# Become invisible briefly
			if is_server:
				player._buff_invisible = true
				player._set_visibility.rpc(false)
				player.add_buff("vanish", "Vanish", skill.duration, Color(0.3, 0.3, 0.4))

		"smoke_bomb":
			# AoE damage + enemies lose target
			if is_server:
				var dmg := skill.damage + stats.dexterity * 0.4
				for enemy in player.get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(enemy):
						continue
					var dist: float = enemy.global_position.distance_to(cast_pos)
					if dist <= skill.radius:
						if enemy.has_method("take_damage"):
							enemy.take_damage(dmg, player)
						# De-aggro
						if enemy.get("target") == player:
							enemy.target = null

		# ── ROGUE: TRAPS ──
		"spike_trap":
			# Delayed AoE + slow
			if is_server:
				var dmg := skill.damage + stats.dexterity * 0.5
				player.get_tree().create_timer(0.5).timeout.connect(func() -> void:
					if not is_instance_valid(player):
						return
					for enemy in player.get_tree().get_nodes_in_group("enemies"):
						if not is_instance_valid(enemy):
							continue
						var dist: float = enemy.global_position.distance_to(cast_pos)
						if dist <= skill.radius and enemy.has_method("take_damage"):
							enemy.take_damage(dmg, player)
							enemy.move_speed *= 0.5
							player.get_tree().create_timer(2.0).timeout.connect(func() -> void:
								if is_instance_valid(enemy):
									enemy.move_speed *= 2.0
							)
				)

		"fan_of_knives":
			# AoE around player
			if is_server:
				var dmg := skill.damage + stats.dexterity * 0.5
				_aoe_damage(player.global_position, skill.radius, dmg)

		"rain_of_arrows":
			# Multi-tick AoE at target
			if is_server:
				var dmg := skill.damage + stats.dexterity * 0.4
				for tick in range(4):
					player.get_tree().create_timer(float(tick) * 1.0).timeout.connect(func() -> void:
						if not is_instance_valid(player):
							return
						_aoe_damage(cast_pos, skill.radius, dmg * 0.4)
					)

		_:
			# Fallback: generic AoE damage
			if skill.damage > 0.0 and is_server:
				var dmg := skill.damage + stats.strength * 0.5
				_aoe_damage(cast_pos, skill.radius if skill.radius > 0.0 else 4.0, dmg)


func _aoe_damage(center: Vector3, radius: float, damage: float) -> void:
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist: float = enemy.global_position.distance_to(center)
		if dist <= radius and enemy.has_method("take_damage"):
			var mult: float = enemy.get_meta(&"death_mark_mult", 1.0)
			enemy.take_damage(damage * mult, player)


## --- Skill Tree System ---

func _load_tree_from_character() -> void:
	# Load from CharacterManager's active character
	var char_data = null
	if Engine.has_singleton("CharacterManager"):
		char_data = Engine.get_singleton("CharacterManager")
	else:
		var cm = player.get_node_or_null("/root/CharacterManager")
		if cm and cm.get("active_character"):
			char_data = cm.active_character

	if char_data and char_data is CharacterData:
		character_class = char_data.character_class
		allocated_points = char_data.allocated_skill_points.duplicate() if char_data.allocated_skill_points else {}
		skill_points = char_data.skill_points if char_data.skill_points > 0 or not allocated_points.is_empty() else _compute_default_skill_points(char_data.level)
	else:
		# Fallback for online players without local save
		skill_points = _compute_default_skill_points(player.stats.level if player.get("stats") else 1)


func _compute_default_skill_points(lv: int) -> int:
	# Players get 1 skill point per level, minus already allocated
	var total := maxi(lv - 1, 0)
	var used := 0
	for pts in allocated_points.values():
		used += int(pts)
	return maxi(total - used, 0)


func can_allocate(node_id: String) -> bool:
	if skill_points <= 0:
		return false
	var node := _find_node(node_id)
	if node.is_empty():
		return false
	var current_rank: int = allocated_points.get(node_id, 0)
	if current_rank >= node.get("max_rank", 1):
		return false
	# Check prerequisites
	for req_id in node.get("requires", []):
		if allocated_points.get(req_id, 0) <= 0:
			return false
	return true


func allocate_point(node_id: String) -> bool:
	if not can_allocate(node_id):
		return false
	allocated_points[node_id] = allocated_points.get(node_id, 0) + 1
	skill_points -= 1
	_apply_passive_bonuses()
	_rebuild_skill_slots()
	_save_tree_to_character()
	# Sync to server for online save
	if player.has_method("sync_skill_tree_to_server"):
		player.sync_skill_tree_to_server()
	skill_tree_changed.emit()
	return true


func get_node_rank(node_id: String) -> int:
	return allocated_points.get(node_id, 0)


func get_total_allocated() -> int:
	var total := 0
	for pts in allocated_points.values():
		total += int(pts)
	return total


func get_unlocked_active_skill_ids() -> Array[String]:
	var ids: Array[String] = []
	var trees := SkillTreeData.get_trees_for_class(character_class)
	for branch in trees:
		for node: Dictionary in branch["nodes"]:
			if node.get("type", "passive") == "active" and allocated_points.get(node["id"], 0) > 0:
				var skill_id: String = node.get("effects", {}).get("skill_id", "")
				if skill_id != "":
					ids.append(skill_id)
	return ids


func _rebuild_skill_slots() -> void:
	# Put unlocked active skills into the 4 slots
	var unlocked := get_unlocked_active_skill_ids()
	var defs := SkillTreeData.get_all_skill_definitions()

	# Always have heal as fallback
	if not unlocked.has("heal"):
		unlocked.append("heal")

	for i in 4:
		if i < unlocked.size():
			skills[i] = _create_skill_from_def(unlocked[i], defs.get(unlocked[i], {}))
		else:
			skills[i] = null


func _create_skill_from_def(skill_id: String, def: Dictionary) -> SkillData:
	var s := SkillData.new()
	s.id = skill_id
	s.display_name = def.get("display_name", skill_id.capitalize())
	s.description = def.get("description", "")
	s.cooldown = def.get("cooldown", 3.0)
	s.mana_cost = def.get("mana_cost", 10.0)
	s.damage = def.get("damage", 20.0)
	s.radius = def.get("radius", 0.0)
	s.range_dist = def.get("range_dist", 0.0)
	s.duration = def.get("duration", 0.0)
	var ic = def.get("icon_color", Color.WHITE)
	if ic is Color:
		s.icon_color = ic
	var tt_str: String = def.get("target_type", "POINT")
	var tt_idx := SkillData.TargetType.keys().find(tt_str)
	if tt_idx >= 0:
		s.target_type = tt_idx as SkillData.TargetType
	_apply_skill_data(s)
	return s


func _apply_passive_bonuses() -> void:
	# Recalculate and apply passive bonuses from the skill tree
	if not player or not player.get("stats"):
		return
	# We store cumulative tree bonuses — first remove old, then reapply
	var trees := SkillTreeData.get_trees_for_class(character_class)
	var bonuses := {}
	for branch in trees:
		for node: Dictionary in branch["nodes"]:
			if node.get("type", "passive") != "passive":
				continue
			var rank: int = allocated_points.get(node["id"], 0)
			if rank <= 0:
				continue
			var effects: Dictionary = node.get("effects", {})
			for key in effects:
				bonuses[key] = bonuses.get(key, 0.0) + effects[key] * rank

	# Apply flat stat bonuses
	var stats: PlayerStats = player.stats
	# We store the tree bonuses separately so they can be recalculated
	var old_bonuses: Dictionary = player.get_meta("_tree_bonuses", {})
	# Remove old
	for key in old_bonuses:
		_apply_stat(stats, key, -old_bonuses[key])
	# Apply new
	for key in bonuses:
		_apply_stat(stats, key, bonuses[key])
	player.set_meta("_tree_bonuses", bonuses)


func _apply_stat(stats: PlayerStats, key: String, value: float) -> void:
	match key:
		"attack_damage": stats.attack_damage += value
		"defense": stats.defense += value
		"max_health":
			stats.max_health += value
			stats.health = minf(stats.health, stats.max_health)
		"max_mana":
			stats.max_mana += value
			stats.mana = minf(stats.mana, stats.max_mana)
		"strength": stats.strength += int(value)
		"dexterity": stats.dexterity += int(value)
		"intelligence": stats.intelligence += int(value)
		"vitality":
			stats.vitality += int(value)
			# Each point of vitality grants 5 max health
			stats.max_health += value * 5.0
			stats.health = minf(stats.health, stats.max_health)
		"move_speed": stats.move_speed += value
		"crit_chance_pct": stats.crit_chance_pct += value * 0.01
		"crit_damage_pct": stats.crit_damage_pct += value * 0.01
		"spell_damage_pct": stats.spell_damage_pct += value * 0.01
		"attack_speed_pct": stats.attack_speed_pct += value * 0.01
		"mana_regen_pct": stats.mana_regen_pct += value * 0.01
		"mana_cost_reduction_pct": stats.mana_cost_reduction_pct += value * 0.01
		"dodge_pct": stats.dodge_pct += value * 0.01


func _find_node(node_id: String) -> Dictionary:
	var trees := SkillTreeData.get_trees_for_class(character_class)
	for branch in trees:
		for node: Dictionary in branch["nodes"]:
			if node["id"] == node_id:
				return node
	return {}


func _save_tree_to_character() -> void:
	var cm = player.get_node_or_null("/root/CharacterManager")
	if cm and cm.get("active_character") and cm.active_character is CharacterData:
		cm.active_character.set("skill_points", skill_points)
		cm.active_character.set("allocated_skill_points", allocated_points.duplicate())
		if cm.has_method("save_character"):
			cm.save_character()


func add_skill_point() -> void:
	skill_points += 1
	skill_tree_changed.emit()


func _apply_skill_data(s: SkillData) -> void:
	_load_game_data()
	if not _game_data.has("skills") or not _game_data["skills"].has(s.id):
		return
	var sd: Dictionary = _game_data["skills"][s.id]
	s.display_name = sd.get("display_name", s.display_name)
	s.description = sd.get("description", s.description)
	s.cooldown = sd.get("cooldown", s.cooldown)
	s.mana_cost = sd.get("mana_cost", s.mana_cost)
	s.damage = sd.get("damage", s.damage)
	s.radius = sd.get("radius", s.radius)
	s.range_dist = sd.get("range_dist", s.range_dist)
	s.duration = sd.get("duration", s.duration)
	var tt_str: String = sd.get("target_type", "")
	var tt_idx := SkillData.TargetType.keys().find(tt_str)
	if tt_idx >= 0:
		s.target_type = tt_idx as SkillData.TargetType
	var ic: Array = sd.get("icon_color", [])
	if ic.size() >= 4:
		s.icon_color = Color(ic[0], ic[1], ic[2], ic[3])
