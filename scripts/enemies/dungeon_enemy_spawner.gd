extends Node3D

## Spawns enemies inside dungeon rooms.
## Distributes enemies across rooms, with more in larger/deeper rooms.
## Initial spawn runs on all peers (deterministic from dungeon seed).
## Respawn is server-authoritative and synced via RPC.

@export var enemy_scene: PackedScene
@export var max_enemies_per_room := 4
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


func _ready() -> void:
	if not enemy_scene:
		enemy_scene_loaded = preload("res://scenes/enemies/enemy.tscn")
	else:
		enemy_scene_loaded = enemy_scene


func setup(rooms: Array[Rect2i], centers: Array[Vector3], ts: float, floor_num: int = 1) -> void:
	room_data = rooms
	room_centers = centers
	tile_size = ts
	floor_level = floor_num
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
		var room := room_data[i]
		var area := room.size.x * room.size.y
		var count := clampi(area / 15, 1, max_enemies_per_room)
		for j in count:
			_spawn_enemy_in_room(i)


func _respawn_pass() -> void:
	var start_idx := 1 if skip_first_room else 0
	for i in range(start_idx, room_data.size()):
		var room := room_data[i]
		var area := room.size.x * room.size.y
		var target_count := clampi(area / 15, 1, max_enemies_per_room)
		while enemies_per_room[i] < target_count:
			# Server generates spawn data and sends to all peers
			var rx := randf_range(room.position.x + 1, room.position.x + room.size.x - 1) * tile_size
			var rz := randf_range(room.position.y + 1, room.position.y + room.size.y - 1) * tile_size
			var spawn_pos := Vector3(rx, 1.0, rz)
			var roll := randf()
			var type: int = 0  # GRUNT
			if roll < 0.15:
				type = 2  # BRUTE
			elif roll < 0.40:
				type = 1  # MAGE
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

	# Randomize enemy type: 60% grunt, 25% mage, 15% brute
	var roll := randf()
	var type: int = 0  # GRUNT
	if roll < 0.15:
		type = 2  # BRUTE
	elif roll < 0.40:
		type = 1  # MAGE

	_create_enemy("E_%d" % _spawn_counter, room_idx, spawn_pos, type)


func _create_enemy(enemy_name: String, room_idx: int, spawn_pos: Vector3, type: int) -> void:
	var instance := enemy_scene_loaded.instantiate()
	instance.name = enemy_name

	match type:
		1: instance.enemy_type = Enemy.EnemyType.MAGE
		2: instance.enemy_type = Enemy.EnemyType.BRUTE

	instance.floor_level = floor_level
	add_child(instance)
	instance.position = spawn_pos

	var idx := room_idx  # Capture for lambda
	instance.died.connect(func(_e: Node): enemies_per_room[idx] = maxi(enemies_per_room[idx] - 1, 0))
	enemies_per_room[room_idx] += 1


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
