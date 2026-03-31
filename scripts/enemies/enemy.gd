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

# Idle wander state (server-side)
var _home_pos := Vector3.ZERO       # Spawn position — wander anchor
var _wander_target := Vector3.ZERO   # Current wander destination
var _wander_timer := 0.0            # Countdown until next wander
var _is_wandering := false           # Currently walking to a wander point
const WANDER_RADIUS := 4.0           # Max distance from home to wander
const WANDER_SPEED_MULT := 0.35      # Walk slower when wandering
const WANDER_PAUSE_MIN := 2.0        # Min seconds between wanders
const WANDER_PAUSE_MAX := 7.0        # Max seconds between wanders

# Idle look-around (server-side, synced via broadcast)
var _look_timer := 0.0
const LOOK_INTERVAL_MIN := 3.0
const LOOK_INTERVAL_MAX := 8.0


func _ready() -> void:
	_load_monster_data()
	_apply_monster_data()
	health = max_health
	add_to_group("enemies")
	dissolve_shader = load("res://assets/shaders/dissolve.gdshader")
	_build_model()
	_apply_floor_scaling()
	# Desync idle animations so enemies don't breathe/sway in unison
	if model:
		model._anim_time = randf() * 10.0
	# Initialize wander timers with random offset
	_wander_timer = randf_range(1.0, WANDER_PAUSE_MAX)
	_look_timer = randf_range(1.0, LOOK_INTERVAL_MAX)


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
			# Apply local knockback on client for immediate visual feedback
			if _knockback_vel.length() > 0.1:
				position += _knockback_vel * delta
				_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 10.0 * delta)
			else:
				_knockback_vel = Vector3.ZERO
			position = position.lerp(_remote_pos, 15.0 * delta)
			model.rotation.y = lerp_angle(model.rotation.y, _remote_rot_y, 15.0 * delta)


func _state_idle(delta: float) -> void:
	# Look for nearest player in aggro range (always top priority)
	target = _find_nearest_player()
	if target:
		_is_wandering = false
		state = State.CHASE
		return

	# Record home position on first idle frame
	if _home_pos == Vector3.ZERO:
		_home_pos = global_position

	# Idle wandering
	if _is_wandering:
		# Walking toward wander target
		var to_wander := _wander_target - global_position
		to_wander.y = 0.0
		var dist := to_wander.length()
		if dist < 0.5:
			# Arrived
			_is_wandering = false
			_wander_timer = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
			velocity.x = 0.0
			velocity.z = 0.0
			if model.has_method("set_walking"):
				model.set_walking(false)
		else:
			var dir := to_wander.normalized()
			var wander_speed := move_speed * WANDER_SPEED_MULT
			velocity.x = dir.x * wander_speed
			velocity.z = dir.z * wander_speed
			model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), 6.0 * delta)
			if model.has_method("set_walking"):
				model.set_walking(true)
	else:
		# Standing still — count down to next wander
		velocity.x = 0.0
		velocity.z = 0.0
		if model.has_method("set_walking"):
			model.set_walking(false)

		# Occasional head/body turn to look around
		_look_timer -= delta
		if _look_timer <= 0.0:
			_look_timer = randf_range(LOOK_INTERVAL_MIN, LOOK_INTERVAL_MAX)
			model.rotation.y = randf_range(-PI, PI)

		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_wander_target()


func _pick_wander_target() -> void:
	## Choose a random point near _home_pos to wander to.
	var angle := randf() * TAU
	var dist := randf_range(1.5, WANDER_RADIUS)
	_wander_target = _home_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_wander_target.y = global_position.y
	_is_wandering = true


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

	# Move toward target with local avoidance of other enemies
	var desired_dir := to_target.normalized()
	var steer := _compute_avoidance_steering(desired_dir)
	var final_dir := (desired_dir + steer).normalized()
	velocity.x = final_dir.x * move_speed
	velocity.z = final_dir.z * move_speed
	if model.has_method("set_walking"):
		model.set_walking(true)

	# Face movement direction
	var target_rot := atan2(final_dir.x, final_dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_rot, 10.0 * delta)


const AVOIDANCE_RADIUS := 2.0  # How close before steering kicks in
const AVOIDANCE_STRENGTH := 1.5  # How strongly to steer away

func _compute_avoidance_steering(desired_dir: Vector3) -> Vector3:
	## Compute a steering vector to avoid nearby enemies.
	var steer := Vector3.ZERO
	for other: Node3D in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		if other is Enemy and (other as Enemy).state == State.DEAD:
			continue
		var to_other: Vector3 = other.global_position - global_position
		to_other.y = 0.0
		var dist := to_other.length()
		if dist < 0.01 or dist > AVOIDANCE_RADIUS:
			continue
		# Push away from the other enemy, stronger when closer
		var away := -to_other.normalized()
		var strength := (AVOIDANCE_RADIUS - dist) / AVOIDANCE_RADIUS * AVOIDANCE_STRENGTH
		steer += away * strength
	return steer


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
	if model.has_method("set_walking"):
		model.set_walking(false)

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
	# Apply knockback velocity and decay it
	if _knockback_vel.length() > 0.1:
		velocity.x = _knockback_vel.x * 8.0
		velocity.z = _knockback_vel.z * 8.0
		_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 10.0 * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_knockback_vel = Vector3.ZERO
	if model.has_method("set_walking"):
		model.set_walking(false)
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
	hit_flash_timer = 0.15
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


# --- Knockback ---
var _knockback_vel := Vector3.ZERO

func apply_knockback(direction: Vector3, damage: float) -> void:
	## Push enemy away from attacker. Heavier enemies (higher max_health) resist more.
	if state == State.DEAD:
		return
	# Base knockback force, scaled inversely by enemy mass (max_health as proxy)
	var weight := clampf(max_health / 40.0, 0.5, 5.0)  # 40 hp = weight 1.0
	var force := clampf(damage * 0.4 / weight, 0.3, 3.0)
	_knockback_vel = direction * force
	_sync_knockback.rpc(direction, force)

@rpc("authority", "call_local", "reliable")
func _sync_knockback(dir: Vector3, force: float) -> void:
	_knockback_vel = dir * force


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
		EnemyType.SKELETON:
			model.build_enemy_skeleton()
		EnemyType.SPIDER:
			model.build_enemy_spider()
		EnemyType.GHOST:
			model.build_enemy_ghost()
		EnemyType.ARCHER:
			model.build_enemy_archer()
		EnemyType.SHAMAN:
			model.build_enemy_shaman()
		EnemyType.GOLEM:
			model.build_enemy_golem()
		EnemyType.SCARAB:
			model.build_enemy_scarab()
		EnemyType.WRAITH:
			model.build_enemy_wraith()
		EnemyType.NECROMANCER:
			model.build_enemy_necromancer()
		EnemyType.DEMON:
			model.build_enemy_demon()
		EnemyType.BOSS_GOLEM:
			model.build_enemy_boss_golem()
		EnemyType.BOSS_DEMON:
			model.build_enemy_boss_demon()
		EnemyType.BOSS_DRAGON:
			model.build_enemy_boss_dragon()


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


func apply_remote_state(pos: Vector3, rot_y: float, st: int, wandering: bool = false) -> void:
	## Called by the spawner's batch broadcast, not an RPC.
	_remote_pos = pos
	_remote_rot_y = rot_y
	state = st as State
	if model.has_method("set_walking"):
		model.set_walking(state == State.CHASE or wandering)
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
	var drops := ItemDatabase.generate_enemy_drops(1, 0.25)
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
