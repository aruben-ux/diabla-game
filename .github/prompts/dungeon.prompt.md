---
description: "Modify or extend the dungeon generator. Use when the user says dungeon, floor, room, corridor, BSP, generation, props, decoration, stairs, level design, or dungeon feature."
agent: "agent"
tools: ["read", "edit", "search", "execute"]
argument-hint: "Describe the dungeon change (e.g. 'add water pools to large rooms')"
---

Modify the Diabla dungeon generation system. Read the relevant files first before making changes.

## Key Files

- `scripts/levels/dungeon_generator.gd` — BSP generation, grid encoding, mesh building
- `scripts/levels/dungeon_level.gd` — floor setup, props, lighting, stairs, enemy spawning
- `scripts/levels/dungeon_props.gd` — static prop builder functions
- `scripts/enemies/dungeon_enemy_spawner.gd` — per-room enemy spawning
- `data/game_data.json` — `world` section for generation params

## Architecture

**Grid encoding**: 0=void, 1=floor, 2=wall, 3=corridor, 4=stairs_up, 5=stairs_down

**Generation pipeline** (`dungeon_generator.gd`):
1. `_init_grid()` → `_bsp_split()` → `_carve_rooms()` → `_shuffle_rooms()`
2. `_connect_rooms_mst()` (Prim's MST + 35% extra edges for loops)
3. `_carve_boss_room()` if boss floor (every 5th floor ≥5)
4. `_place_stairs_bfs()` → `_build_walls()` → `_build_mesh()`
5. Signal `dungeon_generated` → `dungeon_level._on_dungeon_generated()`

**Post-gen** (`dungeon_level.gd`):
- Enemy spawning, room lights, wall torches, stair triggers, treasure chests, props, ambient particles
- Props per room: pots 40%, barrels 30%, braziers 15%, bone piles 25%, broken pillars 20%, blood stains 20%, rubble 25%, skull piles 10%, cobwebs 35%, hanging chains 15%
- Deterministic prop naming via `prop_id` counter (required for multiplayer RPC sync)

**Params** (from `game_data.json`): `dungeon_width=60`, `dungeon_height=60`, `max_depth=5`, `TILE_SIZE=3.0`, `WALL_HEIGHT=4.0`, `MIN_ROOM_SIZE=5`, `MAX_ROOM_SIZE=12`

## Rules

1. **Deterministic**: All placement must use the seeded `RandomNumberGenerator` (`dungeon_seed`), never `randf()`/`randi()`. Server and all clients must generate identical results.
2. **Prop naming**: Use the `prop_id` counter for deterministic node names (e.g., `"Pot_%d" % prop_id`). Non-deterministic names break breakable-prop RPCs.
3. **Primitive meshes only**: All visuals from BoxMesh, CylinderMesh, SphereMesh, QuadMesh + StandardMaterial3D. No imported models.
4. **Performance**: Dungeons already have hundreds of nodes. Batch meshes where possible. Use merged collision shapes (row-runs) not per-tile boxes.
5. **Navigation**: Changes to walkable area must re-bake the NavigationRegion3D.
6. **Boss floors**: Every 5th floor (≥5) has a 20×20 boss room. Stairs-down locked until boss dies.
7. **Multiplayer**: All interactive props need collision layer 4 (breakables) or 8 (interactables). Visual-only decor needs no collision.

## New Props

When adding a new prop type to `dungeon_props.gd`:
1. Create a static `build_<name>(pos, rng)` function returning `Node3D` or `StaticBody3D`
2. Build from primitives with `StandardMaterial3D`
3. Cache materials with `_mat(color, roughness, metallic)` if reused
4. Add placement logic in `dungeon_level.gd` `_spawn_dungeon_props()` with probability % and room-size constraints
5. Use the `prop_id` counter for deterministic naming
