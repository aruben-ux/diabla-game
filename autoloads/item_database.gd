extends Node

## Static database of all item definitions.
## Generates items by ID. Also used for random loot generation.

var _items: Dictionary = {}

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


func _ready() -> void:
	_register_items()


func get_item(item_id: String) -> ItemData:
	if _items.has(item_id):
		return _items[item_id].duplicate()
	return null


func get_random_weapon(enemy_level: int = 1) -> ItemData:
	_load_game_data()
	var lc: Dictionary = _game_data.get("loot_config", {})
	var item := ItemData.new()
	var names: Array = lc.get("weapon_names", ["Rusty Sword", "Iron Axe", "Steel Mace", "War Hammer", "Shadow Blade", "Flame Dagger"])
	item.id = "weapon_%d" % randi()
	item.display_name = names[randi() % names.size()]
	item.item_type = ItemData.ItemType.WEAPON
	item.rarity = _roll_rarity()
	var base_dmg: float = lc.get("weapon_damage_base", 5.0)
	var dmg_per_lv: float = lc.get("weapon_damage_per_level", 2.0)
	var rar_mult: float = lc.get("rarity_bonus_mult", 0.3)
	item.bonus_damage = (base_dmg + enemy_level * dmg_per_lv) * (1.0 + item.rarity * rar_mult)
	item.icon_color = ItemData.get_rarity_color(item.rarity)
	return item


func get_random_armor(enemy_level: int = 1) -> ItemData:
	_load_game_data()
	var lc: Dictionary = _game_data.get("loot_config", {})
	var types := [ItemData.ItemType.HELMET, ItemData.ItemType.CHEST, ItemData.ItemType.BOOTS]
	var armor_names_cfg: Dictionary = lc.get("armor_names", {})
	var type_names := {
		ItemData.ItemType.HELMET: armor_names_cfg.get("HELMET", ["Leather Cap", "Iron Helm", "Plate Helm", "Crown of Thorns"]),
		ItemData.ItemType.CHEST: armor_names_cfg.get("CHEST", ["Cloth Tunic", "Chainmail", "Plate Armor", "Shadow Vestments"]),
		ItemData.ItemType.BOOTS: armor_names_cfg.get("BOOTS", ["Sandals", "Iron Boots", "Greaves", "Windwalkers"]),
	}
	var item := ItemData.new()
	item.item_type = types[randi() % types.size()]
	var names_list: Array = type_names[item.item_type]
	item.display_name = names_list[randi() % names_list.size()]
	item.id = "armor_%d" % randi()
	item.rarity = _roll_rarity()
	var def_base: float = lc.get("armor_defense_base", 3.0)
	var def_per_lv: float = lc.get("armor_defense_per_level", 1.5)
	var hp_per_lv: float = lc.get("armor_health_per_level", 5.0)
	var rar_mult: float = lc.get("rarity_bonus_mult", 0.3)
	item.bonus_defense = (def_base + enemy_level * def_per_lv) * (1.0 + item.rarity * rar_mult)
	item.bonus_health = enemy_level * hp_per_lv * (1.0 + item.rarity * 0.2)
	item.icon_color = ItemData.get_rarity_color(item.rarity)
	return item


func get_health_potion() -> ItemData:
	var item := ItemData.new()
	item.id = "health_potion"
	item.display_name = "Health Potion"
	item.item_type = ItemData.ItemType.POTION
	item.rarity = ItemData.Rarity.COMMON
	item.stackable = true
	item.max_stack = 20
	item.heal_amount = 30.0
	item.icon_color = Color.RED
	_apply_item_data(item)
	return item


func get_mana_potion() -> ItemData:
	var item := ItemData.new()
	item.id = "mana_potion"
	item.display_name = "Mana Potion"
	item.item_type = ItemData.ItemType.POTION
	item.rarity = ItemData.Rarity.COMMON
	item.stackable = true
	item.max_stack = 20
	item.mana_restore = 20.0
	item.icon_color = Color.DODGER_BLUE
	_apply_item_data(item)
	return item


func generate_enemy_drops(enemy_level: int = 1) -> Array[ItemData]:
	_load_game_data()
	var lc: Dictionary = _game_data.get("loot_config", {})
	var drops: Array[ItemData] = []

	var hp_chance: float = lc.get("health_potion_drop_chance", 0.4)
	var mp_chance: float = lc.get("mana_potion_drop_chance", 0.2)
	var eq_chance: float = lc.get("equipment_drop_chance", 0.3)

	if randf() < hp_chance:
		drops.append(get_health_potion())
	if randf() < mp_chance:
		drops.append(get_mana_potion())

	if randf() < eq_chance:
		if randf() < 0.5:
			drops.append(get_random_weapon(enemy_level))
		else:
			drops.append(get_random_armor(enemy_level))

	return drops


func _roll_rarity() -> ItemData.Rarity:
	_load_game_data()
	var lc: Dictionary = _game_data.get("loot_config", {})
	var weights: Array = lc.get("rarity_weights", [0.5, 0.3, 0.13, 0.06, 0.01])
	var roll := randf()
	var cumulative := 0.0
	var rarities := [ItemData.Rarity.COMMON, ItemData.Rarity.UNCOMMON,
					 ItemData.Rarity.RARE, ItemData.Rarity.EPIC, ItemData.Rarity.LEGENDARY]
	for i in range(weights.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return rarities[i] if i < rarities.size() else ItemData.Rarity.COMMON
	return ItemData.Rarity.LEGENDARY


func _register_items() -> void:
	# Register base potions for lookup by ID
	_items["health_potion"] = get_health_potion()
	_items["mana_potion"] = get_mana_potion()


func _apply_item_data(item: ItemData) -> void:
	_load_game_data()
	if not _game_data.has("items") or not _game_data["items"].has(item.id):
		return
	var d: Dictionary = _game_data["items"][item.id]
	item.display_name = d.get("display_name", item.display_name)
	item.description = d.get("description", item.description)
	item.stackable = d.get("stackable", item.stackable)
	item.max_stack = int(d.get("max_stack", item.max_stack))
	item.level_requirement = int(d.get("level_requirement", item.level_requirement))
	item.bonus_damage = d.get("bonus_damage", item.bonus_damage)
	item.bonus_defense = d.get("bonus_defense", item.bonus_defense)
	item.bonus_health = d.get("bonus_health", item.bonus_health)
	item.bonus_mana = d.get("bonus_mana", item.bonus_mana)
	item.bonus_strength = int(d.get("bonus_strength", item.bonus_strength))
	item.bonus_dexterity = int(d.get("bonus_dexterity", item.bonus_dexterity))
	item.bonus_intelligence = int(d.get("bonus_intelligence", item.bonus_intelligence))
	item.heal_amount = d.get("heal_amount", item.heal_amount)
	item.mana_restore = d.get("mana_restore", item.mana_restore)
	var it_str: String = d.get("item_type", "")
	var it_idx := ItemData.ItemType.keys().find(it_str)
	if it_idx >= 0:
		item.item_type = it_idx as ItemData.ItemType
	var r_str: String = d.get("rarity", "")
	var r_idx := ItemData.Rarity.keys().find(r_str)
	if r_idx >= 0:
		item.rarity = r_idx as ItemData.Rarity
	var ic: Array = d.get("icon_color", [])
	if ic.size() >= 4:
		item.icon_color = Color(ic[0], ic[1], ic[2], ic[3])
