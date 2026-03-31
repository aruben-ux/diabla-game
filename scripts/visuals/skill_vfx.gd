extends Node3D

## Manages skill visual effects using GPUParticles3D.
## Attach to the player; call trigger_*() methods when skills fire.

# Pre-built particle systems (reusable one-shots)
var _particles: Dictionary = {}  # id → GPUParticles3D


func _ready() -> void:
	# ── Warrior ──
	_register("cleave", _create_ring_particles(Color.LIGHT_GRAY, 3.0, 35))
	_register("whirlwind", _create_ring_particles(Color.LIGHT_BLUE, 4.0, 50))
	_register("shield_wall", _create_rise_particles(Color(0.7, 0.7, 0.8), 1.8, 25))
	_register("ground_slam", _create_ring_particles(Color(0.6, 0.4, 0.2), 5.0, 60))
	_register("war_cry", _create_ring_particles(Color(1.0, 0.8, 0.2), 6.0, 40))
	_register("charge", _create_burst_particles(Color.YELLOW, 1.5, 30))
	_register("berserker_rage", _create_rise_particles(Color(0.9, 0.2, 0.1), 2.5, 35))

	# ── Mage ──
	_register("fireball", _create_burst_particles(Color.ORANGE_RED, 1.5, 40))
	_register("fire_wall", _create_ring_particles(Color.ORANGE, 3.0, 45))
	_register("meteor", _create_burst_particles(Color(1.0, 0.4, 0.0), 3.0, 70))
	_register("frost_nova", _create_burst_particles(Color.CYAN, 2.5, 50))
	_register("ice_barrier", _create_rise_particles(Color(0.4, 0.7, 1.0), 1.5, 20))
	_register("blizzard", _create_burst_particles(Color(0.6, 0.8, 1.0), 4.0, 60))
	_register("heal", _create_rise_particles(Color.GREEN, 2.0, 30))
	_register("teleport", _create_burst_particles(Color(0.5, 0.3, 0.9), 1.0, 25))
	_register("arcane_missiles", _create_burst_particles(Color(0.6, 0.3, 1.0), 1.5, 35))
	_register("mana_shield", _create_rise_particles(Color(0.5, 0.3, 0.9), 1.8, 20))

	# ── Rogue ──
	_register("backstab", _create_burst_particles(Color(0.8, 0.1, 0.1), 1.0, 20))
	_register("poison_blade", _create_rise_particles(Color(0.3, 0.8, 0.2), 1.5, 20))
	_register("death_mark", _create_burst_particles(Color(0.6, 0.0, 0.0), 1.5, 25))
	_register("shadow_step", _create_burst_particles(Color(0.3, 0.3, 0.4), 1.0, 25))
	_register("vanish", _create_rise_particles(Color(0.3, 0.3, 0.4), 1.0, 15))
	_register("smoke_bomb", _create_burst_particles(Color(0.4, 0.4, 0.4), 3.0, 50))
	_register("spike_trap", _create_ring_particles(Color(0.7, 0.5, 0.2), 3.0, 30))
	_register("fan_of_knives", _create_ring_particles(Color.SILVER, 4.0, 45))
	_register("rain_of_arrows", _create_burst_particles(Color(0.6, 0.5, 0.3), 4.0, 55))


func _register(id: String, p: GPUParticles3D) -> void:
	p.name = id + "_vfx"
	add_child(p)
	_particles[id] = p


## Generic trigger — plays the VFX for the given skill at the given position.
func trigger(skill_id: String, pos: Vector3) -> void:
	var p: GPUParticles3D = _particles.get(skill_id) as GPUParticles3D
	if not p:
		return
	p.global_position = pos + Vector3(0, 0.5, 0)
	p.restart()
	p.emitting = true


## Convenience wrappers kept for back-compat
func trigger_fireball(target_pos: Vector3) -> void:
	trigger("fireball", target_pos)

func trigger_heal() -> void:
	trigger("heal", global_position)

func trigger_whirlwind() -> void:
	trigger("whirlwind", global_position)

func trigger_frost_nova() -> void:
	trigger("frost_nova", global_position)


func _create_burst_particles(color: Color, radius: float, count: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.6
	particles.explosiveness = 0.9

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = radius * 2.0
	mat.initial_velocity_max = radius * 3.0
	mat.gravity = Vector3(0, -2, 0)
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.1
	mat.scale_max = 0.25
	mat.color = color
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	var draw_pass := mesh
	particles.draw_pass_1 = draw_pass

	# Emissive material for the particle mesh
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.0
	particles.material_override = mesh_mat

	return particles


func _create_rise_particles(color: Color, height: float, count: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 1.0
	particles.explosiveness = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = height
	mat.initial_velocity_max = height * 1.5
	mat.gravity = Vector3(0, 0.5, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	mat.color = color
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	particles.draw_pass_1 = mesh

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 1.5
	particles.material_override = mesh_mat

	return particles


func _create_ring_particles(color: Color, radius: float, count: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.8
	particles.explosiveness = 0.8

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = radius * 1.5
	mat.initial_velocity_max = radius * 2.0
	mat.gravity = Vector3(0, 1, 0)
	mat.damping_min = 3.0
	mat.damping_max = 5.0
	mat.scale_min = 0.08
	mat.scale_max = 0.2
	mat.color = color
	# Flatten to horizontal ring
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_height = 0.3
	mat.emission_ring_radius = 0.5
	mat.emission_ring_inner_radius = 0.1
	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	particles.draw_pass_1 = mesh

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.0
	particles.material_override = mesh_mat

	return particles
