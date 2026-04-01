---
description: "Design a new enemy type for Diabla. Use when the user says add enemy, new enemy, create monster, enemy design, or mob type."
agent: "agent"
tools: ["read", "edit", "search"]
argument-hint: "Describe the enemy concept (e.g. 'a fire imp that explodes on death')"
---

Design a new enemy for the Diabla ARPG. Follow these steps precisely:

## 1. Gather Context

Read these files first:
- `docs/enemies.md` — existing enemy stats and abilities
- `data/game_data.json` — the `monsters` section for stat ranges
- `scripts/enemies/enemy_abilities.gd` — how abilities are implemented
- `scripts/enemies/enemy.gd` — VFX RPCs and ability hooks

## 2. Design Stats

Create a balanced stat block that fits alongside existing enemies. Follow the stat ranges in enemies.md. Consider the enemy's role:
- **Swarm**: low HP, high speed, low damage (like Scarab)
- **Standard**: medium HP/speed/damage (like Grunt, Skeleton)
- **Ranged**: low HP, ranged attack (like Mage, Archer)
- **Tank**: high HP, slow, heavy damage (like Golem, Brute)
- **Support**: medium HP, utility ability (like Shaman)
- **Boss**: very high HP, multiple abilities, high rewards

## 3. Design Ability

Every enemy needs exactly one unique ability (bosses get 2-3). Pattern after existing abilities:
- Cooldown-based with % chance per check
- Clear gameplay counterplay
- VFX feedback via RPC

## 4. Implement

1. Add the enemy entry to `data/game_data.json` in the `monsters` object
2. Add the ability logic to `scripts/enemies/enemy_abilities.gd`
3. Add any needed VFX RPCs to `scripts/enemies/enemy.gd`
4. Update `docs/enemies.md` with the new stat row and ability description
5. Add to the dungeon spawner floor table if applicable

## 5. Output

Show the user a summary table of the new enemy's stats and ability before implementing.
