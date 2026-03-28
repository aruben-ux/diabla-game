extends Node3D

## Main game scene. Manages player spawning, HUD, minimap, floating text,
## and per-player transitions between town and dungeon levels.
## Town is always active. Dungeon floors are instantiated on demand and
## spatially separated so multiple floors can coexist simultaneously.
## Players move independently between town and any dungeon floor.

enum ActiveLevel { TOWN, DUNGEON }

const DUNGEON_OFFSET := Vector3(500.0, 0.0, 0.0)
const FLOOR_SPACING := 200.0

@onready var level_container: Node3D = $LevelContainer
@onready var player_container: Node3D = $PlayerContainer
@onready var hud: Control = $CanvasLayer/HUD
@onready var inventory_ui: Control = $CanvasLayer/InventoryUI
@onready var minimap: Control = $CanvasLayer/Minimap
@onready var town_level: Node3D = $LevelContainer/TownLevel

var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
var floating_text_scene: PackedScene = preload("res://scenes/ui/floating_text.tscn")
var dungeon_level_scene: PackedScene = preload("res://scenes/levels/dungeon_level.tscn")
var esc_menu_script: GDScript = preload("res://scripts/ui/esc_menu.gd")
const STAIR_COOLDOWN_MS := 2000

var _game_seed := 0

## Tracks which level each player is in. peer_id -> ActiveLevel
var _player_locations: Dictionary = {}
## Tracks which dungeon floor each player is on. peer_id -> int (0 = town)
var _player_floors: Dictionary = {}
var _town_spawn := Vector3(0, 1, 0)

## Per-player stair cooldown to prevent re-triggering after teleport
var _stair_cooldowns: Dictionary = {}  # peer_id -> int (ticks_msec expiry)

## Active dungeon floor instances: floor_number -> DungeonLevel node
var _dungeon_floors: Dictionary = {}
## Per-floor spawn positions (world coords): floor_number -> Vector3
var _floor_spawns: Dictionary = {}
## Per-floor stair positions (world coords): floor_number -> Vector3
var _floor_stairs_up: Dictionary = {}
var _floor_stairs_down: Dictionary = {}
## Per-floor ready state: floor_number -> bool
var _floor_ready: Dictionary = {}
## Players waiting to be teleported when a floor finishes generating: floor_number -> Array
var _pending_floor_teleports: Dictionary = {}

## Central WorldEnvironment — only one can be active at a time
var _world_env: WorldEnvironment
var _town_environment: Environment
var _dungeon_environment: Environment


var _auto_save_timer: float = 0.0
const AUTO_SAVE_INTERVAL := 60.0

## Fade overlay for transitions
var _fade_rect: ColorRect
const FADE_DURATION := 0.25
var _esc_menu: Control

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_lost)
	EventBus.show_floating_text.connect(_on_show_floating_text)

	if multiplayer.is_server():
		if GameManager.is_dedicated_server:
			_game_seed = GameManager.dedicated_seed
		else:
			_game_seed = randi()

	# Central environment — swapped when local player changes level
	_town_environment = _create_town_environment()
	_world_env = WorldEnvironment.new()
	_world_env.environment = _town_environment
	add_child(_world_env)
	_dungeon_environment = _create_dungeon_environment()

	# Fade overlay — fullscreen black rect on the CanvasLayer
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_fade_rect)
	# Start opaque then fade in once everything is ready
	_fade_rect.modulate.a = 1.0

	# Town is always active
	town_level.visible = true
	town_level.process_mode = Node.PROCESS_MODE_INHERIT

	# Connect town signals
	if town_level:
		town_level.level_ready.connect(_on_town_ready)
		town_level.enter_dungeon.connect(_on_enter_dungeon)


func _process(delta: float) -> void:
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		_save_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_esc_menu()
		get_viewport().set_input_as_handled()


func _toggle_esc_menu() -> void:
	if is_instance_valid(_esc_menu):
		_esc_menu.queue_free()
		_esc_menu = null
		return
	var menu := Control.new()
	menu.set_script(esc_menu_script)
	menu.closed.connect(_on_esc_menu_closed)
	$CanvasLayer.add_child(menu)
	_esc_menu = menu


func _on_esc_menu_closed() -> void:
	_esc_menu = null


# --- Floor instance management ---

func _get_floor_position(floor_num: int) -> Vector3:
	return DUNGEON_OFFSET + Vector3(0.0, 0.0, (floor_num - 1) * FLOOR_SPACING)


func _create_floor_instance(floor_num: int) -> Node3D:
	## Create a new DungeonLevel node for the given floor and add it to the tree.
	var instance := dungeon_level_scene.instantiate()
	instance.name = "DungeonFloor_%d" % floor_num
	instance.position = _get_floor_position(floor_num)
	level_container.add_child(instance)

	# Connect signals with floor_num bound so we know which floor fired
	instance.level_ready.connect(_on_floor_ready.bind(floor_num))
	instance.go_up.connect(_on_floor_go_up.bind(floor_num))
	instance.go_down.connect(_on_floor_go_down.bind(floor_num))

	_dungeon_floors[floor_num] = instance
	_floor_ready[floor_num] = false
	return instance


func _remove_floor_instance(floor_num: int) -> void:
	if floor_num in _dungeon_floors:
		_dungeon_floors[floor_num].queue_free()
		_dungeon_floors.erase(floor_num)
		_floor_ready.erase(floor_num)
		_floor_spawns.erase(floor_num)
		_floor_stairs_up.erase(floor_num)
		_floor_stairs_down.erase(floor_num)
		_pending_floor_teleports.erase(floor_num)


func _maybe_cleanup_floor(floor_num: int) -> void:
	## Remove a floor instance if no players remain on it (server only).
	if floor_num <= 0:
		return
	for peer_id in _player_floors:
		if _player_floors[peer_id] == floor_num:
			return  # Someone still there
	_sync_remove_floor.rpc(floor_num)


# --- Level ready callbacks ---

func _on_town_ready(spawn_pos: Vector3) -> void:
	_town_spawn = spawn_pos
	_update_minimap_for_town()

	# Pre-generate dungeon floor 1 so it's ready when someone enters
	if multiplayer.is_server():
		var gen_seed := _game_seed + 1
		_sync_ensure_floor.rpc(1, gen_seed)
	else:
		_request_game_seed.rpc_id(1)

	# Fade in from black once the town is loaded
	_fade_in()

	_spawn_existing_players()


func _on_floor_ready(spawn_pos: Vector3, stairs_up_pos: Vector3, stairs_down_pos: Vector3, floor_num: int) -> void:
	## Called when a DungeonLevel instance finishes generating.
	if floor_num not in _dungeon_floors:
		return
	var instance: Node3D = _dungeon_floors[floor_num]
	var origin := instance.global_position
	_floor_spawns[floor_num] = origin + spawn_pos
	_floor_stairs_up[floor_num] = origin + stairs_up_pos
	_floor_stairs_down[floor_num] = origin + stairs_down_pos
	_floor_ready[floor_num] = true

	# Server: teleport any players waiting for this floor
	if multiplayer.is_server() and floor_num in _pending_floor_teleports:
		for entry in _pending_floor_teleports[floor_num]:
			var peer_id: int = entry[0]
			var arrive_at: String = entry[1]  # "up", "down", or "spawn"
			_set_stair_cooldown(peer_id)
			var dest := _get_floor_dest(floor_num, arrive_at)
			_sync_player_to_dungeon.rpc(peer_id, dest, floor_num)
		_pending_floor_teleports.erase(floor_num)

	# Update minimap if local player is on this floor
	var my_id := multiplayer.get_unique_id()
	if _player_floors.get(my_id, 0) == floor_num:
		_update_minimap_for_dungeon(floor_num)


# --- Stair trigger handlers (server only) ---

func _has_stair_cooldown(peer_id: int) -> bool:
	if peer_id in _stair_cooldowns:
		return Time.get_ticks_msec() < _stair_cooldowns[peer_id]
	return false


func _set_stair_cooldown(peer_id: int) -> void:
	_stair_cooldowns[peer_id] = Time.get_ticks_msec() + STAIR_COOLDOWN_MS


func _on_enter_dungeon(body: Node3D) -> void:
	## A player walked into the town dungeon stairs -> send them to floor 1.
	if not multiplayer.is_server():
		return
	var peer_id := body.get_multiplayer_authority()
	if _has_stair_cooldown(peer_id):
		return
	if _player_floors.get(peer_id, 0) != 0:
		return  # Already in dungeon
	_set_stair_cooldown(peer_id)
	_send_player_to_floor(peer_id, 1, "up")


func _on_floor_go_up(body: Node3D, from_floor: int) -> void:
	## A player walked into stairs-up on the given floor.
	if not multiplayer.is_server():
		return
	var peer_id := body.get_multiplayer_authority()
	if _has_stair_cooldown(peer_id):
		return
	if _player_floors.get(peer_id, 0) != from_floor:
		return
	_set_stair_cooldown(peer_id)

	if from_floor <= 1:
		# Return to town — place near dungeon entrance
		var old_floor: int = _player_floors.get(peer_id, 0)
		_player_floors[peer_id] = 0
		_player_locations[peer_id] = ActiveLevel.TOWN
		var stairs_dest: Vector3 = town_level.stairs_position if town_level else _town_spawn
		var offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		_sync_player_to_town.rpc(peer_id, stairs_dest + offset)
		_maybe_cleanup_floor(old_floor)
	else:
		# Going up: arrive at stairs-down on the floor above
		_send_player_to_floor(peer_id, from_floor - 1, "down")


func _on_floor_go_down(body: Node3D, from_floor: int) -> void:
	## A player walked into stairs-down on the given floor.
	if not multiplayer.is_server():
		return
	var peer_id := body.get_multiplayer_authority()
	if _has_stair_cooldown(peer_id):
		return
	if _player_floors.get(peer_id, 0) != from_floor:
		return
	_set_stair_cooldown(peer_id)
	# Going down: arrive at stairs-up on the floor below
	_send_player_to_floor(peer_id, from_floor + 1, "up")


func _get_floor_dest(floor_num: int, arrive_at: String) -> Vector3:
	## Get the world-space destination for arriving at a floor.
	var offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	if arrive_at == "down" and floor_num in _floor_stairs_down:
		return _floor_stairs_down[floor_num] + offset
	elif arrive_at == "up" and floor_num in _floor_stairs_up:
		return _floor_stairs_up[floor_num] + offset
	return _floor_spawns[floor_num] + offset


func _send_player_to_floor(peer_id: int, floor_num: int, arrive_at: String = "spawn") -> void:
	## Transition a player to the given dungeon floor (server only).
	## arrive_at: "up" = near stairs-up, "down" = near stairs-down, "spawn" = default spawn
	var old_floor: int = _player_floors.get(peer_id, 0)
	_player_floors[peer_id] = floor_num
	_player_locations[peer_id] = ActiveLevel.DUNGEON

	if _floor_ready.get(floor_num, false):
		# Floor exists and is ready — teleport immediately
		var dest := _get_floor_dest(floor_num, arrive_at)
		_sync_player_to_dungeon.rpc(peer_id, dest, floor_num)
	else:
		# Floor needs to be generated — queue player for teleport
		if floor_num not in _pending_floor_teleports:
			_pending_floor_teleports[floor_num] = []
		_pending_floor_teleports[floor_num].append([peer_id, arrive_at])
		var gen_seed := _game_seed + floor_num
		_sync_ensure_floor.rpc(floor_num, gen_seed)

	# Cleanup old floor if no one remains on it
	if old_floor > 0 and old_floor != floor_num:
		_maybe_cleanup_floor(old_floor)


# --- Synced RPCs (run on all peers) ---

@rpc("any_peer", "call_remote", "reliable")
func _request_game_seed() -> void:
	## Client asks server for the game seed after loading main_game.
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	# Send all currently active floor numbers so the client can generate them
	var active_floors: Array = []
	for f in _dungeon_floors.keys():
		active_floors.append(f)
	_send_game_seed.rpc_id(requester, _game_seed, active_floors)


@rpc("authority", "call_remote", "reliable")
func _send_game_seed(game_seed: int, active_floors: Array) -> void:
	## Server sends game seed + active floors to a late-joining client.
	_game_seed = game_seed
	for floor_num in active_floors:
		if floor_num not in _dungeon_floors:
			var instance := _create_floor_instance(floor_num)
			instance.start_generation(floor_num, _game_seed + floor_num)


@rpc("authority", "call_local", "reliable")
func _sync_ensure_floor(floor_num: int, gen_seed: int) -> void:
	## Ensure a dungeon floor instance exists and is generating on all peers.
	if floor_num in _dungeon_floors:
		return  # Already exists (ready or generating)
	var instance := _create_floor_instance(floor_num)
	instance.start_generation(floor_num, gen_seed)


@rpc("authority", "call_local", "reliable")
func _sync_remove_floor(floor_num: int) -> void:
	## Remove a dungeon floor instance on all peers.
	_remove_floor_instance(floor_num)


@rpc("authority", "call_local", "reliable")
func _sync_player_to_dungeon(peer_id: int, dest: Vector3, floor_num: int) -> void:
	var is_local := peer_id == multiplayer.get_unique_id()
	if is_local:
		_fade_out()

	_player_locations[peer_id] = ActiveLevel.DUNGEON
	_player_floors[peer_id] = floor_num
	_teleport_player_local(peer_id, dest)

	if is_local:
		_world_env.environment = _dungeon_environment
		if town_level and town_level.sun:
			town_level.sun.visible = false
		_update_minimap_for_dungeon(floor_num)
		_snap_camera()
		_fade_in()


@rpc("authority", "call_local", "reliable")
func _sync_player_to_town(peer_id: int, dest: Vector3) -> void:
	var is_local := peer_id == multiplayer.get_unique_id()
	if is_local:
		_fade_out()

	_player_locations[peer_id] = ActiveLevel.TOWN
	_player_floors[peer_id] = 0
	_teleport_player_local(peer_id, dest)

	if is_local:
		_world_env.environment = _town_environment
		if town_level and town_level.sun:
			town_level.sun.visible = true
		_update_minimap_for_town()
		_snap_camera()
		_fade_in()


# --- Local helpers ---

func _teleport_player_local(peer_id: int, dest: Vector3) -> void:
	var player_node := player_container.get_node_or_null(str(peer_id))
	if not player_node:
		return
	player_node.global_position = dest
	player_node.move_target = dest
	player_node.is_moving = false
	if player_node.is_multiplayer_authority():
		player_node._left_mouse_held = false
		_snap_camera()


func _snap_camera() -> void:
	var camera := $IsometricCamera
	if camera and camera.has_method("snap_to_target"):
		camera.snap_to_target()


func _fade_out() -> void:
	## Instantly go to black (called right before a teleport).
	if _fade_rect:
		_fade_rect.modulate.a = 1.0


func _fade_in() -> void:
	## Tween from black to transparent.
	if not _fade_rect:
		return
	var tw := create_tween()
	tw.tween_property(_fade_rect, "modulate:a", 0.0, FADE_DURATION)


func _update_minimap_for_town() -> void:
	if minimap and town_level:
		minimap.setup(
			town_level.get_town_grid(),
			town_level.get_grid_dimensions().x,
			town_level.get_grid_dimensions().y,
			town_level.get_tile_size(),
			Vector3.ZERO
		)


# --- Environment presets ---

func _create_town_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.6, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.65)
	e.ambient_light_energy = 0.6
	return e


func _create_dungeon_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.2, 0.16)
	e.ambient_light_energy = 1.2
	return e


func _update_minimap_for_dungeon(floor_num: int) -> void:
	if not minimap:
		return
	if floor_num not in _dungeon_floors:
		return
	var dl: Node3D = _dungeon_floors[floor_num]
	minimap.setup(
		dl.get_dungeon_grid(),
		dl.get_grid_dimensions().x,
		dl.get_grid_dimensions().y,
		dl.get_tile_size(),
		dl.global_position
	)


func _get_local_player() -> Node:
	var my_id := multiplayer.get_unique_id()
	return player_container.get_node_or_null(str(my_id))


func _save_game() -> void:
	# In online mode, saving is handled by the dedicated game server → lobby API.
	# Only save locally in offline/LAN mode.
	if GameManager.is_online_mode:
		return
	var player := _get_local_player()
	if player:
		CharacterManager.capture_player_state(player)
		CharacterManager.save_character()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
		get_tree().quit()


func _on_server_lost() -> void:
	_save_game()
	if GameManager.is_online_mode:
		get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func respawn_player_in_town(peer_id: int) -> void:
	## Called by player.gd _server_respawn_intent to teleport a respawned player to town.
	if not multiplayer.is_server():
		return
	var old_floor: int = _player_floors.get(peer_id, 0)
	_player_locations[peer_id] = ActiveLevel.TOWN
	_player_floors[peer_id] = 0
	var offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	_sync_player_to_town.rpc(peer_id, _town_spawn + offset)
	if old_floor > 0:
		_maybe_cleanup_floor(old_floor)


# --- Player spawning ---

func _spawn_existing_players() -> void:
	for peer_id in GameManager.players:
		_spawn_player(peer_id)


func _on_player_connected(peer_id: int) -> void:
	_spawn_player(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	_despawn_player(peer_id)


func _spawn_player(peer_id: int) -> void:
	if player_container.has_node(str(peer_id)):
		return

	var player_instance := player_scene.instantiate()
	player_instance.name = str(peer_id)
	player_instance.set_multiplayer_authority(peer_id)

	# All new players start in town
	_player_locations[peer_id] = ActiveLevel.TOWN
	_player_floors[peer_id] = 0

	var spawn_offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	player_container.add_child(player_instance)
	player_instance.global_position = _town_spawn + spawn_offset

	if peer_id == multiplayer.get_unique_id():
		var camera := $IsometricCamera
		if camera:
			camera.target = player_instance
			camera.snap_to_target()
		if hud:
			hud.set_player(player_instance)
		if inventory_ui:
			inventory_ui.setup(player_instance.inventory, player_instance)
			if not inventory_ui.drop_item_on_ground.is_connected(_on_drop_item_on_ground):
				inventory_ui.drop_item_on_ground.connect(_on_drop_item_on_ground)
		if minimap:
			minimap.set_player(player_instance)


func _despawn_player(peer_id: int) -> void:
	var old_floor: int = _player_floors.get(peer_id, 0)
	var player_node := player_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_player_locations.erase(peer_id)
	_player_floors.erase(peer_id)

	# Cleanup floor if it's now empty
	if multiplayer.is_server() and old_floor > 0:
		_maybe_cleanup_floor(old_floor)


func _on_drop_item_on_ground(item: ItemData) -> void:
	## Spawn a loot drop at the local player's feet when they drop an item from inventory.
	var my_id := multiplayer.get_unique_id()
	var player_node := player_container.get_node_or_null(str(my_id))
	if not player_node:
		return
	var drop_pos: Vector3 = player_node.global_position + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
	var loot := preload("res://scenes/loot/loot_drop.tscn").instantiate()
	loot.name = "Dropped_%d" % randi()
	player_node.get_parent().add_child(loot)
	loot.global_position = drop_pos
	loot.setup(item)
	loot.is_local_only = true


func _on_show_floating_text(world_pos: Vector3, text: String, color: Color) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	if camera.is_position_behind(world_pos):
		return

	var screen_pos := camera.unproject_position(world_pos)
	var ft := floating_text_scene.instantiate()
	$CanvasLayer.add_child(ft)
	ft.global_position = screen_pos
	ft.setup(text, color)
