extends Control

## Minimap showing dungeon layout, player position, and enemy dots.
## Fog of war: unexplored areas are hidden until the player gets close.

const MAP_SCALE := 2.0  # Pixels per dungeon tile
const REVEAL_RADIUS := 5  # Tiles around the player to reveal

@export var map_size := Vector2(180, 180)

var dungeon_grid: Array = []
var grid_width := 0
var grid_height := 0
var tile_size := 3.0
var world_offset := Vector3.ZERO
var player_ref: Node3D = null

var floor_color := Color(0.3, 0.3, 0.35, 0.8)
var wall_color := Color(0.15, 0.15, 0.18, 0.9)
var corridor_color := Color(0.28, 0.28, 0.32, 0.8)
var building_color := Color(0.45, 0.35, 0.25, 0.9)
var stairs_up_color := Color(0.3, 0.7, 0.3, 0.9)
var stairs_down_color := Color(0.3, 0.5, 1.0, 0.9)
var player_color := Color(0.2, 0.7, 1.0)
var enemy_color := Color(1.0, 0.2, 0.2, 0.8)
var other_player_color := Color(0.2, 1.0, 0.4, 0.9)
var bg_color := Color(0.05, 0.05, 0.08, 0.7)
var fog_color := Color(0.0, 0.0, 0.0, 1.0)

## Camera rotation angle in XZ plane. The isometric camera sits at (+X, +Y, +Z)
## so its ground-projected forward is toward (-X, -Z) = 225° = -45° for minimap.
const MAP_ROTATION := -PI / 4.0

var _map_texture: ImageTexture
var _fog_texture: ImageTexture
var _fog_image: Image
var _revealed: Array = []  # 2D bool grid — true = explored
var _needs_redraw := true
var _stairs_positions: Array = []  # [{pos: Vector2, is_up: bool}]
var _is_town := false


func setup(grid: Array, width: int, height: int, ts: float, offset: Vector3 = Vector3.ZERO) -> void:
	dungeon_grid = grid
	grid_width = width
	grid_height = height
	tile_size = ts
	world_offset = offset
	# Town maps are fully revealed; dungeons start fogged
	_is_town = (offset == Vector3.ZERO)
	_init_fog()
	_build_map_texture()


func set_player(p: Node3D) -> void:
	player_ref = p


func _init_fog() -> void:
	_revealed.clear()
	for x in grid_width:
		var col: Array[bool] = []
		col.resize(grid_height)
		if _is_town:
			col.fill(true)
		else:
			col.fill(false)
		_revealed.append(col)
	# Build initial fog image
	_fog_image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	if _is_town:
		_fog_image.fill(Color(0, 0, 0, 0))
	else:
		_fog_image.fill(fog_color)
	_fog_texture = ImageTexture.create_from_image(_fog_image)


func _reveal_around_player() -> void:
	if _is_town or not player_ref or not is_instance_valid(player_ref):
		return
	if grid_width == 0 or grid_height == 0:
		return
	var px := int((player_ref.global_position.x - world_offset.x) / tile_size)
	var py := int((player_ref.global_position.z - world_offset.z) / tile_size)
	var changed := false
	for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy > REVEAL_RADIUS * REVEAL_RADIUS:
				continue
			var gx := px + dx
			var gy := py + dy
			if gx >= 0 and gx < grid_width and gy >= 0 and gy < grid_height:
				if not _revealed[gx][gy]:
					_revealed[gx][gy] = true
					_fog_image.set_pixel(gx, gy, Color(0, 0, 0, 0))
					changed = true
	if changed:
		_fog_texture.update(_fog_image)


func _is_revealed(gx: int, gy: int) -> bool:
	if _is_town:
		return true
	if gx < 0 or gx >= grid_width or gy < 0 or gy >= grid_height:
		return false
	return _revealed[gx][gy]


func debug_reveal_all() -> void:
	for x in grid_width:
		for y in grid_height:
			_revealed[x][y] = true
	_fog_image.fill(Color(0, 0, 0, 0))
	_fog_texture.update(_fog_image)


func _build_map_texture() -> void:
	var img := Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_stairs_positions.clear()

	for x in grid_width:
		for y in grid_height:
			var cell: int = dungeon_grid[x][y]
			match cell:
				1: img.set_pixel(x, y, floor_color)
				2: img.set_pixel(x, y, wall_color)
				3: img.set_pixel(x, y, corridor_color)
				4:
					img.set_pixel(x, y, stairs_up_color)
					_stairs_positions.append({"pos": Vector2(x, y), "is_up": true})
				5:
					img.set_pixel(x, y, stairs_down_color)
					_stairs_positions.append({"pos": Vector2(x, y), "is_up": false})

	_map_texture = ImageTexture.create_from_image(img)
	_needs_redraw = true


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, map_size), bg_color)

	if not _map_texture or not player_ref or not is_instance_valid(player_ref):
		return

	# Calculate player grid position (subtract world offset for dungeon)
	var player_gx := (player_ref.global_position.x - world_offset.x) / tile_size
	var player_gy := (player_ref.global_position.z - world_offset.z) / tile_size

	# Center map on player
	var center := map_size / 2.0
	var view_tiles := map_size / MAP_SCALE

	# Draw map & fog rotated around center to match camera orientation
	var half_diag := view_tiles.length() * 0.5 + 2.0  # Slightly oversized to fill corners
	var src_rect := Rect2(
		player_gx - half_diag,
		player_gy - half_diag,
		half_diag * 2.0,
		half_diag * 2.0
	)
	var oversized := half_diag * 2.0 * MAP_SCALE
	var dst_rect := Rect2(
		center.x - oversized * 0.5,
		center.y - oversized * 0.5,
		oversized,
		oversized
	)

	draw_set_transform(center, MAP_ROTATION, Vector2.ONE)
	var offset_dst := Rect2(dst_rect.position - center, dst_rect.size)
	draw_texture_rect_region(_map_texture, offset_dst, src_rect)
	if _fog_texture and not _is_town:
		draw_texture_rect_region(_fog_texture, offset_dst, src_rect)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Helper to convert world grid pos to rotated screen pos
	var cos_r := cos(MAP_ROTATION)
	var sin_r := sin(MAP_ROTATION)

	# Draw enemy dots (only if revealed)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if not enemy_node:
			continue
		var ex: float = (enemy_node.global_position.x - world_offset.x) / tile_size
		var ey: float = (enemy_node.global_position.z - world_offset.z) / tile_size
		if not _is_revealed(int(ex), int(ey)):
			continue
		var dx: float = (ex - player_gx) * MAP_SCALE
		var dy: float = (ey - player_gy) * MAP_SCALE
		var rx: float = dx * cos_r - dy * sin_r + center.x
		var ry: float = dx * sin_r + dy * cos_r + center.y
		if rx >= 0 and rx <= map_size.x and ry >= 0 and ry <= map_size.y:
			draw_circle(Vector2(rx, ry), 2.0, enemy_color)

	# Draw stair markers (pulsing, only if revealed)
	var pulse := 0.7 + sin(Time.get_ticks_msec() * 0.005) * 0.3
	for stair in _stairs_positions:
		var spos: Vector2 = stair["pos"]
		if not _is_revealed(int(spos.x), int(spos.y)):
			continue
		var sdx: float = (spos.x - player_gx) * MAP_SCALE
		var sdy: float = (spos.y - player_gy) * MAP_SCALE
		var srx: float = sdx * cos_r - sdy * sin_r + center.x
		var sry: float = sdx * sin_r + sdy * cos_r + center.y
		if srx >= -4 and srx <= map_size.x + 4 and sry >= -4 and sry <= map_size.y + 4:
			var color: Color = stairs_up_color if stair["is_up"] else stairs_down_color
			color.a = pulse
			draw_circle(Vector2(srx, sry), 4.0, color)

	# Draw player dot (on top, always centered)
	draw_circle(center, 3.0, player_color)

	# Draw other players
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or p == player_ref:
			continue
		var pn := p as Node3D
		if not pn:
			continue
		var pdx: float = ((pn.global_position.x - world_offset.x) / tile_size - player_gx) * MAP_SCALE
		var pdy: float = ((pn.global_position.z - world_offset.z) / tile_size - player_gy) * MAP_SCALE
		var prx: float = pdx * cos_r - pdy * sin_r + center.x
		var pry: float = pdx * sin_r + pdy * cos_r + center.y
		if prx >= 0 and prx <= map_size.x and pry >= 0 and pry <= map_size.y:
			draw_circle(Vector2(prx, pry), 3.0, other_player_color)

	# Border
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)


func _process(_delta: float) -> void:
	_reveal_around_player()
	queue_redraw()


func get_revealed_data() -> PackedByteArray:
	## Serialize the revealed grid into a compact byte array for caching.
	var data := PackedByteArray()
	data.resize(grid_width * grid_height)
	for x in grid_width:
		for y in grid_height:
			data[x * grid_height + y] = 1 if _revealed[x][y] else 0
	return data


func restore_revealed_data(data: PackedByteArray) -> void:
	## Restore a cached revealed grid. Must be called after setup().
	if data.size() != grid_width * grid_height:
		return
	for x in grid_width:
		for y in grid_height:
			if data[x * grid_height + y] == 1:
				_revealed[x][y] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
	_fog_texture.update(_fog_image)
