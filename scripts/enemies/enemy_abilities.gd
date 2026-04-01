class_name EnemyAbilities
## Static utility handling all special enemy abilities.
## Called from enemy.gd at various hook points (attack, take_damage, die, tick).

# -------------------------------------------------------------------------
# Ability assignment
# -------------------------------------------------------------------------

static func get_abilities(enemy_type: Enemy.EnemyType) -> Array[StringName]:
	match enemy_type:
		Enemy.EnemyType.GRUNT:
			return [&"rally_cry"]
		Enemy.EnemyType.MAGE:
			return [&"frost_bolt"]
		Enemy.EnemyType.BRUTE:
			return [&"ground_slam"]
		Enemy.EnemyType.SKELETON:
			return [&"reassemble"]
		Enemy.EnemyType.SPIDER:
			return [&"web_spit"]
		Enemy.EnemyType.GHOST:
			return [&"phase_shift"]
		Enemy.EnemyType.ARCHER:
			return [&"multi_shot"]
		Enemy.EnemyType.SHAMAN:
			return [&"heal_aura"]
		Enemy.EnemyType.GOLEM:
			return [&"fortify"]
		Enemy.EnemyType.SCARAB:
			return [&"swarm_frenzy"]
		Enemy.EnemyType.WRAITH:
			return [&"life_drain"]
		Enemy.EnemyType.NECROMANCER:
			return [&"raise_dead"]
		Enemy.EnemyType.DEMON:
			return [&"enrage"]
		Enemy.EnemyType.BOSS_GOLEM:
			return [&"ground_slam", &"fortify", &"rock_shower"]
		Enemy.EnemyType.BOSS_DEMON:
			return [&"enrage", &"fire_nova", &"summon_imps"]
		Enemy.EnemyType.BOSS_DRAGON:
			return [&"fire_breath", &"tail_swipe", &"wing_gust"]
		_:
			return []


# -------------------------------------------------------------------------
# Hook: on_attack — called when the enemy attacks its target
# Returns true if the ability handled the attack (skip normal attack)
# -------------------------------------------------------------------------

static func on_attack(enemy: Enemy, abilities: Array[StringName]) -> bool:
	for ab in abilities:
		match ab:
			&"ground_slam":
				if _try_ground_slam(enemy):
					return true
			&"multi_shot":
				if _try_multi_shot(enemy):
					return true  # Replaces normal attack this cycle
			&"fire_breath":
				if _try_fire_breath(enemy):
					return true
			&"tail_swipe":
				if _try_tail_swipe(enemy):
					return true
			&"fire_nova":
				if _try_fire_nova(enemy):
					return true
			&"rock_shower":
				if _try_rock_shower(enemy):
					return true
	return false


# -------------------------------------------------------------------------
# Hook: on_hit_player — called after a melee/projectile hits a player
# -------------------------------------------------------------------------

static func on_hit_player(enemy: Enemy, player: Node3D, damage: float, abilities: Array[StringName]) -> void:
	for ab in abilities:
		match ab:
			&"frost_bolt":
				_apply_slow(player, 0.5, 2.0)  # 50% speed for 2s
			&"web_spit":
				_apply_slow(player, 0.4, 2.5)  # 40% speed for 2.5s
			&"life_drain":
				enemy.health = minf(enemy.health + damage * 0.3, enemy.max_health)
				enemy._sync_health.rpc(enemy.health)
				_spawn_drain_vfx.call_deferred(enemy)
			&"rally_cry":
				_do_rally_cry(enemy)


# -------------------------------------------------------------------------
# Hook: on_take_damage — called when enemy takes damage
# Returns modified damage (can reduce it)
# -------------------------------------------------------------------------

static func on_take_damage(enemy: Enemy, amount: float, abilities: Array[StringName]) -> float:
	var final := amount
	for ab in abilities:
		match ab:
			&"fortify":
				# 50% damage reduction while stationary (attack state)
				if enemy.state == Enemy.State.ATTACK:
					final *= 0.5
					_sync_fortify_flash.call_deferred(enemy)
	return final


# -------------------------------------------------------------------------
# Hook: on_die — called on server when enemy dies. Returns true to cancel death.
# -------------------------------------------------------------------------

static func on_die(enemy: Enemy, abilities: Array[StringName]) -> bool:
	for ab in abilities:
		match ab:
			&"reassemble":
				if not enemy.get_meta(&"has_reassembled", false) and randf() < 0.3:
					enemy.set_meta(&"has_reassembled", true)
					enemy.health = enemy.max_health * 0.5
					enemy.state = Enemy.State.HIT
					enemy.hit_flash_timer = 0.5
					enemy._sync_health.rpc(enemy.health)
					_sync_reassemble_vfx.call_deferred(enemy)
					return true  # Cancel death
			&"swarm_frenzy":
				_do_swarm_frenzy(enemy)
	return false


# -------------------------------------------------------------------------
# Hook: on_tick — called every server frame (in _physics_process)
# -------------------------------------------------------------------------

static func on_tick(enemy: Enemy, delta: float, abilities: Array[StringName]) -> void:
	for ab in abilities:
		match ab:
			&"heal_aura":
				_tick_heal_aura(enemy, delta)
			&"phase_shift":
				_tick_phase_shift(enemy, delta)
			&"enrage":
				_tick_enrage(enemy)
			&"raise_dead":
				_tick_raise_dead(enemy, delta)
			&"wing_gust":
				_tick_wing_gust(enemy, delta)
			&"summon_imps":
				_tick_summon_imps(enemy, delta)


# =========================================================================
# Individual ability implementations
# =========================================================================

# --- GRUNT: Rally Cry ---
# On hitting a player, boost nearby grunts' speed for 3 seconds
static func _do_rally_cry(enemy: Enemy) -> void:
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not is_instance_valid(other):
			continue
		if not (other is Enemy):
			continue
		var e := other as Enemy
		if e.state == Enemy.State.DEAD:
			continue
		if e.global_position.distance_to(enemy.global_position) > 8.0:
			continue
		e.move_speed *= 1.3
		# Reset after 3s
		var e_id := e.get_instance_id()
		Engine.get_main_loop().create_timer(3.0).timeout.connect(func() -> void:
			var ref = instance_from_id(e_id)
			if ref:
				ref.move_speed /= 1.3
		)


# --- MAGE: Frost Bolt / SPIDER: Web Spit ---
# Apply a speed slow to the player
static func _apply_slow(player: Node3D, speed_mult: float, duration: float) -> void:
	if not player.has_method("apply_speed_modifier"):
		return
	player.apply_speed_modifier.rpc(speed_mult, duration)


# --- BRUTE / BOSS_GOLEM: Ground Slam ---
# AoE stomp — damages and knocks back all players in range
static func _try_ground_slam(enemy: Enemy) -> bool:
	var timer_key := &"_slam_cooldown"
	var cd: float = enemy.get_meta(timer_key, 0.0)
	if cd > 0.0:
		return false
	# Only use slam 40% of the time it's off cooldown
	if randf() > 0.4:
		return false
	enemy.set_meta(timer_key, 5.0)  # 5s cooldown

	# Play anim
	if enemy.model.has_method("play_attack_anim"):
		enemy.model.play_attack_anim()
	enemy._sync_attack_anim.rpc()

	var radius := 4.0
	var slam_damage := enemy.attack_damage * 1.5
	for player in enemy.get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		var dist: float = enemy.global_position.distance_to(player.global_position)
		if dist <= radius:
			if player.has_method("receive_damage"):
				player.receive_damage.rpc(slam_damage)
			# Knockback away from slam center
			var kb_dir: Vector3 = (player.global_position - enemy.global_position).normalized()
			if player.has_method("apply_knockback_force"):
				player.apply_knockback_force.rpc(kb_dir, 4.0)

	# VFX: spawn ring on all peers
	_sync_aoe_ring.call_deferred(enemy, radius, Color(0.6, 0.4, 0.15), 0.4)
	return true


# --- ARCHER: Multi Shot ---
# Fire 3 arrows in a fan
static func _try_multi_shot(enemy: Enemy) -> bool:
	var timer_key := &"_multi_cd"
	var cd: float = enemy.get_meta(timer_key, 0.0)
	if cd > 0.0:
		return false
	if randf() > 0.35:
		return false
	enemy.set_meta(timer_key, 4.0)

	if not is_instance_valid(enemy.target):
		return false

	enemy._sync_attack_anim.rpc()

	var to_target := (enemy.target.global_position - enemy.global_position).normalized()
	to_target.y = 0.0
	var base_angle := atan2(to_target.x, to_target.z)
	var spread := 0.3  # ~17 degrees each side

	for i in range(3):
		var angle := base_angle + (float(i) - 1.0) * spread
		var dir := Vector3(sin(angle), 0, cos(angle))
		var target_pos := enemy.global_position + dir * 12.0
		Enemy._projectile_counter += 1
		var proj_name := "EProj_%d" % Enemy._projectile_counter
		enemy._sync_fire_projectile.rpc(
			proj_name, enemy.global_position, target_pos,
			enemy.attack_damage * 0.7, 14.0, Color(0.7, 0.5, 0.2)
		)
	return true


# --- GHOST: Phase Shift ---
# Periodically become semi-transparent and move faster, then reappear
static func _tick_phase_shift(enemy: Enemy, delta: float) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var phase_cd_key := &"_phase_cd"
	var phasing_key := &"_phasing"

	var cd: float = enemy.get_meta(phase_cd_key, 6.0)
	cd -= delta
	enemy.set_meta(phase_cd_key, cd)

	if enemy.get_meta(phasing_key, false):
		# Currently phasing — count down
		var pt: float = enemy.get_meta(&"_phase_timer", 0.0) - delta
		enemy.set_meta(&"_phase_timer", pt)
		if pt <= 0.0:
			# End phase
			enemy.set_meta(phasing_key, false)
			enemy.set_meta(phase_cd_key, 8.0)
			enemy.collision_layer = 4  # Restore enemy collision
			_sync_phase.call_deferred(enemy, false)
		return

	if cd <= 0.0 and enemy.state == Enemy.State.CHASE:
		enemy.set_meta(phasing_key, true)
		enemy.set_meta(&"_phase_timer", 1.5)
		enemy.move_speed *= 2.0
		enemy.collision_layer = 0  # Can't be hit while phasing
		var eid := enemy.get_instance_id()
		Engine.get_main_loop().create_timer(1.5).timeout.connect(func() -> void:
			var ref = instance_from_id(eid)
			if ref:
				ref.move_speed /= 2.0
		)
		_sync_phase.call_deferred(enemy, true)


# --- SHAMAN: Heal Aura ---
# Periodically heal nearby enemies by 5% of their max HP
static func _tick_heal_aura(enemy: Enemy, delta: float) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var cd_key := &"_heal_cd"
	var cd: float = enemy.get_meta(cd_key, 3.0)
	cd -= delta
	enemy.set_meta(cd_key, cd)
	if cd > 0.0:
		return
	enemy.set_meta(cd_key, 3.0)

	var heal_range := 10.0
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(other) or not (other is Enemy):
			continue
		var e := other as Enemy
		if e.state == Enemy.State.DEAD or e.health >= e.max_health:
			continue
		if e.global_position.distance_to(enemy.global_position) > heal_range:
			continue
		e.health = minf(e.health + e.max_health * 0.05, e.max_health)
		e._sync_health.rpc(e.health)

	# Green pulse VFX
	_sync_aoe_ring.call_deferred(enemy, heal_range, Color(0.2, 0.9, 0.3, 0.5), 0.6)


# --- SCARAB: Swarm Frenzy ---
# When a scarab dies, nearby scarabs get a speed + damage boost
static func _do_swarm_frenzy(enemy: Enemy) -> void:
	for other in enemy.get_tree().get_nodes_in_group("enemies"):
		if other == enemy or not is_instance_valid(other):
			continue
		if not (other is Enemy):
			continue
		var e := other as Enemy
		if e.state == Enemy.State.DEAD:
			continue
		if e.global_position.distance_to(enemy.global_position) > 8.0:
			continue
		e.move_speed *= 1.4
		e.attack_damage *= 1.2
		var e_id2 := e.get_instance_id()
		Engine.get_main_loop().create_timer(5.0).timeout.connect(func() -> void:
			var ref = instance_from_id(e_id2)
			if ref:
				ref.move_speed /= 1.4
				ref.attack_damage /= 1.2
		)


# --- NECROMANCER: Raise Dead ---
# Periodically summon a skeleton minion
static func _tick_raise_dead(enemy: Enemy, delta: float) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var cd_key := &"_raise_cd"
	var cd: float = enemy.get_meta(cd_key, 8.0)
	cd -= delta
	enemy.set_meta(cd_key, cd)
	if cd > 0.0:
		return
	enemy.set_meta(cd_key, 12.0)

	# Cap summoned minions
	var summon_count: int = enemy.get_meta(&"_summon_count", 0)
	if summon_count >= 3:
		return

	enemy.set_meta(&"_summon_count", summon_count + 1)
	var spawner := enemy.get_parent()
	if not spawner or not spawner.has_method("_create_enemy"):
		return
	Enemy._projectile_counter += 1
	var ename := "Summon_%d" % Enemy._projectile_counter
	var spos := enemy.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	# Spawn a skeleton via RPC
	spawner._rpc_respawn_enemy.rpc(ename, 0, spos, Enemy.EnemyType.SKELETON)

	# Purple raise VFX
	_sync_aoe_ring.call_deferred(enemy, 2.0, Color(0.6, 0.1, 0.7), 0.5)


# --- DEMON: Enrage ---
# Below 30% HP, boost attack speed and damage
static func _tick_enrage(enemy: Enemy) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var enraged: bool = enemy.get_meta(&"_enraged", false)
	if enraged:
		return
	if enemy.health <= enemy.max_health * 0.3:
		enemy.set_meta(&"_enraged", true)
		enemy.attack_cooldown *= 0.5
		enemy.attack_damage *= 1.5
		enemy.move_speed *= 1.3
		_sync_enrage_vfx.call_deferred(enemy)


# --- BOSS_GOLEM: Rock Shower ---
# Rain boulders on random positions near the player
static func _try_rock_shower(enemy: Enemy) -> bool:
	var cd_key := &"_shower_cd"
	var cd: float = enemy.get_meta(cd_key, 0.0)
	if cd > 0.0:
		return false
	if randf() > 0.3:
		return false
	enemy.set_meta(cd_key, 8.0)

	if not is_instance_valid(enemy.target):
		return false

	var center := enemy.target.global_position
	for i in range(5):
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		var pos := center + offset
		_spawn_boulder_impact.call_deferred(enemy, pos, enemy.attack_damage * 0.6)
	return true


# --- BOSS_DEMON: Fire Nova ---
# AoE fire burst around the boss
static func _try_fire_nova(enemy: Enemy) -> bool:
	var cd_key := &"_nova_cd"
	var cd: float = enemy.get_meta(cd_key, 0.0)
	if cd > 0.0:
		return false
	if randf() > 0.3:
		return false
	enemy.set_meta(cd_key, 10.0)

	var radius := 6.0
	for player in enemy.get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		if enemy.global_position.distance_to(player.global_position) <= radius:
			if player.has_method("receive_damage"):
				player.receive_damage.rpc(enemy.attack_damage * 1.2)
			if player.has_method("apply_knockback_force"):
				var dir: Vector3 = (player.global_position - enemy.global_position).normalized()
				player.apply_knockback_force.rpc(dir, 5.0)

	_sync_aoe_ring.call_deferred(enemy, radius, Color(1.0, 0.3, 0.0), 0.5)
	return true


# --- BOSS_DEMON: Summon Imps ---
static func _tick_summon_imps(enemy: Enemy, delta: float) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var cd_key := &"_imp_cd"
	var cd: float = enemy.get_meta(cd_key, 15.0)
	cd -= delta
	enemy.set_meta(cd_key, cd)
	if cd > 0.0:
		return
	enemy.set_meta(cd_key, 20.0)

	var summon_count: int = enemy.get_meta(&"_imp_count", 0)
	if summon_count >= 4:
		return
	enemy.set_meta(&"_imp_count", summon_count + 2)

	var spawner := enemy.get_parent()
	if not spawner or not spawner.has_method("_create_enemy"):
		return
	for i in range(2):
		Enemy._projectile_counter += 1
		var ename := "Imp_%d" % Enemy._projectile_counter
		var spos := enemy.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		spawner._rpc_respawn_enemy.rpc(ename, 0, spos, Enemy.EnemyType.GRUNT)

	_sync_aoe_ring.call_deferred(enemy, 3.0, Color(0.8, 0.2, 0.0), 0.5)


# --- BOSS_DRAGON: Fire Breath ---
# Cone AoE fire in front of the dragon
static func _try_fire_breath(enemy: Enemy) -> bool:
	var cd_key := &"_breath_cd"
	var cd: float = enemy.get_meta(cd_key, 0.0)
	if cd > 0.0:
		return false
	if randf() > 0.4:
		return false
	enemy.set_meta(cd_key, 6.0)

	if not is_instance_valid(enemy.target):
		return false

	var forward := Vector3(sin(enemy.model.rotation.y), 0, cos(enemy.model.rotation.y)).normalized()
	var breath_range := 8.0
	var cone_angle := 0.6  # ~34 degrees

	for player in enemy.get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		var to_player: Vector3 = player.global_position - enemy.global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist > breath_range or dist < 0.1:
			continue
		if forward.angle_to(to_player.normalized()) <= cone_angle:
			if player.has_method("receive_damage"):
				player.receive_damage.rpc(enemy.attack_damage * 0.8)

	# Fire cone VFX
	_sync_breath_vfx.call_deferred(enemy, forward, breath_range)
	return true


# --- BOSS_DRAGON: Tail Swipe ---
# AoE behind the dragon
static func _try_tail_swipe(enemy: Enemy) -> bool:
	var cd_key := &"_tail_cd"
	var cd: float = enemy.get_meta(cd_key, 0.0)
	if cd > 0.0:
		return false
	# Only use when a player is behind
	if not is_instance_valid(enemy.target):
		return false
	var forward := Vector3(sin(enemy.model.rotation.y), 0, cos(enemy.model.rotation.y)).normalized()
	var to_target := (enemy.target.global_position - enemy.global_position)
	to_target.y = 0.0
	# Only tail swipe if someone is behind or to the side (angle > 90 deg)
	if forward.angle_to(to_target.normalized()) < PI * 0.5:
		return false
	enemy.set_meta(cd_key, 5.0)

	var radius := 5.0
	for player in enemy.get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		var to_p: Vector3 = player.global_position - enemy.global_position
		to_p.y = 0.0
		if to_p.length() > radius:
			continue
		if forward.angle_to(to_p.normalized()) < PI * 0.4:
			continue  # Skip players in front
		if player.has_method("receive_damage"):
			player.receive_damage.rpc(enemy.attack_damage * 0.6)
		if player.has_method("apply_knockback_force"):
			player.apply_knockback_force.rpc(to_p.normalized(), 6.0)

	_sync_aoe_ring.call_deferred(enemy, radius, Color(0.4, 0.35, 0.25), 0.3)
	return true


# --- BOSS_DRAGON: Wing Gust ---
# Periodically knock back all nearby players
static func _tick_wing_gust(enemy: Enemy, delta: float) -> void:
	if enemy.state == Enemy.State.DEAD:
		return
	var cd_key := &"_gust_cd"
	var cd: float = enemy.get_meta(cd_key, 12.0)
	cd -= delta
	enemy.set_meta(cd_key, cd)
	if cd > 0.0:
		return
	enemy.set_meta(cd_key, 15.0)

	var radius := 7.0
	for player in enemy.get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player):
			continue
		var dist: float = enemy.global_position.distance_to(player.global_position)
		if dist > radius:
			continue
		if player.has_method("apply_knockback_force"):
			var dir: Vector3 = (player.global_position - enemy.global_position).normalized()
			player.apply_knockback_force.rpc(dir, 8.0)

	_sync_aoe_ring.call_deferred(enemy, radius, Color(0.7, 0.8, 0.9, 0.6), 0.4)


# =========================================================================
# Cooldown ticking — decrements all meta-based cooldowns
# =========================================================================

static func tick_cooldowns(enemy: Enemy, delta: float) -> void:
	for key: StringName in [&"_slam_cooldown", &"_multi_cd", &"_shower_cd", &"_nova_cd", &"_breath_cd", &"_tail_cd"]:
		var v: float = enemy.get_meta(key, 0.0)
		if v > 0.0:
			enemy.set_meta(key, v - delta)


# =========================================================================
# VFX helpers (called via call_deferred so they run on the main thread)
# =========================================================================

static func _sync_aoe_ring(enemy: Enemy, radius: float, color: Color, duration: float) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_aoe_ring.rpc(enemy.global_position, radius, color, duration)


static func _sync_phase(enemy: Enemy, phasing: bool) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_phase_visual.rpc(phasing)


static func _sync_fortify_flash(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_fortify_flash.rpc()


static func _sync_enrage_vfx(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_enrage_vfx.rpc()


static func _sync_reassemble_vfx(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_reassemble_vfx.rpc()


static func _spawn_drain_vfx(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_drain_vfx.rpc()


static func _sync_breath_vfx(enemy: Enemy, forward: Vector3, breath_range: float) -> void:
	if not is_instance_valid(enemy):
		return
	enemy._rpc_breath_vfx.rpc(enemy.global_position, forward, breath_range)


static func _spawn_boulder_impact(enemy: Enemy, pos: Vector3, damage: float) -> void:
	if not is_instance_valid(enemy):
		return
	# Delayed impact — boulder falls after 0.6s
	var eid2 := enemy.get_instance_id()
	Engine.get_main_loop().create_timer(0.6).timeout.connect(func() -> void:
		var ref = instance_from_id(eid2)
		if not ref:
			return
		# Damage check
		for player in ref.get_tree().get_nodes_in_group("players"):
			if not is_instance_valid(player):
				continue
			if player.global_position.distance_to(pos) <= 1.5:
				if player.has_method("receive_damage"):
					player.receive_damage.rpc(damage)
		# VFX for all
		ref._rpc_boulder_impact.rpc(pos)
	)
	# Warning circle immediately
	enemy._rpc_boulder_warning.rpc(pos)
