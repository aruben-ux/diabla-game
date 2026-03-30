extends Node3D

## Builds a humanoid figure from primitives at runtime with toon shading.
## Supports procedural walk/idle animation via limb pivots.

var toon_shader: Shader
var right_arm_pivot: Node3D
var left_arm_pivot: Node3D
var right_leg_pivot: Node3D
var left_leg_pivot: Node3D

# --- Procedural animation state ---
var _is_walking: bool = false
var _anim_time: float = 0.0
const WALK_SPEED := 8.0       # Oscillation speed
const ARM_SWING := 0.5        # Arm rotation amplitude (radians)
const LEG_SWING := 0.6        # Leg rotation amplitude
const BODY_BOB := 0.03        # Vertical bounce
const IDLE_SPEED := 1.5       # Idle breathing speed
const IDLE_BOB := 0.008       # Idle sway amplitude

# Rest rotations (stored after build)
var _right_arm_rest_x: float = 0.0
var _left_arm_rest_x: float = 0.0

func _ready() -> void:
	toon_shader = preload("res://assets/shaders/toon.gdshader")


func build_player_model() -> void:
	# Default fallback — builds warrior with default colors
	build_class_model({
		"character_class": 0,
		"armor_color": [0.35, 0.55, 0.9],
		"accent_color": [0.2, 0.45, 0.85],
		"body_scale": [1.0, 1.0, 1.0],
		"size_mult": 1.0,
	})


func build_class_model(appearance: Dictionary) -> void:
	_clear()
	var cls: int = appearance.get("character_class", 0)
	var ac: Array = appearance.get("armor_color", [0.35, 0.55, 0.9])
	var armor_color := Color(ac[0], ac[1], ac[2])
	var xc: Array = appearance.get("accent_color", [0.2, 0.45, 0.85])
	var accent_color := Color(xc[0], xc[1], xc[2])
	var bs: Array = appearance.get("body_scale", [1.0, 1.0, 1.0])
	var body_scale := Vector3(bs[0], bs[1], bs[2])
	var size_mult: float = appearance.get("size_mult", 1.0)

	match cls:
		0: _build_warrior(armor_color, accent_color, body_scale, size_mult)
		1: _build_mage(armor_color, accent_color, body_scale, size_mult)
		2: _build_rogue(armor_color, accent_color, body_scale, size_mult)
		_: _build_warrior(armor_color, accent_color, body_scale, size_mult)

	# Apply overall size
	scale = Vector3.ONE * size_mult

	# Store rest rotations for animation
	_store_rest_rotations()


func set_walking(walking: bool) -> void:
	_is_walking = walking
	if not walking:
		_anim_time = 0.0


func _process(delta: float) -> void:
	# Only animate if this model has limb pivots (player models)
	if not right_arm_pivot and not left_leg_pivot:
		return

	_anim_time += delta

	if _is_walking:
		var t := _anim_time * WALK_SPEED
		var s := sin(t)

		# Legs swing opposite to each other
		if right_leg_pivot:
			right_leg_pivot.rotation.x = s * LEG_SWING
		if left_leg_pivot:
			left_leg_pivot.rotation.x = -s * LEG_SWING

		# Arms swing opposite to legs, biased forward
		var arm_fwd := 0.3
		if right_arm_pivot:
			right_arm_pivot.rotation.x = _right_arm_rest_x - arm_fwd + (-s * ARM_SWING)
		if left_arm_pivot:
			left_arm_pivot.rotation.x = _left_arm_rest_x - arm_fwd + (s * ARM_SWING)

		# Slight body bob
		position.y = abs(sin(t * 2.0)) * BODY_BOB
		# Reset idle lean
		rotation.x = lerp(rotation.x, 0.0, 8.0 * delta)
		rotation.z = lerp(rotation.z, 0.0, 8.0 * delta)
	else:
		# Idle: gentle breathing sway + subtle limb motion
		var idle_t := _anim_time * IDLE_SPEED
		position.y = sin(idle_t) * IDLE_BOB

		# Very slow, subtle arm sway (like breathing / shifting weight)
		var arm_drift := sin(idle_t * 0.7) * 0.06
		var arm_drift2 := sin(idle_t * 0.7 + 1.2) * 0.06
		if right_arm_pivot:
			right_arm_pivot.rotation.x = lerp(right_arm_pivot.rotation.x, _right_arm_rest_x + arm_drift, 3.0 * delta)
			right_arm_pivot.rotation.z = lerp(right_arm_pivot.rotation.z, sin(idle_t * 0.5) * 0.03, 3.0 * delta)
		if left_arm_pivot:
			left_arm_pivot.rotation.x = lerp(left_arm_pivot.rotation.x, _left_arm_rest_x + arm_drift2, 3.0 * delta)
			left_arm_pivot.rotation.z = lerp(left_arm_pivot.rotation.z, sin(idle_t * 0.5 + PI) * 0.03, 3.0 * delta)

		# Subtle weight-shift on legs
		if right_leg_pivot:
			right_leg_pivot.rotation.x = lerp(right_leg_pivot.rotation.x, sin(idle_t * 0.4) * 0.025, 3.0 * delta)
		if left_leg_pivot:
			left_leg_pivot.rotation.x = lerp(left_leg_pivot.rotation.x, sin(idle_t * 0.4 + PI) * 0.025, 3.0 * delta)

		# Gentle torso lean / breathing
		rotation.x = lerp(rotation.x, sin(idle_t * 0.6) * 0.015, 3.0 * delta)
		rotation.z = lerp(rotation.z, sin(idle_t * 0.35) * 0.01, 3.0 * delta)


func _build_warrior(armor_color: Color, accent_color: Color, body_shape: Vector3, _sm: float) -> void:
	var skin_color := Color(0.85, 0.7, 0.6)
	var boot_color := Color(0.3, 0.25, 0.2)
	var metal_color := Color(0.7, 0.7, 0.75)

	# Legs — thick boots on pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.18, 0.58, 0) * body_shape
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14) * body_shape, boot_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.18, 0.58, 0) * body_shape
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14) * body_shape, boot_color))

	# Torso — heavy chestplate
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.85, 0) * body_shape, Vector3(0.55, 0.5, 0.35) * body_shape, armor_color)
	# Belt
	_add_part("Belt", BoxMesh.new(), Vector3(0, 0.62, 0) * body_shape, Vector3(0.52, 0.06, 0.32) * body_shape, boot_color)

	# Shoulder pads — big, armored
	_add_part("LeftShoulder", SphereMesh.new(), Vector3(-0.38, 1.12, 0) * body_shape, Vector3(0.24, 0.18, 0.24) * body_shape, accent_color)
	_add_part("RightShoulder", SphereMesh.new(), Vector3(0.38, 1.12, 0) * body_shape, Vector3(0.24, 0.18, 0.24) * body_shape, accent_color)

	# Right arm pivot — sword arm
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.38, 1.05, 0) * body_shape
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.1, 0.25, 0.1) * body_shape, skin_color))
	right_arm_pivot.add_child(_create_part("Sword", BoxMesh.new(), Vector3(0.02, -0.72, 0), Vector3(0.07, 0.6, 0.04), metal_color))
	right_arm_pivot.add_child(_create_part("SwordGuard", BoxMesh.new(), Vector3(0.02, -0.43, 0), Vector3(0.2, 0.05, 0.07), accent_color))
	right_arm_pivot.add_child(_create_part("SwordGrip", CylinderMesh.new(), Vector3(0.02, -0.36, 0), Vector3(0.04, 0.12, 0.04), boot_color))

	# Left arm pivot — shield arm
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.38, 1.05, 0) * body_shape
	left_arm_pivot.rotation.x = 0.4
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.1, 0.25, 0.1) * body_shape, skin_color))
	left_arm_pivot.add_child(_create_part("Shield", BoxMesh.new(), Vector3(-0.1, -0.22, 0.14), Vector3(0.05, 0.38, 0.32), armor_color))
	left_arm_pivot.add_child(_create_part("ShieldBoss", SphereMesh.new(), Vector3(-0.1, -0.22, 0.3), Vector3(0.1, 0.1, 0.06), accent_color))

	# Head
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.35, 0) * body_shape, Vector3(0.22, 0.22, 0.22), skin_color)
	# Helmet — full helm
	_add_part("Helmet", SphereMesh.new(), Vector3(0, 1.42, 0) * body_shape, Vector3(0.27, 0.2, 0.27), armor_color)
	# Helmet crest
	_add_part("Crest", BoxMesh.new(), Vector3(0, 1.56, 0) * body_shape, Vector3(0.04, 0.1, 0.2), accent_color)

	# Eyes (emissive)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.07, 1.38, 0.19) * body_shape, Vector3(0.04, 0.04, 0.04), accent_color.lightened(0.5))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.07, 1.38, 0.19) * body_shape, Vector3(0.04, 0.04, 0.04), accent_color.lightened(0.5))


func _build_mage(armor_color: Color, accent_color: Color, body_shape: Vector3, _sm: float) -> void:
	var skin_color := Color(0.8, 0.72, 0.65)

	# Robe skirt — flared cylinder
	_add_part("Robe", CylinderMesh.new(), Vector3(0, 0.4, 0) * body_shape, Vector3(0.3, 0.4, 0.3) * body_shape, armor_color)

	# Hidden leg pivots inside robe (for animation)
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.1, 0.55, 0) * body_shape
	add_child(left_leg_pivot)

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.1, 0.55, 0) * body_shape
	add_child(right_leg_pivot)

	# Torso — elegant robe
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.88, 0) * body_shape, Vector3(0.38, 0.38, 0.25) * body_shape, armor_color)
	# Sash
	_add_part("Sash", BoxMesh.new(), Vector3(0, 0.7, 0.05) * body_shape, Vector3(0.35, 0.04, 0.22) * body_shape, accent_color)

	# Shoulder mantle — softer shape
	_add_part("LeftShoulder", SphereMesh.new(), Vector3(-0.28, 1.08, 0) * body_shape, Vector3(0.16, 0.12, 0.16) * body_shape, accent_color)
	_add_part("RightShoulder", SphereMesh.new(), Vector3(0.28, 1.08, 0) * body_shape, Vector3(0.16, 0.12, 0.16) * body_shape, accent_color)

	# Right arm pivot — staff hand
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.28, 1.0, 0) * body_shape
	right_arm_pivot.rotation.x = 0.2
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.24, 0), Vector3(0.07, 0.22, 0.07) * body_shape, skin_color))
	right_arm_pivot.add_child(_create_part("Staff", CylinderMesh.new(), Vector3(0.02, -0.3, 0), Vector3(0.04, 0.8, 0.04), Color(0.5, 0.35, 0.2)))
	right_arm_pivot.add_child(_create_emissive_part("StaffOrb", SphereMesh.new(), Vector3(0.02, 0.45, 0), Vector3(0.12, 0.12, 0.12), accent_color))

	# Left arm
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.28, 1.0, 0) * body_shape
	left_arm_pivot.rotation.x = 0.15
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.24, 0), Vector3(0.07, 0.22, 0.07) * body_shape, skin_color))
	# Book / tome in off-hand
	left_arm_pivot.add_child(_create_part("Tome", BoxMesh.new(), Vector3(-0.06, -0.35, 0.08), Vector3(0.12, 0.16, 0.04), accent_color.darkened(0.3)))

	# Head
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.3, 0) * body_shape, Vector3(0.2, 0.2, 0.2), skin_color)
	# Wizard hat — tall cone
	_add_part("HatBrim", CylinderMesh.new(), Vector3(0, 1.36, 0) * body_shape, Vector3(0.28, 0.025, 0.28), armor_color)
	_add_part("HatCone", CylinderMesh.new(), Vector3(0, 1.58, 0) * body_shape, Vector3(0.15, 0.22, 0.15), armor_color)
	_add_part("HatTip", SphereMesh.new(), Vector3(0, 1.78, 0) * body_shape, Vector3(0.06, 0.06, 0.06), accent_color)

	# Eyes (emissive, arcane glow)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.33, 0.16) * body_shape, Vector3(0.035, 0.035, 0.035), accent_color)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.33, 0.16) * body_shape, Vector3(0.035, 0.035, 0.035), accent_color)


func _build_rogue(armor_color: Color, accent_color: Color, body_shape: Vector3, _sm: float) -> void:
	var skin_color := Color(0.8, 0.68, 0.58)
	var leather_color := armor_color.lightened(0.1)

	# Legs — slim, with wrapped boots on pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.13, 0.58, 0) * body_shape
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.1, 0.3, 0.1) * body_shape, leather_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.13, 0.58, 0) * body_shape
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.1, 0.3, 0.1) * body_shape, leather_color))

	# Torso — light leather vest
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.82, 0) * body_shape, Vector3(0.4, 0.42, 0.25) * body_shape, armor_color)
	# Bandolier
	_add_part("Bandolier", BoxMesh.new(), Vector3(0.0, 0.85, 0.1) * body_shape, Vector3(0.08, 0.4, 0.05) * body_shape, accent_color)

	# Shoulders — small leather pads
	_add_part("LeftShoulder", SphereMesh.new(), Vector3(-0.28, 1.06, 0) * body_shape, Vector3(0.14, 0.1, 0.14) * body_shape, armor_color)
	_add_part("RightShoulder", SphereMesh.new(), Vector3(0.28, 1.06, 0) * body_shape, Vector3(0.14, 0.1, 0.14) * body_shape, armor_color)

	# Right arm pivot — main-hand dagger
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.3, 1.0, 0) * body_shape
	right_arm_pivot.rotation.x = 0.25
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.26, 0), Vector3(0.07, 0.23, 0.07) * body_shape, skin_color))
	right_arm_pivot.add_child(_create_part("Dagger1", BoxMesh.new(), Vector3(0.02, -0.52, 0), Vector3(0.04, 0.3, 0.03), Color(0.75, 0.75, 0.8)))
	right_arm_pivot.add_child(_create_part("Dagger1Guard", BoxMesh.new(), Vector3(0.02, -0.37, 0), Vector3(0.1, 0.03, 0.05), accent_color))

	# Left arm pivot — off-hand dagger
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.3, 1.0, 0) * body_shape
	left_arm_pivot.rotation.x = 0.25
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.26, 0), Vector3(0.07, 0.23, 0.07) * body_shape, skin_color))
	left_arm_pivot.add_child(_create_part("Dagger2", BoxMesh.new(), Vector3(-0.02, -0.50, 0), Vector3(0.04, 0.28, 0.03), Color(0.75, 0.75, 0.8)))
	left_arm_pivot.add_child(_create_part("Dagger2Guard", BoxMesh.new(), Vector3(-0.02, -0.36, 0), Vector3(0.1, 0.03, 0.05), accent_color))

	# Head
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.3, 0) * body_shape, Vector3(0.2, 0.2, 0.2), skin_color)
	# Hood
	_add_part("Hood", SphereMesh.new(), Vector3(0, 1.38, -0.02) * body_shape, Vector3(0.24, 0.2, 0.24), armor_color)
	# Mask/scarf
	_add_part("Mask", BoxMesh.new(), Vector3(0, 1.26, 0.12) * body_shape, Vector3(0.18, 0.06, 0.06), accent_color)

	# Eyes (emissive, sharp)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.33, 0.17) * body_shape, Vector3(0.03, 0.03, 0.03), Color(0.9, 0.95, 0.8))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.33, 0.17) * body_shape, Vector3(0.03, 0.03, 0.03), Color(0.9, 0.95, 0.8))


func build_from_data(visual_data: Dictionary) -> void:
	_clear()
	# Build root-level parts
	for part_data: Dictionary in visual_data.get("parts", []):
		var pname: String = part_data.get("name", "Part")
		var mesh := _create_mesh(part_data.get("mesh", "box"))
		var pos := Vector3(part_data["position"][0], part_data["position"][1], part_data["position"][2])
		var scl := Vector3(part_data["scale"][0], part_data["scale"][1], part_data["scale"][2])
		var ca: Array = part_data.get("color", [1, 1, 1, 1])
		var col := Color(ca[0], ca[1], ca[2], ca[3])
		if part_data.get("emissive", false):
			_add_emissive_part(pname, mesh, pos, scl, col)
		else:
			_add_part(pname, mesh, pos, scl, col)
	# Build pivots
	for pivot_data: Dictionary in visual_data.get("pivots", []):
		var pivot := Node3D.new()
		pivot.name = pivot_data.get("name", "Pivot")
		var pp: Array = pivot_data.get("position", [0, 0, 0])
		pivot.position = Vector3(pp[0], pp[1], pp[2])
		pivot.rotation.x = pivot_data.get("rotation_x", 0.0)
		add_child(pivot)
		if pivot.name == "RightArmPivot":
			right_arm_pivot = pivot
		elif pivot.name == "LeftArmPivot":
			left_arm_pivot = pivot
		elif pivot.name == "RightLegPivot":
			right_leg_pivot = pivot
		elif pivot.name == "LeftLegPivot":
			left_leg_pivot = pivot
		for child_data: Dictionary in pivot_data.get("parts", []):
			var cname: String = child_data.get("name", "Part")
			var cmesh := _create_mesh(child_data.get("mesh", "box"))
			var cpos := Vector3(child_data["position"][0], child_data["position"][1], child_data["position"][2])
			var cscl := Vector3(child_data["scale"][0], child_data["scale"][1], child_data["scale"][2])
			var cca: Array = child_data.get("color", [1, 1, 1, 1])
			var ccol := Color(cca[0], cca[1], cca[2], cca[3])
			if child_data.get("emissive", false):
				pivot.add_child(_create_emissive_part(cname, cmesh, cpos, cscl, ccol))
			else:
				pivot.add_child(_create_part(cname, cmesh, cpos, cscl, ccol))
	_store_rest_rotations()


static func _create_mesh(mesh_type: String) -> Mesh:
	match mesh_type:
		"cylinder":
			return CylinderMesh.new()
		"sphere":
			return SphereMesh.new()
		_:
			return BoxMesh.new()


func build_enemy_grunt() -> void:
	_clear()

	var body_color := Color(0.55, 0.2, 0.15)
	var skin_color := Color(0.45, 0.55, 0.35)

	# Leg pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.15, 0.5, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.13, 0.25, 0.13), skin_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.15, 0.5, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.13, 0.25, 0.13), skin_color))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.7, 0), Vector3(0.5, 0.4, 0.35), body_color)

	# Left arm pivot
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.35, 0.85, 0)
	left_arm_pivot.rotation.x = 0.3
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.1, 0.25, 0.1), skin_color))

	# Right arm pivot — holds arm + club
	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.35, 0.85, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.1, 0.25, 0.1), skin_color))
	right_arm_pivot.add_child(_create_part("Club", CylinderMesh.new(), Vector3(0.02, -0.55, 0), Vector3(0.08, 0.35, 0.08), Color(0.4, 0.3, 0.15)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.05, 0), Vector3(0.2, 0.2, 0.2), skin_color)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.08, 0.16), Vector3(0.04, 0.04, 0.04), Color(1.0, 0.3, 0.1))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.08, 0.16), Vector3(0.04, 0.04, 0.04), Color(1.0, 0.3, 0.1))
	_store_rest_rotations()


func build_enemy_mage() -> void:
	_clear()

	var robe_color := Color(0.3, 0.1, 0.4)
	var skin_color := Color(0.5, 0.45, 0.55)

	# Hidden leg pivots inside robe
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.1, 0.35, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLegHidden", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.1, 0.35, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLegHidden", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe_color))

	_add_part("Robe", CylinderMesh.new(), Vector3(0, 0.5, 0), Vector3(0.3, 0.5, 0.3), robe_color)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.9, 0), Vector3(0.35, 0.3, 0.25), robe_color)

	# Left arm pivot
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.25, 1.0, 0)
	left_arm_pivot.rotation.x = 0.2
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.07, 0.22, 0.07), skin_color))

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
	_add_part("Hat", CylinderMesh.new(), Vector3(0, 1.5, 0), Vector3(0.15, 0.2, 0.15), robe_color)
	_add_part("HatBrim", CylinderMesh.new(), Vector3(0, 1.32, 0), Vector3(0.25, 0.02, 0.25), robe_color)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.28, 0.14), Vector3(0.035, 0.035, 0.035), Color(0.6, 0.2, 1.0))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.28, 0.14), Vector3(0.035, 0.035, 0.035), Color(0.6, 0.2, 1.0))
	_store_rest_rotations()


func build_enemy_brute() -> void:
	_clear()

	var body_color := Color(0.55, 0.3, 0.2)
	var skin_color := Color(0.5, 0.35, 0.3)

	# Leg pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.2, 0.7, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.35, 0), Vector3(0.16, 0.35, 0.16), skin_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.2, 0.7, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.35, 0), Vector3(0.16, 0.35, 0.16), skin_color))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.95, 0), Vector3(0.65, 0.55, 0.4), body_color)

	# Left arm pivot
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.45, 1.15, 0)
	left_arm_pivot.rotation.x = 0.35
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.32, 0), Vector3(0.14, 0.35, 0.14), skin_color))

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
	_add_part("LeftHorn", CylinderMesh.new(), Vector3(-0.18, 1.55, 0), Vector3(0.05, 0.15, 0.05), Color(0.8, 0.75, 0.6))
	_add_part("RightHorn", CylinderMesh.new(), Vector3(0.18, 1.55, 0), Vector3(0.05, 0.15, 0.05), Color(0.8, 0.75, 0.6))
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.08, 1.38, 0.2), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.5, 0.1))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.08, 1.38, 0.2), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.5, 0.1))
	_store_rest_rotations()


func _store_rest_rotations() -> void:
	_right_arm_rest_x = right_arm_pivot.rotation.x if right_arm_pivot else 0.3
	_left_arm_rest_x = left_arm_pivot.rotation.x if left_arm_pivot else 0.3


# ---------- SKELETON ----------
func build_enemy_skeleton() -> void:
	_clear()
	var bone := Color(0.9, 0.88, 0.8)
	var dark := Color(0.2, 0.18, 0.15)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.12, 0.5, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.07, 0.28, 0.07), bone))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.12, 0.5, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.07, 0.28, 0.07), bone))

	# Ribcage
	_add_part("Ribcage", BoxMesh.new(), Vector3(0, 0.75, 0), Vector3(0.35, 0.35, 0.2), bone)
	_add_part("Spine", CylinderMesh.new(), Vector3(0, 0.55, 0), Vector3(0.05, 0.15, 0.05), bone)
	_add_part("Pelvis", BoxMesh.new(), Vector3(0, 0.45, 0), Vector3(0.25, 0.08, 0.15), bone)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.25, 0.9, 0)
	left_arm_pivot.rotation.x = 0.4
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.06, 0.24, 0.06), bone))
	left_arm_pivot.add_child(_create_part("Shield", BoxMesh.new(), Vector3(-0.08, -0.2, 0.1), Vector3(0.04, 0.22, 0.18), dark))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.25, 0.9, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.06, 0.24, 0.06), bone))
	right_arm_pivot.add_child(_create_part("Sword", BoxMesh.new(), Vector3(0.02, -0.55, 0), Vector3(0.05, 0.4, 0.03), Color(0.7, 0.7, 0.75)))

	_add_part("Skull", SphereMesh.new(), Vector3(0, 1.02, 0), Vector3(0.18, 0.2, 0.18), bone)
	_add_part("Jaw", BoxMesh.new(), Vector3(0, 0.92, 0.08), Vector3(0.12, 0.04, 0.08), bone)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.05, 0.14), Vector3(0.035, 0.04, 0.035), Color(0.1, 1.0, 0.2))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.05, 0.14), Vector3(0.035, 0.04, 0.035), Color(0.1, 1.0, 0.2))
	_store_rest_rotations()


# ---------- SPIDER ----------
func build_enemy_spider() -> void:
	_clear()
	var body_color := Color(0.25, 0.2, 0.18)
	var leg_color := Color(0.35, 0.28, 0.22)

	# Low body
	_add_part("Abdomen", SphereMesh.new(), Vector3(0, 0.35, -0.2), Vector3(0.35, 0.25, 0.4), body_color)
	_add_part("Thorax", SphereMesh.new(), Vector3(0, 0.35, 0.15), Vector3(0.25, 0.2, 0.25), body_color)
	# Mandibles
	_add_part("LeftFang", CylinderMesh.new(), Vector3(-0.08, 0.25, 0.35), Vector3(0.03, 0.1, 0.03), Color(0.6, 0.5, 0.4))
	_add_part("RightFang", CylinderMesh.new(), Vector3(0.08, 0.25, 0.35), Vector3(0.03, 0.1, 0.03), Color(0.6, 0.5, 0.4))

	# Front legs as "arm" pivots
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.2, 0.35, 0.1)
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("FrontLeftLeg", CylinderMesh.new(), Vector3(-0.2, -0.05, 0.15), Vector3(0.04, 0.25, 0.04), leg_color))
	left_arm_pivot.add_child(_create_part("FrontLeftLeg2", CylinderMesh.new(), Vector3(-0.12, -0.05, -0.1), Vector3(0.04, 0.25, 0.04), leg_color))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.2, 0.35, 0.1)
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("FrontRightLeg", CylinderMesh.new(), Vector3(0.2, -0.05, 0.15), Vector3(0.04, 0.25, 0.04), leg_color))
	right_arm_pivot.add_child(_create_part("FrontRightLeg2", CylinderMesh.new(), Vector3(0.12, -0.05, -0.1), Vector3(0.04, 0.25, 0.04), leg_color))

	# Back legs as "leg" pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.2, 0.35, -0.15)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("BackLeftLeg", CylinderMesh.new(), Vector3(-0.2, -0.05, -0.1), Vector3(0.04, 0.25, 0.04), leg_color))
	left_leg_pivot.add_child(_create_part("BackLeftLeg2", CylinderMesh.new(), Vector3(-0.12, -0.05, 0.12), Vector3(0.04, 0.25, 0.04), leg_color))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.2, 0.35, -0.15)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("BackRightLeg", CylinderMesh.new(), Vector3(0.2, -0.05, -0.1), Vector3(0.04, 0.25, 0.04), leg_color))
	right_leg_pivot.add_child(_create_part("BackRightLeg2", CylinderMesh.new(), Vector3(0.12, -0.05, 0.12), Vector3(0.04, 0.25, 0.04), leg_color))

	# Eyes cluster
	_add_emissive_part("Eye1", SphereMesh.new(), Vector3(-0.06, 0.42, 0.3), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.1, 0.1))
	_add_emissive_part("Eye2", SphereMesh.new(), Vector3(0.06, 0.42, 0.3), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.1, 0.1))
	_add_emissive_part("Eye3", SphereMesh.new(), Vector3(-0.03, 0.45, 0.32), Vector3(0.025, 0.025, 0.025), Color(1.0, 0.1, 0.1))
	_add_emissive_part("Eye4", SphereMesh.new(), Vector3(0.03, 0.45, 0.32), Vector3(0.025, 0.025, 0.025), Color(1.0, 0.1, 0.1))
	_store_rest_rotations()


# ---------- GHOST ----------
func build_enemy_ghost() -> void:
	_clear()
	var ghost_color := Color(0.7, 0.75, 0.85)
	var glow_color := Color(0.5, 0.7, 1.0)

	# Wispy lower body (no legs — floats)
	_add_part("LowerBody", CylinderMesh.new(), Vector3(0, 0.4, 0), Vector3(0.25, 0.35, 0.25), ghost_color)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.8, 0), Vector3(0.35, 0.3, 0.2), ghost_color)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.25, 0.85, 0)
	left_arm_pivot.rotation.x = 0.5
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.07, 0.22, 0.07), ghost_color))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.25, 0.85, 0)
	right_arm_pivot.rotation.x = 0.5
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.07, 0.22, 0.07), ghost_color))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.1, 0), Vector3(0.2, 0.22, 0.2), ghost_color)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.13, 0.15), Vector3(0.04, 0.05, 0.04), glow_color)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.13, 0.15), Vector3(0.04, 0.05, 0.04), glow_color)
	_add_emissive_part("Aura", SphereMesh.new(), Vector3(0, 0.7, 0), Vector3(0.5, 0.7, 0.5), Color(0.4, 0.5, 0.8, 0.15))
	_store_rest_rotations()


# ---------- ARCHER ----------
func build_enemy_archer() -> void:
	_clear()
	var leather := Color(0.4, 0.32, 0.2)
	var skin := Color(0.45, 0.55, 0.35)
	var wood := Color(0.5, 0.35, 0.15)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.12, 0.5, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.1, 0.26, 0.1), leather))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.12, 0.5, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.1, 0.26, 0.1), leather))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.75, 0), Vector3(0.38, 0.35, 0.25), leather)
	_add_part("Quiver", CylinderMesh.new(), Vector3(0.12, 0.85, -0.15), Vector3(0.08, 0.25, 0.08), wood)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.28, 0.88, 0)
	left_arm_pivot.rotation.x = 0.6
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.08, 0.24, 0.08), skin))
	# Bow
	left_arm_pivot.add_child(_create_part("BowTop", CylinderMesh.new(), Vector3(-0.02, -0.15, 0.12), Vector3(0.03, 0.3, 0.03), wood))
	left_arm_pivot.add_child(_create_part("BowString", CylinderMesh.new(), Vector3(-0.02, -0.15, 0.08), Vector3(0.01, 0.28, 0.01), Color(0.8, 0.8, 0.75)))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.28, 0.88, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.08, 0.24, 0.08), skin))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.05, 0), Vector3(0.18, 0.18, 0.18), skin)
	_add_part("Hood", SphereMesh.new(), Vector3(0, 1.1, -0.02), Vector3(0.2, 0.16, 0.2), leather)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.08, 0.14), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.8, 0.2))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.08, 0.14), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.8, 0.2))
	_store_rest_rotations()


# ---------- SHAMAN ----------
func build_enemy_shaman() -> void:
	_clear()
	var robe := Color(0.35, 0.25, 0.15)
	var skin := Color(0.45, 0.4, 0.3)
	var accent := Color(0.8, 0.3, 0.1)

	# Hidden leg pivots inside robe
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.1, 0.35, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LL", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.1, 0.35, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RL", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe))

	_add_part("Robe", CylinderMesh.new(), Vector3(0, 0.45, 0), Vector3(0.28, 0.45, 0.28), robe)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.85, 0), Vector3(0.35, 0.3, 0.25), robe)
	_add_part("BoneNecklace", CylinderMesh.new(), Vector3(0, 0.95, 0.1), Vector3(0.18, 0.03, 0.18), Color(0.9, 0.88, 0.8))

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.25, 0.95, 0)
	left_arm_pivot.rotation.x = 0.3
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.07, 0.22, 0.07), skin))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.25, 0.95, 0)
	right_arm_pivot.rotation.x = 0.2
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.07, 0.22, 0.07), skin))
	right_arm_pivot.add_child(_create_part("TotemStaff", CylinderMesh.new(), Vector3(0.02, -0.35, 0), Vector3(0.04, 0.65, 0.04), Color(0.45, 0.3, 0.15)))
	right_arm_pivot.add_child(_create_part("SkullTop", SphereMesh.new(), Vector3(0.02, 0.3, 0), Vector3(0.1, 0.1, 0.1), Color(0.9, 0.88, 0.8)))
	right_arm_pivot.add_child(_create_emissive_part("SkullGlow", SphereMesh.new(), Vector3(0.02, 0.3, 0), Vector3(0.12, 0.12, 0.12), Color(0.2, 0.9, 0.3, 0.5)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.15, 0), Vector3(0.18, 0.18, 0.18), skin)
	# Feathered headdress
	_add_part("Feather1", BoxMesh.new(), Vector3(-0.08, 1.38, -0.02), Vector3(0.03, 0.15, 0.02), accent)
	_add_part("Feather2", BoxMesh.new(), Vector3(0.0, 1.4, -0.02), Vector3(0.03, 0.18, 0.02), Color(0.2, 0.7, 0.3))
	_add_part("Feather3", BoxMesh.new(), Vector3(0.08, 1.38, -0.02), Vector3(0.03, 0.15, 0.02), accent)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.18, 0.14), Vector3(0.03, 0.03, 0.03), Color(0.2, 1.0, 0.3))
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.18, 0.14), Vector3(0.03, 0.03, 0.03), Color(0.2, 1.0, 0.3))
	_store_rest_rotations()


# ---------- GOLEM ----------
func build_enemy_golem() -> void:
	_clear()
	var stone := Color(0.5, 0.48, 0.44)
	var dark_stone := Color(0.35, 0.33, 0.3)
	var rune := Color(0.2, 0.6, 1.0)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.2, 0.65, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", BoxMesh.new(), Vector3(0, -0.32, 0), Vector3(0.2, 0.35, 0.2), stone))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.2, 0.65, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", BoxMesh.new(), Vector3(0, -0.32, 0), Vector3(0.2, 0.35, 0.2), stone))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 1.0, 0), Vector3(0.6, 0.55, 0.4), stone)
	_add_part("Belly", BoxMesh.new(), Vector3(0, 0.7, 0), Vector3(0.45, 0.2, 0.35), dark_stone)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.42, 1.1, 0)
	left_arm_pivot.rotation.x = 0.25
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", BoxMesh.new(), Vector3(0, -0.3, 0), Vector3(0.18, 0.35, 0.18), stone))
	left_arm_pivot.add_child(_create_part("LeftFist", SphereMesh.new(), Vector3(0, -0.55, 0), Vector3(0.2, 0.2, 0.2), dark_stone))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.42, 1.1, 0)
	right_arm_pivot.rotation.x = 0.25
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", BoxMesh.new(), Vector3(0, -0.3, 0), Vector3(0.18, 0.35, 0.18), stone))
	right_arm_pivot.add_child(_create_part("RightFist", SphereMesh.new(), Vector3(0, -0.55, 0), Vector3(0.2, 0.2, 0.2), dark_stone))

	_add_part("Head", BoxMesh.new(), Vector3(0, 1.4, 0), Vector3(0.3, 0.25, 0.25), stone)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.08, 1.43, 0.2), Vector3(0.05, 0.04, 0.04), rune)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.08, 1.43, 0.2), Vector3(0.05, 0.04, 0.04), rune)
	_add_emissive_part("ChestRune", SphereMesh.new(), Vector3(0, 1.0, 0.21), Vector3(0.1, 0.1, 0.04), rune)
	_store_rest_rotations()


# ---------- SCARAB ----------
func build_enemy_scarab() -> void:
	_clear()
	var shell := Color(0.15, 0.2, 0.25)
	var leg_c := Color(0.3, 0.25, 0.2)
	var eye_c := Color(1.0, 0.6, 0.0)

	# Armored shell body
	_add_part("Shell", SphereMesh.new(), Vector3(0, 0.3, 0), Vector3(0.4, 0.2, 0.5), shell)
	_add_part("Head", SphereMesh.new(), Vector3(0, 0.3, 0.3), Vector3(0.2, 0.15, 0.15), shell)
	_add_part("LeftMandible", BoxMesh.new(), Vector3(-0.1, 0.22, 0.42), Vector3(0.04, 0.03, 0.1), leg_c)
	_add_part("RightMandible", BoxMesh.new(), Vector3(0.1, 0.22, 0.42), Vector3(0.04, 0.03, 0.1), leg_c)

	# Front legs as arm pivots
	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.22, 0.25, 0.12)
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("FL1", CylinderMesh.new(), Vector3(-0.12, -0.08, 0.05), Vector3(0.04, 0.18, 0.04), leg_c))
	left_arm_pivot.add_child(_create_part("FL2", CylinderMesh.new(), Vector3(-0.06, -0.08, -0.1), Vector3(0.04, 0.18, 0.04), leg_c))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.22, 0.25, 0.12)
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("FR1", CylinderMesh.new(), Vector3(0.12, -0.08, 0.05), Vector3(0.04, 0.18, 0.04), leg_c))
	right_arm_pivot.add_child(_create_part("FR2", CylinderMesh.new(), Vector3(0.06, -0.08, -0.1), Vector3(0.04, 0.18, 0.04), leg_c))

	# Back legs as leg pivots
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.22, 0.25, -0.15)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("BL1", CylinderMesh.new(), Vector3(-0.12, -0.08, -0.05), Vector3(0.04, 0.18, 0.04), leg_c))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.22, 0.25, -0.15)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("BR1", CylinderMesh.new(), Vector3(0.12, -0.08, -0.05), Vector3(0.04, 0.18, 0.04), leg_c))

	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 0.35, 0.38), Vector3(0.025, 0.025, 0.025), eye_c)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 0.35, 0.38), Vector3(0.025, 0.025, 0.025), eye_c)
	_store_rest_rotations()


# ---------- WRAITH ----------
func build_enemy_wraith() -> void:
	_clear()
	var cloak := Color(0.12, 0.1, 0.15)
	var glow := Color(0.4, 0.1, 0.8)

	# Floating tattered cloak body (no legs)
	_add_part("Cloak", CylinderMesh.new(), Vector3(0, 0.5, 0), Vector3(0.3, 0.5, 0.3), cloak)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.9, 0), Vector3(0.38, 0.32, 0.22), cloak)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.28, 0.95, 0)
	left_arm_pivot.rotation.x = 0.4
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.06, 0.24, 0.06), cloak))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.28, 0.95, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.22, 0), Vector3(0.06, 0.24, 0.06), cloak))
	# Scythe
	right_arm_pivot.add_child(_create_part("ScytheHandle", CylinderMesh.new(), Vector3(0.02, -0.5, 0), Vector3(0.03, 0.65, 0.03), Color(0.3, 0.25, 0.2)))
	right_arm_pivot.add_child(_create_part("ScytheBlade", BoxMesh.new(), Vector3(0.15, 0.15, 0), Vector3(0.25, 0.04, 0.06), Color(0.6, 0.6, 0.65)))

	_add_part("Hood", SphereMesh.new(), Vector3(0, 1.15, -0.02), Vector3(0.22, 0.2, 0.22), cloak)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.15, 0.15), Vector3(0.04, 0.05, 0.04), glow)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.15, 0.15), Vector3(0.04, 0.05, 0.04), glow)
	_add_emissive_part("Aura", SphereMesh.new(), Vector3(0, 0.7, 0), Vector3(0.45, 0.65, 0.45), Color(0.3, 0.05, 0.5, 0.12))
	_store_rest_rotations()


# ---------- NECROMANCER ----------
func build_enemy_necromancer() -> void:
	_clear()
	var robe := Color(0.15, 0.1, 0.12)
	var skin := Color(0.55, 0.5, 0.45)
	var green_glow := Color(0.1, 0.9, 0.2)

	# Hidden leg pivots inside robe
	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.1, 0.35, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LL", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.1, 0.35, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RL", CylinderMesh.new(), Vector3(0, -0.15, 0), Vector3(0.01, 0.01, 0.01), robe))

	_add_part("Robe", CylinderMesh.new(), Vector3(0, 0.48, 0), Vector3(0.3, 0.48, 0.3), robe)
	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.9, 0), Vector3(0.38, 0.32, 0.25), robe)
	_add_part("SkullBelt", SphereMesh.new(), Vector3(0.15, 0.7, 0.12), Vector3(0.06, 0.06, 0.06), Color(0.9, 0.88, 0.8))

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.26, 0.95, 0)
	left_arm_pivot.rotation.x = 0.5
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.06, 0.22, 0.06), skin))
	left_arm_pivot.add_child(_create_emissive_part("LeftHandGlow", SphereMesh.new(), Vector3(0, -0.4, 0), Vector3(0.08, 0.08, 0.08), green_glow))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.26, 0.95, 0)
	right_arm_pivot.rotation.x = 0.2
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.2, 0), Vector3(0.06, 0.22, 0.06), skin))
	right_arm_pivot.add_child(_create_part("SkullStaff", CylinderMesh.new(), Vector3(0.02, -0.35, 0), Vector3(0.04, 0.7, 0.04), Color(0.2, 0.15, 0.1)))
	right_arm_pivot.add_child(_create_part("StaffSkull", SphereMesh.new(), Vector3(0.02, 0.32, 0), Vector3(0.1, 0.1, 0.1), Color(0.9, 0.88, 0.8)))
	right_arm_pivot.add_child(_create_emissive_part("StaffGlow", SphereMesh.new(), Vector3(0.02, 0.32, 0), Vector3(0.14, 0.14, 0.14), Color(0.1, 0.8, 0.2, 0.5)))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.2, 0), Vector3(0.18, 0.18, 0.18), skin)
	_add_part("Hood", SphereMesh.new(), Vector3(0, 1.25, -0.02), Vector3(0.22, 0.18, 0.22), robe)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.05, 1.23, 0.14), Vector3(0.035, 0.035, 0.035), green_glow)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.05, 1.23, 0.14), Vector3(0.035, 0.035, 0.035), green_glow)
	_store_rest_rotations()


# ---------- DEMON ----------
func build_enemy_demon() -> void:
	_clear()
	var skin := Color(0.7, 0.15, 0.1)
	var dark := Color(0.3, 0.08, 0.05)
	var fire := Color(1.0, 0.5, 0.0)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.18, 0.55, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14), dark))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.18, 0.55, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14), dark))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 0.85, 0), Vector3(0.5, 0.45, 0.35), skin)
	_add_part("Abs", BoxMesh.new(), Vector3(0, 0.6, 0.05), Vector3(0.3, 0.12, 0.2), dark)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.35, 1.0, 0)
	left_arm_pivot.rotation.x = 0.3
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.12, 0.28, 0.12), skin))
	left_arm_pivot.add_child(_create_part("LeftClaw", BoxMesh.new(), Vector3(0, -0.5, 0.04), Vector3(0.1, 0.08, 0.06), dark))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.35, 1.0, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.25, 0), Vector3(0.12, 0.28, 0.12), skin))
	right_arm_pivot.add_child(_create_part("RightClaw", BoxMesh.new(), Vector3(0, -0.5, 0.04), Vector3(0.1, 0.08, 0.06), dark))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.2, 0), Vector3(0.22, 0.2, 0.2), skin)
	_add_part("LeftHorn", CylinderMesh.new(), Vector3(-0.14, 1.42, -0.02), Vector3(0.05, 0.18, 0.05), dark)
	_add_part("RightHorn", CylinderMesh.new(), Vector3(0.14, 1.42, -0.02), Vector3(0.05, 0.18, 0.05), dark)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.06, 1.23, 0.16), Vector3(0.04, 0.04, 0.04), fire)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.06, 1.23, 0.16), Vector3(0.04, 0.04, 0.04), fire)
	_store_rest_rotations()


# ---------- BOSS_GOLEM ----------
func build_enemy_boss_golem() -> void:
	_clear()
	var stone := Color(0.45, 0.42, 0.38)
	var dark := Color(0.3, 0.28, 0.25)
	var crystal := Color(0.1, 0.5, 1.0)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.3, 0.8, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", BoxMesh.new(), Vector3(0, -0.4, 0), Vector3(0.28, 0.45, 0.28), stone))
	left_leg_pivot.add_child(_create_part("LeftKnee", SphereMesh.new(), Vector3(0, -0.2, 0.08), Vector3(0.15, 0.12, 0.12), dark))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.3, 0.8, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", BoxMesh.new(), Vector3(0, -0.4, 0), Vector3(0.28, 0.45, 0.28), stone))
	right_leg_pivot.add_child(_create_part("RightKnee", SphereMesh.new(), Vector3(0, -0.2, 0.08), Vector3(0.15, 0.12, 0.12), dark))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 1.25, 0), Vector3(0.8, 0.65, 0.55), stone)
	_add_part("Belly", BoxMesh.new(), Vector3(0, 0.85, 0), Vector3(0.6, 0.25, 0.45), dark)
	# Crystal core
	_add_emissive_part("Core", SphereMesh.new(), Vector3(0, 1.25, 0.28), Vector3(0.18, 0.18, 0.1), crystal)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.55, 1.35, 0)
	left_arm_pivot.rotation.x = 0.2
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", BoxMesh.new(), Vector3(0, -0.35, 0), Vector3(0.25, 0.4, 0.25), stone))
	left_arm_pivot.add_child(_create_part("LeftFist", SphereMesh.new(), Vector3(0, -0.65, 0), Vector3(0.28, 0.28, 0.28), dark))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.55, 1.35, 0)
	right_arm_pivot.rotation.x = 0.2
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", BoxMesh.new(), Vector3(0, -0.35, 0), Vector3(0.25, 0.4, 0.25), stone))
	right_arm_pivot.add_child(_create_part("RightFist", SphereMesh.new(), Vector3(0, -0.65, 0), Vector3(0.28, 0.28, 0.28), dark))

	_add_part("Head", BoxMesh.new(), Vector3(0, 1.7, 0), Vector3(0.35, 0.3, 0.3), stone)
	_add_part("Brow", BoxMesh.new(), Vector3(0, 1.78, 0.16), Vector3(0.38, 0.06, 0.08), dark)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.1, 1.72, 0.24), Vector3(0.06, 0.05, 0.05), crystal)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.1, 1.72, 0.24), Vector3(0.06, 0.05, 0.05), crystal)
	# Rune markings
	_add_emissive_part("RuneL", BoxMesh.new(), Vector3(-0.3, 1.2, 0.28), Vector3(0.04, 0.2, 0.02), crystal)
	_add_emissive_part("RuneR", BoxMesh.new(), Vector3(0.3, 1.2, 0.28), Vector3(0.04, 0.2, 0.02), crystal)
	scale = Vector3(1.8, 1.8, 1.8)
	_store_rest_rotations()


# ---------- BOSS_DEMON ----------
func build_enemy_boss_demon() -> void:
	_clear()
	var skin := Color(0.6, 0.08, 0.05)
	var dark := Color(0.25, 0.05, 0.02)
	var fire := Color(1.0, 0.4, 0.0)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.22, 0.65, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.32, 0), Vector3(0.16, 0.35, 0.16), dark))
	left_leg_pivot.add_child(_create_part("LeftHoof", BoxMesh.new(), Vector3(0, -0.58, 0.04), Vector3(0.14, 0.08, 0.18), dark))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.22, 0.65, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.32, 0), Vector3(0.16, 0.35, 0.16), dark))
	right_leg_pivot.add_child(_create_part("RightHoof", BoxMesh.new(), Vector3(0, -0.58, 0.04), Vector3(0.14, 0.08, 0.18), dark))

	_add_part("Torso", BoxMesh.new(), Vector3(0, 1.0, 0), Vector3(0.6, 0.5, 0.4), skin)
	_add_part("Abs", BoxMesh.new(), Vector3(0, 0.72, 0.06), Vector3(0.38, 0.15, 0.25), dark)
	# Wings (decorative flat planes)
	_add_part("LeftWing", BoxMesh.new(), Vector3(-0.5, 1.3, -0.2), Vector3(0.6, 0.5, 0.04), dark)
	_add_part("RightWing", BoxMesh.new(), Vector3(0.5, 1.3, -0.2), Vector3(0.6, 0.5, 0.04), dark)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.42, 1.15, 0)
	left_arm_pivot.rotation.x = 0.3
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.3, 0), Vector3(0.14, 0.32, 0.14), skin))
	left_arm_pivot.add_child(_create_part("LeftClaw", BoxMesh.new(), Vector3(0, -0.58, 0.05), Vector3(0.12, 0.1, 0.08), dark))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.42, 1.15, 0)
	right_arm_pivot.rotation.x = 0.3
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.3, 0), Vector3(0.14, 0.32, 0.14), skin))
	right_arm_pivot.add_child(_create_part("RightClaw", BoxMesh.new(), Vector3(0, -0.58, 0.05), Vector3(0.12, 0.1, 0.08), dark))
	# Fiery sword
	right_arm_pivot.add_child(_create_emissive_part("FlameBlade", BoxMesh.new(), Vector3(0.02, -0.85, 0), Vector3(0.08, 0.5, 0.04), fire))

	_add_part("Head", SphereMesh.new(), Vector3(0, 1.4, 0), Vector3(0.25, 0.22, 0.22), skin)
	_add_part("LeftHorn", CylinderMesh.new(), Vector3(-0.18, 1.65, -0.04), Vector3(0.06, 0.25, 0.06), dark)
	_add_part("RightHorn", CylinderMesh.new(), Vector3(0.18, 1.65, -0.04), Vector3(0.06, 0.25, 0.06), dark)
	_add_part("Crown", BoxMesh.new(), Vector3(0, 1.55, 0), Vector3(0.28, 0.04, 0.28), dark)
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.07, 1.43, 0.18), Vector3(0.05, 0.05, 0.05), fire)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.07, 1.43, 0.18), Vector3(0.05, 0.05, 0.05), fire)
	_add_emissive_part("ChestFire", SphereMesh.new(), Vector3(0, 1.0, 0.21), Vector3(0.12, 0.12, 0.06), fire)
	scale = Vector3(2.0, 2.0, 2.0)
	_store_rest_rotations()


# ---------- BOSS_DRAGON ----------
func build_enemy_boss_dragon() -> void:
	_clear()
	var scale_c := Color(0.2, 0.35, 0.25)
	var belly := Color(0.55, 0.5, 0.35)
	var fire := Color(1.0, 0.4, 0.0)

	left_leg_pivot = Node3D.new()
	left_leg_pivot.name = "LeftLegPivot"
	left_leg_pivot.position = Vector3(-0.25, 0.7, 0)
	add_child(left_leg_pivot)
	left_leg_pivot.add_child(_create_part("LeftLeg", CylinderMesh.new(), Vector3(0, -0.35, 0), Vector3(0.18, 0.38, 0.18), scale_c))
	left_leg_pivot.add_child(_create_part("LeftFoot", BoxMesh.new(), Vector3(0, -0.62, 0.06), Vector3(0.16, 0.08, 0.22), scale_c))

	right_leg_pivot = Node3D.new()
	right_leg_pivot.name = "RightLegPivot"
	right_leg_pivot.position = Vector3(0.25, 0.7, 0)
	add_child(right_leg_pivot)
	right_leg_pivot.add_child(_create_part("RightLeg", CylinderMesh.new(), Vector3(0, -0.35, 0), Vector3(0.18, 0.38, 0.18), scale_c))
	right_leg_pivot.add_child(_create_part("RightFoot", BoxMesh.new(), Vector3(0, -0.62, 0.06), Vector3(0.16, 0.08, 0.22), scale_c))

	# Massive body
	_add_part("Body", BoxMesh.new(), Vector3(0, 1.1, 0), Vector3(0.7, 0.55, 0.5), scale_c)
	_add_part("Belly", BoxMesh.new(), Vector3(0, 0.85, 0.08), Vector3(0.5, 0.25, 0.35), belly)
	# Tail
	_add_part("Tail1", CylinderMesh.new(), Vector3(0, 0.8, -0.45), Vector3(0.15, 0.2, 0.15), scale_c)
	_add_part("Tail2", CylinderMesh.new(), Vector3(0, 0.7, -0.7), Vector3(0.1, 0.18, 0.1), scale_c)
	_add_part("TailTip", SphereMesh.new(), Vector3(0, 0.6, -0.9), Vector3(0.12, 0.08, 0.08), scale_c)
	# Wings
	_add_part("LeftWing", BoxMesh.new(), Vector3(-0.6, 1.4, -0.15), Vector3(0.7, 0.45, 0.04), scale_c)
	_add_part("RightWing", BoxMesh.new(), Vector3(0.6, 1.4, -0.15), Vector3(0.7, 0.45, 0.04), scale_c)

	left_arm_pivot = Node3D.new()
	left_arm_pivot.name = "LeftArmPivot"
	left_arm_pivot.position = Vector3(-0.45, 1.2, 0)
	left_arm_pivot.rotation.x = 0.35
	add_child(left_arm_pivot)
	left_arm_pivot.add_child(_create_part("LeftArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14), scale_c))
	left_arm_pivot.add_child(_create_part("LeftClaw", BoxMesh.new(), Vector3(0, -0.52, 0.05), Vector3(0.12, 0.08, 0.1), scale_c))

	right_arm_pivot = Node3D.new()
	right_arm_pivot.name = "RightArmPivot"
	right_arm_pivot.position = Vector3(0.45, 1.2, 0)
	right_arm_pivot.rotation.x = 0.35
	add_child(right_arm_pivot)
	right_arm_pivot.add_child(_create_part("RightArm", CylinderMesh.new(), Vector3(0, -0.28, 0), Vector3(0.14, 0.3, 0.14), scale_c))
	right_arm_pivot.add_child(_create_part("RightClaw", BoxMesh.new(), Vector3(0, -0.52, 0.05), Vector3(0.12, 0.08, 0.1), scale_c))

	# Long neck + head
	_add_part("Neck", CylinderMesh.new(), Vector3(0, 1.5, 0.2), Vector3(0.15, 0.25, 0.15), scale_c)
	_add_part("Head", BoxMesh.new(), Vector3(0, 1.7, 0.35), Vector3(0.25, 0.2, 0.35), scale_c)
	_add_part("Snout", BoxMesh.new(), Vector3(0, 1.65, 0.6), Vector3(0.18, 0.12, 0.2), scale_c)
	_add_part("Jaw", BoxMesh.new(), Vector3(0, 1.6, 0.55), Vector3(0.16, 0.06, 0.18), belly)
	# Horns
	_add_part("LeftHorn", CylinderMesh.new(), Vector3(-0.12, 1.88, 0.25), Vector3(0.04, 0.15, 0.04), belly)
	_add_part("RightHorn", CylinderMesh.new(), Vector3(0.12, 1.88, 0.25), Vector3(0.04, 0.15, 0.04), belly)
	# Spines down back
	_add_part("Spine1", BoxMesh.new(), Vector3(0, 1.42, -0.22), Vector3(0.04, 0.12, 0.04), belly)
	_add_part("Spine2", BoxMesh.new(), Vector3(0, 1.3, -0.3), Vector3(0.04, 0.1, 0.04), belly)
	_add_part("Spine3", BoxMesh.new(), Vector3(0, 1.15, -0.38), Vector3(0.04, 0.08, 0.04), belly)
	# Eyes
	_add_emissive_part("LeftEye", SphereMesh.new(), Vector3(-0.08, 1.75, 0.52), Vector3(0.05, 0.05, 0.05), fire)
	_add_emissive_part("RightEye", SphereMesh.new(), Vector3(0.08, 1.75, 0.52), Vector3(0.05, 0.05, 0.05), fire)
	_add_emissive_part("MouthGlow", SphereMesh.new(), Vector3(0, 1.62, 0.65), Vector3(0.08, 0.06, 0.06), fire)
	scale = Vector3(2.2, 2.2, 2.2)
	_store_rest_rotations()


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
	left_arm_pivot = null
	right_leg_pivot = null
	left_leg_pivot = null
	_is_walking = false
	_anim_time = 0.0
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
