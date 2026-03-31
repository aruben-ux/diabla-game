class_name DungeonProps
## Static utility for building procedural dungeon decoration meshes.
## All props are built from primitives with StandardMaterial3D.

static var _mat_cache: Dictionary = {}


static func _mat(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.1f_%.1f" % [color.to_html(), roughness, metallic]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------------------
# 1. Breakable Pot — clay pot (StaticBody3D with breakable_pot.gd script)
# ---------------------------------------------------------------------------
static func build_breakable_pot(pos: Vector3, floor_level: int, drops_gold: bool, gold_amount: int, scale_f: float = 1.0) -> StaticBody3D:
	var pot_script := preload("res://scripts/interactables/breakable_pot.gd")

	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 4   # Layer 3 — detected by player AttackArea
	body.collision_mask = 0
	body.add_to_group("breakables")
	body.set_script(pot_script)
	body.setup(floor_level, drops_gold, gold_amount)

	# Collision
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.25 * scale_f
	shape.height = 0.5 * scale_f
	col.shape = shape
	col.position = Vector3(0, 0.25 * scale_f, 0)
	body.add_child(col)

	# Pot body (tapered cylinder — wider bottom, narrow top)
	var body_mi := MeshInstance3D.new()
	body_mi.name = "PotBody"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.2 * scale_f
	body_mesh.bottom_radius = 0.15 * scale_f
	body_mesh.height = 0.5 * scale_f
	body_mi.mesh = body_mesh
	body_mi.position = Vector3(0, 0.25 * scale_f, 0)
	body_mi.material_override = _mat(Color(0.6, 0.38, 0.2), 0.85)
	body.add_child(body_mi)

	# Rim
	var rim_mi := MeshInstance3D.new()
	rim_mi.name = "PotRim"
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.22 * scale_f
	rim_mesh.bottom_radius = 0.22 * scale_f
	rim_mesh.height = 0.05
	rim_mi.mesh = rim_mesh
	rim_mi.position = Vector3(0, 0.52 * scale_f, 0)
	rim_mi.material_override = _mat(Color(0.52, 0.32, 0.16), 0.9)
	body.add_child(rim_mi)

	return body


# ---------------------------------------------------------------------------
# 2. Floor Brazier — standing fire bowl with particles and OmniLight
# ---------------------------------------------------------------------------
static func build_brazier(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Brazier"
	root.position = pos

	# Stone base
	var base_mi := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.25
	base_mesh.bottom_radius = 0.35
	base_mesh.height = 0.15
	base_mi.mesh = base_mesh
	base_mi.position = Vector3(0, 0.075, 0)
	base_mi.material_override = _mat(Color(0.35, 0.3, 0.28), 0.9)
	root.add_child(base_mi)

	# Pillar
	var pillar_mi := MeshInstance3D.new()
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.1
	pillar_mesh.bottom_radius = 0.12
	pillar_mesh.height = 0.7
	pillar_mi.mesh = pillar_mesh
	pillar_mi.position = Vector3(0, 0.5, 0)
	pillar_mi.material_override = _mat(Color(0.3, 0.28, 0.25), 0.85)
	root.add_child(pillar_mi)

	# Bowl
	var bowl_mi := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.4
	bowl_mesh.bottom_radius = 0.15
	bowl_mesh.height = 0.25
	bowl_mi.mesh = bowl_mesh
	bowl_mi.position = Vector3(0, 0.97, 0)
	bowl_mi.material_override = _mat(Color(0.25, 0.22, 0.2), 0.8, 0.3)
	root.add_child(bowl_mi)

	# Glowing coals inside bowl
	var coal_mi := MeshInstance3D.new()
	var coal_mesh := CylinderMesh.new()
	coal_mesh.top_radius = 0.3
	coal_mesh.bottom_radius = 0.3
	coal_mesh.height = 0.08
	coal_mi.mesh = coal_mesh
	coal_mi.position = Vector3(0, 1.0, 0)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.albedo_color = Color(0.15, 0.05, 0.02)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(0.8, 0.25, 0.0)
	ember_mat.emission_energy_multiplier = 1.5
	ember_mat.roughness = 1.0
	coal_mi.material_override = ember_mat
	root.add_child(coal_mi)

	# Fire particles
	var fire := GPUParticles3D.new()
	fire.position = Vector3(0, 1.2, 0)
	fire.amount = 16
	fire.lifetime = 0.7
	fire.explosiveness = 0.05
	fire.randomness = 0.5
	fire.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 20.0
	pmat.initial_velocity_min = 0.4
	pmat.initial_velocity_max = 0.8
	pmat.gravity = Vector3(0, 1.0, 0)
	pmat.scale_min = 0.05
	pmat.scale_max = 0.1
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.1, 1.0))
	grad.set_color(1, Color(1.0, 0.15, 0.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pmat.color_ramp = ramp
	fire.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.6, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.4, 0.0)
	fmat.emission_energy_multiplier = 3.0
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = fmat
	fire.draw_pass_1 = quad
	root.add_child(fire)

	# Light
	var light := OmniLight3D.new()
	light.name = "TorchLight"  # Name matches flicker code in dungeon_level
	light.position = Vector3(0, 1.5, 0)
	light.omni_range = 8.0
	light.light_energy = 0.9
	light.light_color = Color(1.0, 0.7, 0.35)
	light.shadow_enabled = false
	root.add_child(light)

	return root


# ---------------------------------------------------------------------------
# 3. Bone Pile — flattened bone-shaped cylinders in a cluster
# ---------------------------------------------------------------------------
static func build_bone_pile(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "BonePile"
	root.position = pos
	var bone_mat := _mat(Color(0.85, 0.8, 0.7), 0.9)

	var count := rng.randi_range(4, 7)
	for i in range(count):
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.02
		mesh.bottom_radius = 0.025
		mesh.height = rng.randf_range(0.2, 0.4)
		mi.mesh = mesh
		mi.position = Vector3(rng.randf_range(-0.3, 0.3), 0.01, rng.randf_range(-0.3, 0.3))
		mi.rotation = Vector3(PI * 0.5 + rng.randf_range(-0.2, 0.2), rng.randf_range(0, TAU), 0)
		mi.material_override = bone_mat
		root.add_child(mi)

	# Optional skull (small sphere)
	if rng.randf() < 0.5:
		var skull := MeshInstance3D.new()
		var skull_mesh := SphereMesh.new()
		skull_mesh.radius = 0.07
		skull_mesh.height = 0.1
		skull.mesh = skull_mesh
		skull.position = Vector3(rng.randf_range(-0.15, 0.15), 0.06, rng.randf_range(-0.15, 0.15))
		skull.material_override = bone_mat
		root.add_child(skull)

	return root


# ---------------------------------------------------------------------------
# 4. Broken Pillar — half-height stone column with rubble at base
# ---------------------------------------------------------------------------
static func build_broken_pillar(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "BrokenPillar"
	root.position = pos
	var stone_mat := _mat(Color(0.4, 0.38, 0.35), 0.85)

	# Column stump
	var height := rng.randf_range(1.0, 2.0)
	var col_mi := MeshInstance3D.new()
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 0.35
	col_mesh.bottom_radius = 0.4
	col_mesh.height = height
	col_mi.mesh = col_mesh
	col_mi.position = Vector3(0, height * 0.5, 0)
	col_mi.material_override = stone_mat
	root.add_child(col_mi)

	# Broken top fragment (tilted)
	var frag := MeshInstance3D.new()
	var frag_mesh := CylinderMesh.new()
	frag_mesh.top_radius = 0.28
	frag_mesh.bottom_radius = 0.35
	frag_mesh.height = 0.3
	frag.mesh = frag_mesh
	frag.position = Vector3(0, height + 0.1, 0)
	frag.rotation = Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	frag.material_override = stone_mat
	root.add_child(frag)

	# Rubble at base
	var dark_stone := _mat(Color(0.35, 0.32, 0.3), 0.9)
	for i in range(rng.randi_range(3, 5)):
		var rub := MeshInstance3D.new()
		var rub_mesh := BoxMesh.new()
		var s := rng.randf_range(0.08, 0.18)
		rub_mesh.size = Vector3(s, s * 0.7, s)
		rub.mesh = rub_mesh
		var dist := rng.randf_range(0.3, 0.7)
		var angle := rng.randf() * TAU
		rub.position = Vector3(cos(angle) * dist, s * 0.35, sin(angle) * dist)
		rub.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		rub.material_override = dark_stone
		root.add_child(rub)

	return root


# ---------------------------------------------------------------------------
# 5. Cobweb — semi-transparent billboard quad
# ---------------------------------------------------------------------------
static func build_cobweb(pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.name = "Cobweb"
	root.position = pos

	var web_mesh := QuadMesh.new()
	var size := rng.randf_range(0.8, 1.5)
	web_mesh.size = Vector2(size, size)
	root.mesh = web_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	root.material_override = mat

	root.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))

	return root


# ---------------------------------------------------------------------------
# 6. Blood Stain — flat dark-red circle on the floor
# ---------------------------------------------------------------------------
static func build_blood_stain(pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.name = "BloodStain"
	root.position = pos + Vector3(0, 0.02, 0)  # Above floor to prevent z-fighting

	var mesh := CylinderMesh.new()   # Flat disc
	var radius := rng.randf_range(0.3, 0.7)
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.005
	root.mesh = mesh
	root.rotation.y = rng.randf() * TAU

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.02, 0.02, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.95
	root.material_override = mat

	return root


# ---------------------------------------------------------------------------
# 7. Rubble Pile — cluster of small angular rock-boxes
# ---------------------------------------------------------------------------
static func build_rubble_pile(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "RubblePile"
	root.position = pos

	var stone_colors: Array[Color] = [
		Color(0.38, 0.35, 0.32),
		Color(0.42, 0.4, 0.36),
		Color(0.32, 0.3, 0.28),
	]

	for i in range(rng.randi_range(4, 7)):
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var sx := rng.randf_range(0.08, 0.22)
		var sy := rng.randf_range(0.05, 0.14)
		var sz := rng.randf_range(0.08, 0.18)
		mesh.size = Vector3(sx, sy, sz)
		mi.mesh = mesh
		var dist := rng.randf_range(0.0, 0.45)
		var angle := rng.randf() * TAU
		mi.position = Vector3(cos(angle) * dist, sy * 0.5, sin(angle) * dist)
		mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		mi.material_override = _mat(stone_colors[i % stone_colors.size()], 0.9)
		root.add_child(mi)

	return root


# ---------------------------------------------------------------------------
# 8. Wooden Barrel — cylinder with metal bands (intact or toppled)
# ---------------------------------------------------------------------------
static func build_barrel(pos: Vector3, rng: RandomNumberGenerator, intact: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Barrel"
	root.position = pos

	if not intact:
		root.rotation.x = rng.randf_range(0.3, 0.7) * (1.0 if rng.randf() > 0.5 else -1.0)
		root.rotation.z = rng.randf_range(-0.15, 0.15)

	# Barrel body
	var body_mi := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.28
	body_mesh.bottom_radius = 0.28
	body_mesh.height = 0.8
	body_mi.mesh = body_mesh
	body_mi.position = Vector3(0, 0.4, 0)
	body_mi.material_override = _mat(Color(0.45, 0.3, 0.15), 0.8)
	root.add_child(body_mi)

	# Wider middle bulge
	var bulge_mi := MeshInstance3D.new()
	var bulge_mesh := CylinderMesh.new()
	bulge_mesh.top_radius = 0.305
	bulge_mesh.bottom_radius = 0.305
	bulge_mesh.height = 0.2
	bulge_mi.mesh = bulge_mesh
	bulge_mi.position = Vector3(0, 0.4, 0)
	bulge_mi.material_override = _mat(Color(0.43, 0.28, 0.13), 0.8)
	root.add_child(bulge_mi)

	# Metal bands
	var band_mat := _mat(Color(0.3, 0.28, 0.25), 0.6, 0.5)
	for y_off in [0.12, 0.68]:
		var band := MeshInstance3D.new()
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = 0.295
		band_mesh.bottom_radius = 0.295
		band_mesh.height = 0.04
		band.mesh = band_mesh
		band.position = Vector3(0, y_off, 0)
		band.material_override = band_mat
		root.add_child(band)

	return root


# ---------------------------------------------------------------------------
# 9. Skull Pile — cluster of small spheres and bones
# ---------------------------------------------------------------------------
static func build_skull_pile(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "SkullPile"
	root.position = pos
	var bone_mat := _mat(Color(0.82, 0.77, 0.68), 0.9)

	var count := rng.randi_range(3, 5)
	for i in range(count):
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var r := rng.randf_range(0.06, 0.09)
		mesh.radius = r
		mesh.height = r * 1.4
		mi.mesh = mesh
		var dist := rng.randf_range(0.0, 0.18)
		var angle := rng.randf() * TAU
		mi.position = Vector3(cos(angle) * dist, r + float(i) * 0.02, sin(angle) * dist)
		mi.material_override = bone_mat
		root.add_child(mi)

	# A couple of bone shards
	for i in range(2):
		var bone := MeshInstance3D.new()
		var bone_mesh := CylinderMesh.new()
		bone_mesh.top_radius = 0.015
		bone_mesh.bottom_radius = 0.02
		bone_mesh.height = rng.randf_range(0.15, 0.3)
		bone.mesh = bone_mesh
		bone.position = Vector3(rng.randf_range(-0.2, 0.2), 0.01, rng.randf_range(-0.2, 0.2))
		bone.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0)
		bone.material_override = bone_mat
		root.add_child(bone)

	return root


# ---------------------------------------------------------------------------
# 10. Hanging Chains — thin cylinders dangling from ceiling
# ---------------------------------------------------------------------------
static func build_hanging_chains(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "HangingChains"
	root.position = pos
	var chain_mat := _mat(Color(0.3, 0.28, 0.25), 0.5, 0.7)

	var count := rng.randi_range(1, 3)
	for i in range(count):
		var chain_len := rng.randf_range(1.0, 2.5)
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.015
		mesh.bottom_radius = 0.015
		mesh.height = chain_len
		mi.mesh = mesh
		var y := 4.0 - chain_len * 0.5  # Hanging from ceiling (WALL_HEIGHT = 4.0)
		mi.position = Vector3(rng.randf_range(-0.3, 0.3) * float(i), y, rng.randf_range(-0.3, 0.3))
		mi.rotation.x = rng.randf_range(-0.12, 0.12)
		mi.rotation.z = rng.randf_range(-0.12, 0.12)
		mi.material_override = chain_mat
		root.add_child(mi)

		# Small weight / hook at bottom
		var hook := MeshInstance3D.new()
		var hook_mesh := SphereMesh.new()
		hook_mesh.radius = 0.035
		hook_mesh.height = 0.05
		hook.mesh = hook_mesh
		hook.position = Vector3(mi.position.x, 4.0 - chain_len - 0.02, mi.position.z)
		hook.material_override = chain_mat
		root.add_child(hook)

	return root
