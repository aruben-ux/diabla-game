# Enemy Reference

## Base Stats

All stats scale per dungeon floor: **+25% HP/Damage**, **+15% XP** per floor.

| Enemy | HP | Speed | Damage | Atk Range | Aggro Range | Atk CD | XP | Gold |
|---|---|---|---|---|---|---|---|---|
| Grunt | 40 | 5.5 | 8 | 2.0 | 14 | 0.7 | 6.2 | 1–4 |
| Mage | 40 | 4.0 | 8 | 7.0 | 16 | 0.9 | 6.2 | 1–4 |
| Brute | 80 | 3.5 | 14 | 2.0 | 14 | 1.0 | 6.2 | 1–4 |
| Skeleton | 30 | 6.0 | 7 | 2.0 | 15 | 0.5 | 5.0 | 1–3 |
| Spider | 25 | 7.0 | 5 | 1.8 | 12 | 0.4 | 3.8 | 1–2 |
| Ghost | 35 | 4.5 | 9 | 6.0 | 18 | 1.0 | 7.5 | 1–4 |
| Archer | 35 | 4.0 | 10 | 8.0 | 18 | 1.1 | 7.5 | 1–4 |
| Shaman | 50 | 3.5 | 6 | 5.0 | 16 | 0.8 | 8.8 | 2–6 |
| Golem | 120 | 2.5 | 18 | 2.5 | 12 | 1.5 | 11.2 | 2–8 |
| Scarab | 15 | 8.0 | 3 | 1.5 | 10 | 0.3 | 2.5 | 1–2 |
| Wraith | 40 | 5.5 | 12 | 2.0 | 16 | 0.6 | 8.8 | 2–5 |
| Necromancer | 45 | 3.5 | 11 | 7.5 | 20 | 1.2 | 10.0 | 2–6 |
| Demon | 65 | 4.5 | 12 | 2.5 | 16 | 0.8 | 10.0 | 2–6 |
| **Boss Golem** | 800 | 2.0 | 35 | 3.5 | 20 | 2.0 | 125 | 50–150 |
| **Boss Demon** | 1200 | 3.0 | 45 | 3.5 | 25 | 1.5 | 200 | 100–300 |
| **Boss Dragon** | 2000 | 3.5 | 60 | 4.0 | 30 | 1.8 | 300 | 200–500 |

## Abilities

### Regular Enemies

| Enemy | Ability | Description |
|---|---|---|
| **Grunt** | Rally Cry | On hitting a player, boosts all allies within 8u: +30% speed for 3s |
| **Mage** | Frost Bolt | Projectile slows player to 50% speed for 2s |
| **Brute** | Ground Slam | 5s cooldown, 40% chance. AoE radius 4u, 1.5× damage, knockback |
| **Skeleton** | Reassemble | 30% chance to revive at 50% HP on death (once per skeleton) |
| **Spider** | Web Spit | Projectile slows player to 40% speed for 2.5s |
| **Ghost** | Phase Shift | 8s cooldown, 1.5s duration. Becomes untargetable and moves at 2× speed |
| **Archer** | Multi Shot | 4s cooldown, 35% chance. Fires 3 arrows in a fan (±17°), 0.7× damage each |
| **Shaman** | Heal Aura | Every 3s heals all allies within 10u for 5% of their max HP |
| **Golem** | Fortify | Takes 50% reduced damage while attacking |
| **Scarab** | Swarm Frenzy | On death, nearby scarabs within 8u get +40% speed and +20% damage for 5s |
| **Wraith** | Life Drain | Heals for 30% of damage dealt to players |
| **Necromancer** | Raise Dead | Every 12s summons a skeleton minion (max 3 summons) |
| **Demon** | Enrage | Below 30% HP: permanently gains +50% damage, +30% speed, −50% attack cooldown |

### Bosses

| Boss | Abilities | Details |
|---|---|---|
| **Boss Golem** | Ground Slam, Fortify, Rock Shower | Rock Shower — 8s CD, 30% chance: rains 5 boulders near target with 0.6s warning circles, 0.6× damage each, 1.5u impact radius |
| **Boss Demon** | Enrage, Fire Nova, Summon Imps | Fire Nova — 10s CD, 30% chance: 6u AoE burst, 1.2× damage + knockback. Summon Imps — 20s CD: spawns 2 grunt minions (max 4) |
| **Boss Dragon** | Fire Breath, Tail Swipe, Wing Gust | Fire Breath — 6s CD, 40% chance: 8u cone (±34°), 0.8× damage. Tail Swipe — 5s CD: hits players behind, 5u radius, 0.6× damage + knockback. Wing Gust — 15s CD: 7u knockback-only AoE |
