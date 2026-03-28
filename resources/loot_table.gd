extends Resource
class_name LootTable

## Defines what items an enemy can drop and their probabilities.

@export var drop_chance: float = 0.6  # 60% chance to drop anything
@export var entries: Array[LootEntry] = []


func roll_drops() -> Array[ItemData]:
	var drops: Array[ItemData] = []
	if randf() > drop_chance:
		return drops

	for entry in entries:
		if randf() <= entry.weight:
			var item := entry.item.duplicate()
			# Chance to upgrade rarity
			if randf() < 0.1:
				item.rarity = mini(item.rarity + 1, ItemData.Rarity.LEGENDARY) as ItemData.Rarity
				_scale_item_stats(item)
			drops.append(item)
			if drops.size() >= 3:
				break
	return drops


func _scale_item_stats(item: ItemData) -> void:
	var mult := 1.0 + item.rarity * 0.3
	item.bonus_damage *= mult
	item.bonus_defense *= mult
	item.bonus_health *= mult
	item.bonus_mana *= mult
