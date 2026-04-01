extends Node3D

## Spawns enemies inside dungeon rooms using a cluster-based system.
## Each room gets X clusters. Each cluster is one enemy type, filled
## by a point budget. Harder enemies cost more points. Higher floors
## skew toward tougher enemies and have bigger cluster budgets.

signal boss_died()

@export var enemy_scene: PackedScene
@export var respawn_interval := 15.0
@export var skip_first_room := true

var enemy_scene_loaded: PackedScene
var room_data: Array[Rect2i] = []
var room_centers: Array[Vector3] = []
var tile_size := 3.0
var respawn_timer := 0.0
var enemies_per_room: Array[int] = []
var _room_cluster_targets: Array[int] = []  # target enemy count per room for respawns
var floor_level := 1
var _spawn_counter := 0
var _sync_timer := 0.0
const SYNC_INTERVAL := 0.05
var _boss_room_idx := -1
var _boss_alive := false

# Stagger initial spawns across frames to avoid a hitch
var _spawn_queue: Array = []  # [[enemy_name, room_idx, Vector3, type_int], ...]
const SPAWNS_PER_FRAME := 5

# Point costs per enemy type (higher = tougher)
const ENEMY_POINTS := {
	"GRUNT": 1, "SKELETON": 1, "SCARAB": 1, "SPIDER": 1,
	"ARCHER": 2, "MAGE": 2, "GHOST": 2,
	"BRUTE": 3, "SHAMAN": 3, "WRAITH": 3,
	"GOLEM": 4, "NECROMANCER": 4,
	"DEMON": 5,
}

# Floor tiers: which enemies can appear at what floor ranges
# tier 0 = floor 1+, tier 1 = floor 3+, tier 2 = floor 6+, tier 3 = floor 10+
const ENEMY_TIERS := {
	"GRUNT": 0, "SKELETON": 0, "SCARAB": 0, "SPIDER": 0,
	"ARCHER": 0, "MAGE": 1, "GHOST": 1,
	"BRUTE": 1, "SHAMAN": 2, "WRAITH": 2,
	"GOLEM": 2, "NECROMANCER": 3,
	"DEMON": 3,
}

const TIER_FLOOR_THRESHOLDS := [1, 3, 6, 10]

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
	respawn_interval = _spawning_cfg.get("dungeon_respawn_interval", respawn_interval)


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
	_room_cluster_targets.clear()
	_room_cluster_targets.resize(rooms.size())
	_room_cluster_targets.fill(0)
	_spawn_counter = 0
	_initial_spawn()


func _process(delta: float) -> void:
	# Drain staggered spawn queue on ALL peers (server + clients)
	if not _spawn_queue.is_empty():
		var batch := mini(_spawn_queue.size(), SPAWNS_PER_FRAME)
		for _i in batch:
			var entry: Array = _spawn_queue.pop_front()
			_create_enemy(entry[0], entry[1], entry[2], entry[3])

	if not multiplayer.is_server():
		return

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_broadcast_all_enemies()


## ─── CLUSTER SPAWNING ───

func _get_cluster_budget() -> int:
	## Points per cluster, scales with floor level.
	var base: int = int(_spawning_cfg.get("cluster_base_points", 3))
	var per_floor: float = _spawning_cfg.get("cluster_points_per_floor", 1.0)
	return base + int(floor_level * per_floor)


func _get_clusters_for_room(room: Rect2i) -> int:
	## Number of clusters in a room based on room area.
	var area := room.size.x * room.size.y
	var min_clusters: int = int(_spawning_cfg.get("min_clusters_per_room", 1))
	var max_clusters: int = int(_spawning_cfg.get("max_clusters_per_room", 4))
	var divisor: int = int(_spawning_cfg.get("cluster_area_divisor", 25))
	return clampi(area / divisor, min_clusters, max_clusters)


func _get_eligible_enemy_types() -> Array[String]:
	## Returns enemy type names available for the current floor.
	var types: Array[String] = []
	for type_name: String in ENEMY_TIERS:
		var tier: int = ENEMY_TIERS[type_name]
		if tier < TIER_FLOOR_THRESHOLDS.size() and floor_level >= TIER_FLOOR_THRESHOLDS[tier]:
			types.append(type_name)
	if types.is_empty():
		types.append("GRUNT")
	return types


func _pick_cluster_type() -> String:
	## Pick an enemy type weighted by floor depth.
	## Higher floors favor tougher enemies.
	var eligible := _get_eligible_enemy_types()
	var weights: Array[float] = []
	var total_weight := 0.0

	for type_name: String in eligible:
		var tier: int = ENEMY_TIERS.get(type_name, 0)
		# Weight formula: base weight + bonus for matching floor tier
		# Low tier enemies get reduced weight on high floors, high tier get boosted
		var floor_tier := 0
		for i in range(TIER_FLOOR_THRESHOLDS.size() - 1, -1, -1):
			if floor_level >= TIER_FLOOR_THRESHOLDS[i]:
				floor_tier = i
				break
		# Enemies close to the floor's tier are most common
		var tier_diff: int = absi(tier - floor_tier)
		var w: float = 1.0 / (1.0 + tier_diff * 1.5)
		# Slight bonus for exact match
		if tier == floor_tier:
			w *= 1.5
		weights.append(w)
		total_weight += w

	# Weighted random pick
	var roll := randf() * total_weight
	var cumulative := 0.0
	for i in eligible.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return eligible[i]
	return eligible[eligible.size() - 1]


func _spawn_cluster_in_room(room_idx: int, center_offset: Vector2 = Vector2.ZERO) -> int:
	## Spawn a single cluster of one enemy type. Returns number of enemies spawned.
	var room := room_data[room_idx]
	var budget := _get_cluster_budget()
	var type_name := _pick_cluster_type()
	var point_cost: int = ENEMY_POINTS.get(type_name, 1)
	var type_int: int = Enemy.EnemyType.keys().find(type_name)
	if type_int < 0:
		type_int = 0

	# Cluster center: offset from room center
	var room_cx := (room.position.x + room.size.x / 2.0) * tile_size
	var room_cz := (room.position.y + room.size.y / 2.0) * tile_size
	var cluster_cx := room_cx + center_offset.x * tile_size
	var cluster_cz := room_cz + center_offset.y * tile_size

	# Clamp cluster center inside room bounds
	var min_x := (room.position.x + 1) * tile_size
	var max_x := (room.position.x + room.size.x - 1) * tile_size
	var min_z := (room.position.y + 1) * tile_size
	var max_z := (room.position.y + room.size.y - 1) * tile_size
	cluster_cx = clampf(cluster_cx, min_x, max_x)
	cluster_cz = clampf(cluster_cz, min_z, max_z)

	var count := 0
	var spent := 0
	while spent + point_cost <= budget:
		# Spread enemies within ~3 tiles of cluster center
		var rx := cluster_cx + randf_range(-3.0, 3.0) * tile_size * 0.3
		var rz := cluster_cz + randf_range(-3.0, 3.0) * tile_size * 0.3
		rx = clampf(rx, min_x, max_x)
		rz = clampf(rz, min_z, max_z)
		var spawn_pos := Vector3(rx, 1.0, rz)

		_spawn_counter += 1
		_create_enemy("E_%d" % _spawn_counter, room_idx, spawn_pos, type_int)
		spent += point_cost
		count += 1

	return count


## ─── INITIAL + RESPAWN ───

func _initial_spawn() -> void:
	var start_idx := 1 if skip_first_room else 0
	for i in range(start_idx, room_data.size()):
		if i == _boss_room_idx:
			_spawn_boss_in_room(i)
			continue
		var room := room_data[i]
		var num_clusters := _get_clusters_for_room(room)
		var total_queued := 0
		for c in num_clusters:
			# Offset each cluster from center
			var angle := (float(c) / num_clusters) * TAU
			var dist := minf(room.size.x, room.size.y) * 0.25
			var offset := Vector2(cos(angle) * dist, sin(angle) * dist)
			total_queued += _queue_cluster_in_room(i, offset)
		_room_cluster_targets[i] = total_queued


func _queue_cluster_in_room(room_idx: int, center_offset: Vector2) -> int:
	## Same logic as _spawn_cluster_in_room but queues spawns for staggered creation.
	var room := room_data[room_idx]
	var budget := _get_cluster_budget()
	var type_name := _pick_cluster_type()
	var point_cost: int = ENEMY_POINTS.get(type_name, 1)
	var type_int: int = Enemy.EnemyType.keys().find(type_name)
	if type_int < 0:
		type_int = 0

	var room_cx := (room.position.x + room.size.x / 2.0) * tile_size
	var room_cz := (room.position.y + room.size.y / 2.0) * tile_size
	var cluster_cx := room_cx + center_offset.x * tile_size
	var cluster_cz := room_cz + center_offset.y * tile_size

	var min_x := (room.position.x + 1) * tile_size
	var max_x := (room.position.x + room.size.x - 1) * tile_size
	var min_z := (room.position.y + 1) * tile_size
	var max_z := (room.position.y + room.size.y - 1) * tile_size
	cluster_cx = clampf(cluster_cx, min_x, max_x)
	cluster_cz = clampf(cluster_cz, min_z, max_z)

	var count := 0
	var spent := 0
	while spent + point_cost <= budget:
		var rx := cluster_cx + randf_range(-3.0, 3.0) * tile_size * 0.3
		var rz := cluster_cz + randf_range(-3.0, 3.0) * tile_size * 0.3
		rx = clampf(rx, min_x, max_x)
		rz = clampf(rz, min_z, max_z)
		var spawn_pos := Vector3(rx, 1.0, rz)

		_spawn_counter += 1
		_spawn_queue.append(["E_%d" % _spawn_counter, room_idx, spawn_pos, type_int])
		spent += point_cost
		count += 1

	return count


func _respawn_pass() -> void:
	var start_idx := 1 if skip_first_room else 0
	for i in range(start_idx, room_data.size()):
		if i == _boss_room_idx:
			continue
		var target := _room_cluster_targets[i]
		if enemies_per_room[i] >= target:
			continue
		# Respawn one cluster worth at a time
		var room := room_data[i]
		var offset := Vector2(randf_range(-0.25, 0.25) * room.size.x, randf_range(-0.25, 0.25) * room.size.y)
		_respawn_cluster_in_room(i, offset)


func _respawn_cluster_in_room(room_idx: int, center_offset: Vector2) -> void:
	## Server-side respawn: pick type, fill budget, RPC to all peers.
	var room := room_data[room_idx]
	var budget := _get_cluster_budget()
	var type_name := _pick_cluster_type()
	var point_cost: int = ENEMY_POINTS.get(type_name, 1)
	var type_int: int = Enemy.EnemyType.keys().find(type_name)
	if type_int < 0:
		type_int = 0

	var room_cx := (room.position.x + room.size.x / 2.0) * tile_size
	var room_cz := (room.position.y + room.size.y / 2.0) * tile_size
	var cluster_cx := clampf(room_cx + center_offset.x * tile_size, (room.position.x + 1) * tile_size, (room.position.x + room.size.x - 1) * tile_size)
	var cluster_cz := clampf(room_cz + center_offset.y * tile_size, (room.position.y + 1) * tile_size, (room.position.y + room.size.y - 1) * tile_size)

	var min_x := (room.position.x + 1) * tile_size
	var max_x := (room.position.x + room.size.x - 1) * tile_size
	var min_z := (room.position.y + 1) * tile_size
	var max_z := (room.position.y + room.size.y - 1) * tile_size

	var spent := 0
	while spent + point_cost <= budget:
		var rx := clampf(cluster_cx + randf_range(-3.0, 3.0) * tile_size * 0.3, min_x, max_x)
		var rz := clampf(cluster_cz + randf_range(-3.0, 3.0) * tile_size * 0.3, min_z, max_z)
		var spawn_pos := Vector3(rx, 1.0, rz)
		_spawn_counter += 1
		_rpc_respawn_enemy.rpc("E_%d" % _spawn_counter, room_idx, spawn_pos, type_int)
		spent += point_cost


@rpc("authority", "call_local", "reliable")
func _rpc_respawn_enemy(enemy_name: String, room_idx: int, spawn_pos: Vector3, type: int) -> void:
	_create_enemy(enemy_name, room_idx, spawn_pos, type)


func _create_enemy(enemy_name: String, room_idx: int, spawn_pos: Vector3, type: int) -> void:
	var instance := enemy_scene_loaded.instantiate()
	instance.name = enemy_name
	instance.enemy_type = type as Enemy.EnemyType
	instance.floor_level = floor_level
	add_child(instance)
	instance.position = spawn_pos

	var idx := room_idx
	instance.died.connect(func(_e: Node): enemies_per_room[idx] = maxi(enemies_per_room[idx] - 1, 0))
	enemies_per_room[room_idx] += 1


func _spawn_boss_in_room(room_idx: int) -> void:
	var room := room_data[room_idx]
	_spawn_counter += 1

	var cx := (room.position.x + room.size.x / 2.0) * tile_size
	var cz := (room.position.y + room.size.y / 2.0) * tile_size
	var spawn_pos := Vector3(cx, 1.0, cz)

	var boss_cycle := ((floor_level / 5) - 1) % 3
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

	# Spawn guard clusters around the boss
	for _i in 2:
		var angle := randf() * TAU
		var offset := Vector2(cos(angle) * 3.0, sin(angle) * 3.0)
		_spawn_cluster_in_room(room_idx, offset)


func _broadcast_all_enemies() -> void:
	var data: Array = []
	for child in get_children():
		if child is Enemy and child.state != Enemy.State.DEAD:
			data.append([child.name, child.position, child.model.rotation.y, child.state, child._is_wandering])
	if data.size() == 0:
		return
	# Chunk to stay under MTU (~1392 bytes). ~50 bytes per entry → 20 per chunk.
	var chunk_size := 20
	var i := 0
	while i < data.size():
		var chunk: Array = data.slice(i, i + chunk_size)
		_sync_enemy_states.rpc(chunk)
		i += chunk_size


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemy_states(data: Array) -> void:
	for entry in data:
		var enemy = get_node_or_null(NodePath(entry[0]))
		if enemy and enemy.has_method("apply_remote_state"):
			enemy.apply_remote_state(entry[1], entry[2], entry[3], entry[4])
