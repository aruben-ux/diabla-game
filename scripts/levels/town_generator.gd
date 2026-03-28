extends Node3D

## Procedural town generator — expanded town with named districts:
##   - Central plaza with fountain (spawn point, heals on interact)
##   - Ring road connecting all districts
##   - NW: Town Hall / Elder's house
##   - N : Marketplace with open-air stalls
##   - NE: Alchemist / Potion shop
##   - E : General goods store
##   - W : Tavern / Inn (largest building)
##   - SE: Blacksmith / Armory with forge
##   - S : Dungeon entrance with guard towers
##   - Gardens, benches, barrels, crates, and well scattered about

signal town_generated(spawn_position: Vector3, stairs_position: Vector3)

var TILE_SIZE := 3.0
var WALL_HEIGHT := 5.0
var BUILDING_HEIGHT := 4.5
var ROOF_EXTRA := 1.5
var TOWN_WIDTH := 40
var TOWN_HEIGHT := 40

# Grid values: 0=void, 1=plaza, 2=wall, 3=path, 4=building, 5=stairs, 6=garden
var grid: Array = []

# Materials
var ground_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var path_material: StandardMaterial3D
var building_material: StandardMaterial3D
var roof_material: StandardMaterial3D
var stairs_material: StandardMaterial3D
var garden_material: StandardMaterial3D

# Building placement data — each entry: {rect: Rect2i, label: String, height: float}
var buildings: Array[Dictionary] = []
var stairs_rect := Rect2i(0, 0, 0, 0)
var _spawn_pos := Vector3.ZERO
var _stairs_pos := Vector3.ZERO


func _ready() -> void:
	_load_world_cfg()
	TILE_SIZE = _world_cfg.get("tile_size", TILE_SIZE)
	WALL_HEIGHT = _world_cfg.get("town_wall_height", WALL_HEIGHT)
	BUILDING_HEIGHT = _world_cfg.get("building_height", BUILDING_HEIGHT)
	ROOF_EXTRA = _world_cfg.get("roof_extra", ROOF_EXTRA)
	TOWN_WIDTH = int(_world_cfg.get("town_width", TOWN_WIDTH))
	TOWN_HEIGHT = int(_world_cfg.get("town_height", TOWN_HEIGHT))
	_create_materials()


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


func generate() -> void:
	_init_grid()
	_carve_plaza()
	_place_buildings()
	_place_stairs()
	_place_gardens()
	_carve_paths()
	_build_town_walls()
	_build_mesh()
	_place_props()

	town_generated.emit(_spawn_pos, _stairs_pos)
	print("Town generated: %d buildings" % buildings.size())


# --- Grid ---

func _init_grid() -> void:
	grid.clear()
	for x in TOWN_WIDTH:
		var col: Array[int] = []
		col.resize(TOWN_HEIGHT)
		col.fill(0)
		grid.append(col)


# --- Central Plaza (circular, radius 6 for more room) ---

func _carve_plaza() -> void:
	var cx := TOWN_WIDTH / 2
	var cy := TOWN_HEIGHT / 2
	var radius := 6

	for x in range(cx - radius, cx + radius + 1):
		for y in range(cy - radius, cy + radius + 1):
			if x >= 1 and x < TOWN_WIDTH - 1 and y >= 1 and y < TOWN_HEIGHT - 1:
				var dx := x - cx
				var dy := y - cy
				if dx * dx + dy * dy <= radius * radius:
					grid[x][y] = 1

	_spawn_pos = Vector3(cx * TILE_SIZE, 0.5, cy * TILE_SIZE)


# --- Buildings (named for NPC/vendor system) ---

func _place_buildings() -> void:
	buildings.clear()

	# Each building: {rect, label, height}
	# Heights vary for visual interest
	var plots: Array[Dictionary] = [
		# NW — Town Hall / Elder's house (large, tall)
		{"rect": Rect2i(3, 3, 6, 5), "label": "Town Hall", "height": 6.0},
		# N — Marketplace building (wide)
		{"rect": Rect2i(15, 2, 7, 4), "label": "Marketplace", "height": 4.0},
		# NE — Alchemist / Potion shop
		{"rect": Rect2i(30, 3, 5, 4), "label": "Alchemist", "height": 5.0},
		# W — Tavern / Inn (the biggest building)
		{"rect": Rect2i(2, 16, 7, 6), "label": "Tavern", "height": 5.5},
		# E — General Goods
		{"rect": Rect2i(31, 16, 6, 5), "label": "General Store", "height": 4.5},
		# SW — Residence
		{"rect": Rect2i(3, 30, 5, 5), "label": "Residence", "height": 4.0},
		# SE — Blacksmith / Armory
		{"rect": Rect2i(31, 30, 6, 5), "label": "Blacksmith", "height": 4.5},
		# Inner ring — small buildings near plaza
		{"rect": Rect2i(11, 5, 3, 3), "label": "Healer", "height": 4.0},
		{"rect": Rect2i(26, 5, 3, 3), "label": "Jeweler", "height": 4.0},
		# Market stalls (open-air, low roofs)
		{"rect": Rect2i(15, 7, 3, 2), "label": "Fruit Stall", "height": 2.8},
		{"rect": Rect2i(19, 7, 3, 2), "label": "Weapon Stall", "height": 2.8},
		{"rect": Rect2i(23, 7, 3, 2), "label": "Armor Stall", "height": 2.8},
	]

	for plot in plots:
		var rect: Rect2i = plot["rect"]
		if rect.position.x + rect.size.x >= TOWN_WIDTH - 1:
			continue
		if rect.position.y + rect.size.y >= TOWN_HEIGHT - 1:
			continue

		buildings.append(plot)
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				grid[x][y] = 4


# --- Dungeon Stairs (south-center, flanked by guard towers) ---

func _place_stairs() -> void:
	var sx := TOWN_WIDTH / 2 - 2
	var sy := TOWN_HEIGHT - 5
	stairs_rect = Rect2i(sx, sy, 4, 3)

	for x in range(sx, sx + 4):
		for y in range(sy, sy + 3):
			if x >= 0 and x < TOWN_WIDTH and y >= 0 and y < TOWN_HEIGHT:
				grid[x][y] = 5

	_stairs_pos = Vector3((sx + 2) * TILE_SIZE, 0.5, (sy + 1) * TILE_SIZE)

	# Guard tower plots (small, tall buildings flanking the entrance)
	var left_tower := {"rect": Rect2i(sx - 3, sy - 1, 2, 2), "label": "Guard Tower", "height": 7.0}
	var right_tower := {"rect": Rect2i(sx + 5, sy - 1, 2, 2), "label": "Guard Tower", "height": 7.0}
	for tower in [left_tower, right_tower]:
		var rect: Rect2i = tower["rect"]
		buildings.append(tower)
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			for y in range(rect.position.y, rect.position.y + rect.size.y):
				if x >= 0 and x < TOWN_WIDTH and y >= 0 and y < TOWN_HEIGHT:
					grid[x][y] = 4


# --- Gardens (green patches between buildings) ---

func _place_gardens() -> void:
	# Place small garden plots in open areas
	var garden_spots: Array[Rect2i] = [
		Rect2i(10, 12, 3, 3),   # West of plaza
		Rect2i(27, 12, 3, 3),   # East of plaza
		Rect2i(10, 25, 3, 3),   # SW area
		Rect2i(27, 25, 3, 3),   # SE area
		Rect2i(17, 28, 4, 3),   # South of plaza
	]

	for spot in garden_spots:
		for x in range(spot.position.x, spot.position.x + spot.size.x):
			for y in range(spot.position.y, spot.position.y + spot.size.y):
				if x >= 0 and x < TOWN_WIDTH and y >= 0 and y < TOWN_HEIGHT:
					if grid[x][y] == 0:
						grid[x][y] = 6


# --- Paths (ring road + radial streets + building connections) ---

func _carve_paths() -> void:
	var cx := TOWN_WIDTH / 2
	var cy := TOWN_HEIGHT / 2

	# Main roads from plaza to edges (N, S, E, W)
	_carve_road(cx, cy - 6, cx, 1, 2)                # North
	_carve_road(cx, cy + 6, cx, TOWN_HEIGHT - 2, 2)  # South
	_carve_road(cx - 6, cy, 1, cy, 2)                # West
	_carve_road(cx + 6, cy, TOWN_WIDTH - 2, cy, 2)   # East

	# Ring road — a rectangular loop around the plaza
	var ring_inner := 10
	var ring_outer := TOWN_WIDTH - 10
	var ring_top := 10
	var ring_bottom := TOWN_HEIGHT - 10
	# Top segment
	_carve_road(ring_inner, ring_top, ring_outer, ring_top, 1)
	# Bottom segment
	_carve_road(ring_inner, ring_bottom, ring_outer, ring_bottom, 1)
	# Left segment
	_carve_road(ring_inner, ring_top, ring_inner, ring_bottom, 1)
	# Right segment
	_carve_road(ring_outer, ring_top, ring_outer, ring_bottom, 1)

	# Diagonal shortcuts (NW-SE, NE-SW) — use stepped L-shapes
	_carve_road(ring_inner, ring_top, cx - 6, cy, 1)
	_carve_road(ring_outer, ring_top, cx + 6, cy, 1)
	_carve_road(ring_inner, ring_bottom, cx - 6, cy, 1)
	_carve_road(ring_outer, ring_bottom, cx + 6, cy, 1)

	# Connect each building to the nearest path
	for b in buildings:
		var rect: Rect2i = b["rect"]
		var bx := rect.position.x + rect.size.x / 2
		var by := rect.position.y + rect.size.y / 2
		if bx < cx:
			_carve_road(rect.position.x + rect.size.x, by, mini(cx, ring_inner + 1), by, 1)
		else:
			_carve_road(rect.position.x, by, maxi(cx, ring_outer - 1), by, 1)


func _carve_road(x1: int, y1: int, x2: int, y2: int, half_w: int) -> void:
	# Horizontal
	var sx := mini(x1, x2)
	var ex := maxi(x1, x2)
	for x in range(sx, ex + 1):
		for w in range(-half_w, half_w + 1):
			var yy := y1 + w
			if x >= 0 and x < TOWN_WIDTH and yy >= 0 and yy < TOWN_HEIGHT:
				if grid[x][yy] == 0:
					grid[x][yy] = 3

	# Vertical
	var sy := mini(y1, y2)
	var ey := maxi(y1, y2)
	for y in range(sy, ey + 1):
		for w in range(-half_w, half_w + 1):
			var xx := x2 + w
			if xx >= 0 and xx < TOWN_WIDTH and y >= 0 and y < TOWN_HEIGHT:
				if grid[xx][y] == 0:
					grid[xx][y] = 3


# --- Town outer wall ---

func _build_town_walls() -> void:
	for x in TOWN_WIDTH:
		for y in TOWN_HEIGHT:
			if grid[x][y] == 0:
				if _has_floor_neighbor(x, y):
					grid[x][y] = 2


func _has_floor_neighbor(x: int, y: int) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < TOWN_WIDTH and ny >= 0 and ny < TOWN_HEIGHT:
				var t: int = grid[nx][ny]
				if t == 1 or t == 3 or t == 5 or t == 6:
					return true
	return false


# --- Mesh Building ---

func _build_mesh() -> void:
	for child in get_children():
		child.queue_free()

	var floor_positions := []
	var wall_positions := []
	var path_positions := []
	var stairs_positions := []
	var garden_positions := []

	for x in TOWN_WIDTH:
		for y in TOWN_HEIGHT:
			var world_pos := Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			match grid[x][y]:
				1:  # Plaza
					floor_positions.append(world_pos)
				2:  # Wall
					wall_positions.append(world_pos)
				3:  # Path
					path_positions.append(world_pos)
				5:  # Stairs
					stairs_positions.append(world_pos)
				6:  # Garden
					garden_positions.append(world_pos)

	_build_floor_chunks(floor_positions, "Plaza", ground_material)
	_build_floor_chunks(path_positions, "Path", path_material)
	_build_floor_chunks(garden_positions, "Garden", garden_material)
	_build_wall_blocks(wall_positions)
	_build_buildings()
	_build_stairs_mesh(stairs_positions)
	_build_collision(floor_positions + path_positions + stairs_positions + garden_positions, wall_positions)


func _build_floor_chunks(positions: Array, group_name: String, mat: StandardMaterial3D) -> void:
	if positions.is_empty():
		return

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

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.name = "%s_Chunk_%d" % [group_name, chunk_idx]
		add_child(mi)
		chunk_idx += 1


func _build_wall_blocks(positions: Array) -> void:
	if positions.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for pos in positions:
		_add_wall_box(st, pos as Vector3)

	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = wall_material
	mi.name = "TownWalls"
	add_child(mi)


func _build_buildings() -> void:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		_build_single_building(b["rect"], i, b.get("height", BUILDING_HEIGHT), b.get("label", ""))


func _build_single_building(rect: Rect2i, idx: int, h: float, label: String) -> void:
	var x1 := rect.position.x * TILE_SIZE
	var z1 := rect.position.y * TILE_SIZE
	var x2 := (rect.position.x + rect.size.x) * TILE_SIZE
	var z2 := (rect.position.y + rect.size.y) * TILE_SIZE

	# --- Walls ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_ts := TILE_SIZE / 2.0
	var bx1 := x1 - half_ts
	var bz1 := z1 - half_ts
	var bx2 := x2 - half_ts
	var bz2 := z2 - half_ts

	# Front (Z+)
	_add_quad(st, Vector3(bx1, 0, bz2), Vector3(bx1, h, bz2), Vector3(bx2, h, bz2), Vector3(bx2, 0, bz2))
	# Back (Z-)
	_add_quad(st, Vector3(bx2, 0, bz1), Vector3(bx2, h, bz1), Vector3(bx1, h, bz1), Vector3(bx1, 0, bz1))
	# Left (X-)
	_add_quad(st, Vector3(bx1, 0, bz1), Vector3(bx1, h, bz1), Vector3(bx1, h, bz2), Vector3(bx1, 0, bz2))
	# Right (X+)
	_add_quad(st, Vector3(bx2, 0, bz2), Vector3(bx2, h, bz2), Vector3(bx2, h, bz1), Vector3(bx2, 0, bz1))

	st.generate_normals()
	var wall_mesh := st.commit()
	var wall_mi := MeshInstance3D.new()
	wall_mi.mesh = wall_mesh
	wall_mi.material_override = building_material
	wall_mi.name = "Building_%d_Walls" % idx
	add_child(wall_mi)

	# --- Roof (flat slab + slight overhang) ---
	var overhang := 0.4
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(rst,
		Vector3(bx1 - overhang, h, bz1 - overhang),
		Vector3(bx2 + overhang, h, bz1 - overhang),
		Vector3(bx2 + overhang, h, bz2 + overhang),
		Vector3(bx1 - overhang, h, bz2 + overhang))
	rst.generate_normals()
	var roof_mesh := rst.commit()
	var roof_mi := MeshInstance3D.new()
	roof_mi.mesh = roof_mesh
	roof_mi.material_override = roof_material
	roof_mi.name = "Building_%d_Roof" % idx
	add_child(roof_mi)

	# --- Floor inside building ---
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(fst,
		Vector3(bx1, 0.02, bz1),
		Vector3(bx2, 0.02, bz1),
		Vector3(bx2, 0.02, bz2),
		Vector3(bx1, 0.02, bz2))
	fst.generate_normals()
	var floor_mesh := fst.commit()
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = ground_material
	floor_mi.name = "Building_%d_Floor" % idx
	add_child(floor_mi)

	# Building collision (4 wall blocks)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.name = "Building_%d_Collision" % idx
	add_child(body)

	var thickness := 0.4
	# Front wall
	_add_box_collision(body, Vector3((bx1 + bx2) / 2.0, h / 2.0, bz2), Vector3(bx2 - bx1, h, thickness))
	# Back wall
	_add_box_collision(body, Vector3((bx1 + bx2) / 2.0, h / 2.0, bz1), Vector3(bx2 - bx1, h, thickness))
	# Left wall
	_add_box_collision(body, Vector3(bx1, h / 2.0, (bz1 + bz2) / 2.0), Vector3(thickness, h, bz2 - bz1))
	# Right wall
	_add_box_collision(body, Vector3(bx2, h / 2.0, (bz1 + bz2) / 2.0), Vector3(thickness, h, bz2 - bz1))

	# Interior light
	var light := OmniLight3D.new()
	light.position = Vector3((bx1 + bx2) / 2.0, h - 0.5, (bz1 + bz2) / 2.0)
	light.omni_range = maxf(rect.size.x, rect.size.y) * TILE_SIZE * 0.4
	light.light_energy = 0.8
	light.light_color = Color(1.0, 0.9, 0.7)
	light.shadow_enabled = false
	add_child(light)

	# Building name sign above the front door
	if label != "":
		var sign_label := Label3D.new()
		sign_label.text = label
		sign_label.position = Vector3((bx1 + bx2) / 2.0, h * 0.7, bz2 + 0.15)
		sign_label.pixel_size = 0.01
		sign_label.font_size = 36
		sign_label.modulate = Color(0.95, 0.88, 0.65)
		sign_label.outline_modulate = Color(0.1, 0.05, 0.0)
		sign_label.outline_size = 6
		sign_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		add_child(sign_label)

		# Hanging sign board behind the text
		var sign_board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(label.length() * 0.22 + 0.4, 0.5, 0.06)
		sign_board.mesh = board_mesh
		sign_board.position = Vector3((bx1 + bx2) / 2.0, h * 0.7, bz2 + 0.1)
		var wood_mat := StandardMaterial3D.new()
		wood_mat.albedo_color = Color(0.35, 0.22, 0.1)
		sign_board.material_override = wood_mat
		add_child(sign_board)


func _build_stairs_mesh(positions: Array) -> void:
	if positions.is_empty():
		return

	# Stepped descent — 4 steps going down into the ground
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step_count := 4
	var step_depth := TILE_SIZE * 3.0 / step_count
	var step_height := 0.5

	var min_x := INF
	var max_x := -INF
	var min_z := INF

	for pos in positions:
		var p: Vector3 = pos
		min_x = minf(min_x, p.x - TILE_SIZE / 2.0)
		max_x = maxf(max_x, p.x + TILE_SIZE / 2.0)
		min_z = minf(min_z, p.z - TILE_SIZE / 2.0)

	for i in step_count:
		var y_top: float = -i * step_height
		var y_bot: float = -(i + 1) * step_height
		var z_front: float = min_z + i * step_depth
		var z_back: float = min_z + (i + 1) * step_depth

		# Step top face
		_add_quad(st,
			Vector3(min_x, y_top, z_front),
			Vector3(max_x, y_top, z_front),
			Vector3(max_x, y_top, z_back),
			Vector3(min_x, y_top, z_back))

		# Step front face (vertical riser)
		_add_quad(st,
			Vector3(min_x, y_bot, z_front),
			Vector3(min_x, y_top, z_front),
			Vector3(max_x, y_top, z_front),
			Vector3(max_x, y_bot, z_front))

	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = stairs_material
	mi.name = "DungeonStairs"
	add_child(mi)

	# Side walls for the stairwell
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total_depth_z: float = step_count * step_depth
	var total_drop: float = step_count * step_height

	# Left side wall
	_add_quad(sst,
		Vector3(min_x, 0, min_z),
		Vector3(min_x, 0, min_z + total_depth_z),
		Vector3(min_x, -total_drop, min_z + total_depth_z),
		Vector3(min_x, 0, min_z))
	# Right side wall
	_add_quad(sst,
		Vector3(max_x, 0, min_z + total_depth_z),
		Vector3(max_x, 0, min_z),
		Vector3(max_x, 0, min_z),
		Vector3(max_x, -total_drop, min_z + total_depth_z))

	sst.generate_normals()
	var side_mesh := sst.commit()
	var side_mi := MeshInstance3D.new()
	side_mi.mesh = side_mesh
	side_mi.material_override = wall_material
	side_mi.name = "StairsSideWalls"
	add_child(side_mi)

	# Glowing marker at bottom of stairs
	var glow := OmniLight3D.new()
	glow.position = Vector3((min_x + max_x) / 2.0, -total_drop + 0.5, min_z + total_depth_z - 1.0)
	glow.omni_range = 6.0
	glow.light_energy = 1.5
	glow.light_color = Color(0.4, 0.6, 1.0)
	glow.shadow_enabled = false
	add_child(glow)


func _build_collision(floor_positions: Array, wall_positions: Array) -> void:
	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.name = "FloorCollision"
	add_child(floor_body)

	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(TILE_SIZE, 0.2, TILE_SIZE)
	for pos in floor_positions:
		var col := CollisionShape3D.new()
		col.shape = floor_box
		col.position = pos as Vector3 + Vector3(0, -0.1, 0)
		floor_body.add_child(col)

	# Wall collision
	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	wall_body.name = "WallCollision"
	add_child(wall_body)

	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)
	for pos in wall_positions:
		var col := CollisionShape3D.new()
		col.shape = wall_box
		col.position = pos as Vector3 + Vector3(0, WALL_HEIGHT / 2.0, 0)
		wall_body.add_child(col)


# --- Props ---

func _place_props() -> void:
	# Fountain in plaza center
	_build_fountain()

	# Stone benches around the plaza
	_build_plaza_benches()

	# Town well near the tavern
	_build_well(Vector3(10 * TILE_SIZE, 0, 14 * TILE_SIZE))

	# Blacksmith forge (outdoor anvil + fire near the blacksmith building)
	_build_forge()

	# Barrel & crate clusters scattered around
	_build_barrel_cluster(Vector3(14 * TILE_SIZE, 0, 8 * TILE_SIZE), 3)
	_build_barrel_cluster(Vector3(24 * TILE_SIZE, 0, 8 * TILE_SIZE), 2)
	_build_barrel_cluster(Vector3(4 * TILE_SIZE, 0, 23 * TILE_SIZE), 4)
	_build_barrel_cluster(Vector3(35 * TILE_SIZE, 0, 23 * TILE_SIZE), 3)

	# Trees in garden areas
	_place_garden_trees()

	# Signposts at key locations
	_build_signpost(_stairs_pos + Vector3(-4.0, 0, -2.0), "Dungeon Entrance")
	_build_signpost(Vector3(TOWN_WIDTH / 2 * TILE_SIZE, 0, 9 * TILE_SIZE), "Marketplace")

	# Lanterns along paths
	_place_path_lanterns()

	# Market awnings over stalls
	_build_market_awnings()

	# Decorative plaza ring (stone border)
	_build_plaza_ring()


func _build_fountain() -> void:
	var cx := (TOWN_WIDTH / 2) * TILE_SIZE
	var cz := (TOWN_HEIGHT / 2) * TILE_SIZE

	# Interactable StaticBody3D root for the fountain
	var fountain_body := StaticBody3D.new()
	fountain_body.name = "Fountain"
	fountain_body.position = Vector3(cx, 0.0, cz)
	fountain_body.collision_layer = 128 | 1  # layer 8 (interactable) + layer 1 (physical)
	fountain_body.collision_mask = 0
	fountain_body.add_to_group("interactables")
	fountain_body.set_script(preload("res://scripts/levels/fountain.gd"))
	var col_shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 2.2
	cyl_shape.height = 3.0
	col_shape.shape = cyl_shape
	col_shape.position = Vector3(0, 1.5, 0)
	fountain_body.add_child(col_shape)

	# Basin (wide, short cylinder)
	var basin_mi := MeshInstance3D.new()
	var basin := CylinderMesh.new()
	basin.top_radius = 2.0
	basin.bottom_radius = 2.2
	basin.height = 0.6
	basin_mi.mesh = basin
	basin_mi.position = Vector3(0, 0.3, 0)
	var basin_mat := StandardMaterial3D.new()
	basin_mat.albedo_color = Color(0.5, 0.5, 0.55)
	basin_mat.roughness = 0.6
	basin_mi.material_override = basin_mat
	fountain_body.add_child(basin_mi)

	# Central pillar
	var pillar_mi := MeshInstance3D.new()
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.3
	pillar.bottom_radius = 0.4
	pillar.height = 2.0
	pillar_mi.mesh = pillar
	pillar_mi.position = Vector3(0, 1.0, 0)
	pillar_mi.material_override = basin_mat
	fountain_body.add_child(pillar_mi)

	# Top orb
	var orb_mi := MeshInstance3D.new()
	orb_mi.mesh = SphereMesh.new()
	orb_mi.position = Vector3(0, 2.2, 0)
	orb_mi.scale = Vector3(0.35, 0.35, 0.35)
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(0.4, 0.7, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.3, 0.6, 1.0)
	orb_mat.emission_energy_multiplier = 2.0
	orb_mi.material_override = orb_mat
	fountain_body.add_child(orb_mi)

	# Water particles
	var water := GPUParticles3D.new()
	water.position = Vector3(0, 2.0, 0)
	water.amount = 30
	water.lifetime = 1.2
	water.explosiveness = 0.0
	water.randomness = 0.3
	water.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 40.0
	pmat.initial_velocity_min = 1.0
	pmat.initial_velocity_max = 2.0
	pmat.gravity = Vector3(0, -5, 0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.08
	pmat.color = Color(0.5, 0.7, 1.0, 0.7)
	water.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.5, 0.7, 1.0, 0.6)
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.3, 0.5, 0.9)
	water_mat.emission_energy_multiplier = 1.0
	water_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = water_mat
	water.draw_pass_1 = quad
	fountain_body.add_child(water)

	# Fountain light
	var fl := OmniLight3D.new()
	fl.position = Vector3(0, 2.5, 0)
	fl.omni_range = 10.0
	fl.light_energy = 1.2
	fl.light_color = Color(0.6, 0.8, 1.0)
	fl.shadow_enabled = true
	fl.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	fountain_body.add_child(fl)

	add_child(fountain_body)


func _build_plaza_ring() -> void:
	# Decorative stone ring on the plaza floor around the fountain
	var cx := (TOWN_WIDTH / 2) * TILE_SIZE
	var cz := (TOWN_HEIGHT / 2) * TILE_SIZE
	var ring_segments := 32
	var inner_r := 4.0
	var outer_r := 4.6
	var ring_h := 0.15

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in ring_segments:
		var a0: float = TAU * i / ring_segments
		var a1: float = TAU * (i + 1) / ring_segments
		var cos0 := cos(a0)
		var sin0 := sin(a0)
		var cos1 := cos(a1)
		var sin1 := sin(a1)

		# Top face of ring segment
		var p0 := Vector3(cos0 * inner_r, ring_h, sin0 * inner_r)
		var p1 := Vector3(cos0 * outer_r, ring_h, sin0 * outer_r)
		var p2 := Vector3(cos1 * outer_r, ring_h, sin1 * outer_r)
		var p3 := Vector3(cos1 * inner_r, ring_h, sin1 * inner_r)
		_add_quad(st, p0, p1, p2, p3)

	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(cx, 0, cz)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.45, 0.42, 0.4)
	ring_mat.roughness = 0.5
	mi.material_override = ring_mat
	add_child(mi)


func _build_plaza_benches() -> void:
	var cx := (TOWN_WIDTH / 2) * TILE_SIZE
	var cz := (TOWN_HEIGHT / 2) * TILE_SIZE
	var bench_dist := 5.5

	# 4 benches at cardinal directions, just outside the stone ring
	var offsets := [
		Vector3(bench_dist, 0, 0),
		Vector3(-bench_dist, 0, 0),
		Vector3(0, 0, bench_dist),
		Vector3(0, 0, -bench_dist),
	]
	for off in offsets:
		_build_bench(Vector3(cx, 0, cz) + off, off.z != 0.0)


func _build_bench(pos: Vector3, rotated: bool) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.5, 0.33, 0.15)
	wood_mat.roughness = 0.85

	# Seat plank
	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	if rotated:
		seat_mesh.size = Vector3(0.3, 0.08, 1.4)
	else:
		seat_mesh.size = Vector3(1.4, 0.08, 0.3)
	seat.mesh = seat_mesh
	seat.position = pos + Vector3(0, 0.45, 0)
	seat.material_override = wood_mat
	add_child(seat)

	# Two legs
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.1, 0.45, 0.1)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.25, 0.22, 0.2)
	for i in [-1, 1]:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		if rotated:
			leg.position = pos + Vector3(0, 0.225, i * 0.5)
		else:
			leg.position = pos + Vector3(i * 0.5, 0.225, 0)
		leg.material_override = iron_mat
		add_child(leg)


func _build_well(pos: Vector3) -> void:
	# Circular stone well
	var well_mat := StandardMaterial3D.new()
	well_mat.albedo_color = Color(0.42, 0.4, 0.38)
	well_mat.roughness = 0.8

	# Base cylinder (wall)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.0
	cyl.height = 0.8
	base.mesh = cyl
	base.position = pos + Vector3(0, 0.4, 0)
	base.material_override = well_mat
	add_child(base)

	# Cross-beam (wooden support above)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)

	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.1, 1.5, 0.1)
	beam.mesh = beam_mesh
	beam.position = pos + Vector3(-0.7, 1.5, 0)
	beam.material_override = wood_mat
	add_child(beam)

	var beam2 := MeshInstance3D.new()
	beam2.mesh = beam_mesh
	beam2.position = pos + Vector3(0.7, 1.5, 0)
	beam2.material_override = wood_mat
	add_child(beam2)

	# Horizontal beam
	var hbeam := MeshInstance3D.new()
	var hbeam_mesh := BoxMesh.new()
	hbeam_mesh.size = Vector3(1.6, 0.1, 0.1)
	hbeam.mesh = hbeam_mesh
	hbeam.position = pos + Vector3(0, 2.3, 0)
	hbeam.material_override = wood_mat
	add_child(hbeam)

	# Bucket (small box dangling)
	var bucket := MeshInstance3D.new()
	var bucket_mesh := BoxMesh.new()
	bucket_mesh.size = Vector3(0.2, 0.15, 0.2)
	bucket.mesh = bucket_mesh
	bucket.position = pos + Vector3(0, 1.8, 0)
	bucket.material_override = wood_mat
	add_child(bucket)

	# Rope (thin cylinder)
	var rope := MeshInstance3D.new()
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = 0.015
	rope_mesh.bottom_radius = 0.015
	rope_mesh.height = 0.5
	rope.mesh = rope_mesh
	rope.position = pos + Vector3(0, 2.05, 0)
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.55, 0.45, 0.3)
	rope.material_override = rope_mat
	add_child(rope)


func _build_forge() -> void:
	# Find the Blacksmith building
	var smith_rect: Rect2i
	var found := false
	for b in buildings:
		if b.get("label", "") == "Blacksmith":
			smith_rect = b["rect"]
			found = true
			break
	if not found:
		return

	var forge_x: float = (smith_rect.position.x + smith_rect.size.x / 2) * TILE_SIZE
	var forge_z: float = (smith_rect.position.y + smith_rect.size.y) * TILE_SIZE + 3.0

	# Anvil (dark metallic box)
	var anvil := MeshInstance3D.new()
	var anvil_mesh := BoxMesh.new()
	anvil_mesh.size = Vector3(0.6, 0.5, 0.35)
	anvil.mesh = anvil_mesh
	anvil.position = Vector3(forge_x, 0.25, forge_z)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color(0.2, 0.2, 0.22)
	iron_mat.metallic = 0.8
	iron_mat.roughness = 0.4
	anvil.material_override = iron_mat
	add_child(anvil)

	# Forge fire pit (short box with emissive glow)
	var pit := MeshInstance3D.new()
	var pit_mesh := BoxMesh.new()
	pit_mesh.size = Vector3(1.0, 0.4, 1.0)
	pit.mesh = pit_mesh
	pit.position = Vector3(forge_x + 2.0, 0.2, forge_z)
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(0.3, 0.15, 0.05)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.4, 0.1)
	fire_mat.emission_energy_multiplier = 2.0
	pit.material_override = fire_mat
	add_child(pit)

	# Fire particles
	var fire := GPUParticles3D.new()
	fire.position = Vector3(forge_x + 2.0, 0.6, forge_z)
	fire.amount = 20
	fire.lifetime = 0.8
	fire.explosiveness = 0.1
	fire.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 15.0
	pmat.initial_velocity_min = 0.5
	pmat.initial_velocity_max = 1.5
	pmat.gravity = Vector3(0, -1, 0)
	pmat.scale_min = 0.05
	pmat.scale_max = 0.12
	pmat.color = Color(1.0, 0.6, 0.1, 0.9)
	fire.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var fire_draw_mat := StandardMaterial3D.new()
	fire_draw_mat.albedo_color = Color(1.0, 0.5, 0.1, 0.8)
	fire_draw_mat.emission_enabled = true
	fire_draw_mat.emission = Color(1.0, 0.5, 0.1)
	fire_draw_mat.emission_energy_multiplier = 3.0
	fire_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = fire_draw_mat
	fire.draw_pass_1 = quad
	add_child(fire)

	# Smoke particles above the forge
	var smoke := GPUParticles3D.new()
	smoke.position = Vector3(forge_x + 2.0, 1.5, forge_z)
	smoke.amount = 10
	smoke.lifetime = 2.5
	smoke.explosiveness = 0.0
	smoke.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 8, 6))

	var smat := ParticleProcessMaterial.new()
	smat.direction = Vector3(0, 1, 0)
	smat.spread = 10.0
	smat.initial_velocity_min = 0.3
	smat.initial_velocity_max = 0.8
	smat.gravity = Vector3(0, 0.5, 0)
	smat.scale_min = 0.1
	smat.scale_max = 0.3
	smat.color = Color(0.4, 0.4, 0.4, 0.3)
	smoke.process_material = smat

	var smoke_quad := QuadMesh.new()
	smoke_quad.size = Vector2(0.3, 0.3)
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.25)
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_quad.material = smoke_mat
	smoke.draw_pass_1 = smoke_quad
	add_child(smoke)

	# Forge light
	var forge_light := OmniLight3D.new()
	forge_light.position = Vector3(forge_x + 2.0, 1.0, forge_z)
	forge_light.omni_range = 6.0
	forge_light.light_energy = 1.5
	forge_light.light_color = Color(1.0, 0.6, 0.2)
	forge_light.shadow_enabled = false
	add_child(forge_light)


func _build_barrel_cluster(pos: Vector3, count: int) -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)
	wood_mat.roughness = 0.9

	var iron_band_mat := StandardMaterial3D.new()
	iron_band_mat.albedo_color = Color(0.25, 0.22, 0.2)

	for i in count:
		var offset := Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		# Barrel (cylinder)
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.35
		cyl.height = 0.8
		barrel.mesh = cyl
		barrel.position = pos + offset + Vector3(0, 0.4, 0)
		barrel.material_override = wood_mat
		add_child(barrel)

	# Add a crate or two next to barrels
	if count >= 3:
		var crate := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(0.6, 0.5, 0.6)
		crate.mesh = crate_mesh
		crate.position = pos + Vector3(2.0, 0.25, 0)
		crate.material_override = wood_mat
		add_child(crate)


func _place_garden_trees() -> void:
	var tree_color := Color(0.2, 0.45, 0.15)
	var trunk_color := Color(0.4, 0.25, 0.1)

	# Place trees on garden tiles (sparse — skip some)
	var placed_count := 0
	for x in TOWN_WIDTH:
		for y in TOWN_HEIGHT:
			if grid[x][y] != 6:
				continue
			# Every other garden tile, roughly
			placed_count += 1
			if placed_count % 3 != 0:
				continue

			var world_pos := Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			_build_tree(world_pos, tree_color, trunk_color)


func _build_tree(pos: Vector3, leaf_color: Color, trunk_color: Color) -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = trunk_color
	trunk_mat.roughness = 0.9

	# Trunk
	var trunk := MeshInstance3D.new()
	var tcyl := CylinderMesh.new()
	tcyl.top_radius = 0.08
	tcyl.bottom_radius = 0.12
	tcyl.height = 1.8
	trunk.mesh = tcyl
	trunk.position = pos + Vector3(0, 0.9, 0)
	trunk.material_override = trunk_mat
	add_child(trunk)

	# Canopy (sphere)
	var canopy := MeshInstance3D.new()
	canopy.mesh = SphereMesh.new()
	canopy.position = pos + Vector3(0, 2.3, 0)
	canopy.scale = Vector3(1.0, 0.8, 1.0)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = leaf_color
	leaf_mat.roughness = 0.95
	canopy.material_override = leaf_mat
	add_child(canopy)


func _build_market_awnings() -> void:
	# Colorful cloth awnings over market stall buildings
	var awning_colors := [
		Color(0.7, 0.15, 0.1),  # Red
		Color(0.1, 0.2, 0.65),  # Blue
		Color(0.6, 0.55, 0.1),  # Gold
	]
	var color_idx := 0

	for b in buildings:
		var label: String = b.get("label", "")
		if "Stall" not in label:
			continue
		var rect: Rect2i = b["rect"]
		var h: float = b.get("height", BUILDING_HEIGHT)

		var bx1: float = rect.position.x * TILE_SIZE - TILE_SIZE / 2.0
		var bx2: float = (rect.position.x + rect.size.x) * TILE_SIZE - TILE_SIZE / 2.0
		var bz2: float = (rect.position.y + rect.size.y) * TILE_SIZE - TILE_SIZE / 2.0

		# Awning — a thin angled quad extending from the front wall
		var awning := MeshInstance3D.new()
		var awning_mesh := BoxMesh.new()
		awning_mesh.size = Vector3(bx2 - bx1 + 0.5, 0.05, 2.0)
		awning.mesh = awning_mesh
		awning.position = Vector3((bx1 + bx2) / 2.0, h - 0.3, bz2 + 1.0)
		awning.rotation.x = -0.15  # Slight tilt

		var awning_mat := StandardMaterial3D.new()
		awning_mat.albedo_color = awning_colors[color_idx % awning_colors.size()]
		awning_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		awning.material_override = awning_mat
		add_child(awning)

		color_idx += 1


func _build_signpost(pos: Vector3, text: String) -> void:
	var post_mi := MeshInstance3D.new()
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.06
	post.height = 1.5
	post_mi.mesh = post
	post_mi.position = pos + Vector3(0, 0.75, 0)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.3, 0.15)
	post_mi.material_override = wood_mat
	add_child(post_mi)

	# Sign plank
	var sign_mi := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(1.2, 0.4, 0.06)
	sign_mi.mesh = sign_mesh
	sign_mi.position = pos + Vector3(0, 1.5, 0.06)
	sign_mi.material_override = wood_mat
	add_child(sign_mi)

	# 3D label
	var label := Label3D.new()
	label.text = text
	label.position = pos + Vector3(0, 1.5, 0.12)
	label.pixel_size = 0.01
	label.font_size = 32
	label.modulate = Color(0.95, 0.9, 0.75)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _place_path_lanterns() -> void:
	var placed_positions: Array[Vector2] = []
	var min_spacing := 6.0

	for x in TOWN_WIDTH:
		for y in TOWN_HEIGHT:
			if grid[x][y] != 3:
				continue

			# Only place at path edges next to void/wall
			var is_edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < TOWN_WIDTH and ny >= 0 and ny < TOWN_HEIGHT:
					if grid[nx][ny] == 0 or grid[nx][ny] == 2:
						is_edge = true
						break

			if not is_edge:
				continue

			# Spacing check
			var pos2 := Vector2(x, y)
			var too_close := false
			for other in placed_positions:
				if pos2.distance_to(other) < min_spacing / TILE_SIZE:
					too_close = true
					break
			if too_close:
				continue

			placed_positions.append(pos2)
			var world_pos := Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)

			# Lantern post
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.04
			cyl.bottom_radius = 0.05
			cyl.height = 2.5
			post.mesh = cyl
			post.position = world_pos + Vector3(0, 1.25, 0)
			var iron_mat := StandardMaterial3D.new()
			iron_mat.albedo_color = Color(0.2, 0.2, 0.22)
			post.material_override = iron_mat
			add_child(post)

			# Lantern body
			var lantern := MeshInstance3D.new()
			lantern.mesh = BoxMesh.new()
			lantern.position = world_pos + Vector3(0, 2.6, 0)
			lantern.scale = Vector3(0.2, 0.25, 0.2)
			var lantern_mat := StandardMaterial3D.new()
			lantern_mat.albedo_color = Color(1.0, 0.85, 0.5)
			lantern_mat.emission_enabled = true
			lantern_mat.emission = Color(1.0, 0.8, 0.4)
			lantern_mat.emission_energy_multiplier = 1.5
			lantern.material_override = lantern_mat
			add_child(lantern)

			# Light
			var light := OmniLight3D.new()
			light.position = world_pos + Vector3(0, 2.7, 0)
			light.omni_range = 6.0
			light.light_energy = 0.7
			light.light_color = Color(1.0, 0.85, 0.6)
			light.shadow_enabled = false
			add_child(light)


func _add_box_collision(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	body.add_child(col)


# --- Geometry Helpers ---

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
	var b000 := pos + Vector3(-half, 0, -half)
	var b100 := pos + Vector3(half, 0, -half)
	var b110 := pos + Vector3(half, h, -half)
	var b010 := pos + Vector3(-half, h, -half)
	var b001 := pos + Vector3(-half, 0, half)
	var b101 := pos + Vector3(half, 0, half)
	var b111 := pos + Vector3(half, h, half)
	var b011 := pos + Vector3(-half, h, half)

	_add_quad(st, b010, b110, b111, b011)  # Top
	_add_quad(st, b001, b101, b100, b000)  # Bottom
	_add_quad(st, b001, b011, b111, b101)  # Front Z+
	_add_quad(st, b100, b110, b010, b000)  # Back Z-
	_add_quad(st, b000, b010, b011, b001)  # Left X-
	_add_quad(st, b101, b111, b110, b100)  # Right X+


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


# --- Materials ---

func _create_materials() -> void:
	ground_material = _make_stone_material(
		Color(0.65, 0.55, 0.38), Color(0.40, 0.32, 0.22), 0.85, 0.4)

	wall_material = _make_stone_material(
		Color(0.55, 0.50, 0.42), Color(0.35, 0.30, 0.24), 0.8, 0.5)
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	path_material = _make_stone_material(
		Color(0.60, 0.55, 0.42), Color(0.38, 0.34, 0.26), 0.9, 0.35)

	building_material = _make_stone_material(
		Color(0.72, 0.65, 0.52), Color(0.48, 0.42, 0.32), 0.75, 0.5)
	building_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	roof_material = StandardMaterial3D.new()
	roof_material.albedo_color = Color(0.65, 0.28, 0.18)
	roof_material.roughness = 0.8
	roof_material.uv1_triplanar = true

	stairs_material = _make_stone_material(
		Color(0.45, 0.42, 0.50), Color(0.28, 0.26, 0.32), 0.7, 0.4)

	garden_material = StandardMaterial3D.new()
	garden_material.albedo_color = Color(0.25, 0.42, 0.15)
	garden_material.roughness = 0.95
	garden_material.uv1_triplanar = true


func _make_stone_material(base_color: Color, dark_color: Color, roughness: float, tex_scale: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.roughness = roughness

	# Triplanar mapping so SurfaceTool meshes without UVs get textured
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	mat.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)

	# Procedural stone noise texture
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.08
	noise.fractal_octaves = 3

	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.noise = noise
	noise_tex.color_ramp = _make_stone_gradient(base_color, dark_color)

	mat.albedo_texture = noise_tex

	# Detail noise for surface roughness variation
	var detail_noise := FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.15
	detail_noise.fractal_octaves = 4

	var detail_tex := NoiseTexture2D.new()
	detail_tex.width = 128
	detail_tex.height = 128
	detail_tex.seamless = true
	detail_tex.noise = detail_noise
	detail_tex.as_normal_map = true

	mat.normal_enabled = true
	mat.normal_texture = detail_tex
	mat.normal_scale = 0.4

	return mat


func _make_stone_gradient(light: Color, dark: Color) -> Gradient:
	var grad := Gradient.new()
	grad.set_color(0, dark)
	grad.add_point(0.3, dark.lerp(light, 0.3))
	grad.add_point(0.5, light)
	grad.add_point(0.7, dark.lerp(light, 0.6))
	grad.set_color(1, light.lerp(dark, 0.2))
	return grad
