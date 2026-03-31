extends Node

## Manages saving and loading character data to user://characters/.

signal character_saved(slot: int)
signal character_loaded(data: CharacterData)

const SAVE_DIR := "user://characters/"
const AUTO_SAVE_INTERVAL := 60.0  # Seconds between auto-saves

var active_character: CharacterData = null
var _auto_save_timer: float = 0.0


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
	character_saved.emit(data.save_slot)
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
	_auto_save_timer = 0.0
	character_loaded.emit(data)


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
	var hp_bonus := tree_bonuses.get("max_health", 0.0) + tree_bonuses.get("vitality", 0.0) * 5.0
	var mp_bonus := tree_bonuses.get("max_mana", 0.0)

	active_character.level = stats.level
	active_character.experience = stats.experience
	active_character.max_health = stats.max_health - hp_bonus
	active_character.max_mana = stats.max_mana - mp_bonus
	active_character.health = minf(stats.health, active_character.max_health)
	active_character.mana = minf(stats.mana, active_character.max_mana)
	active_character.strength = stats.strength - int(tree_bonuses.get("strength", 0.0))
	active_character.dexterity = stats.dexterity - int(tree_bonuses.get("dexterity", 0.0))
	active_character.intelligence = stats.intelligence - int(tree_bonuses.get("intelligence", 0.0))
	active_character.vitality = stats.vitality - int(tree_bonuses.get("vitality", 0.0))
	active_character.attack_damage = stats.attack_damage - tree_bonuses.get("attack_damage", 0.0)
	active_character.attack_speed = stats.attack_speed
	active_character.defense = stats.defense - tree_bonuses.get("defense", 0.0)
	active_character.move_speed = stats.move_speed - tree_bonuses.get("move_speed", 0.0)

	# Persist skill tree data
	if player.get("skill_manager") and player.skill_manager:
		active_character.skill_points = player.skill_manager.skill_points
		active_character.allocated_skill_points = player.skill_manager.allocated_points.duplicate()

	# Serialize inventory (grid-based)
	var inv: Inventory = player.inventory
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
