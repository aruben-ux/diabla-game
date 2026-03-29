extends CharacterBody3D
class_name Enemy

## Base enemy with state-machine AI: IDLE → CHASE → ATTACK → DEAD.
## Server-authoritative — only the server runs AI logic.

signal died(enemy: Enemy)

enum State { IDLE, CHASE, ATTACK, DEAD, HIT }

const GRAVITY := 9.8

@export var max_health: float = 40.0
@export var move_speed: float = 5.5
@export var attack_damage: float = 8.0
@export var attack_range: float = 2.0
@export var aggro_range: float = 14.0
@export var attack_cooldown: float = 0.7
@export var xp_reward: float = 25.0

static var _monster_data: Dictionary = {}
static var _monster_data_loaded := false

enum EnemyType { GRUNT, MAGE, BRUTE, SKELETON, SPIDER, GHOST, ARCHER, SHAMAN, GOLEM, SCARAB, WRAITH, NECROMANCER, DEMON, BOSS_GOLEM, BOSS_DEMON, BOSS_DRAGON }

@onready var model = $Model
@onready var hitbox: Area3D = $Hitbox

@export var enemy_type: EnemyType = EnemyType.GRUNT

var health: float
var state: State = State.IDLE
var target: Node3D = null
var attack_timer: float = 0.0
var hit_flash_timer: float = 0.0
var dissolve_shader: Shader
var floor_level: int = 1
static var _loot_counter: int = 0

# Client-side interpolation (mirrors the player RPC broadcast approach)
var _remote_pos := Vector3.ZERO
var _remote_rot_y := 0.0
var _remote_initialized := false


func _ready() -> void:
	_load_monster_data()
	_apply_monster_data()
	health = max_health
	add_to_group("enemies")
	dissolve_shader = load("res://assets/shaders/dissolve.gdshader")
	_build_model()
	_apply_floor_scaling()


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		# Server runs full AI
		if not is_on_floor():
			velocity.y -= GRAVITY * delta

		match state:
			State.IDLE:
				_state_idle(delta)
			State.CHASE:
				_state_chase(delta)
			State.ATTACK:
				_state_attack(delta)
			State.HIT:
				_state_hit(delta)
			State.DEAD:
				pass

		if state != State.DEAD:
			move_and_slide()
	else:
		# Client: interpolate toward server state
		if _remote_initialized and state != State.DEAD:
			position = position.lerp(_remote_pos, 15.0 * delta)
			model.rotation.y = lerp_angle(model.rotation.y, _remote_rot_y, 15.0 * delta)


func _state_idle(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	# Look for nearest player in aggro range
	target = _find_nearest_player()
	if target:
		state = State.CHASE


func _state_chase(delta: float) -> void:
	if not is_instance_valid(target):
		state = State.IDLE
		target = null
		return

	# Drop aggro if target is dead
	if target.get("stats") and target.stats.health <= 0.0:
		state = State.IDLE
		target = null
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	# Lost aggro
	if distance > aggro_range * 1.5:
		state = State.IDLE
		target = null
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# In attack range
	if distance <= attack_range:
		state = State.ATTACK
		attack_timer = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Move toward target
	var direction := to_target.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Face target
	var target_rot := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_rot, 10.0 * delta)


func _state_attack(delta: float) -> void:
	if not is_instance_valid(target):
		state = State.IDLE
		target = null
		return

	# Stop attacking dead targets
	if target.get("stats") and target.stats.health <= 0.0:
		state = State.IDLE
		target = null
		return

	velocity.x = 0.0
	velocity.z = 0.0

	attack_timer += delta
	if attack_timer >= attack_cooldown:
		attack_timer = 0.0

		# Face target before attacking
		var dir := (target.global_position - global_position).normalized()
		model.rotation.y = atan2(dir.x, dir.z)

		var distance := global_position.distance_to(target.global_position)
		if distance <= attack_range * 1.3:
			_deal_damage_to_target()
		else:
			state = State.CHASE


func _state_hit(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	hit_flash_timer -= delta
	if hit_flash_timer <= 0.0:
		if health <= 0.0:
			_die()
		else:
			state = State.CHASE


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return

	health -= amount
	health = maxf(health, 0.0)

	# Brief hit stagger + visual flash
	state = State.HIT
	hit_flash_timer = 0.1
	if model.has_method("play_hit_flash"):
		model.play_hit_flash()
	_sync_hit_flash.rpc()

	# Aggro on attacker
	if attacker and is_instance_valid(attacker):
		target = attacker

	# Broadcast damage event
	EventBus.damage_dealt.emit(-1, get_instance_id(), amount)
	_sync_floating_text.rpc(
		global_position + Vector3(0, 2, 0),
		str(int(amount)),
		Color.RED
	)

	# Sync to clients
	_sync_health.rpc(health)


@rpc("authority", "call_local", "reliable")
func _sync_floating_text(pos: Vector3, text: String, color: Color) -> void:
	EventBus.show_floating_text.emit(pos, text, color)


@rpc("authority", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	health = new_health


static func _load_monster_data() -> void:
	if _monster_data_loaded:
		return
	_monster_data_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_monster_data = json.data
		file.close()


func _apply_monster_data() -> void:
	var type_key: String = EnemyType.keys()[enemy_type]
	if not _monster_data_loaded or not _monster_data.has("monsters"):
		return
	var monsters: Dictionary = _monster_data["monsters"]
	if not monsters.has(type_key):
		return
	var stats: Dictionary = monsters[type_key]
	max_health = stats.get("max_health", max_health)
	move_speed = stats.get("move_speed", move_speed)
	attack_damage = stats.get("attack_damage", attack_damage)
	attack_range = stats.get("attack_range", attack_range)
	aggro_range = stats.get("aggro_range", aggro_range)
	attack_cooldown = stats.get("attack_cooldown", attack_cooldown)
	xp_reward = stats.get("xp_reward", xp_reward)


func _build_model() -> void:
	# Try data-driven visual from JSON first
	var type_key: String = EnemyType.keys()[enemy_type]
	if _monster_data_loaded and _monster_data.has("monsters"):
		var m: Dictionary = _monster_data["monsters"]
		if m.has(type_key) and m[type_key].has("visual"):
			model.build_from_data(m[type_key]["visual"])
			return
	# Fallback to hardcoded models
	match enemy_type:
		EnemyType.GRUNT:
			model.build_enemy_grunt()
		EnemyType.MAGE:
			model.build_enemy_mage()
		EnemyType.BRUTE:
			model.build_enemy_brute()


func _apply_floor_scaling() -> void:
	if floor_level <= 1:
		return
	var hp_dmg_pct := 0.25
	var xp_pct := 0.15
	if _monster_data_loaded and _monster_data.has("floor_scaling"):
		var fs: Dictionary = _monster_data["floor_scaling"]
		hp_dmg_pct = fs.get("health_damage_per_floor", 0.25)
		xp_pct = fs.get("xp_per_floor", 0.15)
	var scale_factor := 1.0 + (floor_level - 1) * hp_dmg_pct
	var xp_factor := 1.0 + (floor_level - 1) * xp_pct
	max_health *= scale_factor
	health = max_health
	attack_damage *= scale_factor
	xp_reward *= xp_factor


func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	EventBus.entity_died.emit(get_instance_id())
	died.emit(self)

	# Give XP to nearby players (server only)
	for player in get_tree().get_nodes_in_group("players"):
		if global_position.distance_to(player.global_position) < 20.0:
			if player.has_method("grant_xp"):
				player.grant_xp(xp_reward)

	# Drop loot (server only, RPC sends to all)
	_drop_loot()

	# Dissolve on all peers
	_sync_die.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	EventBus.enemy_killed.emit(enemy_type)
	_apply_dissolve()
	var tween := create_tween()
	tween.tween_method(_set_dissolve_amount, 0.0, 1.0, 1.2)
	tween.tween_callback(queue_free)


func apply_remote_state(pos: Vector3, rot_y: float, st: int) -> void:
	## Called by the spawner's batch broadcast, not an RPC.
	_remote_pos = pos
	_remote_rot_y = rot_y
	state = st as State
	if not _remote_initialized:
		_remote_initialized = true
		position = pos
		model.rotation.y = rot_y


@rpc("authority", "call_remote", "reliable")
func _sync_attack_anim() -> void:
	if model.has_method("play_attack_anim"):
		model.play_attack_anim()


@rpc("authority", "call_remote", "reliable")
func _sync_hit_flash() -> void:
	if model.has_method("play_hit_flash"):
		model.play_hit_flash()


func _apply_dissolve() -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var old_mat: Material = child.get_active_material(0)
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = dissolve_shader
		if old_mat is StandardMaterial3D:
			shader_mat.set_shader_parameter("base_color", old_mat.albedo_color)
		else:
			shader_mat.set_shader_parameter("base_color", Color.WHITE)
		shader_mat.set_shader_parameter("dissolve_amount", 0.0)
		shader_mat.set_shader_parameter("edge_color", Color(1.0, 0.3, 0.0))
		child.material_override = shader_mat


func _set_dissolve_amount(amount: float) -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mat = child.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("dissolve_amount", amount)


func _drop_loot() -> void:
	# Drop gold
	var g_min := 5
	var g_max := 15
	var type_key: String = EnemyType.keys()[enemy_type]
	if _monster_data_loaded and _monster_data.has("monsters"):
		var m: Dictionary = _monster_data["monsters"]
		if m.has(type_key):
			g_min = int(m[type_key].get("gold_min", 5))
			g_max = int(m[type_key].get("gold_max", 15))
	var gold_amount := randi_range(g_min, g_max) * floor_level
	_loot_counter += 1
	var gold_name := "Gold_%d" % _loot_counter
	_spawn_gold_drop.rpc(gold_name, gold_amount, global_position + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)))

	# Drop items
	var drops := ItemDatabase.generate_enemy_drops(1)
	for i in drops.size():
		var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		var drop_pos := global_position + offset
		_loot_counter += 1
		var loot_name := "Loot_%d" % _loot_counter
		_spawn_loot_drop.rpc(loot_name, drops[i].to_dict(), drop_pos)


@rpc("authority", "call_local", "reliable")
func _spawn_gold_drop(loot_name: String, amount: int, pos: Vector3) -> void:
	var gold_scene := preload("res://scenes/loot/gold_drop.tscn")
	var gold := gold_scene.instantiate()
	gold.name = loot_name
	get_parent().add_child(gold)
	gold.global_position = pos
	gold.setup(amount)


@rpc("authority", "call_local", "reliable")
func _spawn_loot_drop(loot_name: String, item_dict: Dictionary, pos: Vector3) -> void:
	var loot_scene := preload("res://scenes/loot/loot_drop.tscn")
	var loot := loot_scene.instantiate()
	loot.name = loot_name
	get_parent().add_child(loot)
	loot.global_position = pos
	var item := ItemData.from_dict(item_dict)
	loot.setup(item)


func _deal_damage_to_target() -> void:
	# Attack animation
	if model.has_method("play_attack_anim"):
		model.play_attack_anim()
	_sync_attack_anim.rpc()

	if target.has_method("receive_damage"):
		# Use RPC so damage applies on all peers (including the client who owns the player)
		target.receive_damage.rpc(attack_damage)
		# Impact burst at target
		if model.has_method("spawn_impact_burst"):
			model.spawn_impact_burst(target.global_position + Vector3(0, 1.0, 0), Color.RED)


func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := aggro_range

	for player in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		# Skip dead players
		if player.get("stats") and player.stats.health <= 0.0:
			continue
		var dist := global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest
