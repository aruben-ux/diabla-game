extends Node3D

## Spawns enemies in the level at defined intervals.
## Server spawns via RPC so all peers create matching enemies.

@export var enemy_scene: PackedScene
@export var max_enemies: int = 6
@export var spawn_interval: float = 5.0
@export var spawn_radius: float = 15.0

var spawn_timer: float = 0.0
var alive_enemies: int = 0
var _spawn_counter := 0
var _sync_timer := 0.0
const SYNC_INTERVAL := 0.05


func _ready() -> void:
	if not enemy_scene:
		enemy_scene = preload("res://scenes/enemies/enemy.tscn")


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_broadcast_all_enemies()

	spawn_timer += delta
	if spawn_timer >= spawn_interval and alive_enemies < max_enemies:
		spawn_timer = 0.0
		_spawn_enemy()


func _spawn_enemy() -> void:
	var angle := randf() * TAU
	var dist := randf_range(5.0, spawn_radius)
	var spawn_pos := global_position + Vector3(cos(angle) * dist, 1.0, sin(angle) * dist)
	var roll := randf()
	var type: int = 0  # GRUNT
	if roll < 0.15:
		type = 2  # BRUTE
	elif roll < 0.40:
		type = 1  # MAGE
	_spawn_counter += 1
	_rpc_spawn_enemy.rpc("TE_%d" % _spawn_counter, spawn_pos, type)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_enemy(enemy_name: String, spawn_pos: Vector3, type: int) -> void:
	var instance := enemy_scene.instantiate() as CharacterBody3D
	instance.name = enemy_name

	match type:
		1: instance.enemy_type = Enemy.EnemyType.MAGE
		2: instance.enemy_type = Enemy.EnemyType.BRUTE

	add_child(instance)
	instance.global_position = spawn_pos
	instance.died.connect(_on_enemy_died)
	alive_enemies += 1


func _on_enemy_died(_enemy: Node) -> void:
	alive_enemies -= 1


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
