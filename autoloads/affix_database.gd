extends Node

## Manages procedural affix generation and resonance computation.
## All definitions loaded from data/game_data.json for easy tuning.

var _affix_pool: Dictionary = {}          # affix_id -> {tag, stat, range, label, desc}
var _resonance_tags: Dictionary = {}      # tag -> {label, color, tiers}
var _affixes_per_rarity: Array = []       # [0, 1, 2, 3, 3] indexed by Rarity enum
var _data_loaded := false


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data: Dictionary = json.data
	var lc: Dictionary = data.get("loot_config", {})
	_affix_pool = lc.get("affix_pool", {})
	_resonance_tags = lc.get("resonance_tags", {})
	_affixes_per_rarity = lc.get("affixes_per_rarity", [0, 1, 2, 3, 3])


# --- Affix Rolling ---

func roll_affixes_for_item(item: ItemData, enemy_level: int = 1) -> void:
	## Rolls random affixes onto an item based on its rarity.
	_load_data()
	var rarity_idx := int(item.rarity)
	var count: int = _affixes_per_rarity[mini(rarity_idx, _affixes_per_rarity.size() - 1)]
	if count <= 0:
		return

	var pool_keys: Array = _affix_pool.keys()
	if pool_keys.is_empty():
		return

	# Filter to valid affixes for this item type
	var valid_keys: Array = pool_keys.duplicate()
	var used_ids: Array = []

	for _i in range(count):
		if valid_keys.is_empty():
			break
		# Pick a random affix not yet on this item
		var available: Array = valid_keys.filter(func(k: String) -> bool: return k not in used_ids)
		if available.is_empty():
			break
		var affix_id: String = available[randi() % available.size()]
		used_ids.append(affix_id)

		var def: Dictionary = _affix_pool[affix_id]
		var value_range: Array = def.get("range", [1, 10])
		var min_val: float = value_range[0]
		var max_val: float = value_range[1]

		# Scale value by enemy level: higher level = higher end of range
		var level_factor := clampf((enemy_level - 1.0) / 30.0, 0.0, 1.0)
		# Add randomness: ±20% around the level-scaled midpoint
		var base_val: float = lerpf(min_val, max_val, level_factor)
		var variance: float = (max_val - min_val) * 0.2
		var final_val: float = clampf(base_val + randf_range(-variance, variance), min_val, max_val)

		# Round display: integers for flat stats, 2 decimals for percentages
		if final_val > 1.0:
			final_val = roundf(final_val)
		else:
			final_val = snappedf(final_val, 0.01)

		item.affixes.append({
			"id": affix_id,
			"tag": def.get("tag", ""),
			"stat": def.get("stat", ""),
			"value": final_val,
			"label": def.get("label", affix_id),
			"desc": def.get("desc", "").replace("{v}", _format_value(final_val, def.get("stat", ""))),
		})


# --- Resonance Computation ---

func compute_resonances(equipped_items: Dictionary) -> Dictionary:
	## Given a dict of slot->ItemData (equipment dict), returns active resonances.
	## Returns: {tag: {tier_data, count}} for each active resonance.
	_load_data()
	# Count tags across all equipped items
	var tag_counts: Dictionary = {}
	for slot: String in equipped_items:
		var item: ItemData = equipped_items[slot] as ItemData
		if item == null:
			continue
		for affix: Dictionary in item.affixes:
			var tag: String = affix.get("tag", "")
			if tag == "":
				continue
			tag_counts[tag] = tag_counts.get(tag, 0) + 1

	# Resolve which resonance tiers are active
	var active: Dictionary = {}
	for tag: String in tag_counts:
		var count: int = tag_counts[tag]
		if count < 2:
			continue
		var res_def: Dictionary = _resonance_tags.get(tag, {})
		var tiers: Array = res_def.get("tiers", [])
		# Find highest tier met
		var best_tier: Dictionary = {}
		var all_bonuses: Dictionary = {}
		for tier: Dictionary in tiers:
			var required: int = tier.get("count", 99)
			if count >= required:
				best_tier = tier
				# Accumulate all tier bonuses up to this level
				for key: String in tier.get("bonuses", {}):
					all_bonuses[key] = tier["bonuses"][key]

		if not best_tier.is_empty():
			active[tag] = {
				"label": res_def.get("label", tag),
				"tier_label": best_tier.get("label", ""),
				"desc": best_tier.get("desc", ""),
				"bonuses": all_bonuses,
				"count": count,
				"color": res_def.get("color", [1.0, 1.0, 1.0]),
			}

	return active


func get_resonance_stat_bonuses(resonances: Dictionary) -> Dictionary:
	## Flatten resonance bonuses into a stat->value dict for easy application.
	## Only includes numeric stat bonuses (skips booleans like explode_on_kill).
	var bonuses: Dictionary = {}
	for tag: String in resonances:
		var res: Dictionary = resonances[tag]
		for stat: String in res.get("bonuses", {}):
			var val = res["bonuses"][stat]
			if val is float or val is int:
				bonuses[stat] = bonuses.get(stat, 0.0) + float(val)
	return bonuses


func get_resonance_procs(resonances: Dictionary) -> Dictionary:
	## Returns boolean/special proc effects from resonances.
	## e.g. {explode_on_kill: true, chain_on_hit: true, frost_aura: true}
	var procs: Dictionary = {}
	for tag: String in resonances:
		var res: Dictionary = resonances[tag]
		for stat: String in res.get("bonuses", {}):
			var val = res["bonuses"][stat]
			if val is bool and val:
				procs[stat] = true
	return procs


func get_tag_color(tag: String) -> Color:
	_load_data()
	var res_def: Dictionary = _resonance_tags.get(tag, {})
	var c: Array = res_def.get("color", [1.0, 1.0, 1.0])
	return Color(c[0], c[1], c[2])


func get_tag_label(tag: String) -> String:
	_load_data()
	var res_def: Dictionary = _resonance_tags.get(tag, {})
	return res_def.get("label", tag.capitalize())


func _format_value(val: float, stat: String) -> String:
	if stat.ends_with("_pct"):
		return "%d" % int(val * 100)
	return str(int(val)) if val == floorf(val) else "%.1f" % val
