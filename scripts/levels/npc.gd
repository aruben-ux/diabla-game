extends StaticBody3D

## Town NPC that players can click to talk to.
## Uses the same interactable interface as the fountain.

var display_name: String = tr("Villager")
var interact_hint: String = tr("Click to talk")
var dialog_lines: Array = ["..."]
var npc_id: String = ""
var vendor_stock: Array = []  # Array of item dicts — if non-empty, NPC is a vendor
var vendor_type: String = ""  # "potions", "weapons", "armor", "jewelry", "general"

# Visual
var _model: Node3D
var _name_label: Label3D


func setup(data: Dictionary) -> void:
	npc_id = data.get("id", "")
	display_name = data.get("name", tr("Villager"))
	dialog_lines = data.get("dialog", ["..."])
	vendor_stock = data.get("shop", [])
	vendor_type = data.get("vendor_type", "")
	interact_hint = tr("Click to shop") if vendor_stock.size() > 0 else tr("Click to talk")

	name = "NPC_%s" % npc_id
	collision_layer = 128 | 1  # layer 8 (interactable) + layer 1 (physical)
	collision_mask = 0
	add_to_group("interactables")
	add_to_group("npcs")

	# Collision shape
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

	# Build visual model
	_build_model(data.get("appearance", {}))

	# Floating name label
	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.position = Vector3(0, 2.4, 0)
	_name_label.pixel_size = 0.01
	_name_label.font_size = 32
	_name_label.modulate = Color(0.9, 0.85, 0.6)
	_name_label.outline_modulate = Color(0, 0, 0)
	_name_label.outline_size = 6
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_name_label)


func interact(player: Node) -> void:
	if not player:
		return
	# Check if this NPC has quests to offer or turn in
	var has_quests := false
	if QuestManager.get_available_quests(npc_id).size() > 0:
		has_quests = true
	if QuestManager.get_turn_in_quests(npc_id).size() > 0:
		has_quests = true

	if has_quests:
		EventBus.quest_dialog_requested.emit(npc_id)
	elif vendor_stock.size() > 0:
		EventBus.shop_opened.emit(display_name, vendor_stock, vendor_type)
	else:
		EventBus.npc_dialog_opened.emit(display_name, dialog_lines)


func _build_model(appearance: Dictionary) -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var body_color: Color = Color(appearance.get("body_color", "#8B7355"))
	var shirt_color: Color = Color(appearance.get("shirt_color", "#4A6741"))
	var pants_color: Color = Color(appearance.get("pants_color", "#3D3020"))
	var hair_color: Color = Color(appearance.get("hair_color", "#5C3317"))
	var skin_color: Color = Color(appearance.get("skin_color", "#D2A679"))

	# Body / torso
	var torso := _make_part(BoxMesh.new(), Vector3(0.5, 0.6, 0.3),
		Vector3(0, 1.15, 0), shirt_color)

	# Head
	var head := _make_part(BoxMesh.new(), Vector3(0.3, 0.35, 0.3),
		Vector3(0, 1.7, 0), skin_color)

	# Hair
	var hair := _make_part(BoxMesh.new(), Vector3(0.32, 0.15, 0.32),
		Vector3(0, 1.95, 0), hair_color)

	# Legs
	var leg_l := _make_part(BoxMesh.new(), Vector3(0.18, 0.5, 0.22),
		Vector3(-0.12, 0.5, 0), pants_color)
	var leg_r := _make_part(BoxMesh.new(), Vector3(0.18, 0.5, 0.22),
		Vector3(0.12, 0.5, 0), pants_color)

	# Arms
	var arm_l := _make_part(BoxMesh.new(), Vector3(0.15, 0.5, 0.18),
		Vector3(-0.35, 1.1, 0), shirt_color)
	var arm_r := _make_part(BoxMesh.new(), Vector3(0.15, 0.5, 0.18),
		Vector3(0.35, 1.1, 0), shirt_color)

	# Hands
	_make_part(SphereMesh.new(), Vector3(0.08, 0.08, 0.08),
		Vector3(-0.35, 0.8, 0), skin_color)
	_make_part(SphereMesh.new(), Vector3(0.08, 0.08, 0.08),
		Vector3(0.35, 0.8, 0), skin_color)

	# Eyes (small dark spheres)
	_make_part(SphereMesh.new(), Vector3(0.04, 0.04, 0.04),
		Vector3(-0.08, 1.72, 0.14), Color(0.15, 0.1, 0.05))
	_make_part(SphereMesh.new(), Vector3(0.04, 0.04, 0.04),
		Vector3(0.08, 1.72, 0.14), Color(0.15, 0.1, 0.05))


func _make_part(mesh: Mesh, scale: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = scale
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	_model.add_child(mi)
	return mi
