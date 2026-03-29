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

	var src_rect := Rect2(
		player_gx - view_tiles.x / 2.0,
		player_gy - view_tiles.y / 2.0,
		view_tiles.x,
		view_tiles.y
	)
	var dst_rect := Rect2(Vector2.ZERO, map_size)

	draw_texture_rect_region(_map_texture, dst_rect, src_rect)

	# Draw fog overlay
	if _fog_texture and not _is_town:
		draw_texture_rect_region(_fog_texture, dst_rect, src_rect)

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
		var screen_x: float = (ex - (player_gx - view_tiles.x / 2.0)) * MAP_SCALE
		var screen_y: float = (ey - (player_gy - view_tiles.y / 2.0)) * MAP_SCALE
		if screen_x >= 0 and screen_x <= map_size.x and screen_y >= 0 and screen_y <= map_size.y:
			draw_circle(Vector2(screen_x, screen_y), 2.0, enemy_color)

	# Draw stair markers (pulsing, only if revealed)
	var pulse := 0.7 + sin(Time.get_ticks_msec() * 0.005) * 0.3
	var origin_x := player_gx - view_tiles.x / 2.0
	var origin_y := player_gy - view_tiles.y / 2.0
	for stair in _stairs_positions:
		var spos: Vector2 = stair["pos"]
		if not _is_revealed(int(spos.x), int(spos.y)):
			continue
		var sx: float = (spos.x - origin_x) * MAP_SCALE
		var sy: float = (spos.y - origin_y) * MAP_SCALE
		if sx >= -4 and sx <= map_size.x + 4 and sy >= -4 and sy <= map_size.y + 4:
			var color: Color = stairs_up_color if stair["is_up"] else stairs_down_color
			color.a = pulse
			draw_circle(Vector2(sx, sy), 4.0, color)

	# Draw player dot (on top)
	draw_circle(center, 3.0, player_color)

	# Draw other players
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or p == player_ref:
			continue
		var pn := p as Node3D
		if not pn:
			continue
		var px: float = (pn.global_position.x - world_offset.x) / tile_size
		var py: float = (pn.global_position.z - world_offset.z) / tile_size
		var scr_x: float = (px - (player_gx - view_tiles.x / 2.0)) * MAP_SCALE
		var scr_y: float = (py - (player_gy - view_tiles.y / 2.0)) * MAP_SCALE
		if scr_x >= 0 and scr_x <= map_size.x and scr_y >= 0 and scr_y <= map_size.y:
			draw_circle(Vector2(scr_x, scr_y), 3.0, other_player_color)

	# Border
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)


func _process(_delta: float) -> void:
	_reveal_around_player()
	queue_redraw()
