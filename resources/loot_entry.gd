extends Resource
class_name LootEntry

## A single entry in a loot table.

@export var item: ItemData
@export var weight: float = 0.5  # Probability this item drops (0.0–1.0)
