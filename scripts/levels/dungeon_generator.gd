extends Node3D

## Procedural dungeon generator using BSP (Binary Space Partitioning).
## Creates rooms connected by corridors with walls, floors, and collision.
## Server generates the layout and syncs the seed to clients.

signal dungeon_generated(rooms: Array, spawn_position: Vector3, stairs_up_pos: Vector3, stairs_down_pos: Vector3, boss_room_idx: int)

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
var wall_material: ShaderMaterial
var corridor_material: StandardMaterial3D
var stairs_up_material: StandardMaterial3D
var stairs_down_material: StandardMaterial3D

# Internal
var grid: Array = []  # 2D array: 0=void, 1=floor, 2=wall, 3=corridor, 4=stairs_up, 5=stairs_down
var rooms: Array[Rect2i] = []
var _room_centers: Array[Vector3] = []
var _stairs_up_pos := Vector3.ZERO
var _stairs_down_pos := Vector3.ZERO
var _boss_room_idx := -1
var is_boss_floor := false


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
	_boss_room_idx = -1
	dungeon_seed = 0


func generate() -> void:
	if dungeon_seed == 0:
		dungeon_seed = randi()
	seed(dungeon_seed)

	_init_grid()
	var bsp_nodes: Array[Rect2i] = []
	_bsp_split(Rect2i(1, 1, dungeon_width - 2, dungeon_height - 2), 0, bsp_nodes)
	_carve_rooms(bsp_nodes)

	# Shuffle rooms to remove directional bias (NW→SE)
	_shuffle_rooms()

	# Tighter connections: MST + extra links instead of linear chain
	_connect_rooms_mst()

	# Boss room on boss floors
	_boss_room_idx = -1
	if is_boss_floor:
		_carve_boss_room()

	# Place stairs using BFS distance for exploration depth
	_place_stairs_bfs()
	_build_walls()
	_build_mesh()

	var spawn_pos := _room_centers[0] if _room_centers.size() > 0 else _stairs_up_pos

	dungeon_generated.emit(rooms, spawn_pos, _stairs_up_pos, _stairs_down_pos, _boss_room_idx)
	print("Dungeon generated with seed %d: %d rooms, boss_room=%d" % [dungeon_seed, rooms.size(), _boss_room_idx])


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


# --- Shuffle ---

func _shuffle_rooms() -> void:
	## Fisher-Yates shuffle to remove BSP directional ordering bias.
	for i in range(rooms.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var tmp_r := rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp_r
		var tmp_c := _room_centers[i]
		_room_centers[i] = _room_centers[j]
		_room_centers[j] = tmp_c


# --- Corridors (MST + extra links) ---

func _connect_rooms_mst() -> void:
	## Build a minimum spanning tree of room centers (Prim's algorithm),
	## then add ~30% extra edges between nearby rooms for loops.
	## This produces a tighter layout with fewer long hallways.
	if rooms.size() < 2:
		return

	# Build edge list: all room pairs with distances
	var n := rooms.size()
	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)
	var min_cost: Array[float] = []
	min_cost.resize(n)
	min_cost.fill(INF)
	var min_edge: Array[int] = []
	min_edge.resize(n)
	min_edge.fill(-1)

	var mst_edges: Array = []  # Array of [i, j] pairs

	# Start from room 0
	in_tree[0] = true
	for j in range(1, n):
		min_cost[j] = _room_grid_dist(0, j)
		min_edge[j] = 0

	for _step in range(n - 1):
		# Find cheapest edge to add
		var best := -1
		var best_cost := INF
		for j in range(n):
			if not in_tree[j] and min_cost[j] < best_cost:
				best_cost = min_cost[j]
				best = j
		if best == -1:
			break
		in_tree[best] = true
		mst_edges.append([min_edge[best], best])
		# Update costs
		for j in range(n):
			if not in_tree[j]:
				var d := _room_grid_dist(best, j)
				if d < min_cost[j]:
					min_cost[j] = d
					min_edge[j] = best

	# Carve MST corridors
	var connected_set := {}  # Track which pairs are connected
	for edge in mst_edges:
		_carve_room_corridor(edge[0], edge[1])
		var key := mini(edge[0], edge[1]) * 10000 + maxi(edge[0], edge[1])
		connected_set[key] = true

	# Add ~30% extra edges between nearby rooms for tighter layout
	var extra_count := maxi(1, int(mst_edges.size() * 0.35))
	var candidates: Array = []
	for i in range(n):
		for j in range(i + 1, n):
			var key := i * 10000 + j
			if key not in connected_set:
				candidates.append([i, j, _room_grid_dist(i, j)])
	# Sort by distance (shortest first)
	candidates.sort_custom(func(a, b): return a[2] < b[2])
	for k in range(mini(extra_count, candidates.size())):
		_carve_room_corridor(candidates[k][0], candidates[k][1])


func _room_grid_dist(a: int, b: int) -> float:
	## Manhattan distance between room centers in grid coordinates.
	var ra := rooms[a]
	var rb := rooms[b]
	var ax := ra.position.x + ra.size.x / 2
	var ay := ra.position.y + ra.size.y / 2
	var bx := rb.position.x + rb.size.x / 2
	var by := rb.position.y + rb.size.y / 2
	return float(absi(ax - bx) + absi(ay - by))


func _carve_room_corridor(a_idx: int, b_idx: int) -> void:
	var ra := rooms[a_idx]
	var rb := rooms[b_idx]
	var ax := ra.position.x + ra.size.x / 2
	var ay := ra.position.y + ra.size.y / 2
	var bx := rb.position.x + rb.size.x / 2
	var by := rb.position.y + rb.size.y / 2
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


func _place_stairs_bfs() -> void:
	## Place stairs using BFS distance to ensure exploration depth.
	## Stairs up in room[0] (spawn). Stairs down in the room farthest from spawn
	## by actual walkable grid distance (not Euclidean), ensuring the player
	## must explore most of the dungeon to find them.
	## On boss floors, stairs down go in the boss room instead.
	if rooms.size() < 2:
		return

	var spawn_room := rooms[0]

	# Place stairs_up in spawn room corner
	var up_x := spawn_room.position.x + 1
	var up_y := spawn_room.position.y + 1
	for sx in range(up_x, up_x + 2):
		for sy in range(up_y, up_y + 2):
			if sx < dungeon_width and sy < dungeon_height:
				grid[sx][sy] = 4
	_stairs_up_pos = Vector3((up_x + 1) * TILE_SIZE, 0.5, (up_y + 1) * TILE_SIZE)

	# Determine stairs-down room
	var down_room_idx := -1
	if is_boss_floor and _boss_room_idx >= 0:
		# Boss floor: stairs go in boss room
		down_room_idx = _boss_room_idx
	else:
		# BFS from spawn room center to find farthest room
		var start_x := spawn_room.position.x + spawn_room.size.x / 2
		var start_y := spawn_room.position.y + spawn_room.size.y / 2
		var distances := _bfs_flood(start_x, start_y)

		# Find room with maximum BFS distance from spawn
		var best_dist := -1
		for i in range(1, rooms.size()):
			var r := rooms[i]
			var cx := r.position.x + r.size.x / 2
			var cy := r.position.y + r.size.y / 2
			var d: int = distances[cx][cy] if distances[cx][cy] >= 0 else 0
			if d > best_dist:
				best_dist = d
				down_room_idx = i

	if down_room_idx < 0:
		down_room_idx = rooms.size() - 1

	var down_room := rooms[down_room_idx]
	var down_x := down_room.position.x + down_room.size.x / 2 - 1
	var down_y := down_room.position.y + down_room.size.y / 2 - 1
	for sx in range(down_x, down_x + 2):
		for sy in range(down_y, down_y + 2):
			if sx >= 0 and sx < dungeon_width and sy >= 0 and sy < dungeon_height:
				grid[sx][sy] = 5
	_stairs_down_pos = Vector3((down_x + 1) * TILE_SIZE, 0.5, (down_y + 1) * TILE_SIZE)


func _bfs_flood(start_x: int, start_y: int) -> Array:
	## BFS flood fill from a grid position. Returns 2D distance array.
	## Walkable tiles: floor(1), corridor(3), stairs(4,5).
	var dist: Array = []
	for x in dungeon_width:
		var col: Array[int] = []
		col.resize(dungeon_height)
		col.fill(-1)
		dist.append(col)

	if start_x < 0 or start_x >= dungeon_width or start_y < 0 or start_y >= dungeon_height:
		return dist

	dist[start_x][start_y] = 0
	var queue: Array = [[start_x, start_y]]
	var head := 0

	while head < queue.size():
		var cur = queue[head]
		head += 1
		var cx: int = cur[0]
		var cy: int = cur[1]
		var cd: int = dist[cx][cy]
		for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dir[0]
			var ny: int = cy + dir[1]
			if nx >= 0 and nx < dungeon_width and ny >= 0 and ny < dungeon_height:
				if dist[nx][ny] < 0:
					var tile: int = grid[nx][ny]
					if tile == 1 or tile == 3 or tile == 4 or tile == 5:
						dist[nx][ny] = cd + 1
						queue.append([nx, ny])
	return dist


func _carve_boss_room() -> void:
	## Carve a large boss room for boss floors.
	## Picks a random quadrant of the grid and carves a big room there.
	## Connects it to the nearest existing room.
	var boss_size := 20  # 20x20 tile boss room
	var margin := 3

	# Try to find a clear spot by picking random positions (up to 20 attempts)
	var best_pos := Vector2i(-1, -1)
	for _attempt in 20:
		var rx := randi_range(margin, dungeon_width - boss_size - margin)
		var ry := randi_range(margin, dungeon_height - boss_size - margin)
		# Check for overlap with existing rooms (allow some void)
		var overlap := false
		var boss_rect := Rect2i(rx, ry, boss_size, boss_size)
		for room in rooms:
			if boss_rect.intersects(room.grow(2)):
				overlap = true
				break
		if not overlap:
			best_pos = Vector2i(rx, ry)
			break

	if best_pos.x < 0:
		# Fallback: place at grid edge
		best_pos = Vector2i(dungeon_width - boss_size - margin, dungeon_height - boss_size - margin)

	# Carve the boss room
	var boss_rect := Rect2i(best_pos.x, best_pos.y, boss_size, boss_size)
	for x in range(boss_rect.position.x, boss_rect.position.x + boss_rect.size.x):
		for y in range(boss_rect.position.y, boss_rect.position.y + boss_rect.size.y):
			if x >= 0 and x < dungeon_width and y >= 0 and y < dungeon_height:
				grid[x][y] = 1

	rooms.append(boss_rect)
	var center := Vector3(
		(boss_rect.position.x + boss_rect.size.x / 2.0) * TILE_SIZE,
		0.0,
		(boss_rect.position.y + boss_rect.size.y / 2.0) * TILE_SIZE
	)
	_room_centers.append(center)
	_boss_room_idx = rooms.size() - 1

	# Connect boss room to nearest existing room
	var boss_cx := boss_rect.position.x + boss_rect.size.x / 2
	var boss_cy := boss_rect.position.y + boss_rect.size.y / 2
	var nearest_idx := 0
	var nearest_dist := INF
	for i in range(rooms.size() - 1):
		var d := _room_grid_dist(i, _boss_room_idx)
		if d < nearest_dist:
			nearest_dist = d
			nearest_idx = i
	_carve_room_corridor(nearest_idx, _boss_room_idx)


func get_stairs_up_pos() -> Vector3:
	return _stairs_up_pos


func get_stairs_down_pos() -> Vector3:
	return _stairs_down_pos


func get_boss_room_idx() -> int:
	return _boss_room_idx


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
		mesh_instance.add_to_group("occludable")
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

	var wall_std := _make_dungeon_material(
		Color(0.42, 0.36, 0.30), Color(0.22, 0.18, 0.14), 0.85, 0.5)
	var _occlusion_shader: Shader = preload("res://assets/shaders/wall_occlusion.gdshader")
	wall_material = ShaderMaterial.new()
	wall_material.shader = _occlusion_shader
	wall_material.set_shader_parameter("albedo_color", wall_std.albedo_color)
	wall_material.set_shader_parameter("roughness", wall_std.roughness)
	wall_material.set_shader_parameter("uv1_scale", wall_std.uv1_scale)
	wall_material.set_shader_parameter("normal_scale", wall_std.normal_scale if wall_std.normal_enabled else 0.0)
	if wall_std.albedo_texture:
		wall_material.set_shader_parameter("albedo_texture", wall_std.albedo_texture)
	if wall_std.normal_enabled and wall_std.normal_texture:
		wall_material.set_shader_parameter("normal_texture", wall_std.normal_texture)

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
