extends Resource
class_name CharacterData

## Persistent character save data. Serialized to JSON on disk.

enum CharacterClass { WARRIOR, MAGE, ROGUE }

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

var character_name: String = "Hero"
var character_class: CharacterClass = CharacterClass.WARRIOR
var level: int = 1
var experience: float = 0.0
var max_health: float = 100.0
var max_mana: float = 50.0
var health: float = 100.0
var mana: float = 50.0
var strength: int = 10
var dexterity: int = 10
var intelligence: int = 10
var vitality: int = 10
var attack_damage: float = 10.0
var attack_speed: float = 1.0
var defense: float = 5.0
var move_speed: float = 7.0
var play_time_seconds: float = 0.0
var gold: int = 0
var health_potions: int = 0
var mana_potions: int = 0

# Inventory + equipment stored as arrays of item dicts
var inventory_items: Array = []
var equipment: Dictionary = {}

# Quest progress
var quest_data: Array = []

# Metadata
var created_at: String = ""
var last_played: String = ""
var save_slot: int = 0


static func create_new(char_name: String, char_class: CharacterClass) -> CharacterData:
	var data := CharacterData.new()
	data.character_name = char_name
	data.character_class = char_class
	data.created_at = Time.get_datetime_string_from_system()
	data.last_played = data.created_at

	# Class-specific starting stats (hardcoded fallback)
	match char_class:
		CharacterClass.WARRIOR:
			data.strength = 14
			data.vitality = 12
			data.dexterity = 8
			data.intelligence = 6
			data.max_health = 120.0
			data.health = 120.0
			data.max_mana = 30.0
			data.mana = 30.0
			data.attack_damage = 14.0
			data.defense = 8.0
		CharacterClass.MAGE:
			data.strength = 6
			data.vitality = 8
			data.dexterity = 8
			data.intelligence = 14
			data.max_health = 70.0
			data.health = 70.0
			data.max_mana = 100.0
			data.mana = 100.0
			data.attack_damage = 6.0
			data.defense = 3.0
		CharacterClass.ROGUE:
			data.strength = 8
			data.vitality = 8
			data.dexterity = 14
			data.intelligence = 8
			data.max_health = 90.0
			data.health = 90.0
			data.max_mana = 50.0
			data.mana = 50.0
			data.attack_damage = 11.0
			data.attack_speed = 1.4
			data.defense = 5.0

	# Override from JSON if available
	_load_game_data()
	var class_key: String = CharacterClass.keys()[char_class]
	if _game_data.has("classes") and _game_data["classes"].has(class_key):
		var cs: Dictionary = _game_data["classes"][class_key]
		data.strength = int(cs.get("strength", data.strength))
		data.dexterity = int(cs.get("dexterity", data.dexterity))
		data.intelligence = int(cs.get("intelligence", data.intelligence))
		data.vitality = int(cs.get("vitality", data.vitality))
		data.max_health = cs.get("max_health", data.max_health)
		data.health = data.max_health
		data.max_mana = cs.get("max_mana", data.max_mana)
		data.mana = data.max_mana
		data.attack_damage = cs.get("attack_damage", data.attack_damage)
		data.attack_speed = cs.get("attack_speed", data.attack_speed)
		data.defense = cs.get("defense", data.defense)
		data.move_speed = cs.get("move_speed", data.move_speed)

	return data


func to_dict() -> Dictionary:
	return {
		"character_name": character_name,
		"character_class": character_class,
		"level": level,
		"experience": experience,
		"max_health": max_health,
		"max_mana": max_mana,
		"health": health,
		"mana": mana,
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"vitality": vitality,
		"attack_damage": attack_damage,
		"attack_speed": attack_speed,
		"defense": defense,
		"move_speed": move_speed,
		"play_time_seconds": play_time_seconds,
		"gold": gold,
		"health_potions": health_potions,
		"mana_potions": mana_potions,
		"inventory_items": inventory_items,
		"equipment": equipment,
		"quest_data": quest_data,
		"created_at": created_at,
		"last_played": last_played,
		"save_slot": save_slot,
	}


static func from_dict(d: Dictionary) -> CharacterData:
	var data := CharacterData.new()
	data.character_name = d.get("character_name", "Hero")
	data.character_class = d.get("character_class", CharacterClass.WARRIOR) as CharacterClass
	data.level = d.get("level", 1)
	data.experience = d.get("experience", 0.0)
	data.max_health = d.get("max_health", 100.0)
	data.max_mana = d.get("max_mana", 50.0)
	data.health = d.get("health", 100.0)
	data.mana = d.get("mana", 50.0)
	data.strength = d.get("strength", 10)
	data.dexterity = d.get("dexterity", 10)
	data.intelligence = d.get("intelligence", 10)
	data.vitality = d.get("vitality", 10)
	data.attack_damage = d.get("attack_damage", 10.0)
	data.attack_speed = d.get("attack_speed", 1.0)
	data.defense = d.get("defense", 5.0)
	data.move_speed = d.get("move_speed", 7.0)
	data.play_time_seconds = d.get("play_time_seconds", 0.0)
	data.gold = d.get("gold", 0)
	data.health_potions = d.get("health_potions", 0)
	data.mana_potions = d.get("mana_potions", 0)
	data.inventory_items = d.get("inventory_items", [])
	data.equipment = d.get("equipment", {})
	data.quest_data = d.get("quest_data", [])
	data.created_at = d.get("created_at", "")
	data.last_played = d.get("last_played", "")
	data.save_slot = d.get("save_slot", 0)
	return data


static func class_name_from_enum(c: CharacterClass) -> String:
	match c:
		CharacterClass.WARRIOR: return "Warrior"
		CharacterClass.MAGE: return "Mage"
		CharacterClass.ROGUE: return "Rogue"
	return "Unknown"
