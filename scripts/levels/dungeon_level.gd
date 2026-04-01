extends Node3D

## Dungeon level controller: generates the dungeon, spawns enemies,
## and places point lights in rooms for atmosphere.
## Supports multiple floors with stairs up/down.

signal level_ready(spawn_position: Vector3, stairs_up_pos: Vector3, stairs_down_pos: Vector3)
signal go_up(body: Node3D)
signal go_down(body: Node3D)

@onready var generator = $DungeonGenerator
@onready var enemy_spawner = $DungeonEnemySpawner
@onready var light_container: Node3D = $PointLightContainer

var spawn_position := Vector3.ZERO
var stairs_up_position := Vector3.ZERO
var stairs_down_position := Vector3.ZERO
var current_floor := 1
var _stairs_up_area: Node3D
var _stairs_down_area: Node3D
var _stair_props_container: Node3D
var _particles_node: GPUParticles3D
var _chest_container: Node3D
var _flicker_time := 0.0
var _boss_room_idx := -1
var _stairs_down_locked := false
var _props_container: Node3D


func _process(delta: float) -> void:
	# Animate torch / brazier lights — subtle flicker
	_flicker_time += delta
	_flicker_lights(light_container)
	if _props_container and is_instance_valid(_props_container):
		_flicker_lights(_props_container)


func _flicker_lights(container: Node3D) -> void:
	for torch_node in container.get_children():
		var tl := torch_node.get_node_or_null("TorchLight") as OmniLight3D
		if tl:
			var offset: float = torch_node.position.x * 3.7 + torch_node.position.z * 7.3
			var flicker: float = sin(_flicker_time * 8.0 + offset) * 0.08 + sin(_flicker_time * 13.0 + offset * 2.0) * 0.05
			tl.light_energy = 0.8 + flicker


func _ready() -> void:
	generator.dungeon_generated.connect(_on_dungeon_generated)


func start_generation(floor_num: int = 1, gen_seed: int = 0) -> void:
	## Generate (or regenerate) the dungeon for a given floor.
	current_floor = floor_num

	# Clear previous floor
	_cleanup_floor()
	generator.reset()

	# Set the seed so all peers generate the same layout
	if gen_seed != 0:
		generator.dungeon_seed = gen_seed

	# Boss floors every 5 levels (5, 10, 15, ...)
	generator.is_boss_floor = (floor_num >= 5 and floor_num % 5 == 0)

	generator.generate.call_deferred()


func _cleanup_floor() -> void:
	_boss_room_idx = -1
	_stairs_down_locked = false
	# Remove stair triggers
	if _stairs_up_area and is_instance_valid(_stairs_up_area):
		_stairs_up_area.queue_free()
		_stairs_up_area = null
	if _stairs_down_area and is_instance_valid(_stairs_down_area):
		_stairs_down_area.queue_free()
		_stairs_down_area = null
	if _stair_props_container and is_instance_valid(_stair_props_container):
		_stair_props_container.queue_free()
		_stair_props_container = null
	if _particles_node and is_instance_valid(_particles_node):
		_particles_node.queue_free()
		_particles_node = null
		_stair_props_container = null
	if _chest_container and is_instance_valid(_chest_container):
		_chest_container.queue_free()
		_chest_container = null
	if _props_container and is_instance_valid(_props_container):
		_props_container.queue_free()
		_props_container = null

	# Clear lights
	for child in light_container.get_children():
		child.queue_free()

	# Clear spawned enemies
	for child in enemy_spawner.get_children():
		child.queue_free()


func _on_dungeon_generated(room_list: Array, spawn_pos: Vector3, stairs_up: Vector3, stairs_down: Vector3, boss_room_idx: int) -> void:
	spawn_position = spawn_pos
	stairs_up_position = stairs_up
	stairs_down_position = stairs_down
	_boss_room_idx = boss_room_idx

	# Setup enemy spawner with room data + floor scaling + boss room
	var typed_rooms: Array[Rect2i] = []
	for r in room_list:
		typed_rooms.append(r as Rect2i)
	enemy_spawner.setup(typed_rooms, generator.get_room_centers(), generator.TILE_SIZE, current_floor, boss_room_idx)

	# Connect boss_died signal if this is a boss floor
	if boss_room_idx >= 0:
		_stairs_down_locked = true
		if not enemy_spawner.boss_died.is_connected(_on_boss_died):
			enemy_spawner.boss_died.connect(_on_boss_died)

	# Place lights in rooms
	_place_room_lights(room_list)

	# Setup dungeon atmosphere (fog, ambient)
	_setup_dungeon_environment()

	# Floating dust / ember particles
	_add_ambient_particles()

	# Create stair triggers and visuals
	_stair_props_container = Node3D.new()
	_stair_props_container.name = "StairProps"
	add_child(_stair_props_container)

	_create_stairs_trigger(stairs_up, true)
	_create_stairs_trigger(stairs_down, false)

	# Spawn treasure chests in some rooms
	_spawn_treasure_chests(room_list)

	# Scatter decorative props and breakable objects
	_spawn_dungeon_props(room_list)

	level_ready.emit(spawn_position, stairs_up_position, stairs_down_position)


func _spawn_treasure_chests(room_list: Array) -> void:
	_chest_container = Node3D.new()
	_chest_container.name = "ChestContainer"
	add_child(_chest_container)

	# Use a LOCAL RNG seeded from the dungeon seed so chest placement is
	# identical on server and client, regardless of global RNG divergence
	# caused by enemy spawning or other setup consuming random calls.
	var rng := RandomNumberGenerator.new()
	rng.seed = generator.dungeon_seed + 99991

	var tile_size: float = generator.TILE_SIZE
	var chest_idx := 0

	# Skip first room (spawn) and last room (stairs down) — place chests in others
	for i in range(1, room_list.size() - 1):
		# ~50% chance per room to have a chest
		if rng.randf() > 0.5:
			continue
		var room: Rect2i = room_list[i]
		# Place chest near a wall inside the room
		var cx := (room.position.x + rng.randi_range(1, room.size.x - 2)) * tile_size
		var cz := (room.position.y + rng.randi_range(1, room.size.y - 2)) * tile_size
		chest_idx += 1
		_build_chest(Vector3(cx, 0.0, cz), "Chest_%d" % chest_idx)


func _build_chest(pos: Vector3, chest_name: String) -> void:
	var chest_script := preload("res://scripts/loot/treasure_chest.gd")

	var body := StaticBody3D.new()
	body.name = chest_name
	body.position = pos
	body.collision_layer = 128 | 1  # layer 8 (interactable) + layer 1 (physical)
	body.collision_mask = 0
	body.add_to_group("interactables")
	body.set_script(chest_script)
	body.setup(current_floor)

	# Collision shape
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.8, 0.8)
	col.shape = box
	col.position = Vector3(0, 0.4, 0)
	body.add_child(col)

	# Chest body (base box)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.45, 0.28, 0.12)
	base_mat.roughness = 0.7

	var base_mi := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.0, 0.5, 0.7)
	base_mi.mesh = base_mesh
	base_mi.position = Vector3(0, 0.25, 0)
	base_mi.material_override = base_mat
	body.add_child(base_mi)

	# Metal trim band
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.6, 0.55, 0.3)
	trim_mat.metallic = 0.8
	trim_mat.roughness = 0.4

	var trim_mi := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(1.05, 0.08, 0.75)
	trim_mi.mesh = trim_mesh
	trim_mi.position = Vector3(0, 0.5, 0)
	trim_mi.material_override = trim_mat
	body.add_child(trim_mi)

	# Lid (opens on interact)
	var lid_mi := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.0, 0.15, 0.7)
	lid_mi.mesh = lid_mesh
	# Pivot at back edge: offset mesh forward, then position lid node at back
	lid_mi.position = Vector3(0, 0.075, 0.175)
	lid_mi.material_override = base_mat

	var lid_pivot := Node3D.new()
	lid_pivot.name = "LidPivot"
	lid_pivot.position = Vector3(0, 0.5, -0.35)
	body.add_child(lid_pivot)
	lid_pivot.add_child(lid_mi)
	body.set_lid(lid_pivot)

	# Lock / clasp
	var lock_mat := StandardMaterial3D.new()
	lock_mat.albedo_color = Color(0.7, 0.6, 0.2)
	lock_mat.metallic = 0.9
	lock_mat.roughness = 0.3

	var lock_mi := MeshInstance3D.new()
	var lock_mesh := BoxMesh.new()
	lock_mesh.size = Vector3(0.12, 0.12, 0.05)
	lock_mi.mesh = lock_mesh
	lock_mi.position = Vector3(0, 0.45, 0.36)
	lock_mi.material_override = lock_mat
	body.add_child(lock_mi)

	_chest_container.add_child(body)


# ---------------------------------------------------------------------------
# Dungeon Props — decorative and breakable objects
# ---------------------------------------------------------------------------

func _spawn_dungeon_props(room_list: Array) -> void:
	_props_container = Node3D.new()
	_props_container.name = "PropsContainer"
	add_child(_props_container)

	var rng := RandomNumberGenerator.new()
	rng.seed = generator.dungeon_seed + 77713
	var ts: float = generator.TILE_SIZE
	var prop_id := 0  # Deterministic counter for unique names (needed for RPCs)

	# Place room props (skip first room = spawn and last room = stairs down)
	for i in range(1, room_list.size() - 1):
		var room: Rect2i = room_list[i]
		prop_id = _place_room_props(room, rng, ts, prop_id)

	# Scatter some props in corridors
	_place_corridor_props(rng, ts)


func _place_room_props(room: Rect2i, rng: RandomNumberGenerator, ts: float, prop_id: int) -> int:
	# Skip tiny rooms
	if room.size.x < 4 or room.size.y < 4:
		return prop_id

	var min_x := room.position.x + 1
	var max_x := room.position.x + room.size.x - 2
	var min_y := room.position.y + 1
	var max_y := room.position.y + room.size.y - 2

	# Pot cluster (40%)
	if rng.randf() < 0.4:
		var cx := float(rng.randi_range(min_x, max_x)) * ts
		var cz := float(rng.randi_range(min_y, max_y)) * ts
		var pot_count := rng.randi_range(2, 4)
		for j in range(pot_count):
			var offset := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			var scale_f := rng.randf_range(0.7, 1.2)
			var drops := rng.randf() < 0.3
			var gold := rng.randi_range(5, 15) * current_floor if drops else 0
			prop_id += 1
			var pot := DungeonProps.build_breakable_pot(
				Vector3(cx, 0, cz) + offset, current_floor, drops, gold, scale_f
			)
			pot.name = "Pot_%d" % prop_id
			_props_container.add_child(pot)

	# Barrel group (30%)
	if rng.randf() < 0.3:
		var bx := float(rng.randi_range(min_x, max_x)) * ts
		var bz := float(rng.randi_range(min_y, max_y)) * ts
		var barrel_count := rng.randi_range(1, 3)
		for j in range(barrel_count):
			var offset := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
			var intact := rng.randf() > 0.3
			prop_id += 1
			var barrel_name := "Barrel_%d" % prop_id if intact else ""
			var barrel := DungeonProps.build_barrel(Vector3(bx, 0, bz) + offset, rng, intact, barrel_name, current_floor)
			_props_container.add_child(barrel)

	# Brazier (15%, larger rooms only)
	if rng.randf() < 0.15 and room.size.x >= 6 and room.size.y >= 6:
		var bcx := (float(room.position.x) + float(room.size.x) * 0.5) * ts
		var bcz := (float(room.position.y) + float(room.size.y) * 0.5) * ts
		bcx += rng.randf_range(-2.0, 2.0)
		bcz += rng.randf_range(-2.0, 2.0)
		_props_container.add_child(DungeonProps.build_brazier(Vector3(bcx, 0, bcz)))

	# Bone pile (25%)
	if rng.randf() < 0.25:
		var bpx := float(rng.randi_range(min_x, max_x)) * ts
		var bpz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_bone_pile(Vector3(bpx, 0, bpz), rng))

	# Broken pillar (20%, medium+ rooms)
	if rng.randf() < 0.2 and room.size.x >= 5 and room.size.y >= 5:
		var ppx := float(rng.randi_range(min_x, max_x)) * ts
		var ppz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_broken_pillar(Vector3(ppx, 0, ppz), rng))

	# Blood stain (20%)
	if rng.randf() < 0.2:
		var bsx := float(rng.randi_range(min_x, max_x)) * ts
		var bsz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_blood_stain(Vector3(bsx, 0, bsz), rng))

	# Rubble pile (25%)
	if rng.randf() < 0.25:
		var rpx := float(rng.randi_range(min_x, max_x)) * ts
		var rpz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_rubble_pile(Vector3(rpx, 0, rpz), rng))

	# Skull pile (10%)
	if rng.randf() < 0.1:
		var spx := float(rng.randi_range(min_x, max_x)) * ts
		var spz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_skull_pile(Vector3(spx, 0, spz), rng))

	# Cobweb in corner (35%)
	if rng.randf() < 0.35:
		var corners: Array[Vector3] = [
			Vector3(float(room.position.x) * ts + 0.5, 3.0, float(room.position.y) * ts + 0.5),
			Vector3(float(room.position.x + room.size.x) * ts - 0.5, 3.0, float(room.position.y) * ts + 0.5),
			Vector3(float(room.position.x) * ts + 0.5, 3.0, float(room.position.y + room.size.y) * ts - 0.5),
			Vector3(float(room.position.x + room.size.x) * ts - 0.5, 3.0, float(room.position.y + room.size.y) * ts - 0.5),
		]
		_props_container.add_child(DungeonProps.build_cobweb(corners[rng.randi_range(0, 3)], rng))

	# Hanging chains (15%)
	if rng.randf() < 0.15:
		var hcx := float(rng.randi_range(min_x, max_x)) * ts
		var hcz := float(rng.randi_range(min_y, max_y)) * ts
		_props_container.add_child(DungeonProps.build_hanging_chains(Vector3(hcx, 0, hcz), rng))

	return prop_id


func _place_corridor_props(rng: RandomNumberGenerator, ts: float) -> void:
	var g: Array = generator.grid
	var gw: int = generator.dungeon_width
	var gh: int = generator.dungeon_height

	for x in range(0, gw, 3):
		for y in range(0, gh, 3):
			if g[x][y] != 3:  # 3 = corridor
				continue
			if rng.randf() > 0.08:  # ~8% of sampled corridor tiles
				continue

			var pos := Vector3(float(x) * ts, 0, float(y) * ts)
			var roll := rng.randf()
			if roll < 0.25:
				_props_container.add_child(DungeonProps.build_bone_pile(pos, rng))
			elif roll < 0.45:
				_props_container.add_child(DungeonProps.build_blood_stain(pos, rng))
			elif roll < 0.65:
				_props_container.add_child(DungeonProps.build_rubble_pile(pos, rng))
			elif roll < 0.8:
				_props_container.add_child(DungeonProps.build_cobweb(pos + Vector3(0, 3.2, 0), rng))
			else:
				_props_container.add_child(DungeonProps.build_skull_pile(pos, rng))


func _create_stairs_trigger(pos: Vector3, is_up: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 128  # Layer 8 = interactable
	body.collision_mask = 0
	body.name = ("StairsUp_F%d" % current_floor) if is_up else ("StairsDown_F%d" % current_floor)
	body.add_to_group("interactables")
	body.position = pos
	add_child(body)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 5.0)
	col.shape = box
	col.position = Vector3(0, 1.5, 0)
	body.add_child(col)

	# Set up interact properties and store reference to this dungeon_level
	var label_text: String
	if is_up:
		if current_floor == 1:
			label_text = tr("Return to Town")
		else:
			label_text = tr("Stairs Up (Floor %d)") % (current_floor - 1)
		_stairs_up_area = body
	else:
		if _stairs_down_locked:
			label_text = tr("BOSS GUARDS THIS PASSAGE")
		else:
			label_text = tr("Stairs Down (Floor %d)") % (current_floor + 1)
		_stairs_down_area = body

	body.set_meta("display_name", label_text)
	body.set_meta("interact_hint", tr("Click to use stairs"))
	body.set_meta("_dungeon_level", self)
	body.set_meta("_is_up", is_up)
	body.set_script(_stairs_interact_script())

	# Visual marker

	var label := Label3D.new()
	label.text = label_text
	label.position = pos + Vector3(0, 3.5, 0)
	label.pixel_size = 0.012
	label.font_size = 36
	label.modulate = Color(0.5, 1.0, 0.5) if is_up else Color(0.5, 0.5, 1.0)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stair_props_container.add_child(label)

	# Glowing pillar at stair location
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.2
	cyl.height = 3.0
	pillar.mesh = cyl
	pillar.position = pos + Vector3(0, 1.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.3, 0.6) if is_up else Color(0.3, 0.3, 0.8, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 0.2) if is_up else Color(0.2, 0.2, 0.8)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar.material_override = mat
	_stair_props_container.add_child(pillar)

	# Light
	var glow := OmniLight3D.new()
	glow.position = pos + Vector3(0, 2.0, 0)
	glow.omni_range = 6.0
	glow.light_energy = 1.2
	glow.light_color = Color(0.4, 0.9, 0.4) if is_up else Color(0.4, 0.4, 0.9)
	glow.shadow_enabled = false
	_stair_props_container.add_child(glow)


func _on_stairs_up_entered(_body: Node3D) -> void:
	pass  # Kept for compatibility — interaction is now click-based


func _on_stairs_down_entered(_body: Node3D) -> void:
	pass  # Kept for compatibility — interaction is now click-based


func _stairs_interact_script() -> GDScript:
	var src := """extends StaticBody3D
var display_name: String = ""
var interact_hint: String = ""
func _ready() -> void:
	display_name = get_meta("display_name") if has_meta("display_name") else tr("Stairs")
	interact_hint = get_meta("interact_hint") if has_meta("interact_hint") else tr("Click to use stairs")
func interact(player: Node) -> void:
	if not player or not is_instance_valid(player):
		return
	var dl = get_meta("_dungeon_level")
	if not dl or not is_instance_valid(dl):
		return
	var is_up_stair: bool = get_meta("_is_up")
	if is_up_stair:
		dl.go_up.emit(player)
	else:
		dl.go_down.emit(player)
"""
	var script := GDScript.new()
	script.source_code = src
	script.reload()
	return script


func _on_boss_died() -> void:
	_stairs_down_locked = false
	# Notify all peers that stairs are unlocked
	_sync_unlock_stairs.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_unlock_stairs() -> void:
	_stairs_down_locked = false
	# Update the stairs label to show they're now accessible
	if _stair_props_container:
		for child in _stair_props_container.get_children():
			if child is Label3D and "Stairs Down" in child.text:
				child.text = tr("Stairs Down (Floor %d)") % (current_floor + 1)
				child.modulate = Color(0.5, 0.5, 1.0)


func _place_room_lights(room_list: Array) -> void:
	for child in light_container.get_children():
		child.queue_free()

	for room in room_list:
		var r := room as Rect2i
		var cx: float = (r.position.x + r.size.x / 2.0) * generator.TILE_SIZE
		var cz: float = (r.position.y + r.size.y / 2.0) * generator.TILE_SIZE

		# Central room light — warm, shadows only on large rooms
		var light := OmniLight3D.new()
		light.omni_range = maxf(r.size.x, r.size.y) * generator.TILE_SIZE * 0.75
		light.light_energy = 3.0
		light.light_color = Color(1.0, 0.85, 0.6)
		var is_large := r.size.x >= 10 or r.size.y >= 10
		light.shadow_enabled = is_large
		if is_large:
			light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light_container.add_child(light)
		light.global_position = Vector3(cx, 3.5, cz)

		# Place wall torches around room perimeter
		_place_torches_in_room(r)

	# Place dim lights along corridors
	_place_corridor_lights()


func _place_corridor_lights() -> void:
	var g: Array = generator.grid
	var gw: int = generator.dungeon_width
	var gh: int = generator.dungeon_height
	var ts: float = generator.TILE_SIZE
	var spacing := 8  # Place a light every N corridor tiles
	var count := 0

	for x in range(0, gw, 2):  # Skip every other column for speed
		for y in range(0, gh, 2):
			if g[x][y] != 3:  # 3 = corridor
				continue
			if (x + y) % spacing != 0:
				continue
			var light := OmniLight3D.new()
			light.position = Vector3(x * ts, 2.5, y * ts)
			light.omni_range = 12.0
			light.light_energy = 2.0
			light.light_color = Color(0.8, 0.7, 0.55)
			light.shadow_enabled = false
			light_container.add_child(light)
			count += 1

	#print("[Dungeon] Placed %d corridor lights" % count)


func _place_torches_in_room(room: Rect2i) -> void:
	var ts: float = generator.TILE_SIZE
	var half_ts: float = ts / 2.0
	var spacing := 6
	var g: Array = generator.grid
	var gw: int = generator.dungeon_width
	var gh: int = generator.dungeon_height

	# North wall — wall tiles sit at grid y = room.position.y - 1
	for x in range(room.position.x + 2, room.position.x + room.size.x - 1, spacing):
		var wy := room.position.y - 1
		if wy >= 0 and wy < gh and x >= 0 and x < gw and g[x][wy] == 2:
			_create_torch(Vector3(x * ts, 2.4, room.position.y * ts - half_ts), 0.0)

	# South wall — wall tiles sit at grid y = room.position.y + room.size.y
	for x in range(room.position.x + 2, room.position.x + room.size.x - 1, spacing):
		var wy := room.position.y + room.size.y
		if wy >= 0 and wy < gh and x >= 0 and x < gw and g[x][wy] == 2:
			_create_torch(Vector3(x * ts, 2.4, (room.position.y + room.size.y) * ts - half_ts), PI)

	# West wall — wall tiles sit at grid x = room.position.x - 1
	for y in range(room.position.y + 2, room.position.y + room.size.y - 1, spacing):
		var wx := room.position.x - 1
		if wx >= 0 and wx < gw and y >= 0 and y < gh and g[wx][y] == 2:
			_create_torch(Vector3(room.position.x * ts - half_ts, 2.4, y * ts), -PI * 0.5)

	# East wall — wall tiles sit at grid x = room.position.x + room.size.x
	for y in range(room.position.y + 2, room.position.y + room.size.y - 1, spacing):
		var wx := room.position.x + room.size.x
		if wx >= 0 and wx < gw and y >= 0 and y < gh and g[wx][y] == 2:
			_create_torch(Vector3((room.position.x + room.size.x) * ts - half_ts, 2.4, y * ts), PI * 0.5)


func _create_torch(pos: Vector3, rot_y: float) -> void:
	var torch := Node3D.new()
	torch.position = pos
	torch.rotation.y = rot_y

	# Bracket (small box flush against wall)
	var bracket_mesh := MeshInstance3D.new()
	var bracket := BoxMesh.new()
	bracket.size = Vector3(0.15, 0.15, 0.1)
	bracket_mesh.mesh = bracket
	bracket_mesh.position = Vector3(0, 0, 0.05)
	var bracket_mat := StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.25, 0.2, 0.15)
	bracket_mesh.material_override = bracket_mat
	torch.add_child(bracket_mesh)

	# Stick (cylinder angled outward from wall)
	var stick_mesh := MeshInstance3D.new()
	var stick := CylinderMesh.new()
	stick.top_radius = 0.04
	stick.bottom_radius = 0.05
	stick.height = 0.55
	stick_mesh.mesh = stick
	stick_mesh.position = Vector3(0, 0.15, 0.35)
	stick_mesh.rotation.x = -0.4  # Tilt outward
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.35, 0.2, 0.1)
	stick_mesh.material_override = stick_mat
	torch.add_child(stick_mesh)

	# Flame particles
	var fire := GPUParticles3D.new()
	fire.position = Vector3(0, 0.45, 0.55)
	fire.amount = 12
	fire.lifetime = 0.6
	fire.explosiveness = 0.1
	fire.randomness = 0.4
	fire.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 15.0
	pmat.initial_velocity_min = 0.5
	pmat.initial_velocity_max = 1.0
	pmat.gravity = Vector3(0, 1.5, 0)
	pmat.scale_min = 0.06
	pmat.scale_max = 0.12
	pmat.color = Color(1.0, 0.6, 0.1)
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.1, 1.0))
	grad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	color_ramp.gradient = grad
	pmat.color_ramp = color_ramp
	fire.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.6, 0.1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.5, 0.0)
	fire_mat.emission_energy_multiplier = 3.0
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = fire_mat
	fire.draw_pass_1 = quad
	torch.add_child(fire)

	# Point light for torch (no shadows for performance)
	var torch_light := OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.position = Vector3(0, 0.5, 0.55)
	torch_light.omni_range = 7.0
	torch_light.light_energy = 1.0
	torch_light.light_color = Color(1.0, 0.75, 0.4)
	torch_light.shadow_enabled = false
	torch.add_child(torch_light)

	light_container.add_child(torch)


func _setup_dungeon_environment() -> void:
	pass  # Environment now managed centrally by MainGame


func _add_ambient_particles() -> void:
	# Remove previous particles
	if _particles_node and is_instance_valid(_particles_node):
		_particles_node.queue_free()
		_particles_node = null

	# Floating dust motes across the dungeon area
	var half_w: float = generator.dungeon_width * generator.TILE_SIZE * 0.5
	var half_h: float = generator.dungeon_height * generator.TILE_SIZE * 0.5

	var dust := GPUParticles3D.new()
	dust.name = "AmbientDust"
	dust.position = Vector3(half_w, 2.0, half_h)
	dust.amount = 120
	dust.lifetime = 6.0
	dust.explosiveness = 0.0
	dust.randomness = 1.0
	dust.visibility_aabb = AABB(Vector3(-half_w, -3, -half_h), Vector3(half_w * 2, 6, half_h * 2))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(half_w, 2.0, half_h)
	pmat.direction = Vector3(0, 0.3, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.1
	pmat.initial_velocity_max = 0.3
	pmat.gravity = Vector3(0, 0.05, 0)
	pmat.scale_min = 0.02
	pmat.scale_max = 0.05

	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.6, 0.0))
	grad.add_point(0.2, Color(1.0, 0.85, 0.6, 0.35))
	grad.add_point(0.8, Color(1.0, 0.85, 0.6, 0.35))
	grad.set_color(1, Color(1.0, 0.85, 0.6, 0.0))
	pmat.color_ramp = color_ramp
	dust.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(1.0, 0.9, 0.7, 0.4)
	dust_mat.emission_enabled = true
	dust_mat.emission = Color(1.0, 0.8, 0.5)
	dust_mat.emission_energy_multiplier = 0.5
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = dust_mat
	dust.draw_pass_1 = quad

	_particles_node = dust
	add_child(dust)


func get_dungeon_grid() -> Array:
	return generator.grid


func get_grid_dimensions() -> Vector2i:
	return Vector2i(generator.dungeon_width, generator.dungeon_height)


func get_tile_size() -> float:
	return generator.TILE_SIZE
