extends Node3D

## Manages skill visual effects using GPUParticles3D.
## Attach to the player; call trigger_*() methods when skills fire.

var _fireball_particles: GPUParticles3D
var _heal_particles: GPUParticles3D
var _whirlwind_particles: GPUParticles3D
var _frost_particles: GPUParticles3D


func _ready() -> void:
	_fireball_particles = _create_burst_particles(Color.ORANGE_RED, 1.5, 40)
	_fireball_particles.name = "FireballVFX"
	add_child(_fireball_particles)

	_heal_particles = _create_rise_particles(Color.GREEN, 2.0, 30)
	_heal_particles.name = "HealVFX"
	add_child(_heal_particles)

	_whirlwind_particles = _create_ring_particles(Color.LIGHT_BLUE, 4.0, 50)
	_whirlwind_particles.name = "WhirlwindVFX"
	add_child(_whirlwind_particles)

	_frost_particles = _create_burst_particles(Color.CYAN, 2.5, 50)
	_frost_particles.name = "FrostVFX"
	add_child(_frost_particles)


func trigger_fireball(target_pos: Vector3) -> void:
	_fireball_particles.global_position = target_pos + Vector3(0, 0.5, 0)
	_fireball_particles.restart()
	_fireball_particles.emitting = true


func trigger_heal() -> void:
	_heal_particles.position = Vector3(0, 0.5, 0)
	_heal_particles.restart()
	_heal_particles.emitting = true


func trigger_whirlwind() -> void:
	_whirlwind_particles.position = Vector3(0, 0.8, 0)
	_whirlwind_particles.restart()
	_whirlwind_particles.emitting = true


func trigger_frost_nova() -> void:
	_frost_particles.position = Vector3(0, 0.5, 0)
	_frost_particles.restart()
	_frost_particles.emitting = true


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
