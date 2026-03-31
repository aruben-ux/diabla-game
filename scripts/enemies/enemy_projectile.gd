extends Area3D

## Enemy projectile that travels toward a target position.
## On contact with a player, deals damage. Despawns after timeout or hit.

const DESPAWN_TIME := 4.0

var _direction := Vector3.ZERO
var _speed := 12.0
var _damage := 0.0
var _alive := true
var _lifetime := 0.0
var _projectile_color := Color(0.8, 0.3, 0.1)


func setup(from_pos: Vector3, target_pos: Vector3, damage: float, speed: float = 12.0, color: Color = Color(0.8, 0.3, 0.1)) -> void:
	global_position = from_pos + Vector3(0, 1.2, 0)  # Launch from chest height
	_damage = damage
	_speed = speed
	_projectile_color = color
	var dir := target_pos - from_pos
	dir.y = 0.0
	_direction = dir.normalized()
	# Face travel direction
	rotation.y = atan2(_direction.x, _direction.z)


func _ready() -> void:
	# Collision: detect players (layer 2)
	collision_layer = 0
	collision_mask = 2  # Players
	monitoring = true
	monitorable = false

	# Collision shape — small sphere
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)

	# Visual — glowing orb
	var orb := MeshInstance3D.new()
	orb.name = "Orb"
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	orb.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _projectile_color
	mat.emission_enabled = true
	mat.emission = _projectile_color
	mat.emission_energy_multiplier = 3.0
	orb.material_override = mat
	add_child(orb)

	# Trail particles
	var trail := GPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 8
	trail.lifetime = 0.3
	trail.explosiveness = 0.0
	trail.randomness = 0.3
	trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 0, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.2
	pmat.initial_velocity_max = 0.5
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.04
	pmat.scale_max = 0.08
	var grad := Gradient.new()
	grad.set_color(0, Color(_projectile_color, 0.8))
	grad.set_color(1, Color(_projectile_color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pmat.color_ramp = ramp
	trail.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = _projectile_color
	qmat.emission_enabled = true
	qmat.emission = _projectile_color
	qmat.emission_energy_multiplier = 2.0
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = qmat
	trail.draw_pass_1 = quad
	add_child(trail)

	# Point light
	var light := OmniLight3D.new()
	light.omni_range = 3.0
	light.light_energy = 0.6
	light.light_color = _projectile_color
	light.shadow_enabled = false
	add_child(light)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_lifetime += delta
	if _lifetime >= DESPAWN_TIME:
		_despawn()
		return
	global_position += _direction * _speed * delta


func _on_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if not multiplayer.is_server():
		return
	if body.is_in_group("players") and body.has_method("receive_damage"):
		body.receive_damage.rpc(_damage)
		_sync_hit.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_hit() -> void:
	_alive = false
	_spawn_impact()
	queue_free()


func _despawn() -> void:
	_alive = false
	queue_free()


func _spawn_impact() -> void:
	# Brief flash at impact point
	var burst := GPUParticles3D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 10
	burst.lifetime = 0.25
	burst.explosiveness = 0.95

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 120.0
	pmat.initial_velocity_min = 2.0
	pmat.initial_velocity_max = 4.0
	pmat.gravity = Vector3(0, -5, 0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.08
	pmat.color = _projectile_color
	burst.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = _projectile_color
	qmat.emission_enabled = true
	qmat.emission = _projectile_color
	qmat.emission_energy_multiplier = 2.0
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = qmat
	burst.draw_pass_1 = quad

	# Parent to level root so it doesn't die with projectile
	var level_root := get_tree().current_scene
	if level_root:
		burst.global_position = global_position
		level_root.add_child(burst)
		get_tree().create_timer(0.5).timeout.connect(burst.queue_free)
