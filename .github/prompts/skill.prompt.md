---
description: "Design a new skill for a class in Diabla. Use when the user says add skill, new skill, new ability, skill design, or create spell."
agent: "agent"
tools: ["read", "edit", "search"]
argument-hint: "Describe the skill concept (e.g. 'warrior leap attack that stuns')"
---

Design a new skill for the Diabla ARPG. Follow these steps:

## 1. Gather Context

Read these files first:
- [scripts/player/skill_tree_data.gd](scripts/player/skill_tree_data.gd) — all tree definitions and skill defs
- [scripts/player/skill_manager.gd](scripts/player/skill_manager.gd) — `_execute_skill()` implementation
- [scripts/visuals/skill_vfx.gd](scripts/visuals/skill_vfx.gd) — VFX system
- [scripts/player/player.gd](scripts/player/player.gd) — buff system, `_on_skill_used()`
- [resources/skill_data.gd](resources/skill_data.gd) — SkillData resource fields

## 2. Determine Placement

Each class has 3 branches × 6 nodes (alternating passive/active). Check which slots are available. If adding to an existing branch, it must fit the branch theme:
- **Warrior**: Arms (offense), Valor (defense), Warcry (utility/buffs)
- **Mage**: Fire (burst), Frost (control), Arcane (mana/utility)
- **Rogue**: Assassination (burst/crit), Shadow (evasion/stealth), Traps (control/AoE)

## 3. Design

For **passive** nodes: define effect keys and values per rank. Must use one of these recognized stat keys:
`attack_damage`, `defense`, `max_health`, `max_mana`, `strength`, `dexterity`, `intelligence`, `vitality`, `move_speed`, `crit_chance_pct`, `crit_damage_pct`, `spell_damage_pct`, `attack_speed_pct`, `mana_regen_pct`, `mana_cost_reduction_pct`, `dodge_pct`

For **active** nodes: define a skill definition dict with these fields:
`display_name`, `description`, `target_type` (SELF/POINT), `cooldown`, `mana_cost`, `damage`, `radius`, `range_dist`, `duration`, `icon_color`

**Important**: Never leave `radius` at 0 for AoE damage skills — it will hit nothing!

## 4. Implement

1. Add tree node definition to `get_<class>_trees()` in `skill_tree_data.gd`
2. Add skill definition to `get_all_skill_definitions()` in `skill_tree_data.gd`
3. Add `_execute_skill()` case in `skill_manager.gd` — server-authoritative, use `_aoe_damage()` helper
4. Register VFX in `skill_vfx.gd` `_ready()` using `_register()` and the existing builders
5. For buff skills: call `player.add_buff()` and add cleanup in `_on_buff_expired()`
6. All damage must happen on server only (`if is_server:`)
7. Spell damage skills should multiply by `(1.0 + stats.spell_damage_pct)`

## 5. Output

Show the user the skill design (stats, behavior, tree placement) before implementing.
