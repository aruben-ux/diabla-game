extends Node3D

## Spawns enemies inside dungeon rooms.
## Distributes enemies across rooms, with more in larger/deeper rooms.
## Initial spawn runs on all peers (deterministic from dungeon seed).
## Respawn is server-authoritative and synced via RPC.

signal boss_died()

@export var enemy_scene: PackedScene
@export var max_enemies_per_room := 5
@export var respawn_interval := 15.0
@export var skip_first_room := true  # Don't spawn in the spawn room

var enemy_scene_loaded: PackedScene
var room_data: Array[Rect2i] = []
var room_centers: Array[Vector3] = []
var tile_size := 3.0
var respawn_timer := 0.0
var enemies_per_room: Array[int] = []
var floor_level := 1
var _spawn_counter := 0
var _sync_timer := 0.0
const SYNC_INTERVAL := 0.05  # 20 Hz batch broadcast
var _room_density_div := 12
var _boss_room_idx := -1
var _boss_alive := false
var _type_weights: Array = []  # Array of [type_int, cumulative_weight]

static var _spawning_cfg: Dictionary = {}
static var _spawning_loaded := false


static func _load_spawning_cfg() -> void:
	if _spawning_loaded:
		return
	_spawning_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_spawning_cfg = json.data.get("spawning", {})
		file.close()


func _ready() -> void:
	if not enemy_scene:
		enemy_scene_loaded = preload("res://scenes/enemies/enemy.tscn")
	else:
		enemy_scene_loaded = enemy_scene
	_load_spawning_cfg()
	max_enemies_per_room = int(_spawning_cfg.get("dungeon_max_per_room", max_enemies_per_room))
	respawn_interval = _spawning_cfg.get("dungeon_respawn_interval", respawn_interval)
	_room_density_div = int(_spawning_cfg.get("dungeon_room_density_divisor", _room_density_div))
	_build_type_weights()


func _build_type_weights() -> void:
	## Build cumulative weight table from the type_weights dictionary in config.
	_type_weights.clear()
	var weights: Dictionary = _spawning_cfg.get("type_weights", {})
	if weights.is_empty():
		# Fallback to old format
		_type_weights = [[0, 0.60], [1, 0.85], [2, 1.0]]
		return
	var cumulative := 0.0
	var type_names := Enemy.EnemyType.keys()
	for i in range(type_names.size()):
		var w: float = weights.get(type_names[i], 0.0)
		if w > 0.0 and not type_names[i].begins_with("BOSS"):
			cumulative += w
			_type_weights.append([i, cumulative])
	# Normalize
	if cumulative > 0.0 and _type_weights.size() > 0:
		for entry in _type_weights:
			entry[1] /= cumulative


func _pick_enemy_type() -> int:
	var roll := randf()
	for entry in _type_weights:
		if roll <= entry[1]:
			return entry[0]
	return 0  # GRUNT fallback


func setup(rooms: Array[Rect2i], centers: Array[Vector3], ts: float, floor_num: int = 1, boss_room_idx: int = -1) -> void:
	room_data = rooms
	room_centers = centers
	tile_size = ts
	floor_level = floor_num
	_boss_room_idx = boss_room_idx
	_boss_alive = false
	enemies_per_room.clear()
	enemies_per_room.resize(rooms.size())
	enemies_per_room.fill(0)
	_spawn_counter = 0

	# All peers spawn enemies — RNG state is deterministic from dungeon seed
	_initial_spawn()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_broadcast_all_enemies()

	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		_respawn_pass()


func _initial_spawn() -> void:
	var start_idx := 1 if skip_first_room else 0
	for i in range(start_idx, room_data.size()):
		if i == _boss_room_idx:
			# Spawn the boss instead of regular enemies
			_spawn_boss_in_room(i)
			continue
		var room := room_data[i]
		var area := room.size.x * room.size.y
		var count := clampi(area / _room_density_div, 1, max_enemies_per_room)
		for j in count:
			_spawn_enemy_in_room(i)


func _respawn_pass() -> void:
	var start_idx := 1 if skip_first_room else 0
	for i in range(start_idx, room_data.size()):
		if i == _boss_room_idx:
			continue  # Don't respawn in boss room
		var room := room_data[i]
		var area := room.size.x * room.size.y
		var target_count := clampi(area / _room_density_div, 1, max_enemies_per_room)
		while enemies_per_room[i] < target_count:
			# Server generates spawn data and sends to all peers
			var rx := randf_range(room.position.x + 1, room.position.x + room.size.x - 1) * tile_size
			var rz := randf_range(room.position.y + 1, room.position.y + room.size.y - 1) * tile_size
			var spawn_pos := Vector3(rx, 1.0, rz)
			var type: int = _pick_enemy_type()
			_spawn_counter += 1
			_rpc_respawn_enemy.rpc("E_%d" % _spawn_counter, i, spawn_pos, type)


@rpc("authority", "call_local", "reliable")
func _rpc_respawn_enemy(enemy_name: String, room_idx: int, spawn_pos: Vector3, type: int) -> void:
	_create_enemy(enemy_name, room_idx, spawn_pos, type)


func _spawn_enemy_in_room(room_idx: int) -> void:
	var room := room_data[room_idx]
	_spawn_counter += 1

	# Random position within the room
	var rx := randf_range(room.position.x + 1, room.position.x + room.size.x - 1) * tile_size
	var rz := randf_range(room.position.y + 1, room.position.y + room.size.y - 1) * tile_size
	var spawn_pos := Vector3(rx, 1.0, rz)

	var type: int = _pick_enemy_type()

	_create_enemy("E_%d" % _spawn_counter, room_idx, spawn_pos, type)


func _create_enemy(enemy_name: String, room_idx: int, spawn_pos: Vector3, type: int) -> void:
	var instance := enemy_scene_loaded.instantiate()
	instance.name = enemy_name
	instance.enemy_type = type as Enemy.EnemyType
	instance.floor_level = floor_level
	add_child(instance)
	instance.position = spawn_pos

	var idx := room_idx  # Capture for lambda
	instance.died.connect(func(_e: Node): enemies_per_room[idx] = maxi(enemies_per_room[idx] - 1, 0))
	enemies_per_room[room_idx] += 1


func _spawn_boss_in_room(room_idx: int) -> void:
	## Spawn a boss enemy in the center of the boss room.
	var room := room_data[room_idx]
	_spawn_counter += 1

	var cx := (room.position.x + room.size.x / 2.0) * tile_size
	var cz := (room.position.y + room.size.y / 2.0) * tile_size
	var spawn_pos := Vector3(cx, 1.0, cz)

	# Cycle boss types: floor 5=BOSS_GOLEM, 10=BOSS_DEMON, 15=BOSS_DRAGON, 20=BOSS_GOLEM...
	var boss_cycle := ((floor_level / 5) - 1) % 3  # 0, 1, or 2
	var boss_type: int
	match boss_cycle:
		0: boss_type = Enemy.EnemyType.BOSS_GOLEM
		1: boss_type = Enemy.EnemyType.BOSS_DEMON
		2: boss_type = Enemy.EnemyType.BOSS_DRAGON
		_: boss_type = Enemy.EnemyType.BOSS_GOLEM

	var instance := enemy_scene_loaded.instantiate()
	instance.name = "Boss_%d" % _spawn_counter
	instance.enemy_type = boss_type as Enemy.EnemyType
	instance.floor_level = floor_level
	add_child(instance)
	instance.position = spawn_pos
	_boss_alive = true

	var idx := room_idx
	instance.died.connect(func(_e: Node):
		enemies_per_room[idx] = maxi(enemies_per_room[idx] - 1, 0)
		_boss_alive = false
		boss_died.emit()
	)
	enemies_per_room[room_idx] += 1

	# Also spawn some guards in the boss room
	for _i in 4:
		_spawn_enemy_in_room(room_idx)


func _broadcast_all_enemies() -> void:
	var data: Array = []
	for child in get_children():
		if child is Enemy and child.state != Enemy.State.DEAD:
			data.append([child.name, child.position, child.model.rotation.y, child.state])
	if data.size() > 0:
		_sync_enemy_states.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemy_states(data: Array) -> void:
	for entry in data:
		var enemy = get_node_or_null(NodePath(entry[0]))
		if enemy and enemy.has_method("apply_remote_state"):
			enemy.apply_remote_state(entry[1], entry[2], entry[3])
