extends Node

## Manages saving and loading character data to user://characters/.

#signal character_saved(slot: int)
#signal character_loaded(data: CharacterData)

const SAVE_DIR := "user://characters/"

var active_character: CharacterData = null


func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _process(delta: float) -> void:
	if active_character == null:
		return
	active_character.play_time_seconds += delta


func get_all_characters() -> Array[CharacterData]:
	var characters: Array[CharacterData] = []
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return characters

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data := _load_file(SAVE_DIR + file_name)
			if data:
				characters.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort by last played (most recent first)
	characters.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return a.last_played > b.last_played
	)
	return characters


func save_character(data: CharacterData = active_character) -> bool:
	if data == null:
		return false

	data.last_played = Time.get_datetime_string_from_system()
	var path := _get_save_path(data.save_slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("CharacterManager: Failed to save character to ", path)
		return false

	var json_string := JSON.stringify(data.to_dict(), "\t")
	file.store_string(json_string)
	file.close()
	#character_saved.emit(data.save_slot)
	#print("Character saved: %s (slot %d)" % [data.character_name, data.save_slot])
	return true


func delete_character(slot: int) -> bool:
	var path := _get_save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return true
	return false


func select_character(data: CharacterData) -> void:
	active_character = data


func get_next_free_slot() -> int:
	var used_slots: Array[int] = []
	for c in get_all_characters():
		used_slots.append(c.save_slot)
	var slot := 0
	while slot in used_slots:
		slot += 1
	return slot


func capture_player_state(player: Node) -> void:
	## Copies the live player state back into the active CharacterData.
	if active_character == null or player == null:
		return
	var stats: PlayerStats = player.stats

	# Compute effective stat deltas from tree bonuses to save BASE values
	var tree_bonuses: Dictionary = player.get_meta("_tree_bonuses", {})
	var hp_bonus: float = tree_bonuses.get("max_health", 0.0) + tree_bonuses.get("vitality", 0.0) * 5.0
	var mp_bonus: float = tree_bonuses.get("max_mana", 0.0)

	# Compute equipment bonuses (base stats + affix stats) to subtract from saved values
	var inv = player.inventory
	var eq_dmg := 0.0
	var eq_def := 0.0
	var eq_hp := 0.0
	var eq_mp := 0.0
	var eq_str := 0
	var eq_dex := 0
	var eq_int := 0
	for slot_name: String in inv.equipment:
		var eq_item: ItemData = inv.equipment[slot_name]
		if eq_item == null:
			continue
		eq_dmg += eq_item.bonus_damage
		eq_def += eq_item.bonus_defense
		eq_hp += eq_item.bonus_health
		eq_mp += eq_item.bonus_mana
		eq_str += eq_item.bonus_strength
		eq_dex += eq_item.bonus_dexterity
		eq_int += eq_item.bonus_intelligence
		# Also subtract affix bonuses that affect base stats
		for affix: Dictionary in eq_item.affixes:
			var stat: String = affix.get("stat", "")
			var val: float = float(affix.get("value", 0.0))
			match stat:
				"bonus_damage": eq_dmg += val
				"bonus_defense": eq_def += val
				"bonus_health": eq_hp += val
				"bonus_mana": eq_mp += val
				"bonus_strength": eq_str += int(val)
				"bonus_dexterity": eq_dex += int(val)
				"bonus_intelligence": eq_int += int(val)

	# Also subtract resonance bonuses that affect saved base stats
	var res_bonuses: Dictionary = AffixDatabase.get_resonance_stat_bonuses(inv.get_active_resonances())
	eq_dmg += res_bonuses.get("bonus_damage", 0.0) + res_bonuses.get("attack_damage", 0.0)
	eq_def += res_bonuses.get("bonus_defense", 0.0)
	eq_hp += res_bonuses.get("bonus_health", 0.0)
	eq_mp += res_bonuses.get("bonus_mana", 0.0)

	active_character.level = stats.level
	active_character.experience = stats.experience
	active_character.max_health = stats.max_health - hp_bonus - eq_hp
	active_character.max_mana = stats.max_mana - mp_bonus - eq_mp
	active_character.health = minf(stats.health, active_character.max_health)
	active_character.mana = minf(stats.mana, active_character.max_mana)
	active_character.strength = stats.strength - int(tree_bonuses.get("strength", 0.0)) - eq_str
	active_character.dexterity = stats.dexterity - int(tree_bonuses.get("dexterity", 0.0)) - eq_dex
	active_character.intelligence = stats.intelligence - int(tree_bonuses.get("intelligence", 0.0)) - eq_int
	active_character.vitality = stats.vitality - int(tree_bonuses.get("vitality", 0.0))
	active_character.attack_damage = stats.attack_damage - tree_bonuses.get("attack_damage", 0.0) - eq_dmg
	active_character.attack_speed = stats.attack_speed
	active_character.defense = stats.defense - tree_bonuses.get("defense", 0.0) - eq_def
	active_character.move_speed = stats.move_speed - tree_bonuses.get("move_speed", 0.0)

	# Persist skill tree data
	if player.get("skill_manager") and player.skill_manager:
		active_character.skill_points = player.skill_manager.skill_points
		active_character.allocated_skill_points = player.skill_manager.allocated_points.duplicate()

	# Serialize inventory (grid-based)
	active_character.gold = inv.gold
	active_character.health_potions = inv.health_potions
	active_character.mana_potions = inv.mana_potions
	active_character.inventory_items = inv.serialize_grid()

	active_character.equipment = {}
	for slot_name in inv.equipment:
		var eq_item: ItemData = inv.equipment[slot_name]
		if eq_item != null:
			active_character.equipment[slot_name] = eq_item.to_dict()

	# Save quest progress
	active_character.quest_data = QuestManager.save_to_array()


func _load_file(path: String) -> CharacterData:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		printerr("CharacterManager: Failed to parse ", path)
		return null
	var dict: Dictionary = json.data
	return CharacterData.from_dict(dict)


func _get_save_path(slot: int) -> String:
	return SAVE_DIR + "char_%d.json" % slot
