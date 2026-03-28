extends Resource
class_name ItemData

## Defines a single item type (weapon, armor, potion, etc.)

enum ItemType { WEAPON, HELMET, CHEST, BOOTS, RING, AMULET, POTION, MISC }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon_color: Color = Color.WHITE
@export var item_type: ItemType = ItemType.MISC
@export var rarity: Rarity = Rarity.COMMON
@export var stackable: bool = false
@export var max_stack: int = 1
@export var level_requirement: int = 1

# Stat bonuses when equipped
@export var bonus_damage: float = 0.0
@export var bonus_defense: float = 0.0
@export var bonus_health: float = 0.0
@export var bonus_mana: float = 0.0
@export var bonus_strength: int = 0
@export var bonus_dexterity: int = 0
@export var bonus_intelligence: int = 0

# Consumable effect
@export var heal_amount: float = 0.0
@export var mana_restore: float = 0.0


static func get_rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.COMMON: return Color.WHITE
		Rarity.UNCOMMON: return Color.GREEN
		Rarity.RARE: return Color.CORNFLOWER_BLUE
		Rarity.EPIC: return Color.MEDIUM_PURPLE
		Rarity.LEGENDARY: return Color.ORANGE
	return Color.WHITE


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"description": description,
		"item_type": item_type,
		"rarity": rarity,
		"stackable": stackable,
		"max_stack": max_stack,
		"level_requirement": level_requirement,
		"bonus_damage": bonus_damage,
		"bonus_defense": bonus_defense,
		"bonus_health": bonus_health,
		"bonus_mana": bonus_mana,
		"bonus_strength": bonus_strength,
		"bonus_dexterity": bonus_dexterity,
		"bonus_intelligence": bonus_intelligence,
		"heal_amount": heal_amount,
		"mana_restore": mana_restore,
	}


static func from_dict(d: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = d.get("id", "")
	item.display_name = d.get("display_name", "")
	item.description = d.get("description", "")
	item.item_type = d.get("item_type", ItemType.MISC) as ItemType
	item.rarity = d.get("rarity", Rarity.COMMON) as Rarity
	item.stackable = d.get("stackable", false)
	item.max_stack = d.get("max_stack", 1)
	item.level_requirement = d.get("level_requirement", 1)
	item.bonus_damage = d.get("bonus_damage", 0.0)
	item.bonus_defense = d.get("bonus_defense", 0.0)
	item.bonus_health = d.get("bonus_health", 0.0)
	item.bonus_mana = d.get("bonus_mana", 0.0)
	item.bonus_strength = d.get("bonus_strength", 0)
	item.bonus_dexterity = d.get("bonus_dexterity", 0)
	item.bonus_intelligence = d.get("bonus_intelligence", 0)
	item.heal_amount = d.get("heal_amount", 0.0)
	item.mana_restore = d.get("mana_restore", 0.0)
	return item
