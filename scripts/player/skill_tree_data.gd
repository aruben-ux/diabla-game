extends RefCounted
class_name SkillTreeData

## Static skill tree definitions for all classes.
## Each class has 3 branches, each branch has 6 nodes in a linear chain
## (some nodes branch or have prereqs).
##
## Node structure:
##   id: String — unique identifier
##   name: String — display name
##   description: String — tooltip text
##   icon_color: Color — visual color for the node
##   max_rank: int — how many points can be invested (1 = unlock, 2-3 = rankable)
##   requires: Array[String] — node IDs that must have at least 1 point
##   row: int — vertical position in the tree (0 = top, 5 = bottom)
##   col: int — horizontal position within the branch (0 = center, -1 left, 1 right)
##   type: String — "passive" or "active"
##   effects: Dictionary — what the node does per rank
##     For passives: stat bonuses like {"strength": 3} or {"attack_damage_pct": 5}
##     For actives: {"skill_id": "whirlwind"} — unlocks/upgrades a skill

# ===================== WARRIOR =====================
# Branch 1: Arms (Offense — weapon mastery and raw damage)
# Branch 2: Valor (Defense — toughness and survivability)
# Branch 3: Warcry (Utility — buffs, auras, shouts)

static func get_warrior_trees() -> Array[Dictionary]:
	return [
		# --- ARMS (Offense) ---
		{
			"branch_name": "Arms",
			"branch_color": Color(0.9, 0.3, 0.2),
			"branch_description": "Weapon mastery and raw damage.",
			"nodes": [
				{"id": "w_arms_1", "name": "Sharpened Blade", "description": "+4 Attack Damage per rank.", "icon_color": Color(0.9, 0.3, 0.2), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"attack_damage": 4}},
				{"id": "w_arms_2", "name": "Cleave", "description": "Unlocks Cleave: Slash in an arc, hitting all enemies in front.", "icon_color": Color(1.0, 0.4, 0.2), "max_rank": 1, "requires": ["w_arms_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "cleave"}},
				{"id": "w_arms_3", "name": "Deep Wounds", "description": "+5% critical damage per rank.", "icon_color": Color(0.8, 0.2, 0.2), "max_rank": 3, "requires": ["w_arms_2"], "row": 2, "col": 0, "type": "passive", "effects": {"crit_damage_pct": 5}},
				{"id": "w_arms_4", "name": "Brutal Strike", "description": "+3% critical chance per rank.", "icon_color": Color(0.85, 0.25, 0.15), "max_rank": 3, "requires": ["w_arms_2"], "row": 3, "col": 0, "type": "passive", "effects": {"crit_chance_pct": 3}},
				{"id": "w_arms_5", "name": "Whirlwind", "description": "Unlocks Whirlwind: Spin and damage all nearby enemies.", "icon_color": Color(0.7, 0.85, 1.0), "max_rank": 1, "requires": ["w_arms_3"], "row": 4, "col": 0, "type": "active", "effects": {"skill_id": "whirlwind"}},
				{"id": "w_arms_6", "name": "Executioner", "description": "+8 Attack Damage, +5% crit damage per rank.", "icon_color": Color(1.0, 0.2, 0.1), "max_rank": 3, "requires": ["w_arms_5"], "row": 5, "col": 0, "type": "passive", "effects": {"attack_damage": 8, "crit_damage_pct": 5}},
			],
		},
		# --- VALOR (Defense) ---
		{
			"branch_name": "Valor",
			"branch_color": Color(0.3, 0.5, 0.9),
			"branch_description": "Toughness and survivability.",
			"nodes": [
				{"id": "w_valor_1", "name": "Tough Skin", "description": "+3 Defense per rank.", "icon_color": Color(0.3, 0.5, 0.9), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"defense": 3}},
				{"id": "w_valor_2", "name": "Shield Wall", "description": "Unlocks Shield Wall: Block all damage for 3 seconds.", "icon_color": Color(0.4, 0.6, 1.0), "max_rank": 1, "requires": ["w_valor_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "shield_wall"}},
				{"id": "w_valor_3", "name": "Vitality", "description": "+15 Max Health per rank.", "icon_color": Color(0.2, 0.7, 0.3), "max_rank": 3, "requires": ["w_valor_2"], "row": 2, "col": 0, "type": "passive", "effects": {"max_health": 15}},
				{"id": "w_valor_4", "name": "Iron Will", "description": "+5 Defense, +10 Max Health per rank.", "icon_color": Color(0.5, 0.5, 0.6), "max_rank": 3, "requires": ["w_valor_2"], "row": 3, "col": 0, "type": "passive", "effects": {"defense": 5, "max_health": 10}},
				{"id": "w_valor_5", "name": "Ground Slam", "description": "Unlocks Ground Slam: Slam the ground, stunning nearby enemies.", "icon_color": Color(0.6, 0.4, 0.2), "max_rank": 1, "requires": ["w_valor_4"], "row": 4, "col": 0, "type": "active", "effects": {"skill_id": "ground_slam"}},
				{"id": "w_valor_6", "name": "Unbreakable", "description": "+8 Defense, +20 Max Health per rank.", "icon_color": Color(0.4, 0.55, 0.95), "max_rank": 3, "requires": ["w_valor_5"], "row": 5, "col": 0, "type": "passive", "effects": {"defense": 8, "max_health": 20}},
			],
		},
		# --- WARCRY (Utility) ---
		{
			"branch_name": "Warcry",
			"branch_color": Color(0.9, 0.75, 0.2),
			"branch_description": "Buffs, battle shouts, and auras.",
			"nodes": [
				{"id": "w_warcry_1", "name": "Battle Shout", "description": "+2 Strength per rank.", "icon_color": Color(0.9, 0.75, 0.2), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"strength": 2}},
				{"id": "w_warcry_2", "name": "War Cry", "description": "Unlocks War Cry: Boost damage of nearby allies for 8s.", "icon_color": Color(1.0, 0.85, 0.3), "max_rank": 1, "requires": ["w_warcry_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "war_cry"}},
				{"id": "w_warcry_3", "name": "Bloodlust", "description": "+5% Attack Speed per rank.", "icon_color": Color(0.8, 0.2, 0.2), "max_rank": 3, "requires": ["w_warcry_2"], "row": 2, "col": 0, "type": "passive", "effects": {"attack_speed_pct": 5}},
				{"id": "w_warcry_4", "name": "Charge", "description": "Unlocks Charge: Rush forward and stun the first enemy hit.", "icon_color": Color(0.95, 0.6, 0.1), "max_rank": 1, "requires": ["w_warcry_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "charge"}},
				{"id": "w_warcry_5", "name": "Veteran", "description": "+3 to Strength and Vitality per rank.", "icon_color": Color(0.7, 0.65, 0.3), "max_rank": 3, "requires": ["w_warcry_3"], "row": 4, "col": 0, "type": "passive", "effects": {"strength": 3, "vitality": 3}},
				{"id": "w_warcry_6", "name": "Berserker Rage", "description": "Unlocks Berserker Rage: Greatly boost damage but take more damage for 10s.", "icon_color": Color(1.0, 0.3, 0.1), "max_rank": 1, "requires": ["w_warcry_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "berserker_rage"}},
			],
		},
	]


# ===================== MAGE =====================
# Branch 1: Fire (Destruction — fire spells and burst damage)
# Branch 2: Frost (Control — slows, freezes, and area denial)
# Branch 3: Arcane (Utility — mana, shields, teleport)

static func get_mage_trees() -> Array[Dictionary]:
	return [
		# --- FIRE (Destruction) ---
		{
			"branch_name": "Fire",
			"branch_color": Color(1.0, 0.4, 0.1),
			"branch_description": "Fire spells and burst damage.",
			"nodes": [
				{"id": "m_fire_1", "name": "Ignite", "description": "+3 Intelligence per rank.", "icon_color": Color(1.0, 0.5, 0.1), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"intelligence": 3}},
				{"id": "m_fire_2", "name": "Fireball", "description": "Unlocks Fireball: Hurl a ball of fire at a target area.", "icon_color": Color(1.0, 0.4, 0.0), "max_rank": 1, "requires": ["m_fire_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "fireball"}},
				{"id": "m_fire_3", "name": "Searing Heat", "description": "+6% spell damage per rank.", "icon_color": Color(1.0, 0.6, 0.2), "max_rank": 3, "requires": ["m_fire_2"], "row": 2, "col": 0, "type": "passive", "effects": {"spell_damage_pct": 6}},
				{"id": "m_fire_4", "name": "Fire Wall", "description": "Unlocks Fire Wall: Create a wall of flame that damages enemies passing through.", "icon_color": Color(0.9, 0.3, 0.0), "max_rank": 1, "requires": ["m_fire_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "fire_wall"}},
				{"id": "m_fire_5", "name": "Pyromaniac", "description": "+4 Intelligence, +5% spell damage per rank.", "icon_color": Color(1.0, 0.35, 0.05), "max_rank": 3, "requires": ["m_fire_3"], "row": 4, "col": 0, "type": "passive", "effects": {"intelligence": 4, "spell_damage_pct": 5}},
				{"id": "m_fire_6", "name": "Meteor", "description": "Unlocks Meteor: Call down a devastating meteor on a target area.", "icon_color": Color(1.0, 0.2, 0.0), "max_rank": 1, "requires": ["m_fire_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "meteor"}},
			],
		},
		# --- FROST (Control) ---
		{
			"branch_name": "Frost",
			"branch_color": Color(0.3, 0.7, 1.0),
			"branch_description": "Slows, freezes, and area denial.",
			"nodes": [
				{"id": "m_frost_1", "name": "Chilling Touch", "description": "+2 Intelligence, +5 Max Mana per rank.", "icon_color": Color(0.4, 0.75, 1.0), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"intelligence": 2, "max_mana": 5}},
				{"id": "m_frost_2", "name": "Frost Nova", "description": "Unlocks Frost Nova: Blast frost around you, damaging and slowing enemies.", "icon_color": Color(0.3, 0.8, 1.0), "max_rank": 1, "requires": ["m_frost_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "frost_nova"}},
				{"id": "m_frost_3", "name": "Hypothermia", "description": "+4% spell damage, +8 Max Mana per rank.", "icon_color": Color(0.5, 0.8, 1.0), "max_rank": 3, "requires": ["m_frost_2"], "row": 2, "col": 0, "type": "passive", "effects": {"spell_damage_pct": 4, "max_mana": 8}},
				{"id": "m_frost_4", "name": "Ice Barrier", "description": "Unlocks Ice Barrier: Shield yourself in ice, absorbing damage for 5s.", "icon_color": Color(0.6, 0.85, 1.0), "max_rank": 1, "requires": ["m_frost_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "ice_barrier"}},
				{"id": "m_frost_5", "name": "Permafrost", "description": "+3 Intelligence, +10 Max Mana per rank.", "icon_color": Color(0.2, 0.6, 0.9), "max_rank": 3, "requires": ["m_frost_3"], "row": 4, "col": 0, "type": "passive", "effects": {"intelligence": 3, "max_mana": 10}},
				{"id": "m_frost_6", "name": "Blizzard", "description": "Unlocks Blizzard: Summon a blizzard that rains ice on an area for 6s.", "icon_color": Color(0.15, 0.5, 0.95), "max_rank": 1, "requires": ["m_frost_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "blizzard"}},
			],
		},
		# --- ARCANE (Utility) ---
		{
			"branch_name": "Arcane",
			"branch_color": Color(0.6, 0.3, 0.9),
			"branch_description": "Mana mastery, shields, and teleportation.",
			"nodes": [
				{"id": "m_arcane_1", "name": "Mana Flow", "description": "+8 Max Mana per rank.", "icon_color": Color(0.5, 0.3, 0.8), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"max_mana": 8}},
				{"id": "m_arcane_2", "name": "Arcane Missiles", "description": "Unlocks Arcane Missiles: Fire a rapid volley of arcane bolts.", "icon_color": Color(0.6, 0.3, 1.0), "max_rank": 1, "requires": ["m_arcane_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "arcane_missiles"}},
				{"id": "m_arcane_3", "name": "Meditation", "description": "+5% mana regen speed per rank.", "icon_color": Color(0.55, 0.4, 0.85), "max_rank": 3, "requires": ["m_arcane_2"], "row": 2, "col": 0, "type": "passive", "effects": {"mana_regen_pct": 5}},
				{"id": "m_arcane_4", "name": "Teleport", "description": "Unlocks Teleport: Instantly blink to a target location.", "icon_color": Color(0.7, 0.4, 1.0), "max_rank": 1, "requires": ["m_arcane_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "teleport"}},
				{"id": "m_arcane_5", "name": "Arcane Mastery", "description": "+4 Intelligence, -5% mana cost per rank.", "icon_color": Color(0.65, 0.35, 0.95), "max_rank": 3, "requires": ["m_arcane_3"], "row": 4, "col": 0, "type": "passive", "effects": {"intelligence": 4, "mana_cost_reduction_pct": 5}},
				{"id": "m_arcane_6", "name": "Mana Shield", "description": "Unlocks Mana Shield: Convert damage taken to mana cost for 10s.", "icon_color": Color(0.5, 0.2, 1.0), "max_rank": 1, "requires": ["m_arcane_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "mana_shield"}},
			],
		},
	]


# ===================== ROGUE =====================
# Branch 1: Assassination (Burst damage — crits, poisons, backstab)
# Branch 2: Shadow (Evasion — stealth, dodge, mobility)
# Branch 3: Traps (Control — traps, bleeds, debuffs)

static func get_rogue_trees() -> Array[Dictionary]:
	return [
		# --- ASSASSINATION (Burst) ---
		{
			"branch_name": "Assassination",
			"branch_color": Color(0.6, 0.1, 0.2),
			"branch_description": "Burst damage, crits, and poisons.",
			"nodes": [
				{"id": "r_assn_1", "name": "Lethality", "description": "+3 Dexterity per rank.", "icon_color": Color(0.6, 0.1, 0.2), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"dexterity": 3}},
				{"id": "r_assn_2", "name": "Backstab", "description": "Unlocks Backstab: Teleport behind an enemy and deal massive damage.", "icon_color": Color(0.7, 0.15, 0.25), "max_rank": 1, "requires": ["r_assn_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "backstab"}},
				{"id": "r_assn_3", "name": "Twist the Knife", "description": "+5% critical chance per rank.", "icon_color": Color(0.65, 0.1, 0.15), "max_rank": 3, "requires": ["r_assn_2"], "row": 2, "col": 0, "type": "passive", "effects": {"crit_chance_pct": 5}},
				{"id": "r_assn_4", "name": "Poison Blade", "description": "Unlocks Poison Blade: Coat your weapons in poison, adding DoT to attacks.", "icon_color": Color(0.3, 0.7, 0.2), "max_rank": 1, "requires": ["r_assn_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "poison_blade"}},
				{"id": "r_assn_5", "name": "Cold Blood", "description": "+6% critical damage, +3 Dexterity per rank.", "icon_color": Color(0.5, 0.05, 0.1), "max_rank": 3, "requires": ["r_assn_3"], "row": 4, "col": 0, "type": "passive", "effects": {"crit_damage_pct": 6, "dexterity": 3}},
				{"id": "r_assn_6", "name": "Death Mark", "description": "Unlocks Death Mark: Mark an enemy to take 50% more damage for 6s.", "icon_color": Color(0.8, 0.1, 0.1), "max_rank": 1, "requires": ["r_assn_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "death_mark"}},
			],
		},
		# --- SHADOW (Evasion) ---
		{
			"branch_name": "Shadow",
			"branch_color": Color(0.25, 0.2, 0.35),
			"branch_description": "Stealth, evasion, and mobility.",
			"nodes": [
				{"id": "r_shadow_1", "name": "Nimble Feet", "description": "+0.5 Move Speed per rank.", "icon_color": Color(0.25, 0.2, 0.35), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"move_speed": 0.5}},
				{"id": "r_shadow_2", "name": "Shadow Step", "description": "Unlocks Shadow Step: Dash through shadows to a target location.", "icon_color": Color(0.3, 0.25, 0.45), "max_rank": 1, "requires": ["r_shadow_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "shadow_step"}},
				{"id": "r_shadow_3", "name": "Evasion", "description": "+4% dodge chance per rank.", "icon_color": Color(0.35, 0.3, 0.5), "max_rank": 3, "requires": ["r_shadow_2"], "row": 2, "col": 0, "type": "passive", "effects": {"dodge_pct": 4}},
				{"id": "r_shadow_4", "name": "Vanish", "description": "Unlocks Vanish: Become invisible for 4s, next attack deals bonus damage.", "icon_color": Color(0.15, 0.12, 0.25), "max_rank": 1, "requires": ["r_shadow_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "vanish"}},
				{"id": "r_shadow_5", "name": "Fleet Footed", "description": "+0.5 Move Speed, +3% dodge per rank.", "icon_color": Color(0.2, 0.18, 0.3), "max_rank": 3, "requires": ["r_shadow_3"], "row": 4, "col": 0, "type": "passive", "effects": {"move_speed": 0.5, "dodge_pct": 3}},
				{"id": "r_shadow_6", "name": "Smoke Bomb", "description": "Unlocks Smoke Bomb: Throw a smoke bomb, blinding enemies in the area.", "icon_color": Color(0.4, 0.35, 0.5), "max_rank": 1, "requires": ["r_shadow_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "smoke_bomb"}},
			],
		},
		# --- TRAPS (Control) ---
		{
			"branch_name": "Traps",
			"branch_color": Color(0.7, 0.55, 0.2),
			"branch_description": "Traps, bleeds, and debuffs.",
			"nodes": [
				{"id": "r_traps_1", "name": "Cunning", "description": "+2 Dexterity, +2 Intelligence per rank.", "icon_color": Color(0.7, 0.55, 0.2), "max_rank": 3, "requires": [], "row": 0, "col": 0, "type": "passive", "effects": {"dexterity": 2, "intelligence": 2}},
				{"id": "r_traps_2", "name": "Spike Trap", "description": "Unlocks Spike Trap: Place a trap that damages and slows enemies.", "icon_color": Color(0.75, 0.6, 0.25), "max_rank": 1, "requires": ["r_traps_1"], "row": 1, "col": 0, "type": "active", "effects": {"skill_id": "spike_trap"}},
				{"id": "r_traps_3", "name": "Serrated Edges", "description": "+4 Attack Damage per rank.", "icon_color": Color(0.65, 0.5, 0.15), "max_rank": 3, "requires": ["r_traps_2"], "row": 2, "col": 0, "type": "passive", "effects": {"attack_damage": 4}},
				{"id": "r_traps_4", "name": "Fan of Knives", "description": "Unlocks Fan of Knives: Throw knives in all directions.", "icon_color": Color(0.7, 0.5, 0.3), "max_rank": 1, "requires": ["r_traps_2"], "row": 3, "col": 0, "type": "active", "effects": {"skill_id": "fan_of_knives"}},
				{"id": "r_traps_5", "name": "Resourceful", "description": "+3 Dexterity, +4 Attack Damage per rank.", "icon_color": Color(0.6, 0.45, 0.15), "max_rank": 3, "requires": ["r_traps_3"], "row": 4, "col": 0, "type": "passive", "effects": {"dexterity": 3, "attack_damage": 4}},
				{"id": "r_traps_6", "name": "Rain of Arrows", "description": "Unlocks Rain of Arrows: Shower a target area with arrows for 4s.", "icon_color": Color(0.8, 0.6, 0.1), "max_rank": 1, "requires": ["r_traps_5"], "row": 5, "col": 0, "type": "active", "effects": {"skill_id": "rain_of_arrows"}},
			],
		},
	]


static func get_trees_for_class(char_class: int) -> Array[Dictionary]:
	match char_class:
		0: return get_warrior_trees()
		1: return get_mage_trees()
		2: return get_rogue_trees()
	return get_warrior_trees()


## Returns all skill definitions (SkillData) for active skills that exist in the tree system.
## Used by SkillManager to create skill objects when unlocked.
static func get_all_skill_definitions() -> Dictionary:
	var skills := {}

	# --- WARRIOR ACTIVES ---
	skills["cleave"] = {"display_name": "Cleave", "description": "Slash in an arc, hitting all enemies in front.", "target_type": "SELF", "cooldown": 2.0, "mana_cost": 8.0, "damage": 25.0, "radius": 4.0, "icon_color": Color(1.0, 0.4, 0.2)}
	skills["whirlwind"] = {"display_name": "Whirlwind", "description": "Spin and damage all nearby enemies.", "target_type": "SELF", "cooldown": 2.5, "mana_cost": 8.0, "damage": 22.0, "radius": 4.5, "icon_color": Color(0.7, 0.85, 1.0)}
	skills["shield_wall"] = {"display_name": "Shield Wall", "description": "Block all damage for 3 seconds.", "target_type": "SELF", "cooldown": 12.0, "mana_cost": 15.0, "damage": 0.0, "duration": 3.0, "icon_color": Color(0.4, 0.6, 1.0)}
	skills["ground_slam"] = {"display_name": "Ground Slam", "description": "Slam the ground, stunning nearby enemies.", "target_type": "SELF", "cooldown": 6.0, "mana_cost": 12.0, "damage": 30.0, "radius": 5.0, "icon_color": Color(0.6, 0.4, 0.2)}
	skills["war_cry"] = {"display_name": "War Cry", "description": "Boost damage of nearby allies for 8s.", "target_type": "SELF", "cooldown": 15.0, "mana_cost": 10.0, "damage": 0.0, "duration": 8.0, "icon_color": Color(1.0, 0.85, 0.3)}
	skills["charge"] = {"display_name": "Charge", "description": "Rush forward and stun the first enemy hit.", "target_type": "POINT", "cooldown": 5.0, "mana_cost": 8.0, "damage": 20.0, "radius": 3.5, "range_dist": 12.0, "icon_color": Color(0.95, 0.6, 0.1)}
	skills["berserker_rage"] = {"display_name": "Berserker Rage", "description": "Greatly boost damage but take more damage for 10s.", "target_type": "SELF", "cooldown": 20.0, "mana_cost": 5.0, "damage": 0.0, "duration": 10.0, "icon_color": Color(1.0, 0.3, 0.1)}

	# --- MAGE ACTIVES ---
	skills["fireball"] = {"display_name": "Fireball", "description": "Hurl a ball of fire at a target area.", "target_type": "POINT", "cooldown": 1.8, "mana_cost": 10.0, "damage": 28.0, "radius": 4.0, "range_dist": 12.0, "icon_color": Color(1.0, 0.4, 0.0)}
	skills["fire_wall"] = {"display_name": "Fire Wall", "description": "Create a wall of flame that damages enemies passing through.", "target_type": "POINT", "cooldown": 8.0, "mana_cost": 18.0, "damage": 15.0, "radius": 4.0, "duration": 5.0, "range_dist": 10.0, "icon_color": Color(0.9, 0.3, 0.0)}
	skills["meteor"] = {"display_name": "Meteor", "description": "Call down a devastating meteor on a target area.", "target_type": "POINT", "cooldown": 10.0, "mana_cost": 25.0, "damage": 80.0, "radius": 5.0, "range_dist": 14.0, "icon_color": Color(1.0, 0.2, 0.0)}
	skills["frost_nova"] = {"display_name": "Frost Nova", "description": "Blast frost around you, damaging and slowing enemies.", "target_type": "SELF", "cooldown": 3.0, "mana_cost": 11.0, "damage": 26.0, "radius": 5.5, "icon_color": Color(0.3, 0.8, 1.0)}
	skills["ice_barrier"] = {"display_name": "Ice Barrier", "description": "Shield yourself in ice, absorbing damage for 5s.", "target_type": "SELF", "cooldown": 14.0, "mana_cost": 16.0, "damage": 0.0, "duration": 5.0, "icon_color": Color(0.6, 0.85, 1.0)}
	skills["blizzard"] = {"display_name": "Blizzard", "description": "Summon a blizzard that rains ice on an area for 6s.", "target_type": "POINT", "cooldown": 12.0, "mana_cost": 22.0, "damage": 12.0, "radius": 6.0, "duration": 6.0, "range_dist": 12.0, "icon_color": Color(0.15, 0.5, 0.95)}
	skills["arcane_missiles"] = {"display_name": "Arcane Missiles", "description": "Fire a rapid volley of arcane bolts.", "target_type": "POINT", "cooldown": 1.5, "mana_cost": 8.0, "damage": 18.0, "radius": 3.0, "range_dist": 10.0, "icon_color": Color(0.6, 0.3, 1.0)}
	skills["teleport"] = {"display_name": "Teleport", "description": "Instantly blink to a target location.", "target_type": "POINT", "cooldown": 6.0, "mana_cost": 12.0, "damage": 0.0, "range_dist": 12.0, "icon_color": Color(0.7, 0.4, 1.0)}
	skills["mana_shield"] = {"display_name": "Mana Shield", "description": "Convert damage taken to mana cost for 10s.", "target_type": "SELF", "cooldown": 18.0, "mana_cost": 8.0, "damage": 0.0, "duration": 10.0, "icon_color": Color(0.5, 0.2, 1.0)}

	# --- ROGUE ACTIVES ---
	skills["backstab"] = {"display_name": "Backstab", "description": "Teleport behind an enemy and deal massive damage.", "target_type": "POINT", "cooldown": 4.0, "mana_cost": 10.0, "damage": 45.0, "range_dist": 8.0, "icon_color": Color(0.7, 0.15, 0.25)}
	skills["poison_blade"] = {"display_name": "Poison Blade", "description": "Coat your weapons in poison, adding DoT to attacks.", "target_type": "SELF", "cooldown": 15.0, "mana_cost": 10.0, "damage": 5.0, "duration": 10.0, "icon_color": Color(0.3, 0.7, 0.2)}
	skills["death_mark"] = {"display_name": "Death Mark", "description": "Mark an enemy to take 50% more damage for 6s.", "target_type": "POINT", "cooldown": 12.0, "mana_cost": 14.0, "damage": 0.0, "duration": 6.0, "range_dist": 10.0, "icon_color": Color(0.8, 0.1, 0.1)}
	skills["shadow_step"] = {"display_name": "Shadow Step", "description": "Dash through shadows to a target location.", "target_type": "POINT", "cooldown": 4.0, "mana_cost": 8.0, "damage": 0.0, "range_dist": 10.0, "icon_color": Color(0.3, 0.25, 0.45)}
	skills["vanish"] = {"display_name": "Vanish", "description": "Become invisible for 4s, next attack deals bonus damage.", "target_type": "SELF", "cooldown": 16.0, "mana_cost": 12.0, "damage": 0.0, "duration": 4.0, "icon_color": Color(0.15, 0.12, 0.25)}
	skills["smoke_bomb"] = {"display_name": "Smoke Bomb", "description": "Throw a smoke bomb, blinding enemies in the area.", "target_type": "POINT", "cooldown": 10.0, "mana_cost": 10.0, "damage": 10.0, "radius": 5.0, "duration": 4.0, "range_dist": 8.0, "icon_color": Color(0.4, 0.35, 0.5)}
	skills["spike_trap"] = {"display_name": "Spike Trap", "description": "Place a trap that damages and slows enemies.", "target_type": "POINT", "cooldown": 8.0, "mana_cost": 10.0, "damage": 30.0, "radius": 3.0, "range_dist": 8.0, "icon_color": Color(0.75, 0.6, 0.25)}
	skills["fan_of_knives"] = {"display_name": "Fan of Knives", "description": "Throw knives in all directions.", "target_type": "SELF", "cooldown": 3.5, "mana_cost": 9.0, "damage": 20.0, "radius": 5.0, "icon_color": Color(0.7, 0.5, 0.3)}
	skills["rain_of_arrows"] = {"display_name": "Rain of Arrows", "description": "Shower a target area with arrows for 4s.", "target_type": "POINT", "cooldown": 10.0, "mana_cost": 18.0, "damage": 15.0, "radius": 6.0, "duration": 4.0, "range_dist": 12.0, "icon_color": Color(0.8, 0.6, 0.1)}

	# --- SHARED (Heal - available if no tree skill in slot) ---
	skills["heal"] = {"display_name": "Heal", "description": "Restore health.", "target_type": "SELF", "cooldown": 5.0, "mana_cost": 12.0, "damage": 45.0, "icon_color": Color(0.2, 0.9, 0.3)}

	return skills
