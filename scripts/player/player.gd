extends CharacterBody3D

## Player character with click-to-move, combat, and multiplayer sync.
## Supports two modes:
##   Offline/LAN: client-authoritative (original behavior)
##   Online: server-authoritative — client sends intents, server simulates

const MOVE_SPEED := 10.0
const ROTATION_SPEED := 20.0
const ARRIVAL_THRESHOLD := 0.3
const GRAVITY := 9.8
const ATTACK_RANGE := 2.8

@export var player_name: String = "Player"

@onready var model = $Model
@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer
@onready var attack_area: Area3D = $AttackArea
@onready var skill_vfx = $SkillVFX

var stats: PlayerStats = PlayerStats.new()
var inventory: Inventory = Inventory.new()
var skill_manager: SkillManager = SkillManager.new()
var move_target: Vector3 = Vector3.ZERO
var is_moving: bool = false
var attack_timer: float = 0.0
var is_attacking: bool = false
var _left_mouse_held: bool = false
var _remote_pos := Vector3.ZERO
var _remote_rot_y := 0.0
var _remote_initialized := false

## True when running in server-authoritative online mode
var _is_server_auth: bool = false

## Currently hovered/targeted node (enemy, player, interactable)
var current_target: Node3D = null


func _ready() -> void:
	move_target = global_position
	add_to_group("players")
	add_child(inventory)
	add_child(skill_manager)
	skill_manager.setup(self)
	skill_manager.skill_used.connect(_on_skill_used)

	_is_server_auth = GameManager.is_online_mode

	# Load character data
	if _is_server_auth and multiplayer.is_server():
		# Dedicated server: load from online_players data passed by game_server_main
		var peer_id := get_multiplayer_authority()
		if peer_id in GameManager.online_players:
			_load_from_dict(GameManager.online_players[peer_id])
	elif _is_server_auth and not multiplayer.is_server():
		# Client in online mode: read character name from synced online_players
		var peer_id := get_multiplayer_authority()
		if peer_id in GameManager.online_players:
			var data: Dictionary = GameManager.online_players[peer_id]
			player_name = data.get("character_name", "Player")
	elif is_multiplayer_authority() and CharacterManager.active_character:
		# Offline/LAN: load from local save
		_load_from_character_data(CharacterManager.active_character)

	# Build the multi-mesh player model
	if model.has_method("build_player_model"):
		model.build_player_model()

	# Name label above head (hidden for local player)
	_setup_name_label()

	# Server broadcasts player name to all clients after loading
	if _is_server_auth and multiplayer.is_server() and player_name != "Player":
		_sync_player_name.rpc(player_name)


func _load_from_character_data(data: CharacterData) -> void:
	stats.level = data.level
	stats.experience = data.experience
	stats.max_health = data.max_health
	stats.max_mana = data.max_mana
	stats.health = data.health
	stats.mana = data.mana
	# Never start a session dead
	if stats.health <= 0.0:
		stats.health = stats.max_health
	if stats.mana <= 0.0:
		stats.mana = stats.max_mana
	stats.strength = data.strength
	stats.dexterity = data.dexterity
	stats.intelligence = data.intelligence
	stats.vitality = data.vitality
	stats.attack_damage = data.attack_damage
	stats.attack_speed = data.attack_speed
	stats.defense = data.defense
	stats.move_speed = data.move_speed
	player_name = data.character_name

	# Restore gold
	inventory.gold = data.gold

	# Restore inventory items
	for item_dict in data.inventory_items:
		var item := ItemData.from_dict(item_dict)
		inventory.add_item(item)

	# Restore equipment
	for slot_name in data.equipment:
		var eq_dict: Dictionary = data.equipment[slot_name]
		if not eq_dict.is_empty():
			var item := ItemData.from_dict(eq_dict)
			inventory.equipment[slot_name] = item
			_apply_equipment_stats(item)


func _apply_equipment_stats(item: ItemData) -> void:
	stats.attack_damage += item.bonus_damage
	stats.defense += item.bonus_defense
	stats.max_health += item.bonus_health
	stats.health = minf(stats.health + item.bonus_health, stats.max_health)
	stats.max_mana += item.bonus_mana
	stats.mana = minf(stats.mana + item.bonus_mana, stats.max_mana)
	stats.strength += item.bonus_strength
	stats.dexterity += item.bonus_dexterity
	stats.intelligence += item.bonus_intelligence


var _name_label: Label3D

func _setup_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.font_size = 48
	_name_label.pixel_size = 0.01
	_name_label.position = Vector3(0, 2.2, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.modulate = Color(1, 1, 1, 0.9)
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color(0, 0, 0, 0.8)
	add_child(_name_label)
	# Hide for the local player
	if is_multiplayer_authority():
		_name_label.visible = false


@rpc("any_peer", "call_remote", "reliable")
func _sync_player_name(p_name: String) -> void:
	player_name = p_name
	if _name_label:
		_name_label.text = p_name


func _load_from_dict(data: Dictionary) -> void:
	## Load stats from a plain Dictionary (online mode, server-side).
	stats.level = data.get("level", 1)
	stats.experience = data.get("experience", 0.0)
	stats.max_health = data.get("max_health", 100.0)
	stats.max_mana = data.get("max_mana", 50.0)
	stats.health = data.get("health", 100.0)
	stats.mana = data.get("mana", 50.0)
	# Never start a new game session dead
	if stats.health <= 0.0:
		stats.health = stats.max_health
	if stats.mana <= 0.0:
		stats.mana = stats.max_mana
	stats.strength = data.get("strength", 10)
	stats.dexterity = data.get("dexterity", 10)
	stats.intelligence = data.get("intelligence", 10)
	stats.vitality = data.get("vitality", 10)
	stats.attack_damage = data.get("attack_damage", 10.0)
	stats.attack_speed = data.get("attack_speed", 1.0)
	stats.defense = data.get("defense", 5.0)
	stats.move_speed = data.get("move_speed", 7.0)
	player_name = data.get("character_name", "Player")
	inventory.gold = data.get("gold", 0)
	for item_dict in data.get("inventory_items", []):
		var item := ItemData.from_dict(item_dict)
		inventory.add_item(item)
	for slot_name in data.get("equipment", {}):
		var eq_dict: Dictionary = data["equipment"][slot_name]
		if not eq_dict.is_empty():
			var item := ItemData.from_dict(eq_dict)
			inventory.equipment[slot_name] = item
			_apply_equipment_stats(item)


func _update_mouse_target() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		current_target = null
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state := get_world_3d().direct_space_state
	# Check enemies (layer 4), players (layer 2), and interactables (layer 8)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4 | 2 | 128  # layers 3, 2, 8
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result and result.collider:
		var collider: Node3D = result.collider as Node3D
		if not collider:
			current_target = null
			return
		# Walk up to find the targetable parent
		if collider is Enemy:
			current_target = collider
		elif collider.is_in_group("players"):
			current_target = collider
		elif collider.is_in_group("interactables"):
			current_target = collider
		elif collider.get_parent() and collider.get_parent() is Enemy:
			current_target = collider.get_parent()
		elif collider.get_parent() and collider.get_parent().is_in_group("interactables"):
			current_target = collider.get_parent()
		else:
			current_target = null
	else:
		current_target = null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if stats.health <= 0.0:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_left_mouse_held = event.pressed
			if event.pressed:
				# Check for interactable click (fountain etc.)
				if current_target and is_instance_valid(current_target) and current_target.is_in_group("interactables"):
					if current_target.has_method("interact"):
						if _is_server_auth:
							_server_fountain_heal_intent.rpc_id(1)
						else:
							current_target.interact(self)
				_handle_move_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_attack_click()

	if event.is_action_pressed("skill_1"):
		_use_skill(0)
	elif event.is_action_pressed("skill_2"):
		_use_skill(1)
	elif event.is_action_pressed("skill_3"):
		_use_skill(2)
	elif event.is_action_pressed("skill_4"):
		_use_skill(3)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_mouse_target()
	if _is_server_auth:
		_physics_process_server_auth(delta)
	else:
		_physics_process_lan(delta)


## Server-authoritative mode: server simulates all players.
## Clients only send intents and receive state.
func _physics_process_server_auth(delta: float) -> void:
	if multiplayer.is_server():
		# Server simulates movement for ALL players
		if attack_timer > 0.0:
			attack_timer -= delta
		_process_movement(delta)
		# Broadcast authoritative position to all clients
		_apply_remote_position.rpc(global_position, model.rotation.y)
	else:
		# Client: interpolate toward server state
		if is_multiplayer_authority():
			# Also send continuous move intent while dragging
			if _left_mouse_held and not is_attacking:
				var hit_pos := _raycast_ground()
				if hit_pos != Vector3.INF:
					_server_move_intent.rpc_id(1, hit_pos)

		if _remote_initialized:
			var move_dir := _remote_pos - global_position
			move_dir.y = 0.0
			var dist := move_dir.length()
			if dist > 0.1:
				global_position = global_position.lerp(_remote_pos, 15.0 * delta)
				var target_rot := atan2(move_dir.x, move_dir.z)
				model.rotation.y = lerp_angle(model.rotation.y, target_rot, ROTATION_SPEED * delta)
				_play_animation("run")
			else:
				global_position = _remote_pos
				_play_animation("idle")
		else:
			_play_animation("idle")


## Offline/LAN mode: original client-authoritative behavior.
func _physics_process_lan(delta: float) -> void:
	if not is_multiplayer_authority():
		if _remote_initialized:
			var move_dir := _remote_pos - global_position
			move_dir.y = 0.0
			var dist := move_dir.length()
			if dist > 0.1:
				global_position = global_position.lerp(_remote_pos, 15.0 * delta)
				var target_rot := atan2(move_dir.x, move_dir.z)
				model.rotation.y = lerp_angle(model.rotation.y, target_rot, ROTATION_SPEED * delta)
				_play_animation("run")
			else:
				global_position = _remote_pos
				_play_animation("idle")
		else:
			_play_animation("idle")
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	if _left_mouse_held and not is_attacking:
		var hit_pos := _raycast_ground()
		if hit_pos != Vector3.INF:
			_set_move_target.rpc(hit_pos)

	_process_movement(delta)
	_broadcast_position()


func _handle_move_click() -> void:
	var hit_pos := _raycast_ground()
	if hit_pos != Vector3.INF:
		is_attacking = false
		if _is_server_auth:
			_server_move_intent.rpc_id(1, hit_pos)
		else:
			_set_move_target.rpc(hit_pos)


func _handle_attack_click() -> void:
	if attack_timer > 0.0:
		return

	var hit_pos := _raycast_ground()
	if hit_pos != Vector3.INF:
		var dir := (hit_pos - global_position).normalized()
		model.rotation.y = atan2(dir.x, dir.z)

	if _is_server_auth:
		_server_attack_intent.rpc_id(1, hit_pos if hit_pos != Vector3.INF else global_position)
	else:
		is_attacking = true
		is_moving = false
		attack_timer = 1.0 / stats.attack_speed
		_perform_attack.rpc()


func _raycast_ground() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var to := from + camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 # Ground layer
	var result := space_state.intersect_ray(query)

	if result:
		return result.position
	return Vector3.INF


@rpc("authority", "call_local", "reliable")
func _set_move_target(target: Vector3) -> void:
	move_target = target
	is_moving = true


## Server-authoritative: client sends move intent, server sets the target.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _server_move_intent(target: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if stats.health <= 0.0:
		return
	move_target = target
	is_moving = true
	is_attacking = false


## Server-authoritative: client sends attack intent.
@rpc("any_peer", "call_remote", "reliable")
func _server_attack_intent(target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if attack_timer > 0.0:
		return

	# Face the target direction
	var dir := (target_pos - global_position).normalized()
	if dir.length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)

	is_attacking = true
	is_moving = false
	attack_timer = 1.0 / stats.attack_speed
	_perform_attack.rpc()


## Server-authoritative: client sends skill intent.
@rpc("any_peer", "call_remote", "reliable")
func _server_skill_intent(slot: int, target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if stats.health <= 0.0:
		return
	if skill_manager.try_use_skill(slot, target_pos):
		# Broadcast to all clients: stat correction + VFX for other players
		_sync_skill_cast.rpc(slot, target_pos, stats.mana, stats.health)


## Broadcast skill results to clients: sync stats + show VFX on non-caster clients.
@rpc("authority", "call_remote", "reliable")
func _sync_skill_cast(slot: int, target_pos: Vector3, new_mana: float, new_health: float) -> void:
	stats.mana = new_mana
	stats.health = new_health
	if is_multiplayer_authority():
		return  # Caster already has local prediction feedback
	var skill: SkillData = skill_manager.skills[slot]
	if skill:
		skill_manager.cooldowns[slot] = skill.cooldown
		skill_manager._execute_skill(skill, target_pos)
		skill_manager.skill_used.emit(slot, skill)


@rpc("authority", "call_local", "reliable")
func _perform_attack() -> void:
	_play_animation("attack")

	# Play swing animation on model
	if model.has_method("play_attack_anim"):
		model.play_attack_anim()

	# Only server does hit detection
	if not multiplayer.is_server():
		return

	# Damage all enemies in the attack area
	if attack_area:
		var hit_count := 0
		for body in attack_area.get_overlapping_bodies():
			if body.is_in_group("enemies") and body.has_method("take_damage"):
				var was_alive: bool = body.health > 0.0
				body.take_damage(stats.attack_damage, self)
				hit_count += 1
				# Impact burst at enemy position
				_spawn_hit_effect.rpc(body.global_position + Vector3(0, 1.0, 0))
				# Hitstop on kill
				if was_alive and body.health <= 0.0:
					_trigger_hitstop.rpc(0.06)
		if hit_count > 0:
			_trigger_camera_shake.rpc(0.12, 0.1)


@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: float) -> void:
	var actual := stats.take_damage(amount)
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.2, 0),
		str(int(actual)),
		Color.ORANGE_RED
	)
	# Hit flash feedback
	if model.has_method("play_hit_flash"):
		model.play_hit_flash()
	# Camera shake when player takes damage (owning player only)
	if is_multiplayer_authority():
		var camera := get_viewport().get_camera_3d()
		if camera and camera.has_method("shake"):
			camera.shake(0.2, 0.15)

	if stats.health <= 0.0:
		_on_player_died()


func grant_xp(amount: float) -> void:
	_sync_grant_xp.rpc(amount)


@rpc("any_peer", "call_local", "reliable")
func _sync_grant_xp(amount: float) -> void:
	var leveled := stats.add_experience(amount)
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.5, 0),
		"+%d XP" % int(amount),
		Color.GOLD
	)
	if leveled:
		EventBus.show_floating_text.emit(
			global_position + Vector3(0, 3.0, 0),
			"LEVEL UP!",
			Color.YELLOW
		)


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	stats.health = new_health


func pick_up_item(item: ItemData) -> void:
	if inventory.add_item(item):
		EventBus.show_floating_text.emit(
			global_position + Vector3(0, 2.5, 0),
			"+ " + item.display_name,
			ItemData.get_rarity_color(item.rarity)
		)


func add_gold(amount: int) -> void:
	inventory.add_gold(amount)
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.5, 0),
		"+ %d Gold" % amount,
		Color.GOLD
	)


func _use_skill(slot: int) -> void:
	var target_pos := _raycast_ground()
	if target_pos == Vector3.INF:
		target_pos = global_position
	if _is_server_auth:
		# Local prediction: immediate VFX + cooldown for the caster
		skill_manager.try_use_skill(slot, target_pos)
		# Server validates and applies damage
		_server_skill_intent.rpc_id(1, slot, target_pos)
	else:
		_cast_skill.rpc(slot, target_pos)


@rpc("authority", "call_local", "reliable")
func _cast_skill(slot: int, target_pos: Vector3) -> void:
	skill_manager.try_use_skill(slot, target_pos)


func _on_player_died() -> void:
	is_moving = false
	is_attacking = false
	if multiplayer.is_server():
		_sync_player_died.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_player_died() -> void:
	is_moving = false
	is_attacking = false
	_left_mouse_held = false
	# Fall-over animation
	var tween := create_tween()
	tween.tween_property(model, "rotation:x", -PI / 2.0, 0.5).set_ease(Tween.EASE_IN)


func request_respawn() -> void:
	if _is_server_auth:
		_server_respawn_intent.rpc_id(1)
	else:
		# LAN mode: restore locally and broadcast
		stats.health = stats.max_health
		stats.mana = stats.max_mana
		_do_respawn.rpc(stats.health, stats.mana)


@rpc("any_peer", "call_remote", "reliable")
func _server_respawn_intent() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if stats.health > 0.0:
		return
	stats.health = stats.max_health
	stats.mana = stats.max_mana
	# Reset server-side state
	move_target = global_position
	is_moving = false
	is_attacking = false
	model.rotation.x = 0.0
	_do_respawn.rpc(stats.health, stats.mana)
	# Teleport to town
	var main_game := get_tree().current_scene
	if main_game and main_game.has_method("respawn_player_in_town"):
		main_game.respawn_player_in_town(get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _do_respawn(new_health: float, new_mana: float) -> void:
	stats.health = new_health
	stats.mana = new_mana
	stats.max_health = maxf(stats.max_health, new_health)
	stats.max_mana = maxf(stats.max_mana, new_mana)
	move_target = global_position
	is_moving = false
	is_attacking = false
	# Reset fall-over animation
	model.rotation.x = 0.0


@rpc("any_peer", "call_remote", "reliable")
func _server_fountain_heal_intent() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if stats.health <= 0.0:
		return
	stats.health = stats.max_health
	stats.mana = stats.max_mana
	_sync_fountain_heal.rpc(stats.health, stats.mana)


@rpc("any_peer", "call_remote", "reliable")
func _sync_fountain_heal(new_health: float, new_mana: float) -> void:
	stats.health = new_health
	stats.mana = new_mana


func _process_movement(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if not is_moving:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_animation("idle")
		move_and_slide()
		return

	var to_target := move_target - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance < ARRIVAL_THRESHOLD:
		is_moving = false
		velocity.x = 0.0
		velocity.z = 0.0
		_play_animation("idle")
		move_and_slide()
		return

	var direction := to_target.normalized()

	# Rotate model to face movement direction
	var target_rotation := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_rotation, ROTATION_SPEED * delta)

	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED

	_play_animation("run")
	move_and_slide()


var _current_anim: String = ""

func _play_animation(anim_name: String) -> void:
	if not anim_player:
		return
	if _current_anim != anim_name and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
		_current_anim = anim_name


func _on_skill_used(slot: int, skill: SkillData) -> void:
	if not skill_vfx:
		return
	var target_pos := _raycast_ground()
	if target_pos == Vector3.INF:
		target_pos = global_position
	match skill.id:
		"fireball":
			skill_vfx.trigger_fireball(target_pos)
		"heal":
			skill_vfx.trigger_heal()
		"whirlwind":
			skill_vfx.trigger_whirlwind()
		"frost_nova":
			skill_vfx.trigger_frost_nova()


@rpc("any_peer", "call_local", "reliable")
func _spawn_hit_effect(hit_pos: Vector3) -> void:
	if model.has_method("spawn_impact_burst"):
		model.spawn_impact_burst(hit_pos, Color.ORANGE)


@rpc("any_peer", "call_local", "reliable")
func _trigger_camera_shake(intensity: float, duration: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(intensity, duration)


@rpc("any_peer", "call_local", "reliable")
func _trigger_hitstop(duration: float) -> void:
	## Brief engine time-scale dip for impactful kills.
	Engine.time_scale = 0.05
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)


# --- Position broadcasting for multiplayer sync ---

func _broadcast_position() -> void:
	var pos := global_position
	var rot_y: float = model.rotation.y
	if multiplayer.is_server():
		# Host player: server sends directly to all clients
		_apply_remote_position.rpc(pos, rot_y)
	else:
		# Client player: send to server for relay
		_server_receive_position.rpc_id(1, pos, rot_y)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _server_receive_position(pos: Vector3, rot_y: float) -> void:
	if not multiplayer.is_server():
		return
	# Validate that the sender owns this player
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	# Apply on server copy
	global_position = pos
	model.rotation.y = rot_y
	# Relay to all clients
	_apply_remote_position.rpc(pos, rot_y)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _apply_remote_position(pos: Vector3, rot_y: float) -> void:
	if is_multiplayer_authority() and not _is_server_auth:
		return  # LAN mode: owning peer does its own movement
	_remote_pos = pos
	_remote_rot_y = rot_y
	_remote_initialized = true
