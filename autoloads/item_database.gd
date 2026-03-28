extends Node

## Static database of all item definitions.
## Generates items by ID. Also used for random loot generation.

var _items: Dictionary = {}


func _ready() -> void:
	_register_items()


func get_item(item_id: String) -> ItemData:
	if _items.has(item_id):
		return _items[item_id].duplicate()
	return null


func get_random_weapon(enemy_level: int = 1) -> ItemData:
	var item := ItemData.new()
	var names := ["Rusty Sword", "Iron Axe", "Steel Mace", "War Hammer", "Shadow Blade", "Flame Dagger"]
	item.id = "weapon_%d" % randi()
	item.display_name = names[randi() % names.size()]
	item.item_type = ItemData.ItemType.WEAPON
	item.rarity = _roll_rarity()
	item.bonus_damage = (5.0 + enemy_level * 2.0) * (1.0 + item.rarity * 0.3)
	item.icon_color = ItemData.get_rarity_color(item.rarity)
	return item


func get_random_armor(enemy_level: int = 1) -> ItemData:
	var types := [ItemData.ItemType.HELMET, ItemData.ItemType.CHEST, ItemData.ItemType.BOOTS]
	var type_names := {
		ItemData.ItemType.HELMET: ["Leather Cap", "Iron Helm", "Plate Helm", "Crown of Thorns"],
		ItemData.ItemType.CHEST: ["Cloth Tunic", "Chainmail", "Plate Armor", "Shadow Vestments"],
		ItemData.ItemType.BOOTS: ["Sandals", "Iron Boots", "Greaves", "Windwalkers"],
	}
	var item := ItemData.new()
	item.item_type = types[randi() % types.size()]
	var names_list: Array = type_names[item.item_type]
	item.display_name = names_list[randi() % names_list.size()]
	item.id = "armor_%d" % randi()
	item.rarity = _roll_rarity()
	item.bonus_defense = (3.0 + enemy_level * 1.5) * (1.0 + item.rarity * 0.3)
	item.bonus_health = enemy_level * 5.0 * (1.0 + item.rarity * 0.2)
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
	return item


func generate_enemy_drops(enemy_level: int = 1) -> Array[ItemData]:
	var drops: Array[ItemData] = []

	# Always a chance at a potion
	if randf() < 0.4:
		drops.append(get_health_potion())
	if randf() < 0.2:
		drops.append(get_mana_potion())

	# Chance for equipment
	if randf() < 0.3:
		if randf() < 0.5:
			drops.append(get_random_weapon(enemy_level))
		else:
			drops.append(get_random_armor(enemy_level))

	return drops


func _roll_rarity() -> ItemData.Rarity:
	var roll := randf()
	if roll < 0.5:
		return ItemData.Rarity.COMMON
	elif roll < 0.8:
		return ItemData.Rarity.UNCOMMON
	elif roll < 0.93:
		return ItemData.Rarity.RARE
	elif roll < 0.99:
		return ItemData.Rarity.EPIC
	else:
		return ItemData.Rarity.LEGENDARY


func _register_items() -> void:
	# Register base potions for lookup by ID
	_items["health_potion"] = get_health_potion()
	_items["mana_potion"] = get_mana_potion()
