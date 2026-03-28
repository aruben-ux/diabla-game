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
var _stairs_up_area: Area3D
var _stairs_down_area: Area3D
var _stair_props_container: Node3D
var _particles_node: GPUParticles3D
var _flicker_time := 0.0


func _process(delta: float) -> void:
	# Animate torch lights — subtle flicker
	_flicker_time += delta
	for torch_node in light_container.get_children():
		var tl := torch_node.get_node_or_null("TorchLight") as OmniLight3D
		if tl:
			# Use the torch's position to offset the flicker so each is unique
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

	generator.generate.call_deferred()


func _cleanup_floor() -> void:
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

	# Clear lights
	for child in light_container.get_children():
		child.queue_free()

	# Clear spawned enemies
	for child in enemy_spawner.get_children():
		child.queue_free()


func _on_dungeon_generated(room_list: Array, spawn_pos: Vector3, stairs_up: Vector3, stairs_down: Vector3) -> void:
	spawn_position = spawn_pos
	stairs_up_position = stairs_up
	stairs_down_position = stairs_down

	# Setup enemy spawner with room data + floor scaling
	var typed_rooms: Array[Rect2i] = []
	for r in room_list:
		typed_rooms.append(r as Rect2i)
	enemy_spawner.setup(typed_rooms, generator.get_room_centers(), generator.TILE_SIZE, current_floor)

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

	level_ready.emit(spawn_position, stairs_up_position, stairs_down_position)


func _create_stairs_trigger(pos: Vector3, is_up: bool) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2  # Player layer
	area.monitoring = false  # Disabled until activation delay expires
	area.name = "StairsUp" if is_up else "StairsDown"
	add_child(area)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 5.0)
	col.shape = box
	col.position = pos + Vector3(0, 1.5, 0)
	area.add_child(col)

	if is_up:
		_stairs_up_area = area
		area.body_entered.connect(_on_stairs_up_entered)
	else:
		_stairs_down_area = area
		area.body_entered.connect(_on_stairs_down_entered)

	# Activate after a short delay so spawning on stairs doesn't trigger them
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(area):
			area.monitoring = true
	)

	# Visual marker
	var label_text := "Stairs Up (Floor %d)" % (current_floor - 1) if is_up else "Stairs Down (Floor %d)" % (current_floor + 1)
	if is_up and current_floor == 1:
		label_text = "Return to Town"

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


func _on_stairs_up_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		go_up.emit(body)


func _on_stairs_down_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		go_down.emit(body)


func _place_room_lights(room_list: Array) -> void:
	for child in light_container.get_children():
		child.queue_free()

	for room in room_list:
		var r := room as Rect2i
		var cx: float = (r.position.x + r.size.x / 2.0) * generator.TILE_SIZE
		var cz: float = (r.position.y + r.size.y / 2.0) * generator.TILE_SIZE

		# Central room light — warm, shadow-casting
		var light := OmniLight3D.new()
		light.global_position = Vector3(cx, 3.5, cz)
		light.omni_range = maxf(r.size.x, r.size.y) * generator.TILE_SIZE * 0.75
		light.light_energy = 3.0
		light.light_color = Color(1.0, 0.85, 0.6)
		light.shadow_enabled = true
		light.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		light_container.add_child(light)

		# Place wall torches around room perimeter
		_place_torches_in_room(r)

	# Place dim lights along corridors
	_place_corridor_lights()


func _place_corridor_lights() -> void:
	var g: Array = generator.grid
	var gw: int = generator.dungeon_width
	var gh: int = generator.dungeon_height
	var ts: float = generator.TILE_SIZE
	var spacing := 4  # Place a light every N corridor tiles
	var count := 0

	for x in gw:
		for y in gh:
			if g[x][y] != 3:  # 3 = corridor
				continue
			# Only place at intervals to avoid too many lights
			if (x + y) % spacing != 0:
				continue
			var light := OmniLight3D.new()
			light.position = Vector3(x * ts, 2.5, y * ts)
			light.omni_range = 10.0
			light.light_energy = 1.5
			light.light_color = Color(0.8, 0.7, 0.55)
			light.shadow_enabled = false
			light_container.add_child(light)
			count += 1

	print("[Dungeon] Placed %d corridor lights" % count)


func _place_torches_in_room(room: Rect2i) -> void:
	var ts: float = generator.TILE_SIZE
	var half_ts: float = ts / 2.0
	var spacing := 4
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

	# Point light for torch with shadow
	var torch_light := OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.position = Vector3(0, 0.5, 0.55)
	torch_light.omni_range = 7.0
	torch_light.light_energy = 1.0
	torch_light.light_color = Color(1.0, 0.75, 0.4)
	torch_light.shadow_enabled = true
	torch_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
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
