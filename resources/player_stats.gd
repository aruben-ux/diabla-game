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

var experience_to_next_level: float:
	get:
		return level * 100.0


func take_damage(amount: float) -> float:
	var reduced := maxf(amount - defense * 0.5, 1.0)
	health = maxf(health - reduced, 0.0)
	return reduced


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)


func use_mana(amount: float) -> bool:
	if mana >= amount:
		mana -= amount
		return true
	return false


func add_experience(amount: float) -> bool:
	experience += amount
	if experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		_on_level_up()
		return true
	return false


func _on_level_up() -> void:
	max_health += 10.0
	max_mana += 5.0
	health = max_health
	mana = max_mana
	strength += 2
	dexterity += 2
	intelligence += 2
	vitality += 2
