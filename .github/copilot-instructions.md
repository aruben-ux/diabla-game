# Project Guidelines

## Architecture
- Godot 4.6.1 (Windows) / 4.6.0 (Linux server), GDScript, Forward+, Jolt Physics
- Diablo-like ARPG: isometric camera, 3 classes (Warrior/Mage/Rogue), BSP dungeons, procedural town
- Two modes: **Online** (dedicated servers via lobby) and **Offline** (LAN peer-to-peer)
- Autoloads: GameManager, NetworkManager, EventBus, ItemDatabase, CharacterManager, OnlineManager, QuestManager, TranslationManager
- Data-driven: `data/game_data.json` configures monsters, classes, skills, items, loot, progression, floor scaling
- Toon art style: cel shader, all geometry from primitive meshes (no imported models)
- i18n: use `tr("English text")` for all user-facing strings

## Multiplayer-First Rule
**Every feature must work with ENet multiplayer (host + clients).**
- Server-authoritative: server runs AI, hit detection, damage, loot, level transitions
- Visual-only code (animations, VFX, UI) uses `call_local` RPCs
- State changes (HP, mana, XP, inventory, position) must sync via RPC
- Use `"authority"` RPC mode for server→client. Use `"any_peer"` only for client→server intents
- Level transitions, loot drops, enemy spawns must be RPC'd to all clients
- Non-deterministic node names break RPCs — use deterministic naming (counters, IDs)

## GDScript 4.6 Gotchas
- `:=` type inference fails with Variant from `get_nodes_in_group()` → use explicit `: Type`
- `in` on typed arrays fails for enums → use `match` instead
- `global_position` before `add_child()` has no effect → store and apply in `_ready()`
- Lambdas cannot self-reference → use `CONNECT_ONE_SHOT` instead
- Ternary expressions need explicit types: `var x: Vector3 = a if cond else b`
- Linux server is stricter about type checking than Windows editor

## Deployment
- Export: `& "<godot_exe>" --headless --export-pack "Linux" F:\Godot\diabla\diabla.pck`
- Upload: `scp F:\Godot\diabla\diabla.pck root@5.78.206.166:/opt/diabla/diabla.pck`
- Server: Hetzner VPS `5.78.206.166`, lobby service: `diabla-lobby` (systemd)
- Game instances spawned by lobby on ports 9000-9099 (auto-killed when idle)
- See [docs/enemies.md](docs/enemies.md) for enemy reference
