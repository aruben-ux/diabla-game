extends Node3D

## Builds a humanoid figure from primitives at runtime with toon shading.
## Call build() after adding to tree.

var toon_shader: Shader
var right_arm_pivot: Node3D

func _ready() -> void:
	toon_shader = preload("res://assets/shaders/toon.gdshader")


func build_player_model() -> void:
	_clear()

	var body_color := Color(0.2, 0.45, 0.85)
	var skin_color := Color(0.85, 0.7, 0.6)
	var armor_color := Color(0.35, 0.55, 0.9)
	var boot_color := Color(0.3, 0.25, 0.2)

	# Legs
	_add_part("LeftLeg", CylinderMesh.new(), Vector3(-0.15, 0.3, 0), Vector3(0.12, 0.3, 0.12), boot_color)
	_add_part("RightLeg", CylinderMesh.new(), Vector3(0.15, 0.3, 0), Vector3(0.12, 0.3, 0.12), boot_color)

	# Torso
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.85, 0), Vector3(0.5, 0.5, 0.3), armor_color)

	# Shoulder pads
	_add_part("LeftShoulder", SphereMesh.new(), Vector3(-0.35, 1.1, 0), Vector3(0.2, 0.15, 0.2), armor_color)
	_add_part("RightShoulder", SphereMesh.new(), Vector3(0.35, 1.1, 0), Vector3(0.2, 0.15, 0.2), armor_color)

	# Right arm pivot (shoulder) — holds arm + sword
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.35, 1.05, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.08, 0.25, 0.08), skin_color))
	right_arm_pivot.add_child(_create_part("Sword", BoxMesh.new(), Vector3(0.02, -0.68, 0), Vector3(0.06, 0.55, 0.04), Color(0.8, 0.8, 0.85)))
	right_arm_pivot.add_child(_create_part("SwordGuard", BoxMesh.new(), Vector3(0.02, -0.43, 0), Vector3(0.18, 0.04, 0.06), Color(0.6, 0.5, 0.2)))

	# Left arm pivot — holds arm + shield
	var left_pivot := Node3D.new()
	left_pivot.name = "LeftArmPivot"
	left_pivot.position = Vector3(-0.35, 1.05, 0)
	left_pivot.rotation.x = 0.4
	add_child(left_pivot)
	left_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.08, 0.25, 0.08), skin_color))
	left_pivot.add_child(_create_part("Shield", BoxMesh.new(), Vector3(-0.1, -0.22, 0.12), Vector3(0.04, 0.35, 0.3), armor_color))

	# Head
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.35, 0), Vector3(0.22, 0.22, 0.22), skin_color)

	# Helmet
	_add_part("Helmet", SphereMesh.new(), Vector3(0, 1.42, 0), Vector3(0.26, 0.18, 0.26), body_color)

	# Eyes (emissive)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.07, 1.38, 0.18), Vector3(0.04, 0.04, 0.04), Color(0.8, 0.9, 1.0))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.07, 1.38, 0.18), Vector3(0.04, 0.04, 0.04), Color(0.8, 0.9, 1.0))


func build_enemy_grunt() -> void:
	_clear()

	var body_color := Color(0.55, 0.2, 0.15)
	var skin_color := Color(0.45, 0.55, 0.35)

	_add_part("LeftLeg", CylinderMesh.new(), Vector3(-0.15, 0.25, 0), Vector3(0.13, 0.25, 0.13), skin_color)
	_add_part("RightLeg", CylinderMesh.new(), Vector3(0.15, 0.25, 0), Vector3(0.13, 0.25, 0.13), skin_color)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.7, 0), Vector3(0.5, 0.4, 0.35), body_color)
	_add_part("LeftArm", CylinderMesh.new(), Vector3(-0.35, 0.55, 0), Vector3(0.1, 0.25, 0.1), skin_color)

	# Right arm pivot — holds arm + club
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.35, 0.85, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.1, 0.25, 0.1), skin_color))
	right_arm_pivot.add_child(_create_part("Club", CylinderMesh.new(), Vector3(0.02, -0.55, 0), Vector3(0.08, 0.35, 0.08), Color(0.4, 0.3, 0.15)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.05, 0), Vector3(0.2, 0.2, 0.2), skin_color)
	# Angry eyes
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.08, 0.16), Vector3(0.04, 0.04, 0.04), Color(1.0, 0.3, 0.1))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.08, 0.16), Vector3(0.04, 0.04, 0.04), Color(1.0, 0.3, 0.1))


func build_enemy_mage() -> void:
	_clear()

	var robe_color := Color(0.3, 0.1, 0.4)
	var skin_color := Color(0.5, 0.45, 0.55)

	_add_part("Robe", CylinderMesh.new(), Vector3(0, 0.5, 0), Vector3(0.3, 0.5, 0.3), robe_color)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.9, 0), Vector3(0.35, 0.3, 0.25), robe_color)
	_add_part("LeftArm", CylinderMesh.new(), Vector3(-0.25, 0.75, 0), Vector3(0.07, 0.22, 0.07), skin_color)

	# Right arm pivot — holds arm + staff + orb
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.25, 1.0, 0)
	right_arm_pivot.rotation.x = 0.2
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.07, 0.22, 0.07), skin_color))
	right_arm_pivot.add_child(_create_part("Staff", CylinderMesh.new(), Vector3(0.02, -0.4, 0), Vector3(0.04, 0.7, 0.04), Color(0.5, 0.35, 0.2)))
	right_arm_pivot.add_child(_create_emissive_part("StaffOrb", SphereMesh.new(), Vector3(0.02, 0.3, 0), Vector3(0.1, 0.1, 0.1), Color(0.6, 0.2, 1.0)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.25, 0), Vector3(0.18, 0.18, 0.18), skin_color)
	# Pointy hat
	_add_part("Hat", CylinderMesh.new(), Vector3(0, 1.5, 0), Vector3(0.15, 0.2, 0.15), robe_color)
	_add_part("HatBrim", CylinderMesh.new(), Vector3(0, 1.32, 0), Vector3(0.25, 0.02, 0.25), robe_color)
	# Glowing eyes
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.28, 0.14), Vector3(0.035, 0.035, 0.035), Color(0.6, 0.2, 1.0))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.28, 0.14), Vector3(0.035, 0.035, 0.035), Color(0.6, 0.2, 1.0))


func build_enemy_brute() -> void:
	_clear()

	var body_color := Color(0.55, 0.3, 0.2)
	var skin_color := Color(0.5, 0.35, 0.3)

	_add_part("LeftLeg", CylinderMesh.new(), Vector3(-0.2, 0.35, 0), Vector3(0.16, 0.35, 0.16), skin_color)
	_add_part("RightLeg", CylinderMesh.new(), Vector3(0.2, 0.35, 0), Vector3(0.16, 0.35, 0.16), skin_color)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.95, 0), Vector3(0.65, 0.55, 0.4), body_color)
	_add_part("LeftArm", CylinderMesh.new(), Vector3(-0.45, 0.75, 0), Vector3(0.14, 0.35, 0.14), skin_color)

	# Right arm pivot — holds arm + hammer
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.45, 1.15, 0)
	right_arm_pivot.rotation.x = 0.35
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.32, 0), Vector3(0.14, 0.35, 0.14), skin_color))
	right_arm_pivot.add_child(_create_part("HammerHandle", CylinderMesh.new(), Vector3(0.02, -0.65, 0), Vector3(0.06, 0.5, 0.06), Color(0.4, 0.3, 0.15)))
	right_arm_pivot.add_child(_create_part("HammerHead", BoxMesh.new(), Vector3(0.02, -0.95, 0), Vector3(0.25, 0.18, 0.18), Color(0.5, 0.5, 0.55)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.35, 0), Vector3(0.25, 0.22, 0.25), skin_color)
	# Horns
	_add_part("LeftHorn", CylinderMesh.new(), Vector3(-0.18, 1.55, 0), Vector3(0.05, 0.15, 0.05), Color(0.8, 0.75, 0.6))
	_add_part("RightHorn", CylinderMesh.new(), Vector3(0.18, 1.55, 0), Vector3(0.05, 0.15, 0.05), Color(0.8, 0.75, 0.6))
	# Glowing eyes
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.08, 1.38, 0.2), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.5, 0.1))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.08, 1.38, 0.2), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.5, 0.1))


func _add_part(part_name: String, mesh: Mesh, pos: Vector3, scale_vec: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_vec

	var mat := ShaderMaterial.new()
	mat.shader = toon_shader
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("rim_color", Color(1, 1, 1, 1))
	mat.set_shader_parameter("rim_strength", 0.3)
	mat.set_shader_parameter("rim_power", 3.0)
	mat.set_shader_parameter("bands", 3.0)
	mi.material_override = mat

	add_child(mi)


func _add_emissive_part(part_name: String, mesh: Mesh, pos: Vector3, scale_vec: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_vec

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat

	add_child(mi)


func _create_part(part_name: String, mesh: Mesh, pos: Vector3, scale_vec: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_vec

	var mat := ShaderMaterial.new()
	mat.shader = toon_shader
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("rim_color", Color(1, 1, 1, 1))
	mat.set_shader_parameter("rim_strength", 0.3)
	mat.set_shader_parameter("rim_power", 3.0)
	mat.set_shader_parameter("bands", 3.0)
	mi.material_override = mat

	return mi


func _create_emissive_part(part_name: String, mesh: Mesh, pos: Vector3, scale_vec: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_vec

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat

	return mi


func _clear() -> void:
	right_arm_pivot = null
	for child in get_children():
		child.queue_free()


# --- Attack Animation ---
# Swings the model: quick rotation wind-up, fast swing through, then recover.
var _attack_tween: Tween

func play_attack_anim() -> void:
	if _attack_tween and _attack_tween.is_running():
		_attack_tween.kill()

	_attack_tween = create_tween()

	if right_arm_pivot:
		var rest_x := right_arm_pivot.rotation.x
		# Wind up — arm swings back (snappy)
		_attack_tween.tween_property(right_arm_pivot, "rotation:x", -1.8, 0.05).set_ease(Tween.EASE_OUT)
		# Fast forward swing
		_attack_tween.tween_property(right_arm_pivot, "rotation:x", 1.2, 0.07).set_ease(Tween.EASE_IN)
		# Body lunge accompanies swing
		_attack_tween.parallel().tween_property(self, "rotation:x", 0.2, 0.07)
		# Recover arm and body
		_attack_tween.tween_property(right_arm_pivot, "rotation:x", rest_x, 0.1).set_ease(Tween.EASE_IN_OUT)
		_attack_tween.parallel().tween_property(self, "rotation:x", 0.0, 0.1)
	else:
		# Fallback body lunge
		_attack_tween.tween_property(self, "rotation:x", 0.25, 0.06)
		_attack_tween.tween_property(self, "rotation:x", 0.0, 0.08)

	# Slash arc VFX
	_spawn_slash_arc()


# --- Slash Arc VFX ---
func _spawn_slash_arc() -> void:
	var arc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.9
	torus.rings = 8
	torus.ring_segments = 12
	arc.mesh = torus
	arc.position = Vector3(0, 1.0, 0.6)
	arc.rotation.x = PI * 0.5
	arc.scale = Vector3(0.3, 1.0, 0.5)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.95, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	arc.material_override = mat
	add_child(arc)

	var tw := create_tween()
	tw.tween_property(arc, "scale", Vector3(1.4, 1.8, 1.2), 0.12)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(arc.queue_free)


# --- Hit Flash ---
# Briefly flashes all meshes white, then restores original materials.
var _flash_tween: Tween
var _original_materials: Dictionary = {}

func play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
		_restore_materials()

	_original_materials.clear()

	# Store originals and apply white flash
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color.WHITE
	flash_mat.emission_energy_multiplier = 3.0

	for child in find_children("*", "MeshInstance3D", true, false):
		_original_materials[child] = child.material_override
		child.material_override = flash_mat

	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.1)
	_flash_tween.tween_callback(_restore_materials)


func _restore_materials() -> void:
	for node in _original_materials:
		if is_instance_valid(node):
			node.material_override = _original_materials[node]
	_original_materials.clear()


# --- Impact Burst ---
# Spawns a brief particle burst at a world position to show a hit landing.
func spawn_impact_burst(world_pos: Vector3, color: Color = Color.ORANGE_RED) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 16
	particles.lifetime = 0.35
	particles.explosiveness = 0.95

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 120.0
	pmat.initial_velocity_min = 3.0
	pmat.initial_velocity_max = 5.0
	pmat.gravity = Vector3(0, -8, 0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.1
	pmat.color = color
	particles.process_material = pmat

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	particles.draw_pass_1 = mesh

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = color
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.5
	particles.material_override = mesh_mat

	# Add to scene tree at hit location
	get_tree().current_scene.add_child(particles)
	particles.global_position = world_pos

	# Auto-cleanup
	var tw := get_tree().create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(particles.queue_free)
