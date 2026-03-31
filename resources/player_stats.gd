extends Resource
class_name PlayerStats

## Defines RPG stats for a player character.

@export var max_health: float = 100.0
@export var max_mana: float = 50.0
@export var health: float = 100.0
@export var mana: float = 50.0
@export var strength: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var vitality: int = 10
@export var move_speed: float = 10.0
@export var attack_damage: float = 12.0
@export var attack_speed: float = 1.6
@export var defense: float = 5.0
@export var level: int = 1
@export var experience: float = 0.0

## Percentage-based stats from skill tree passives (stored as fractions, e.g. 0.05 = 5%)
var crit_chance_pct: float = 0.0
var crit_damage_pct: float = 0.0
var spell_damage_pct: float = 0.0
var attack_speed_pct: float = 0.0
var mana_regen_pct: float = 0.0
var mana_cost_reduction_pct: float = 0.0
var dodge_pct: float = 0.0

static var _progression: Dictionary = {}
static var _progression_loaded := false


static func _load_progression() -> void:
	if _progression_loaded:
		return
	_progression_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_progression = json.data.get("progression", {})
		file.close()


var experience_to_next_level: float:
	get:
		_load_progression()
		var base: float = _progression.get("xp_per_level_base", 100)
		return level * base


func take_damage(amount: float) -> float:
	_load_progression()
	var def_mult: float = _progression.get("defense_multiplier", 0.5)
	var reduced := maxf(amount - defense * def_mult, 1.0)
	health = maxf(health - reduced, 0.0)
	return reduced


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)


func tick_mana_regen(delta: float) -> void:
	if mana_regen_pct > 0.0 and mana < max_mana:
		mana = minf(mana + max_mana * mana_regen_pct * delta, max_mana)


func use_mana(amount: float) -> bool:
	if mana >= amount:
		mana -= amount
		return true
	return false


func add_experience(amount: float) -> int:
	experience += amount
	var levels_gained := 0
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		_on_level_up()
		levels_gained += 1
	return levels_gained


func _on_level_up() -> void:
	_load_progression()
	var hp_lv: float = _progression.get("hp_per_level", 10.0)
	var mp_lv: float = _progression.get("mana_per_level", 5.0)
	var st_lv: int = int(_progression.get("stats_per_level", 2))
	max_health += hp_lv
	max_mana += mp_lv
	health = max_health
	mana = max_mana
	strength += st_lv
	dexterity += st_lv
	intelligence += st_lv
	vitality += st_lv
