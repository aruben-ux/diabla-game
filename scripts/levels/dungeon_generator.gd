extends Node3D

## Procedural dungeon generator using BSP (Binary Space Partitioning).
## Creates rooms connected by corridors with walls, floors, and collision.
## Server generates the layout and syncs the seed to clients.

signal dungeon_generated(rooms: Array, spawn_position: Vector3, stairs_up_pos: Vector3, stairs_down_pos: Vector3)

var TILE_SIZE := 3.0
var WALL_HEIGHT := 4.0
var MIN_ROOM_SIZE := 5
var MAX_ROOM_SIZE := 12
var MIN_SPLIT_SIZE := 12
var CORRIDOR_WIDTH := 3

@export var dungeon_width := 60
@export var dungeon_height := 60
@export var max_depth := 5
@export var dungeon_seed := 0

static var _world_cfg: Dictionary = {}
static var _world_loaded := false


static func _load_world_cfg() -> void:
	if _world_loaded:
		return
	_world_loaded = true
	var file := FileAccess.open("res://data/game_data.json", FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			_world_cfg = json.data.get("world", {})
		file.close()

# Materials
var floor_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var corridor_material: StandardMaterial3D
var stairs_up_material: StandardMaterial3D
var stairs_down_material: StandardMaterial3D

# Internal
var grid: Array = []  # 2D array: 0=void, 1=floor, 2=wall, 3=corridor, 4=stairs_up, 5=stairs_down
var rooms: Array[Rect2i] = []
var _room_centers: Array[Vector3] = []
var _stairs_up_pos := Vector3.ZERO
var _stairs_down_pos := Vector3.ZERO


func _ready() -> void:
	_load_world_cfg()
	TILE_SIZE = _world_cfg.get("tile_size", TILE_SIZE)
	WALL_HEIGHT = _world_cfg.get("wall_height", WALL_HEIGHT)
	MIN_ROOM_SIZE = int(_world_cfg.get("min_room_size", MIN_ROOM_SIZE))
	MAX_ROOM_SIZE = int(_world_cfg.get("max_room_size", MAX_ROOM_SIZE))
	MIN_SPLIT_SIZE = int(_world_cfg.get("min_split_size", MIN_SPLIT_SIZE))
	CORRIDOR_WIDTH = int(_world_cfg.get("corridor_width", CORRIDOR_WIDTH))
	dungeon_width = int(_world_cfg.get("dungeon_width", dungeon_width))
	dungeon_height = int(_world_cfg.get("dungeon_height", dungeon_height))
	max_depth = int(_world_cfg.get("bsp_max_depth", max_depth))
	_create_materials()


func reset() -> void:
	## Clears all generated geometry so a new floor can be built.
	for child in get_children():
		child.queue_free()
	grid.clear()
	rooms.clear()
	_room_centers.clear()
	_stairs_up_pos = Vector3.ZERO
	_stairs_down_pos = Vector3.ZERO
	dungeon_seed = 0


func generate() -> void:
	if dungeon_seed == 0:
		dungeon_seed = randi()
	seed(dungeon_seed)

	_init_grid()
	var bsp_nodes: Array[Rect2i] = []
	_bsp_split(Rect2i(1, 1, dungeon_width - 2, dungeon_height - 2), 0, bsp_nodes)
	_carve_rooms(bsp_nodes)
	_connect_rooms()
	_place_stairs()
	_build_walls()
	_build_mesh()

	# Determine spawn position (center of first room, away from stairs)
	var spawn_pos := _room_centers[0] if _room_centers.size() > 0 else _stairs_up_pos

	dungeon_generated.emit(rooms, spawn_pos, _stairs_up_pos, _stairs_down_pos)
	print("Dungeon generated with seed %d: %d rooms" % [dungeon_seed, rooms.size()])


func get_room_centers() -> Array[Vector3]:
	return _room_centers


func get_spawn_position() -> Vector3:
	if rooms.size() > 0:
		var r := rooms[0]
		return Vector3(
			(r.position.x + r.size.x / 2.0) * TILE_SIZE,
			0.5,
			(r.position.y + r.size.y / 2.0) * TILE_SIZE
		)
	return Vector3(0, 0.5, 0)


# --- Grid ---

func _init_grid() -> void:
	grid.clear()
	for x in dungeon_width:
		var col: Array[int] = []
		col.resize(dungeon_height)
		col.fill(0)
		grid.append(col)


# --- BSP ---

func _bsp_split(rect: Rect2i, depth: int, leaves: Array[Rect2i]) -> void:
	if depth >= max_depth or (rect.size.x < MIN_SPLIT_SIZE and rect.size.y < MIN_SPLIT_SIZE):
		leaves.append(rect)
		return

	var split_h := randf() < 0.5
	# Force direction if one axis is too small
	if rect.size.x < MIN_SPLIT_SIZE:
		split_h = true
	elif rect.size.y < MIN_SPLIT_SIZE:
		split_h = false

	if split_h:
		if rect.size.y < MIN_SPLIT_SIZE * 2:
			leaves.append(rect)
			return
		var split := randi_range(rect.position.y + MIN_ROOM_SIZE + 1, rect.position.y + rect.size.y - MIN_ROOM_SIZE - 1)
		var a := Rect2i(rect.position.x, rect.position.y, rect.size.x, split - rect.position.y)
		var b := Rect2i(rect.position.x, split, rect.size.x, rect.position.y + rect.size.y - split)
		_bsp_split(a, depth + 1, leaves)
		_bsp_split(b, depth + 1, leaves)
	else:
		if rect.size.x < MIN_SPLIT_SIZE * 2:
			leaves.append(rect)
			return
		var split := randi_range(rect.position.x + MIN_ROOM_SIZE + 1, rect.position.x + rect.size.x - MIN_ROOM_SIZE - 1)
		var a := Rect2i(rect.position.x, rect.position.y, split - rect.position.x, rect.size.y)
		var b := Rect2i(split, rect.position.y, rect.position.x + rect.size.x - split, rect.size.y)
		_bsp_split(a, depth + 1, leaves)
		_bsp_split(b, depth + 1, leaves)


# --- Rooms ---

func _carve_rooms(leaves: Array[Rect2i]) -> void:
	rooms.clear()
	_room_centers.clear()

	for leaf in leaves:
		var rw := randi_range(MIN_ROOM_SIZE, mini(MAX_ROOM_SIZE, leaf.size.x - 2))
		var rh := randi_range(MIN_ROOM_SIZE, mini(MAX_ROOM_SIZE, leaf.size.y - 2))
		var rx := randi_range(leaf.position.x + 1, leaf.position.x + leaf.size.x - rw - 1)
		var ry := randi_range(leaf.position.y + 1, leaf.position.y + leaf.size.y - rh - 1)

		var room := Rect2i(rx, ry, rw, rh)
		rooms.append(room)

		var center := Vector3(
			(rx + rw / 2.0) * TILE_SIZE,
			0.0,
			(ry + rh / 2.0) * TILE_SIZE
		)
		_room_centers.append(center)

		# Carve floor
		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				if x >= 0 and x < dungeon_width and y >= 0 and y < dungeon_height:
					grid[x][y] = 1


# --- Corridors ---

func _connect_rooms() -> void:
	for i in range(1, rooms.size()):
		var a := rooms[i - 1]
		var b := rooms[i]
		var ax := a.position.x + a.size.x / 2
		var ay := a.position.y + a.size.y / 2
		var bx := b.position.x + b.size.x / 2
		var by := b.position.y + b.size.y / 2
		_carve_corridor(ax, ay, bx, by)


func _carve_corridor(x1: int, y1: int, x2: int, y2: int) -> void:
	var half_w := CORRIDOR_WIDTH / 2

	# Horizontal first, then vertical
	var sx := mini(x1, x2)
	var ex := maxi(x1, x2)
	for x in range(sx, ex + 1):
		for w in range(-half_w, half_w + 1):
			var yy := y1 + w
			if x >= 0 and x < dungeon_width and yy >= 0 and yy < dungeon_height:
				if grid[x][yy] == 0:
					grid[x][yy] = 3

	var sy := mini(y1, y2)
	var ey := maxi(y1, y2)
	for y in range(sy, ey + 1):
		for w in range(-half_w, half_w + 1):
			var xx := x2 + w
			if xx >= 0 and xx < dungeon_width and y >= 0 and y < dungeon_height:
				if grid[xx][y] == 0:
					grid[xx][y] = 3


# --- Walls ---

func _build_walls() -> void:
	for x in dungeon_width:
		for y in dungeon_height:
			if grid[x][y] == 0:
				# Check neighbors — if adjacent to floor or corridor, make it a wall
				if _has_floor_neighbor(x, y):
					grid[x][y] = 2


func _has_floor_neighbor(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < dungeon_width and ny >= 0 and ny < dungeon_height:
				if grid[nx][ny] == 1 or grid[nx][ny] == 3 or grid[nx][ny] == 4 or grid[nx][ny] == 5:
					return true
	return false


func _place_stairs() -> void:
	# Stairs up in first room, stairs down in last room
	if rooms.size() < 2:
		return

	var first := rooms[0]
	var last := rooms[rooms.size() - 1]

	# Place stairs_up in corner of first room
	var up_x := first.position.x + 1
	var up_y := first.position.y + 1
	for sx in range(up_x, up_x + 2):
		for sy in range(up_y, up_y + 2):
			if sx < dungeon_width and sy < dungeon_height:
				grid[sx][sy] = 4
	_stairs_up_pos = Vector3((up_x + 1) * TILE_SIZE, 0.5, (up_y + 1) * TILE_SIZE)

	# Place stairs_down in corner of last room
	var down_x := last.position.x + last.size.x - 3
	var down_y := last.position.y + last.size.y - 3
	for sx in range(down_x, down_x + 2):
		for sy in range(down_y, down_y + 2):
			if sx >= 0 and sx < dungeon_width and sy >= 0 and sy < dungeon_height:
				grid[sx][sy] = 5
	_stairs_down_pos = Vector3((down_x + 1) * TILE_SIZE, 0.5, (down_y + 1) * TILE_SIZE)


func get_stairs_up_pos() -> Vector3:
	return _stairs_up_pos


func get_stairs_down_pos() -> Vector3:
	return _stairs_down_pos


# --- Mesh Building ---

func _build_mesh() -> void:
	# Clear existing children (except self)
	for child in get_children():
		child.queue_free()

	var floor_mesh_data := []
	var wall_positions := []
	var corridor_mesh_data := []
	var stairs_up_data := []
	var stairs_down_data := []

	for x in dungeon_width:
		for y in dungeon_height:
			var world_pos := Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			match grid[x][y]:
				1:  # Floor
					floor_mesh_data.append(world_pos)
				2:  # Wall
					wall_positions.append(world_pos)
				3:  # Corridor
					corridor_mesh_data.append(world_pos)
				4:  # Stairs up
					stairs_up_data.append(world_pos)
				5:  # Stairs down
					stairs_down_data.append(world_pos)

	_build_floor_chunks(floor_mesh_data, "Floor", floor_material)
	_build_floor_chunks(corridor_mesh_data, "Corridor", corridor_material)
	_build_floor_chunks(stairs_up_data, "StairsUp", stairs_up_material)
	_build_floor_chunks(stairs_down_data, "StairsDown", stairs_down_material)
	_build_wall_blocks(wall_positions)
	_build_navigation()


func _build_floor_chunks(positions: Array, group_name: String, mat: StandardMaterial3D) -> void:
	if positions.is_empty():
		return

	# Build in chunks of 500 tiles for performance
	var chunk_size := 500
	var chunk_idx := 0

	for i in range(0, positions.size(), chunk_size):
		var chunk_end := mini(i + chunk_size, positions.size())
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for j in range(i, chunk_end):
			var pos: Vector3 = positions[j]
			_add_floor_quad(st, pos)

		st.generate_normals()
		var mesh := st.commit()

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = mat
		mesh_instance.name = "%s_Chunk_%d" % [group_name, chunk_idx]
		add_child(mesh_instance)
		chunk_idx += 1

	# Solid box collision for all floor tiles (thin slab)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1  # Ground
	floor_body.collision_mask = 0
	floor_body.name = "%s_Collision" % group_name
	add_child(floor_body)

	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(TILE_SIZE, 0.2, TILE_SIZE)

	for pos in positions:
		var col := CollisionShape3D.new()
		col.shape = box_shape
		col.position = pos + Vector3(0, -0.1, 0)
		floor_body.add_child(col)


func _build_wall_blocks(positions: Array) -> void:
	if positions.is_empty():
		return

	# Visual mesh in chunks
	var chunk_size := 500
	var chunk_idx := 0

	for i in range(0, positions.size(), chunk_size):
		var chunk_end := mini(i + chunk_size, positions.size())
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for j in range(i, chunk_end):
			var pos: Vector3 = positions[j]
			_add_wall_box(st, pos)

		st.generate_normals()
		var mesh := st.commit()

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = wall_material
		mesh_instance.name = "Wall_Chunk_%d" % chunk_idx
		add_child(mesh_instance)
		chunk_idx += 1

	# Solid box collision per wall tile (not trimesh — trimesh is one-sided)
	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	wall_body.name = "WallCollision"
	add_child(wall_body)

	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)

	for pos in positions:
		var col := CollisionShape3D.new()
		col.shape = box_shape
		col.position = pos + Vector3(0, WALL_HEIGHT / 2.0, 0)
		wall_body.add_child(col)


func _add_floor_quad(st: SurfaceTool, pos: Vector3) -> void:
	var half := TILE_SIZE / 2.0
	var a := pos + Vector3(-half, 0, -half)
	var b := pos + Vector3(half, 0, -half)
	var c := pos + Vector3(half, 0, half)
	var d := pos + Vector3(-half, 0, half)

	# Winding order: a→b→c and a→c→d gives upward-facing normals
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _add_wall_box(st: SurfaceTool, pos: Vector3) -> void:
	var half := TILE_SIZE / 2.0
	var h := WALL_HEIGHT

	# 8 corners of the box
	var b000 := pos + Vector3(-half, 0, -half)
	var b100 := pos + Vector3(half, 0, -half)
	var b110 := pos + Vector3(half, h, -half)
	var b010 := pos + Vector3(-half, h, -half)
	var b001 := pos + Vector3(-half, 0, half)
	var b101 := pos + Vector3(half, 0, half)
	var b111 := pos + Vector3(half, h, half)
	var b011 := pos + Vector3(-half, h, half)

	# Top face (Y+) — normal pointing up
	_add_quad(st, b010, b110, b111, b011)
	# Bottom face (Y-) — normal pointing down
	_add_quad(st, b001, b101, b100, b000)
	# Front face (Z+) — normal pointing toward +Z
	_add_quad(st, b001, b011, b111, b101)
	# Back face (Z-) — normal pointing toward -Z
	_add_quad(st, b100, b110, b010, b000)
	# Left face (X-) — normal pointing toward -X
	_add_quad(st, b000, b010, b011, b001)
	# Right face (X+) — normal pointing toward +X
	_add_quad(st, b101, b111, b110, b100)


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Two triangles, CCW winding (outward-facing normals)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _build_navigation() -> void:
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "DungeonNavRegion"

	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.1
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.8

	nav_region.navigation_mesh = nav_mesh
	add_child(nav_region)

	# Bake after a frame so geometry is ready
	nav_region.bake_navigation_mesh.call_deferred()


# --- Materials ---

func _create_materials() -> void:
	floor_material = _make_dungeon_material(
		Color(0.35, 0.28, 0.22), Color(0.18, 0.14, 0.10), 0.9, 0.4)

	wall_material = _make_dungeon_material(
		Color(0.42, 0.36, 0.30), Color(0.22, 0.18, 0.14), 0.85, 0.5)
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	corridor_material = _make_dungeon_material(
		Color(0.30, 0.25, 0.20), Color(0.16, 0.12, 0.09), 0.9, 0.4)

	stairs_up_material = StandardMaterial3D.new()
	stairs_up_material.albedo_color = Color(0.35, 0.5, 0.35)
	stairs_up_material.emission_enabled = true
	stairs_up_material.emission = Color(0.2, 0.5, 0.2)
	stairs_up_material.emission_energy_multiplier = 0.3
	stairs_up_material.roughness = 0.7
	stairs_up_material.uv1_triplanar = true

	stairs_down_material = StandardMaterial3D.new()
	stairs_down_material.albedo_color = Color(0.35, 0.35, 0.55)
	stairs_down_material.emission_enabled = true
	stairs_down_material.emission = Color(0.2, 0.2, 0.6)
	stairs_down_material.emission_energy_multiplier = 0.3
	stairs_down_material.roughness = 0.7
	stairs_down_material.uv1_triplanar = true


func _make_dungeon_material(base_color: Color, dark_color: Color, roughness: float, tex_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = roughness

	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	mat.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)

	# Cracked stone noise
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.06
	noise.fractal_octaves = 3

	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise
	noise_tex.color_ramp = _make_dungeon_gradient(base_color, dark_color)

	mat.albedo_texture = noise_tex

	# Normal map for surface roughness
	var detail_noise := FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.12
	detail_noise.fractal_octaves = 4

	var detail_tex := NoiseTexture2D.new()
	detail_tex.width = 128
	detail_tex.height = 128
	detail_tex.seamless = true
	detail_tex.noise = detail_noise
	detail_tex.as_normal_map = true

	mat.normal_enabled = true
	mat.normal_texture = detail_tex
	mat.normal_scale = 0.5

	return mat


func _make_dungeon_gradient(light: Color, dark: Color) -> Gradient:
	var grad := Gradient.new()
	grad.set_color(0, dark)
	grad.add_point(0.35, dark.lerp(light, 0.3))
	grad.add_point(0.5, light)
	grad.add_point(0.65, dark.lerp(light, 0.5))
	grad.set_color(1, light.lerp(dark, 0.3))
	return grad
