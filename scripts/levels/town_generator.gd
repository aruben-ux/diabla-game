extends Node3D

## Procedural town generator. Builds a small walled town with:
##   - Central plaza with fountain
##   - Surrounding buildings (future shop/vendor/quest locations)
##   - Cobblestone paths between buildings
##   - Dungeon entrance stairs at the edge of town
##   - Ambient lighting and decoration

signal town_generated(spawn_position: Vector3, stairs_position: Vector3)

var TILE_SIZE := 3.0
var WALL_HEIGHT := 5.0
var BUILDING_HEIGHT := 4.5
var ROOF_EXTRA := 1.5
var TOWN_WIDTH := 30
var TOWN_HEIGHT := 30

# Grid values: 0=void, 1=plaza, 2=wall, 3=path, 4=building, 5=stairs
var grid: Array = []

# Materials
var ground_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var path_material: StandardMaterial3D
var building_material: StandardMaterial3D
var roof_material: StandardMaterial3D
var stairs_material: StandardMaterial3D

# Building placement data: array of Rect2i
var buildings: Array[Rect2i] = []
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


# --- Central Plaza ---

func _carve_plaza() -> void:
	var cx := TOWN_WIDTH / 2
	var cy := TOWN_HEIGHT / 2
	var radius := 5

	for x in range(cx - radius, cx + radius + 1):
		for y in range(cy - radius, cy + radius + 1):
			if x >= 1 and x < TOWN_WIDTH - 1 and y >= 1 and y < TOWN_HEIGHT - 1:
				var dx := x - cx
				var dy := y - cy
				if dx * dx + dy * dy <= radius * radius:
					grid[x][y] = 1

	_spawn_pos = Vector3(cx * TILE_SIZE, 0.5, cy * TILE_SIZE)


# --- Buildings ---

func _place_buildings() -> void:
	buildings.clear()

	# Predefined building plots around the plaza
	var plots: Array[Rect2i] = [
		# Top-left area
		Rect2i(3, 3, 5, 4),
		Rect2i(3, 8, 4, 3),
		# Top-right area
		Rect2i(22, 3, 5, 4),
		Rect2i(23, 8, 4, 3),
		# Bottom-left area
		Rect2i(3, 22, 5, 5),
		Rect2i(3, 18, 4, 3),
		# Bottom-right area
		Rect2i(22, 22, 5, 5),
		Rect2i(23, 18, 4, 3),
		# Side buildings
		Rect2i(11, 2, 3, 3),
		Rect2i(17, 2, 3, 3),
	]

	for plot in plots:
		# Validate plot fits in grid
		if plot.position.x + plot.size.x >= TOWN_WIDTH - 1:
			continue
		if plot.position.y + plot.size.y >= TOWN_HEIGHT - 1:
			continue

		buildings.append(plot)
		for x in range(plot.position.x, plot.position.x + plot.size.x):
			for y in range(plot.position.y, plot.position.y + plot.size.y):
				grid[x][y] = 4


# --- Dungeon Stairs ---

func _place_stairs() -> void:
	# Place stairs at the bottom-center of town
	var sx := TOWN_WIDTH / 2 - 2
	var sy := TOWN_HEIGHT - 4
	stairs_rect = Rect2i(sx, sy, 4, 3)

	for x in range(sx, sx + 4):
		for y in range(sy, sy + 3):
			if x >= 0 and x < TOWN_WIDTH and y >= 0 and y < TOWN_HEIGHT:
				grid[x][y] = 5

	_stairs_pos = Vector3((sx + 2) * TILE_SIZE, 0.5, (sy + 1) * TILE_SIZE)


# --- Paths ---

func _carve_paths() -> void:
	var cx := TOWN_WIDTH / 2
	var cy := TOWN_HEIGHT / 2

	# Main roads from plaza to edges (N, S, E, W)
	_carve_road(cx, cy - 5, cx, 1, 2)        # North
	_carve_road(cx, cy + 5, cx, TOWN_HEIGHT - 2, 2)  # South
	_carve_road(cx - 5, cy, 1, cy, 2)        # West
	_carve_road(cx + 5, cy, TOWN_WIDTH - 2, cy, 2)   # East

	# Side streets to buildings
	for b in buildings:
		var bx := b.position.x + b.size.x / 2
		var by := b.position.y + b.size.y / 2
		# Connect building to nearest main road axis
		if bx < cx:
			_carve_road(b.position.x + b.size.x, by, cx, by, 1)
		else:
			_carve_road(b.position.x, by, cx, by, 1)


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
				if grid[nx][ny] == 1 or grid[nx][ny] == 3 or grid[nx][ny] == 5:
					return true
	return false


# --- Mesh Building ---

func _build_mesh() -> void:
	for child in get_children():
		child.queue_free()

	var floor_positions := []
	var wall_positions := []
	var path_positions := []
	var building_data := []  # {pos, rect}
	var stairs_positions := []

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

	_build_floor_chunks(floor_positions, "Plaza", ground_material)
	_build_floor_chunks(path_positions, "Path", path_material)
	_build_wall_blocks(wall_positions)
	_build_buildings()
	_build_stairs_mesh(stairs_positions)
	_build_collision(floor_positions + path_positions + stairs_positions, wall_positions)


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
		var b := buildings[i]
		_build_single_building(b, i)


func _build_single_building(rect: Rect2i, idx: int) -> void:
	var x1 := rect.position.x * TILE_SIZE
	var z1 := rect.position.y * TILE_SIZE
	var x2 := (rect.position.x + rect.size.x) * TILE_SIZE
	var z2 := (rect.position.y + rect.size.y) * TILE_SIZE
	var h := BUILDING_HEIGHT

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

	# Signposts near buildings
	_build_signpost(Vector3(buildings[0].position.x * TILE_SIZE - 2.0, 0, (buildings[0].position.y + buildings[0].size.y) * TILE_SIZE + 1.0), "Shop (Coming Soon)")
	if buildings.size() > 2:
		_build_signpost(Vector3(buildings[2].position.x * TILE_SIZE - 2.0, 0, (buildings[2].position.y + buildings[2].size.y) * TILE_SIZE + 1.0), "Armory (Coming Soon)")

	# Stairs sign
	_build_signpost(_stairs_pos + Vector3(-3.0, 0, -2.0), "Dungeon Entrance")

	# Lanterns along paths
	_place_path_lanterns()


func _build_fountain() -> void:
	var cx := (TOWN_WIDTH / 2) * TILE_SIZE
	var cz := (TOWN_HEIGHT / 2) * TILE_SIZE

	# Basin (wide, short cylinder)
	var basin_mi := MeshInstance3D.new()
	var basin := CylinderMesh.new()
	basin.top_radius = 2.0
	basin.bottom_radius = 2.2
	basin.height = 0.6
	basin_mi.mesh = basin
	basin_mi.position = Vector3(cx, 0.3, cz)
	var basin_mat := StandardMaterial3D.new()
	basin_mat.albedo_color = Color(0.5, 0.5, 0.55)
	basin_mat.roughness = 0.6
	basin_mi.material_override = basin_mat
	add_child(basin_mi)

	# Central pillar
	var pillar_mi := MeshInstance3D.new()
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.3
	pillar.bottom_radius = 0.4
	pillar.height = 2.0
	pillar_mi.mesh = pillar
	pillar_mi.position = Vector3(cx, 1.0, cz)
	pillar_mi.material_override = basin_mat
	add_child(pillar_mi)

	# Top orb
	var orb_mi := MeshInstance3D.new()
	orb_mi.mesh = SphereMesh.new()
	orb_mi.position = Vector3(cx, 2.2, cz)
	orb_mi.scale = Vector3(0.35, 0.35, 0.35)
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(0.4, 0.7, 1.0)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(0.3, 0.6, 1.0)
	orb_mat.emission_energy_multiplier = 2.0
	orb_mi.material_override = orb_mat
	add_child(orb_mi)

	# Water particles
	var water := GPUParticles3D.new()
	water.position = Vector3(cx, 2.0, cz)
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
	add_child(water)

	# Fountain light
	var fl := OmniLight3D.new()
	fl.position = Vector3(cx, 2.5, cz)
	fl.omni_range = 10.0
	fl.light_energy = 1.2
	fl.light_color = Color(0.6, 0.8, 1.0)
	fl.shadow_enabled = true
	fl.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	add_child(fl)


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
