extends Node
class_name Inventory

## Player inventory: 5x10 grid with variable-size items, equipment paperdoll.

signal inventory_changed
signal item_equipped(slot: String, item: ItemData)
signal item_unequipped(slot: String)
signal gold_changed(amount: int)
signal potions_changed

const GRID_W := 5
const GRID_H := 10
const MAX_POTIONS := 5

var health_potions: int = 0
var mana_potions: int = 0

## Each placed item: { "item": ItemData, "x": int, "y": int, "stack": int }
var placed_items: Array[Dictionary] = []
var gold: int = 0
var equipment: Dictionary = {
	"weapon": null,
	"helmet": null,
	"chest": null,
	"boots": null,
	"ring": null,
	"amulet": null,
	"shield": null,
}


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


## Returns a 2D bool grid. True = occupied.
func _build_occupancy() -> Array:
	var grid: Array = []
	for y in GRID_H:
		var row: Array = []
		for x in GRID_W:
			row.append(false)
		grid.append(row)
	for entry in placed_items:
		var item: ItemData = entry["item"]
		var gx: int = entry["x"]
		var gy: int = entry["y"]
		var sz := item.get_grid_size()
		for dy in sz.y:
			for dx in sz.x:
				grid[gy + dy][gx + dx] = true
	return grid


func can_place_at(item: ItemData, gx: int, gy: int, exclude_entry: Dictionary = {}) -> bool:
	## Check if item fits at grid position (gx, gy).
	var sz := item.get_grid_size()
	if gx < 0 or gy < 0 or gx + sz.x > GRID_W or gy + sz.y > GRID_H:
		return false
	var grid := _build_occupancy()
	# Clear cells occupied by exclude_entry (when moving an item)
	if not exclude_entry.is_empty():
		var ex_item: ItemData = exclude_entry["item"]
		var ex: int = exclude_entry["x"]
		var ey: int = exclude_entry["y"]
		var esz := ex_item.get_grid_size()
		for dy in esz.y:
			for dx in esz.x:
				grid[ey + dy][ex + dx] = false
	for dy in sz.y:
		for dx in sz.x:
			if grid[gy + dy][gx + dx]:
				return false
	return true


func add_potion(potion_id: String) -> bool:
	## Add a potion by ID. Returns false if at max.
	if potion_id == "health_potion":
		if health_potions >= MAX_POTIONS:
			return false
		health_potions += 1
		potions_changed.emit()
		return true
	elif potion_id == "mana_potion":
		if mana_potions >= MAX_POTIONS:
			return false
		mana_potions += 1
		potions_changed.emit()
		return true
	return false


func can_hold_potion(potion_id: String) -> bool:
	if potion_id == "health_potion":
		return health_potions < MAX_POTIONS
	elif potion_id == "mana_potion":
		return mana_potions < MAX_POTIONS
	return false


func use_health_potion(player: Node) -> bool:
	if health_potions <= 0:
		return false
	health_potions -= 1
	if player and player.get("stats"):
		var stats: PlayerStats = player.stats
		stats.heal(30.0)
	potions_changed.emit()
	return true


func use_mana_potion(player: Node) -> bool:
	if mana_potions <= 0:
		return false
	mana_potions -= 1
	if player and player.get("stats"):
		var stats: PlayerStats = player.stats
		stats.mana = minf(stats.mana + 20.0, stats.max_mana)
	potions_changed.emit()
	return true


func add_item(item: ItemData) -> bool:
	## Auto-place item in grid. Potions are handled separately via add_potion().
	# Find first free position
	var pos := find_free_position(item)
	if pos.x < 0:
		return false
	placed_items.append({"item": item, "x": pos.x, "y": pos.y, "stack": 1})
	inventory_changed.emit()
	return true


func find_free_position(item: ItemData) -> Vector2i:
	## Try placing at every grid cell, return first valid position or (-1,-1).
	var sz := item.get_grid_size()
	for gy in GRID_H:
		for gx in GRID_W:
			if gx + sz.x <= GRID_W and gy + sz.y <= GRID_H:
				if can_place_at(item, gx, gy):
					return Vector2i(gx, gy)
	return Vector2i(-1, -1)


func place_item_at(item: ItemData, gx: int, gy: int, stack: int = 1) -> bool:
	## Place item at specific grid position.
	if not can_place_at(item, gx, gy):
		return false
	placed_items.append({"item": item, "x": gx, "y": gy, "stack": stack})
	inventory_changed.emit()
	return true


func remove_entry(entry: Dictionary) -> void:
	var idx := placed_items.find(entry)
	if idx >= 0:
		placed_items.remove_at(idx)
		inventory_changed.emit()


func get_entry_at(gx: int, gy: int) -> Dictionary:
	## Find which placed item covers grid cell (gx, gy).
	for entry in placed_items:
		var item: ItemData = entry["item"]
		var ex: int = entry["x"]
		var ey: int = entry["y"]
		var sz := item.get_grid_size()
		if gx >= ex and gx < ex + sz.x and gy >= ey and gy < ey + sz.y:
			return entry
	return {}


func move_entry(entry: Dictionary, new_x: int, new_y: int) -> bool:
	## Move an existing entry to a new grid position.
	var item: ItemData = entry["item"]
	if not can_place_at(item, new_x, new_y, entry):
		return false
	entry["x"] = new_x
	entry["y"] = new_y
	inventory_changed.emit()
	return true


## --- Equipment ---

func equip_item_from_entry(entry: Dictionary, player: Node) -> void:
	var item: ItemData = entry["item"]
	var slot := _get_equip_slot(item.item_type)
	if slot.is_empty():
		return
	# Remove from grid
	var idx := placed_items.find(entry)
	if idx < 0:
		return
	placed_items.remove_at(idx)
	# Unequip current item in slot (put back in grid)
	if equipment[slot] != null:
		var old_item: ItemData = equipment[slot]
		_remove_stat_bonuses(old_item, player)
		# Try to place old item in freed grid space
		if not add_item(old_item):
			# Grid full — re-put in equipment and abort
			_apply_stat_bonuses(old_item, player)
			placed_items.insert(idx, entry)
			return
	equipment[slot] = item
	_apply_stat_bonuses(item, player)
	item_equipped.emit(slot, item)
	inventory_changed.emit()


func unequip_item(slot: String, player: Node) -> bool:
	if not equipment.has(slot) or equipment[slot] == null:
		return false
	var item: ItemData = equipment[slot]
	var pos := find_free_position(item)
	if pos.x < 0:
		return false  # No grid space
	_remove_stat_bonuses(item, player)
	equipment[slot] = null
	placed_items.append({"item": item, "x": pos.x, "y": pos.y, "stack": 1})
	item_unequipped.emit(slot)
	inventory_changed.emit()
	return true





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
		ItemData.ItemType.SHIELD: return "shield"
	return ""


## --- Serialization for save/load ---

func serialize_grid() -> Array:
	## Convert placed_items to serializable array of dicts.
	var result: Array = []
	for entry in placed_items:
		var item: ItemData = entry["item"]
		result.append({
			"item": item.to_dict(),
			"x": entry["x"],
			"y": entry["y"],
			"stack": entry.get("stack", 1),
		})
	return result


func deserialize_grid(data: Array) -> void:
	## Load placed_items from serialized array.
	placed_items.clear()
	for d in data:
		var item := ItemData.from_dict(d["item"])
		placed_items.append({
			"item": item,
			"x": int(d["x"]),
			"y": int(d["y"]),
			"stack": int(d.get("stack", 1)),
		})


func serialize_potions() -> Dictionary:
	return {"health_potions": health_potions, "mana_potions": mana_potions}


func deserialize_potions(data: Dictionary) -> void:
	health_potions = int(data.get("health_potions", 0))
	mana_potions = int(data.get("mana_potions", 0))
	potions_changed.emit()
	inventory_changed.emit()


func legacy_import(items_array: Array) -> void:
	## Import flat item list from old save format into grid.
	placed_items.clear()
	for item_dict in items_array:
		var item := ItemData.from_dict(item_dict)
		add_item(item)  # Auto-places in grid
