extends Node
class_name Inventory

## Player inventory: holds items, manages equipment slots.

signal inventory_changed
signal item_equipped(slot: String, item: ItemData)
signal item_unequipped(slot: String)
signal gold_changed(amount: int)

const MAX_SLOTS := 30

var items: Array[ItemData] = []
var gold: int = 0
var equipment: Dictionary = {
	"weapon": null,
	"helmet": null,
	"chest": null,
	"boots": null,
	"ring": null,
	"amulet": null,
}

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func add_item(item: ItemData) -> bool:
	# Try stacking first
	if item.stackable:
		for existing in items:
			if existing.id == item.id:
				# Already have it (simplified stacking — count not tracked here, just allow)
				inventory_changed.emit()
				return true

	if items.size() >= MAX_SLOTS:
		return false

	items.append(item)
	inventory_changed.emit()
	return true


func remove_item(index: int) -> ItemData:
	if index < 0 or index >= items.size():
		return null
	var item := items[index]
	items.remove_at(index)
	inventory_changed.emit()
	return item


func use_item(index: int, player: Node) -> void:
	if index < 0 or index >= items.size():
		return

	var item := items[index]
	match item.item_type:
		ItemData.ItemType.POTION:
			_use_potion(item, player)
			items.remove_at(index)
			inventory_changed.emit()
		ItemData.ItemType.WEAPON, ItemData.ItemType.HELMET, \
		ItemData.ItemType.CHEST, ItemData.ItemType.BOOTS, \
		ItemData.ItemType.RING, ItemData.ItemType.AMULET:
			equip_item(index, player)


func equip_item(index: int, player: Node) -> void:
	if index < 0 or index >= items.size():
		return

	var item := items[index]
	var slot := _get_equip_slot(item.item_type)
	if slot.is_empty():
		return

	# Unequip current item in slot (put back in inventory)
	if equipment[slot] != null:
		items.append(equipment[slot])
		_remove_stat_bonuses(equipment[slot], player)

	# Equip new item
	equipment[slot] = item
	items.remove_at(index)
	_apply_stat_bonuses(item, player)
	item_equipped.emit(slot, item)
	inventory_changed.emit()


func unequip_item(slot: String, player: Node) -> bool:
	if not equipment.has(slot) or equipment[slot] == null:
		return false
	if items.size() >= MAX_SLOTS:
		return false

	var item: ItemData = equipment[slot]
	_remove_stat_bonuses(item, player)
	items.append(item)
	equipment[slot] = null
	item_unequipped.emit(slot)
	inventory_changed.emit()
	return true


func _use_potion(item: ItemData, player: Node) -> void:
	if not player or not player.get("stats"):
		return
	var stats: PlayerStats = player.stats
	if item.heal_amount > 0.0:
		stats.heal(item.heal_amount)
	if item.mana_restore > 0.0:
		stats.mana = minf(stats.mana + item.mana_restore, stats.max_mana)


func _apply_stat_bonuses(item: ItemData, player: Node) -> void:
	if not player or not player.get("stats"):
		return
	var stats: PlayerStats = player.stats
	stats.attack_damage += item.bonus_damage
	stats.defense += item.bonus_defense
	stats.max_health += item.bonus_health
	stats.health += item.bonus_health
	stats.max_mana += item.bonus_mana
	stats.mana += item.bonus_mana
	stats.strength += item.bonus_strength
	stats.dexterity += item.bonus_dexterity
	stats.intelligence += item.bonus_intelligence


func _remove_stat_bonuses(item: ItemData, player: Node) -> void:
	if not player or not player.get("stats"):
		return
	var stats: PlayerStats = player.stats
	stats.attack_damage -= item.bonus_damage
	stats.defense -= item.bonus_defense
	stats.max_health -= item.bonus_health
	stats.health = minf(stats.health, stats.max_health)
	stats.max_mana -= item.bonus_mana
	stats.mana = minf(stats.mana, stats.max_mana)
	stats.strength -= item.bonus_strength
	stats.dexterity -= item.bonus_dexterity
	stats.intelligence -= item.bonus_intelligence


func _get_equip_slot(item_type: ItemData.ItemType) -> String:
	match item_type:
		ItemData.ItemType.WEAPON: return "weapon"
		ItemData.ItemType.HELMET: return "helmet"
		ItemData.ItemType.CHEST: return "chest"
		ItemData.ItemType.BOOTS: return "boots"
		ItemData.ItemType.RING: return "ring"
		ItemData.ItemType.AMULET: return "amulet"
	return ""
