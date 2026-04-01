extends CharacterBody3D

## Player character with click-to-move, combat, and multiplayer sync.
## Supports two modes:
##   Offline/LAN: client-authoritative (original behavior)
##   Online: server-authoritative — client sends intents, server simulates

const MOVE_SPEED := 10.0
const ROTATION_SPEED := 20.0
const ARRIVAL_THRESHOLD := 0.3
const GRAVITY := 9.8
const ATTACK_RANGE := 3.5
const ATTACK_CONE_HALF_ANGLE := 0.85  # ~49 degrees — wide enough for 2-3 enemies

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
var _spawn_grace: float = 0.5  # Seconds to ignore gravity after spawn
var _grid_sync_dirty: bool = false
var _grid_sync_timer: float = 0.0
const GRID_SYNC_INTERVAL := 0.5
var _remote_initialized := false

## True when running in server-authoritative online mode
var _is_server_auth: bool = false

## Currently hovered/targeted node (enemy, player, interactable)
var current_target: Node3D = null
var _prev_target: Node3D = null
var _pending_interact: Node3D = null
const INTERACT_RANGE := 4.0
var debug_invincible: bool = false

## Town Portal casting
var _tp_casting: bool = false
var _tp_cast_timer: float = 0.0
const TP_CAST_TIME := 3.0

## Shared outline overlay material
static var _outline_material: ShaderMaterial

## Cached appearance for UI displays (party panel, portraits)
var cached_appearance: Dictionary = {}

## Speed modifier applied by enemy abilities (frost, web, etc.)
var _speed_mod: float = 1.0
## Knockback velocity from enemy abilities
var _knockback_vel: Vector3 = Vector3.ZERO
## Active debuffs — Array of Dictionaries: {id: String, name: String, remaining: float, duration: float, color: Color}
var active_debuffs: Array[Dictionary] = []

## Buff state variables (managed by skill_manager, ticked by _tick_buffs)
var _buff_damage_mult: float = 0.0     # Extra damage multiplier from buffs (war_cry, berserker_rage)
var _buff_invulnerable: bool = false    # Shield Wall
var _buff_absorb: float = 0.0          # Ice Barrier absorb pool
var _buff_mana_shield: bool = false     # Mana Shield active
var _buff_invisible: bool = false       # Vanish stealth


func _ready() -> void:
	if _outline_material == null:
		var shader := load("res://assets/shaders/outline.gdshader") as Shader
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = shader
		_outline_material.set_shader_parameter("outline_color", Color(1.0, 0.8, 0.2, 1.0))
		_outline_material.set_shader_parameter("outline_width", 0.025)
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
		# Client in online mode: load full stats so HUD/display is correct
		var peer_id := get_multiplayer_authority()
		if peer_id in GameManager.online_players:
			_load_from_dict(GameManager.online_players[peer_id])
	elif is_multiplayer_authority() and CharacterManager.active_character:
		# Offline/LAN: load from local save
		_load_from_character_data(CharacterManager.active_character)

	# Sync equipment changes to server
	if _is_server_auth and is_multiplayer_authority():
		inventory.item_equipped.connect(_on_item_equipped_sync)
		inventory.item_unequipped.connect(_on_item_unequipped_sync)
		inventory.inventory_changed.connect(_on_inventory_changed_sync)
		inventory.potions_changed.connect(_on_potions_changed_sync)

	# Build the class-specific model from appearance data
	var appearance: Dictionary = {}
	# 1) Try full custom appearance from local save (only for our own player node)
	if is_multiplayer_authority() and CharacterManager.active_character and CharacterManager.active_character.appearance.size() > 0:
		appearance = CharacterManager.active_character.appearance
	# 2) Try online_players dict (server or client loading any player)
	if appearance.is_empty() and _is_server_auth:
		var pid := get_multiplayer_authority()
		if pid in GameManager.online_players:
			appearance = GameManager.online_players[pid].get("appearance", {})
	# 3) Fallback: build default appearance from known character class
	if appearance.is_empty():
		var cls_id: int = 0
		if is_multiplayer_authority() and CharacterManager.active_character:
			cls_id = CharacterManager.active_character.character_class as int
		elif _is_server_auth:
			var pid2 := get_multiplayer_authority()
			if pid2 in GameManager.online_players:
				cls_id = int(GameManager.online_players[pid2].get("character_class", 0))
		appearance = _default_appearance_for_class(cls_id)
	cached_appearance = appearance
	if model.has_method("build_class_model"):
		model.build_class_model(appearance)

	# For remote players on a client, load name from online_players
	if _is_server_auth and not multiplayer.is_server() and not is_multiplayer_authority():
		var pid3 := get_multiplayer_authority()
		if pid3 in GameManager.online_players:
			player_name = GameManager.online_players[pid3].get("character_name", player_name)

	# Name label above head (hidden for local player)
	_setup_name_label()

	# Server broadcasts player name and appearance to all clients after loading
	if _is_server_auth and multiplayer.is_server() and player_name != "Player":
		_sync_player_name.rpc(player_name)
		_sync_appearance.rpc(appearance)
	elif not _is_server_auth and is_multiplayer_authority():
		# LAN: broadcast our appearance to peers
		_sync_appearance.rpc(appearance)


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

	# Restore potion counts
	inventory.health_potions = data.health_potions
	inventory.mana_potions = data.mana_potions

	# Restore inventory items (support both grid and legacy format)
	var items_data: Array = data.inventory_items
	if items_data.size() > 0 and items_data[0] is Dictionary and items_data[0].has("x"):
		inventory.deserialize_grid(items_data)
	else:
		inventory.legacy_import(items_data)

	# Restore equipment
	for slot_name in data.equipment:
		var eq_dict: Dictionary = data.equipment[slot_name]
		if not eq_dict.is_empty():
			var item := ItemData.from_dict(eq_dict)
			inventory.equipment[slot_name] = item
			_apply_equipment_stats(item)

	# Compute initial resonances from loaded equipment
	inventory.recalculate_resonances(self)

	# Restore quests
	if data.quest_data.size() > 0:
		QuestManager.load_from_array(data.quest_data)

	# Restore skill points
	if skill_manager:
		skill_manager.skill_points = data.skill_points
		skill_manager.allocated_points = data.allocated_skill_points.duplicate()
		# If save has no points at all, recompute from level
		if skill_manager.skill_points <= 0 and skill_manager.allocated_points.is_empty() and stats.level > 1:
			skill_manager.skill_points = stats.level - 1
		skill_manager._apply_passive_bonuses()
		skill_manager._rebuild_skill_slots()


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
	inventory._apply_affix_stats(item, stats, 1.0)


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


@rpc("any_peer", "call_remote", "reliable")
func _sync_appearance(p_appearance: Dictionary) -> void:
	if p_appearance.size() > 0:
		cached_appearance = p_appearance
	if model and model.has_method("build_class_model") and p_appearance.size() > 0:
		model.build_class_model(p_appearance)


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
	# Load potion counts
	inventory.health_potions = int(data.get("health_potions", 0))
	inventory.mana_potions = int(data.get("mana_potions", 0))
	# Load inventory: support both grid format and legacy flat array
	var items_data: Array = data.get("inventory_items", [])
	if items_data.size() > 0 and items_data[0] is Dictionary and items_data[0].has("x"):
		# New grid format
		inventory.deserialize_grid(items_data)
	else:
		# Legacy flat array format
		inventory.legacy_import(items_data)
	for slot_name in data.get("equipment", {}):
		var eq_dict: Dictionary = data["equipment"][slot_name]
		if not eq_dict.is_empty():
			var item := ItemData.from_dict(eq_dict)
			inventory.equipment[slot_name] = item
			_apply_equipment_stats(item)
	# Restore quests (client only)
	var quest_arr: Array = data.get("quest_data", [])
	if quest_arr.size() > 0 and is_multiplayer_authority():
		QuestManager.load_from_array(quest_arr)

	# Restore skill points
	if skill_manager:
		skill_manager.skill_points = int(data.get("skill_points", 0))
		skill_manager.allocated_points = data.get("allocated_skill_points", {}).duplicate()
		# If save has no points at all, recompute from level
		if skill_manager.skill_points <= 0 and skill_manager.allocated_points.is_empty() and stats.level > 1:
			skill_manager.skill_points = stats.level - 1
		skill_manager._apply_passive_bonuses()
		skill_manager._rebuild_skill_slots()


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

	# Apply/remove outline when target changes
	if current_target != _prev_target:
		if _prev_target and is_instance_valid(_prev_target):
			_remove_outline(_prev_target)
		if current_target and is_instance_valid(current_target):
			_apply_outline(current_target)
		_prev_target = current_target


func _apply_outline(node: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_overlay = _outline_material
		elif child is Node3D:
			_apply_outline(child)


func _remove_outline(node: Node3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.material_overlay = null
		elif child is Node3D:
			_remove_outline(child)


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
						_pending_interact = current_target
						# Move toward the interactable
						var target_pos := current_target.global_position
						is_attacking = false
						if _is_server_auth:
							_server_move_intent.rpc_id(1, target_pos)
						else:
							_set_move_target.rpc(target_pos)
				else:
					_pending_interact = null
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

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_use_health_potion()
		elif event.keycode == KEY_E:
			_use_mana_potion()
		elif event.keycode == KEY_T:
			_start_town_portal_cast()


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_mouse_target()
		_check_pending_interact()
		_tick_town_portal_cast(delta)
		_tick_debuffs(delta)
		if _is_server_auth:
			_process_grid_sync(delta)
	if _is_server_auth:
		_physics_process_server_auth(delta)
	else:
		_physics_process_lan(delta)


func _check_pending_interact() -> void:
	if not _pending_interact or not is_instance_valid(_pending_interact):
		_pending_interact = null
		return
	var dist := global_position.distance_to(_pending_interact.global_position)
	if dist <= INTERACT_RANGE:
		var target := _pending_interact
		_pending_interact = null
		if target.has_method("interact"):
			target.interact(self)
			if _is_server_auth:
				#print("[Client] Sending interact intent for '%s'" % target.name)
				_server_interact_intent.rpc_id(1, target.name)


## Server-authoritative mode: server simulates all players.
## Clients only send intents and receive state.
func _physics_process_server_auth(delta: float) -> void:
	if multiplayer.is_server():
		# Server simulates movement for ALL players
		if attack_timer > 0.0:
			attack_timer -= delta
		stats.tick_mana_regen(delta)
		_tick_buffs(delta)
		_tick_debuffs(delta)
		_process_movement(delta)
		# Broadcast authoritative position to all clients
		_apply_remote_position.rpc(global_position, model.rotation.y)
	else:
		# Client: interpolate toward server state
		if is_multiplayer_authority():
			# Also send continuous move intent while dragging
			if _left_mouse_held and not is_attacking and not _pending_interact and not _tp_casting:
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

	if _left_mouse_held and not is_attacking and not _pending_interact:
		var hit_pos := _raycast_ground()
		if hit_pos != Vector3.INF:
			_set_move_target.rpc(hit_pos)

	_process_movement(delta)
	_broadcast_position()


func _handle_move_click() -> void:
	_cancel_town_portal_cast()
	var hit_pos := _raycast_ground()
	if hit_pos != Vector3.INF:
		is_attacking = false
		if _is_server_auth:
			_server_move_intent.rpc_id(1, hit_pos)
		else:
			_set_move_target.rpc(hit_pos)


func _handle_attack_click() -> void:
	_cancel_town_portal_cast()
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
		attack_timer = 1.0 / (stats.attack_speed * (1.0 + stats.attack_speed_pct))
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


@rpc("any_peer", "call_local", "reliable")
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
	if _tp_casting:
		return  # Block movement while casting town portal
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
	attack_timer = 1.0 / (stats.attack_speed * (1.0 + stats.attack_speed_pct))
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
@rpc("any_peer", "call_remote", "reliable")
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


@rpc("any_peer", "call_local", "reliable")
func _perform_attack() -> void:
	_play_animation("attack")

	# Play swing animation on model
	if model.has_method("play_attack_anim"):
		model.play_attack_anim()

	# Only server does hit detection
	if not multiplayer.is_server():
		return

	# Cone-shaped hit detection: check all nearby bodies in a forward arc
	var forward := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y)).normalized()
	var hit_count := 0
	if attack_area:
		for body in attack_area.get_overlapping_bodies():
			var to_body := body.global_position - global_position
			to_body.y = 0.0
			var dist := to_body.length()
			if dist < 0.1 or dist > ATTACK_RANGE:
				continue
			# Angle check — must be within the cone
			var angle := forward.angle_to(to_body.normalized())
			if angle > ATTACK_CONE_HALF_ANGLE:
				continue

			if body.is_in_group("enemies") and body.has_method("take_damage"):
				var was_alive: bool = body.health > 0.0
				var dmg := (stats.attack_damage + stats.strength * 0.5) * (1.0 + _buff_damage_mult)
				dmg += stats.bonus_fire_damage + stats.bonus_cold_damage + stats.bonus_lightning_damage
				# Poison Blade — add bonus poison damage per hit
				var has_poison := false
				for b in active_buffs:
					if b["id"] == "poison_blade":
						has_poison = true
						break
				if has_poison:
					dmg += stats.dexterity * 0.3
				# Vanish — bonus damage on first attack from stealth
				if _buff_invisible:
					dmg *= 1.8
					_buff_invisible = false
					_set_visibility.rpc(true)
					# Remove vanish buff early
					for bi in range(active_buffs.size() - 1, -1, -1):
						if active_buffs[bi]["id"] == "vanish":
							active_buffs.remove_at(bi)
				# Crit check
				if randf() < stats.crit_chance_pct:
					dmg *= 1.5 + stats.crit_damage_pct
				body.take_damage(dmg, self)
				hit_count += 1
				# Life steal
				if stats.life_steal_pct > 0.0:
					stats.heal(dmg * stats.life_steal_pct)
				# Burn chance
				if stats.burn_chance_pct > 0.0 and randf() < stats.burn_chance_pct and body.has_method("apply_burn"):
					body.apply_burn(stats.bonus_fire_damage * 0.5, 3.0)
				# Slow on hit
				if stats.slow_on_hit_pct > 0.0 and randf() < stats.slow_on_hit_pct and body.has_method("apply_slow"):
					body.apply_slow(0.5, 2.0)
				# Impact burst at enemy position
				_spawn_hit_effect.rpc(body.global_position + Vector3(0, 1.0, 0))
				# Knockback — push enemy away from player
				var kb_dir := to_body.normalized()
				body.apply_knockback(kb_dir, stats.attack_damage)
				# Hitstop on kill
				if was_alive and body.health <= 0.0:
					_trigger_hitstop.rpc(0.06)
					if stats.heal_on_kill > 0.0:
						stats.heal(stats.heal_on_kill)
			elif body.is_in_group("breakables") and body.has_method("take_damage"):
				body.take_damage(1.0, self)
				_spawn_hit_effect.rpc(body.global_position + Vector3(0, 0.3, 0))
	if hit_count > 0:
		_trigger_camera_shake.rpc(0.12, 0.1)


@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: float) -> void:
	if debug_invincible:
		return
	# Shield Wall — block all damage
	if _buff_invulnerable:
		EventBus.show_floating_text.emit(
			global_position + Vector3(0, 2.2, 0),
			tr("Blocked"),
			Color.GRAY
		)
		return
	# Berserker Rage — take 30% more damage while active
	var has_berserk := false
	for b in active_buffs:
		if b["id"] == "berserker_rage":
			has_berserk = true
			break
	if has_berserk:
		amount *= 1.3
	# Mana Shield — redirect to mana
	if _buff_mana_shield and stats.mana > 0.0:
		var mana_cost := amount * 0.5
		if stats.mana >= mana_cost:
			stats.mana -= mana_cost
			amount *= 0.5
		else:
			amount -= stats.mana * 2.0
			stats.mana = 0.0
	# Dodge check
	if stats.dodge_pct > 0.0 and randf() < stats.dodge_pct:
		EventBus.show_floating_text.emit(
			global_position + Vector3(0, 2.2, 0),
			tr("Dodge!"),
			Color.LIGHT_BLUE
		)
		return
	# Ice Barrier absorb
	if _buff_absorb > 0.0:
		if _buff_absorb >= amount:
			_buff_absorb -= amount
			EventBus.show_floating_text.emit(
				global_position + Vector3(0, 2.2, 0),
				tr("Absorbed"),
				Color.CYAN
			)
			return
		else:
			amount -= _buff_absorb
			_buff_absorb = 0.0
	# Damage reduction from affixes/resonances
	if stats.damage_reduction_pct > 0.0:
		amount *= (1.0 - stats.damage_reduction_pct)
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
	var xp_mult := 1.0 + stats.xp_bonus_pct
	var levels_gained: int = stats.add_experience(amount * xp_mult)
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.5, 0),
		tr("+%d XP") % int(amount),
		Color.GOLD
	)
	if levels_gained > 0:
		EventBus.show_floating_text.emit(
			global_position + Vector3(0, 3.0, 0),
			tr("LEVEL UP!"),
			Color.YELLOW
		)
		if skill_manager:
			for _i in range(levels_gained):
				skill_manager.add_skill_point()


@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: float) -> void:
	stats.health = new_health


func pick_up_item(item: ItemData) -> bool:
	# Route potions to the separate potion counter system
	if item.item_type == ItemData.ItemType.POTION:
		if inventory.add_potion(item.id):
			_show_pickup_text.rpc("+ " + tr(item.display_name), ItemData.get_rarity_color(item.rarity).to_html())
			if multiplayer.is_server():
				_client_receive_potion.rpc_id(get_multiplayer_authority(), item.id)
			return true
		else:
			return false
	if inventory.add_item(item):
		_show_pickup_text.rpc("+ " + tr(item.display_name), ItemData.get_rarity_color(item.rarity).to_html())
		# Send item to owning client so it appears in their local inventory
		if multiplayer.is_server():
			_client_receive_pickup.rpc_id(get_multiplayer_authority(), item.to_dict())
		return true
	else:
		_show_pickup_text.rpc(tr("Inventory Full!"), Color.RED.to_html())
		return false


@rpc("any_peer", "call_local", "reliable")
func _show_pickup_text(text: String, color_html: String) -> void:
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.5, 0),
		text,
		Color.from_string(color_html, Color.WHITE)
	)


func add_gold(amount: int) -> void:
	inventory.add_gold(amount)
	EventBus.show_floating_text.emit(
		global_position + Vector3(0, 2.5, 0),
		tr("+ %d Gold") % amount,
		Color.GOLD
	)


## Called by shop UI to sync gold changes to the server.
func sync_gold_to_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_sync_gold.rpc_id(1, inventory.gold)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_gold(new_gold: int) -> void:
	if not multiplayer.is_server():
		return
	inventory.gold = new_gold


## Called to sync quest progress to the server for online save.
var _quest_data_cache: Array = []

func sync_quests_to_server() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var data := QuestManager.save_to_array()
		_rpc_sync_quests.rpc_id(1, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_quests(data: Array) -> void:
	if not multiplayer.is_server():
		return
	_quest_data_cache = data


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


@rpc("any_peer", "call_local", "reliable")
func _cast_skill(slot: int, target_pos: Vector3) -> void:
	skill_manager.try_use_skill(slot, target_pos)


## --- Potion use (Q / E hotkeys) ---

func _use_health_potion() -> void:
	if inventory.health_potions <= 0:
		return
	inventory.use_health_potion(self)
	if _is_server_auth:
		_server_use_potion.rpc_id(1, "health_potion")


func _use_mana_potion() -> void:
	if inventory.mana_potions <= 0:
		return
	inventory.use_mana_potion(self)
	if _is_server_auth:
		_server_use_potion.rpc_id(1, "mana_potion")


@rpc("any_peer", "call_remote", "reliable")
func _server_use_potion(potion_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if potion_id == "health_potion":
		inventory.use_health_potion(self)
	elif potion_id == "mana_potion":
		inventory.use_mana_potion(self)


## Server -> client: add a picked-up potion to the client's counter
@rpc("any_peer", "call_remote", "reliable")
func _client_receive_potion(potion_id: String) -> void:
	inventory.add_potion(potion_id)


func _on_player_died() -> void:
	is_moving = false
	is_attacking = false
	if multiplayer.is_server():
		_sync_player_died.rpc()


@rpc("any_peer", "call_local", "reliable")
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
func _server_interact_intent(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if stats.health <= 0.0:
		return
	# Find the interactable by name
	var best: Node3D = null
	for node in get_tree().get_nodes_in_group("interactables"):
		if node.name == target_name:
			best = node as Node3D
			break
	if not best or not best.has_method("interact"):
		#print("[Interact] '%s' not found in interactables group" % target_name)
		return
	var player_dist := global_position.distance_to(best.global_position)
	#print("[Interact] %s -> %s  dist=%.1f" % [player_name, target_name, player_dist])
	best.interact(self)
	# If this is a chest that just opened, spawn loot
	if best.has_method("get_floor_level") and best.get("_opened") == true:
		if not best.get("_loot_dropped"):
			best._loot_dropped = true
			var floor_lvl: int = best.get_floor_level()
			_spawn_chest_loot(floor_lvl, best.global_position)
	# Tell client to run interact() locally for stat changes (fountain heal etc.)
	_sync_interact_done.rpc(target_name)

@rpc("any_peer", "call_remote", "reliable")
func _sync_interact_done(target_name: String) -> void:
	for node in get_tree().get_nodes_in_group("interactables"):
		if node.name == target_name and node.has_method("interact"):
			node.interact(self)
			break


## --- Equipment sync (client -> server) ---

func _on_item_equipped_sync(slot: String, item: ItemData) -> void:
	_server_equip_item.rpc_id(1, slot, item.to_dict())


func _on_item_unequipped_sync(slot: String) -> void:
	_server_unequip_item.rpc_id(1, slot)


@rpc("any_peer", "call_remote", "reliable")
func _server_equip_item(slot: String, item_dict: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	# Remove old equipment bonuses if something was in this slot
	if inventory.equipment.has(slot) and inventory.equipment[slot] != null:
		var old_item: ItemData = inventory.equipment[slot]
		_remove_item_stats(old_item)
	# Apply new item bonuses
	var item := ItemData.from_dict(item_dict)
	inventory.equipment[slot] = item
	_apply_item_stats(item)
	inventory.recalculate_resonances(self)


@rpc("any_peer", "call_remote", "reliable")
func _server_unequip_item(slot: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	if not inventory.equipment.has(slot) or inventory.equipment[slot] == null:
		return
	var item: ItemData = inventory.equipment[slot]
	_remove_item_stats(item)
	inventory.equipment[slot] = null
	inventory.recalculate_resonances(self)


func _apply_item_stats(item: ItemData) -> void:
	stats.attack_damage += item.bonus_damage
	stats.defense += item.bonus_defense
	stats.max_health += item.bonus_health
	stats.health = minf(stats.health + item.bonus_health, stats.max_health)
	stats.max_mana += item.bonus_mana
	stats.mana = minf(stats.mana + item.bonus_mana, stats.max_mana)
	stats.strength += item.bonus_strength
	stats.dexterity += item.bonus_dexterity
	stats.intelligence += item.bonus_intelligence
	inventory._apply_affix_stats(item, stats, 1.0)


func _remove_item_stats(item: ItemData) -> void:
	stats.attack_damage -= item.bonus_damage
	stats.defense -= item.bonus_defense
	stats.max_health -= item.bonus_health
	stats.health = minf(stats.health, stats.max_health)
	stats.max_mana -= item.bonus_mana
	stats.mana = minf(stats.mana, stats.max_mana)
	stats.strength -= item.bonus_strength
	stats.dexterity -= item.bonus_dexterity
	stats.intelligence -= item.bonus_intelligence
	inventory._apply_affix_stats(item, stats, -1.0)


## --- Inventory grid sync (client -> server) ---

func _on_inventory_changed_sync() -> void:
	_grid_sync_dirty = true


func _on_potions_changed_sync() -> void:
	# Potions changed on client — sync to server immediately
	if _is_server_auth and is_multiplayer_authority():
		_server_sync_potions.rpc_id(1, inventory.health_potions, inventory.mana_potions)


func _process_grid_sync(delta: float) -> void:
	if not _grid_sync_dirty:
		return
	_grid_sync_timer += delta
	if _grid_sync_timer >= GRID_SYNC_INTERVAL:
		_grid_sync_timer = 0.0
		_grid_sync_dirty = false
		var grid_data := inventory.serialize_grid()
		_server_sync_grid.rpc_id(1, grid_data)


@rpc("any_peer", "call_remote", "reliable")
func _server_sync_grid(grid_data: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	inventory.deserialize_grid(grid_data)


@rpc("any_peer", "call_remote", "reliable")
func _server_sync_potions(hp: int, mp: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	inventory.health_potions = hp
	inventory.mana_potions = mp


## Server -> client: add a picked-up item to the client's inventory
@rpc("any_peer", "call_remote", "reliable")
func _client_receive_pickup(item_dict: Dictionary) -> void:
	var item := ItemData.from_dict(item_dict)
	inventory.add_item(item)


## --- Chest loot spawning (called on server, RPCs to all peers) ---

static var _chest_loot_counter: int = 0


func _spawn_chest_loot(floor_lvl: int, chest_pos: Vector3) -> void:
	## Server generates chest loot and broadcasts via RPCs.
	# Gold
	var gold_amount := randi_range(10, 30) * floor_lvl
	_chest_loot_counter += 1
	var gold_name := "ChestGold_%d" % _chest_loot_counter
	_sync_spawn_gold.rpc(gold_name, gold_amount, chest_pos + Vector3(0, 0.5, 0))

	# Item drops
	var drops := ItemDatabase.generate_enemy_drops(floor_lvl)
	if drops.is_empty():
		if randf() < 0.5:
			drops.append(ItemDatabase.get_random_weapon(floor_lvl))
		else:
			drops.append(ItemDatabase.get_random_armor(floor_lvl))
	for i in drops.size():
		var offset := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
		_chest_loot_counter += 1
		var loot_name := "ChestLoot_%d" % _chest_loot_counter
		_sync_spawn_loot.rpc(loot_name, drops[i].to_dict(), chest_pos + offset + Vector3(0, 0.5, 0))


func rpc_spawn_gold(amount: int, pos: Vector3) -> void:
	_chest_loot_counter += 1
	var loot_name := "ChestGold_%d" % _chest_loot_counter
	_sync_spawn_gold.rpc(loot_name, amount, pos)


func rpc_spawn_loot(item_dict: Dictionary, pos: Vector3) -> void:
	_chest_loot_counter += 1
	var loot_name := "ChestLoot_%d" % _chest_loot_counter
	_sync_spawn_loot.rpc(loot_name, item_dict, pos)


@rpc("any_peer", "call_local", "reliable")
func _sync_spawn_gold(loot_name: String, amount: int, pos: Vector3) -> void:
	var gold := preload("res://scenes/loot/gold_drop.tscn").instantiate()
	gold.name = loot_name
	get_parent().add_child(gold)
	gold.global_position = pos
	gold.setup(amount)


@rpc("any_peer", "call_local", "reliable")
func _sync_spawn_loot(loot_name: String, item_dict: Dictionary, pos: Vector3) -> void:
	var loot := preload("res://scenes/loot/loot_drop.tscn").instantiate()
	loot.name = loot_name
	get_parent().add_child(loot)
	loot.global_position = pos
	var item_data := ItemData.from_dict(item_dict)
	loot.setup(item_data)


func _process_movement(delta: float) -> void:
	# Decay knockback
	if _knockback_vel.length() > 0.1:
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 20.0 * delta)
	else:
		_knockback_vel = Vector3.ZERO

	# Spawn grace — skip gravity until physics has processed floor collision
	if _spawn_grace > 0.0:
		_spawn_grace -= delta
		velocity.y = 0.0
		move_and_slide()
		return
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if not is_moving:
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		if _knockback_vel.length() < 0.1:
			_play_animation("idle")
		move_and_slide()
		return

	var to_target := move_target - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance < ARRIVAL_THRESHOLD:
		is_moving = false
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		if _knockback_vel.length() < 0.1:
			_play_animation("idle")
		move_and_slide()
		return

	var direction := to_target.normalized()

	# Rotate model to face movement direction
	var target_rotation := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_rotation, ROTATION_SPEED * delta)

	velocity.x = direction.x * stats.move_speed * _speed_mod + _knockback_vel.x
	velocity.z = direction.z * stats.move_speed * _speed_mod + _knockback_vel.z

	_play_animation("run")
	move_and_slide()
	_push_colliding_enemies()


const PUSH_FORCE := 1.5  # How fast players push enemies (units/sec)

func _push_colliding_enemies() -> void:
	## After move_and_slide, gently push any enemy we collided with.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Enemy and (collider as Enemy).state != Enemy.State.DEAD:
			var enemy: Enemy = collider as Enemy
			var push_dir: Vector3 = (enemy.global_position - global_position).normalized()
			push_dir.y = 0.0
			enemy.global_position += push_dir * PUSH_FORCE * get_physics_process_delta_time()


var _current_anim: String = ""

func _play_animation(anim_name: String) -> void:
	if _current_anim == anim_name:
		return
	_current_anim = anim_name
	var walking := anim_name == "run"
	if model and model.has_method("set_walking"):
		model.set_walking(walking)
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)


static func _default_appearance_for_class(cls_id: int) -> Dictionary:
	## Build a default appearance dict for a class when no customization is saved.
	match cls_id:
		1: return {
			"character_class": 1,
			"armor_color": [0.25, 0.1, 0.5],
			"accent_color": [0.6, 0.2, 1.0],
			"body_scale": [1.0, 1.0, 1.0],
			"size_mult": 1.0,
		}
		2: return {
			"character_class": 2,
			"armor_color": [0.15, 0.15, 0.2],
			"accent_color": [0.3, 0.3, 0.4],
			"body_scale": [1.0, 1.0, 1.0],
			"size_mult": 1.0,
		}
		_: return {
			"character_class": 0,
			"armor_color": [0.7, 0.15, 0.1],
			"accent_color": [0.9, 0.35, 0.15],
			"body_scale": [1.0, 1.0, 1.0],
			"size_mult": 1.0,
		}


func _on_skill_used(_slot: int, skill: SkillData) -> void:
	if not skill_vfx:
		return
	var target_pos := _raycast_ground()
	if target_pos == Vector3.INF:
		target_pos = global_position

	# Self-centered skills use player position; targeted skills use cursor position
	var self_skills: Array[String] = [
		"heal", "whirlwind", "shield_wall", "war_cry", "berserker_rage",
		"frost_nova", "ice_barrier", "mana_shield", "poison_blade",
		"vanish", "fan_of_knives", "cleave"
	]
	if skill.id in self_skills:
		skill_vfx.trigger(skill.id, global_position)
	else:
		skill_vfx.trigger(skill.id, target_pos)


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


# --- Town Portal ---

func _start_town_portal_cast() -> void:
	if stats.health <= 0:
		return
	if _tp_casting:
		return  # Already casting
	_tp_casting = true
	_tp_cast_timer = TP_CAST_TIME
	is_moving = false
	is_attacking = false
	_left_mouse_held = false
	move_target = global_position
	if _is_server_auth:
		_server_tp_cast_start.rpc_id(1)
	EventBus.show_floating_text.emit(global_position + Vector3(0, 2.5, 0), "Casting Town Portal...", Color(0.3, 0.5, 1.0))


func _cancel_town_portal_cast() -> void:
	if _tp_casting:
		_tp_casting = false
		_tp_cast_timer = 0.0
		if _is_server_auth:
			_server_tp_cast_cancel.rpc_id(1)


func _tick_town_portal_cast(delta: float) -> void:
	if not _tp_casting:
		return
	# Safety: if cast timer somehow goes very negative, force cancel
	if _tp_cast_timer < -2.0:
		_tp_casting = false
		_tp_cast_timer = 0.0
		if _is_server_auth:
			_server_tp_cast_cancel.rpc_id(1)
		return
	_tp_cast_timer -= delta
	if _tp_cast_timer <= 0.0:
		_tp_casting = false
		_tp_cast_timer = 0.0
		_finish_town_portal_cast()


func _finish_town_portal_cast() -> void:
	if _is_server_auth:
		_server_town_portal_intent.rpc_id(1)
	else:
		# LAN mode: open portal locally
		var main_game := _get_main_game()
		if main_game and main_game.has_method("open_town_portal"):
			main_game.open_town_portal(get_multiplayer_authority(), global_position)


func reset_movement_locks() -> void:
	## Safety reset: clear all states that can block movement.
	## Called on teleport / scene transitions.
	_tp_casting = false
	_tp_cast_timer = 0.0
	is_attacking = false
	_left_mouse_held = false


@rpc("any_peer", "call_remote", "reliable")
func _server_town_portal_intent() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	# Clear cast lock on server so movement is unblocked
	_tp_casting = false
	var main_game := _get_main_game()
	if main_game and main_game.has_method("open_town_portal"):
		main_game.open_town_portal(sender, global_position)


@rpc("any_peer", "call_remote", "reliable")
func _server_tp_cast_start() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	_tp_casting = true
	is_moving = false
	is_attacking = false
	move_target = global_position


@rpc("any_peer", "call_remote", "reliable")
func _server_tp_cast_cancel() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	_tp_casting = false


func _get_main_game() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("open_town_portal"):
			return node
		node = node.get_parent()
	return null


# =========================================================================
# Enemy ability effects on the player
# =========================================================================

@rpc("any_peer", "call_local", "reliable")
func apply_speed_modifier(speed_mult: float, duration: float) -> void:
	_speed_mod = speed_mult
	# Determine debuff name/color from the multiplier
	var debuff_id := "slow"
	var debuff_name := "Slowed"
	var debuff_color := Color(0.3, 0.6, 1.0)  # Blue = frost
	if speed_mult <= 0.45:
		debuff_id = "web"
		debuff_name = "Webbed"
		debuff_color = Color(0.6, 0.7, 0.5)  # Green-gray = web
	_add_debuff(debuff_id, debuff_name, duration, debuff_color)


@rpc("authority", "call_local", "reliable")
func apply_knockback_force(direction: Vector3, force: float) -> void:
	_knockback_vel = direction * force


func _add_debuff(id: String, debuff_name: String, duration: float, color: Color) -> void:
	# Replace existing debuff with same id (refresh duration)
	for d in active_debuffs:
		if d["id"] == id:
			d["remaining"] = duration
			d["duration"] = duration
			return
	active_debuffs.append({
		"id": id,
		"name": debuff_name,
		"remaining": duration,
		"duration": duration,
		"color": color,
	})


func _tick_debuffs(delta: float) -> void:
	var i := active_debuffs.size() - 1
	while i >= 0:
		active_debuffs[i]["remaining"] -= delta
		if active_debuffs[i]["remaining"] <= 0.0:
			var id: String = active_debuffs[i]["id"]
			active_debuffs.remove_at(i)
			# Reset effects when debuff expires
			if id == "slow" or id == "web":
				# Only reset if no other slow is still active
				var still_slowed := false
				for d in active_debuffs:
					if d["id"] == "slow" or d["id"] == "web":
						still_slowed = true
						break
				if not still_slowed:
					_speed_mod = 1.0
		i -= 1


# =========================================================================
# Player buff system (from active skills)
# =========================================================================

## active_buffs uses same format as active_debuffs for HUD display
## {id, name, remaining, duration, color}
var active_buffs: Array[Dictionary] = []


func add_buff(id: String, buff_name: String, duration: float, color: Color) -> void:
	for b in active_buffs:
		if b["id"] == id:
			b["remaining"] = duration
			b["duration"] = duration
			return
	active_buffs.append({
		"id": id,
		"name": buff_name,
		"remaining": duration,
		"duration": duration,
		"color": color,
	})


func _tick_buffs(delta: float) -> void:
	var i := active_buffs.size() - 1
	while i >= 0:
		active_buffs[i]["remaining"] -= delta
		if active_buffs[i]["remaining"] <= 0.0:
			var id: String = active_buffs[i]["id"]
			active_buffs.remove_at(i)
			_on_buff_expired(id)
		i -= 1


func _on_buff_expired(id: String) -> void:
	match id:
		"shield_wall":
			_buff_invulnerable = false
		"war_cry":
			_buff_damage_mult = maxf(_buff_damage_mult - 0.3, 0.0)
		"berserker_rage":
			_buff_damage_mult = maxf(_buff_damage_mult - 0.5, 0.0)
		"ice_barrier":
			_buff_absorb = 0.0
		"mana_shield":
			_buff_mana_shield = false
		"vanish":
			_buff_invisible = false
			_set_visibility.rpc(true)
		"poison_blade":
			pass  # Handled per-attack
		"death_mark":
			pass  # Handled on target


@rpc("authority", "call_local", "reliable")
func _set_visibility(visible_flag: bool) -> void:
	if model:
		for child in model.find_children("*", "MeshInstance3D", true, false):
			child.visible = visible_flag
