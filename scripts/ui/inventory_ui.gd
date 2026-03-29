extends Control

## Grid-based inventory UI with paperdoll equipment and drag-and-drop.
## Grid is 5 columns x 10 rows. Items occupy variable cell sizes.
## Press R while dragging to rotate. Drop outside to drop on ground.

signal closed
signal drop_item_on_ground(item: ItemData)

const CELL_SIZE := 48
const GRID_COLS := Inventory.GRID_W  # 5
const GRID_ROWS := Inventory.GRID_H  # 10

## Colors
const COLOR_GRID_BG := Color(0.12, 0.12, 0.15, 0.95)
const COLOR_CELL_EMPTY := Color(0.18, 0.18, 0.22, 1.0)
const COLOR_CELL_BORDER := Color(0.3, 0.3, 0.35, 1.0)
const COLOR_VALID := Color(0.2, 0.7, 0.2, 0.4)
const COLOR_INVALID := Color(0.8, 0.2, 0.2, 0.4)
const COLOR_EQUIP_SLOT_BG := Color(0.15, 0.15, 0.2, 1.0)
const COLOR_EQUIP_SLOT_BORDER := Color(0.4, 0.35, 0.2, 1.0)

var inventory: Inventory
var player_ref: Node

## Drag state
var _dragging: bool = false
var _drag_entry: Dictionary = {}   # The placed_items entry being moved (empty if from equip)
var _drag_equip_slot: String = ""  # If dragging from equipment slot
var _drag_item: ItemData = null
var _drag_stack: int = 1
var _drag_offset := Vector2.ZERO   # Offset from mouse to item top-left
var _drag_ghost: Control = null     # Visual ghost following mouse

## Node refs (created in _ready)
var _grid_panel: Panel
var _grid_container: Control  # Houses the cell visuals
var _equip_slots: Dictionary = {}  # slot_name -> Panel
var _tooltip: Panel
var _tooltip_label: RichTextLabel
var _gold_label: Label
var _paperdoll_panel: Panel
var _main_panel: Panel
var _tooltip_from_equip: bool = false

## Shop mode state
var _in_shop_mode: bool = false
var _shop_stock: Array = []         # Raw stock dicts from NPC
var _shop_placed: Array = []        # { "item": ItemData, "x": int, "y": int, "price": int, "stock_entry": Dictionary }
var _shop_vendor_name: String = ""
var _shop_panel: Panel              # Panel on the left side showing vendor grid
var _shop_grid_container: Control   # Draws shop item grid
var _shop_title_label: Label
var _shop_gold_label: Label
var _drag_from_shop: bool = false   # True when dragging FROM the shop grid
var _drag_shop_entry: Dictionary = {}  # The shop_placed entry being dragged (for visual only)

const SHOP_GRID_COLS := 5
const SHOP_GRID_ROWS := 10


func setup(inv: Inventory, player: Node) -> void:
	inventory = inv
	player_ref = player
	if not _grid_container:
		_build_ui()
	if not _shop_panel:
		_build_shop_panel()
	inventory.inventory_changed.connect(_refresh)
	inventory.gold_changed.connect(_on_gold_changed)
	if not EventBus.shop_opened.is_connected(_on_event_shop_opened):
		EventBus.shop_opened.connect(_on_event_shop_opened)
	_refresh()
	_update_gold()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		visible = !visible
		if visible:
			_refresh()
		else:
			if _dragging:
				_cancel_drag()
			if _in_shop_mode:
				close_shop()

	if event.is_action_pressed("ui_cancel") and _in_shop_mode and visible:
		close_shop()
		get_viewport().set_input_as_handled()

	if _dragging and event is InputEventKey:
		if event.pressed and event.keycode == KEY_R:
			_rotate_drag_item()


func _input(event: InputEvent) -> void:
	if not visible or not _dragging:
		return
	if event is InputEventMouseMotion:
		_update_ghost_position()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_finish_drag()


## ─── UI BUILDING ───

func _build_ui() -> void:
	# Main panel (right side of screen)
	var main_panel := Panel.new()
	_main_panel = main_panel
	main_panel.name = "MainPanel"
	var paperdoll_w := 260
	var panel_w := paperdoll_w + 24 + CELL_SIZE * GRID_COLS + 16
	var panel_h := CELL_SIZE * GRID_ROWS + 80
	main_panel.size = Vector2(panel_w, panel_h)
	main_panel.position = Vector2(get_viewport_rect().size.x - panel_w - 16, get_viewport_rect().size.y - panel_h - 16)
	main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = COLOR_GRID_BG
	panel_sb.corner_radius_top_left = 6
	panel_sb.corner_radius_top_right = 6
	panel_sb.corner_radius_bottom_left = 6
	panel_sb.corner_radius_bottom_right = 6
	panel_sb.border_width_left = 2
	panel_sb.border_width_right = 2
	panel_sb.border_width_top = 2
	panel_sb.border_width_bottom = 2
	panel_sb.border_color = Color(0.4, 0.35, 0.2)
	main_panel.add_theme_stylebox_override("panel", panel_sb)
	add_child(main_panel)

	# Title
	var title := Label.new()
	title.text = "Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 4)
	title.size = Vector2(panel_w, 20)
	main_panel.add_child(title)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(panel_w - 30, 4)
	close_btn.size = Vector2(24, 24)
	close_btn.pressed.connect(func(): visible = false; if _in_shop_mode: close_shop())
	main_panel.add_child(close_btn)

	# Gold label
	_gold_label = Label.new()
	_gold_label.text = "Gold: 0"
	_gold_label.position = Vector2(12, 26)
	_gold_label.add_theme_color_override("font_color", Color.GOLD)
	main_panel.add_child(_gold_label)

	# ── Paperdoll (left side of panel) ──
	_paperdoll_panel = Panel.new()
	_paperdoll_panel.name = "Paperdoll"
	_paperdoll_panel.position = Vector2(8, 48)
	_paperdoll_panel.size = Vector2(paperdoll_w, CELL_SIZE * GRID_ROWS + 20)
	var pd_sb := StyleBoxFlat.new()
	pd_sb.bg_color = Color(0.1, 0.1, 0.13, 1.0)
	pd_sb.corner_radius_top_left = 4
	pd_sb.corner_radius_top_right = 4
	pd_sb.corner_radius_bottom_left = 4
	pd_sb.corner_radius_bottom_right = 4
	_paperdoll_panel.add_theme_stylebox_override("panel", pd_sb)
	main_panel.add_child(_paperdoll_panel)

	# Equipment slot layout — positions and sizes matching item grid dimensions
	# Sizes: weapon 1x3, helmet 2x2, chest 2x3, boots 2x2, ring 1x1, amulet 1x1, shield 2x2
	var cs := CELL_SIZE
	var gap := 4
	var pad := 6
	# Row 1 (y=pad): helmet + amulet
	# Row 2 (y=pad+2*cs+gap): weapon + chest + shield
	# Row 3 (y=pad+2*cs+gap+3*cs+gap): ring + boots
	var row1_y := pad
	var row2_y := row1_y + 2 * cs + gap
	var row3_y := row2_y + 3 * cs + gap
	var col_weapon_x := pad
	var col_chest_x := pad + 1 * cs + gap
	var col_shield_x := col_chest_x + 2 * cs + gap
	var equip_layout := {
		"helmet":  Vector2(col_chest_x, row1_y),
		"amulet":  Vector2(col_shield_x, row1_y),
		"weapon":  Vector2(col_weapon_x, row2_y),
		"chest":   Vector2(col_chest_x, row2_y),
		"shield":  Vector2(col_shield_x, row2_y),
		"ring":    Vector2(col_weapon_x, row3_y),
		"boots":   Vector2(col_chest_x, row3_y),
	}
	var equip_sizes := {
		"weapon":  Vector2(1 * cs, 3 * cs),
		"helmet":  Vector2(2 * cs, 2 * cs),
		"chest":   Vector2(2 * cs, 3 * cs),
		"boots":   Vector2(2 * cs, 2 * cs),
		"ring":    Vector2(1 * cs, 1 * cs),
		"amulet":  Vector2(1 * cs, 1 * cs),
		"shield":  Vector2(2 * cs, 2 * cs),
	}
	# Only create slots that exist in inventory.equipment
	for slot_name in inventory.equipment:
		var pos: Vector2 = equip_layout.get(slot_name, Vector2(pad, 400))
		var sz: Vector2 = equip_sizes.get(slot_name, Vector2(cs, cs))
		var slot_panel := _create_equip_slot(slot_name, pos, sz)
		_paperdoll_panel.add_child(slot_panel)
		_equip_slots[slot_name] = slot_panel

	# ── Grid (right side of panel) ──
	var grid_x := paperdoll_w + 16
	_grid_container = Control.new()
	_grid_container.name = "GridContainer"
	_grid_container.position = Vector2(grid_x, 48)
	_grid_container.size = Vector2(CELL_SIZE * GRID_COLS, CELL_SIZE * GRID_ROWS)
	_grid_container.mouse_filter = Control.MOUSE_FILTER_STOP
	main_panel.add_child(_grid_container)

	# Draw grid cells background
	_grid_container.draw.connect(_draw_grid)

	# ── Tooltip ──
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.size = Vector2(220, 160)
	_tooltip.z_index = 100
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	tip_sb.border_width_left = 1
	tip_sb.border_width_right = 1
	tip_sb.border_width_top = 1
	tip_sb.border_width_bottom = 1
	tip_sb.border_color = Color(0.5, 0.45, 0.3)
	_tooltip.add_theme_stylebox_override("panel", tip_sb)
	add_child(_tooltip)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.position = Vector2(8, 8)
	_tooltip_label.size = Vector2(204, 144)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_label)


func _build_shop_panel() -> void:
	_shop_panel = Panel.new()
	_shop_panel.name = "ShopPanel"
	var panel_w := CELL_SIZE * SHOP_GRID_COLS + 24
	var panel_h := CELL_SIZE * SHOP_GRID_ROWS + 80
	_shop_panel.size = Vector2(panel_w, panel_h)
	_shop_panel.position = Vector2(16, get_viewport_rect().size.y - panel_h - 16)
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_GRID_BG
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.5, 0.4, 0.25)
	_shop_panel.add_theme_stylebox_override("panel", sb)
	add_child(_shop_panel)

	# Vendor name title
	_shop_title_label = Label.new()
	_shop_title_label.text = "Shop"
	_shop_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_title_label.position = Vector2(0, 4)
	_shop_title_label.size = Vector2(panel_w, 20)
	_shop_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_shop_panel.add_child(_shop_title_label)

	# Gold label
	_shop_gold_label = Label.new()
	_shop_gold_label.text = "Gold: 0"
	_shop_gold_label.position = Vector2(12, 26)
	_shop_gold_label.add_theme_color_override("font_color", Color.GOLD)
	_shop_panel.add_child(_shop_gold_label)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(panel_w - 30, 4)
	close_btn.size = Vector2(24, 24)
	close_btn.pressed.connect(close_shop)
	_shop_panel.add_child(close_btn)

	# Shop grid
	_shop_grid_container = Control.new()
	_shop_grid_container.name = "ShopGridContainer"
	_shop_grid_container.position = Vector2(12, 48)
	_shop_grid_container.size = Vector2(CELL_SIZE * SHOP_GRID_COLS, CELL_SIZE * SHOP_GRID_ROWS)
	_shop_grid_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_grid_container.draw.connect(_draw_shop_grid)
	_shop_grid_container.gui_input.connect(_on_shop_grid_gui_input)
	_shop_panel.add_child(_shop_grid_container)

	_shop_panel.visible = false


func open_shop(vendor_name: String, stock: Array) -> void:
	_in_shop_mode = true
	_shop_vendor_name = vendor_name
	_shop_stock = stock
	_place_shop_stock()
	if not _shop_panel:
		_build_shop_panel()
	_shop_title_label.text = vendor_name
	_update_shop_gold()
	_shop_panel.visible = true
	visible = true
	_refresh()


func close_shop() -> void:
	_in_shop_mode = false
	_shop_stock = []
	_shop_placed = []
	if _shop_panel:
		_shop_panel.visible = false
	EventBus.shop_closed.emit()


func _on_event_shop_opened(vendor_name: String, stock: Array, _vendor_type: String) -> void:
	open_shop(vendor_name, stock)


func _place_shop_stock() -> void:
	## Auto-place vendor stock items into the shop grid.
	_shop_placed = []
	var occupancy: Array = []
	for y in SHOP_GRID_ROWS:
		var row: Array = []
		for x in SHOP_GRID_COLS:
			row.append(false)
		occupancy.append(row)

	for stock_entry in _shop_stock:
		var item := _create_item_from_stock(stock_entry)
		var sz := item.get_grid_size()
		var placed := false
		for gy in SHOP_GRID_ROWS:
			if placed:
				break
			for gx in SHOP_GRID_COLS:
				if gx + sz.x > SHOP_GRID_COLS or gy + sz.y > SHOP_GRID_ROWS:
					continue
				var fits := true
				for dy in sz.y:
					for dx in sz.x:
						if occupancy[gy + dy][gx + dx]:
							fits = false
							break
					if not fits:
						break
				if fits:
					for dy in sz.y:
						for dx in sz.x:
							occupancy[gy + dy][gx + dx] = true
					_shop_placed.append({
						"item": item,
						"x": gx,
						"y": gy,
						"price": int(stock_entry.get("price", 0)),
						"stock_entry": stock_entry,
					})
					placed = true
					break


func _create_item_from_stock(entry: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.id = entry.get("id", "item_%d" % randi())
	item.display_name = entry.get("name", "Item")
	item.description = entry.get("description", "")
	item.item_type = int(entry.get("item_type", ItemData.ItemType.MISC)) as ItemData.ItemType
	item.rarity = int(entry.get("rarity", ItemData.Rarity.COMMON)) as ItemData.Rarity
	item.bonus_damage = entry.get("bonus_damage", 0.0)
	item.bonus_defense = entry.get("bonus_defense", 0.0)
	item.bonus_health = entry.get("bonus_health", 0.0)
	item.bonus_mana = entry.get("bonus_mana", 0.0)
	item.bonus_strength = int(entry.get("bonus_strength", 0))
	item.bonus_dexterity = int(entry.get("bonus_dexterity", 0))
	item.bonus_intelligence = int(entry.get("bonus_intelligence", 0))
	item.heal_amount = entry.get("heal_amount", 0.0)
	item.mana_restore = entry.get("mana_restore", 0.0)
	item.grid_w = int(entry.get("grid_w", 1))
	item.grid_h = int(entry.get("grid_h", 1))
	item.icon_color = ItemData.get_rarity_color(item.rarity)
	return item


func _update_shop_gold() -> void:
	if _shop_gold_label and inventory:
		_shop_gold_label.text = "Gold: %d" % inventory.gold


func _get_sell_price(item: ItemData) -> int:
	var value := 0.0
	value += item.bonus_damage * 5.0
	value += item.bonus_defense * 4.0
	value += item.bonus_health * 0.5
	value += item.bonus_mana * 0.5
	value += item.bonus_strength * 8.0
	value += item.bonus_dexterity * 8.0
	value += item.bonus_intelligence * 8.0
	value += item.heal_amount * 0.3
	value += item.mana_restore * 0.3
	value *= (1.0 + item.rarity * 0.3)
	return maxi(int(value), 1)


func _create_equip_slot(slot_name: String, pos: Vector2, slot_size: Vector2 = Vector2(48, 48)) -> Panel:
	var panel := Panel.new()
	panel.name = "Equip_" + slot_name
	panel.position = pos
	panel.size = slot_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_EQUIP_SLOT_BG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = COLOR_EQUIP_SLOT_BORDER
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Slot label (centered in slot)
	var label := Label.new()
	label.text = slot_name.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2.ZERO
	label.size = slot_size
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.name = "SlotLabel"
	panel.add_child(label)

	# Item display (will be updated in _refresh)
	var item_rect := ColorRect.new()
	item_rect.name = "ItemRect"
	item_rect.position = Vector2(2, 2)
	item_rect.size = slot_size - Vector2(4, 4)
	item_rect.visible = false
	item_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(item_rect)

	var item_label := Label.new()
	item_label.name = "ItemLabel"
	item_label.position = Vector2(2, 2)
	item_label.size = slot_size - Vector2(4, 4)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_label.add_theme_font_size_override("font_size", 10)
	item_label.clip_text = true
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(item_label)

	panel.gui_input.connect(_on_equip_slot_input.bind(slot_name))
	panel.mouse_entered.connect(_on_equip_slot_hover.bind(slot_name))
	panel.mouse_exited.connect(_hide_tooltip)

	return panel


## ─── DRAWING ───

func _draw_grid() -> void:
	if not _grid_container:
		return
	# Draw empty cell backgrounds
	for gy in GRID_ROWS:
		for gx in GRID_COLS:
			var rect := Rect2(gx * CELL_SIZE, gy * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			_grid_container.draw_rect(rect, COLOR_CELL_EMPTY)
			_grid_container.draw_rect(rect, COLOR_CELL_BORDER, false, 1.0)

	if not inventory:
		return

	# Draw placed items
	for entry in inventory.placed_items:
		# Skip item being dragged
		if _dragging and entry == _drag_entry:
			continue
		var item: ItemData = entry["item"]
		var gx: int = entry["x"]
		var gy: int = entry["y"]
		var sz := item.get_grid_size()
		var item_rect := Rect2(gx * CELL_SIZE + 1, gy * CELL_SIZE + 1, sz.x * CELL_SIZE - 2, sz.y * CELL_SIZE - 2)
		var bg_color := ItemData.get_rarity_color(item.rarity) * Color(0.3, 0.3, 0.3, 0.6)
		_grid_container.draw_rect(item_rect, bg_color)
		_grid_container.draw_rect(item_rect, ItemData.get_rarity_color(item.rarity) * Color(1, 1, 1, 0.7), false, 2.0)
		# Item name (truncated)
		var text := item.display_name.left(8)
		var stack_count: int = entry.get("stack", 1)
		if stack_count > 1:
			text = "%s x%d" % [text, stack_count]
		var font := ThemeDB.fallback_font
		var font_size := 11
		var text_pos := Vector2(gx * CELL_SIZE + 4, gy * CELL_SIZE + sz.y * CELL_SIZE * 0.5 + 4)
		_grid_container.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, sz.x * CELL_SIZE - 8, font_size, ItemData.get_rarity_color(item.rarity))

	# Draw drop preview while dragging
	if _dragging and _drag_item:
		var grid_pos := _get_grid_cell_under_mouse()
		if grid_pos.x >= 0:
			var sz := _drag_item.get_grid_size()
			var can_place := inventory.can_place_at(_drag_item, grid_pos.x, grid_pos.y, _drag_entry)
			var preview_color := COLOR_VALID if can_place else COLOR_INVALID
			for dy in sz.y:
				for dx in sz.x:
					var cx := grid_pos.x + dx
					var cy := grid_pos.y + dy
					if cx < GRID_COLS and cy < GRID_ROWS:
						var r := Rect2(cx * CELL_SIZE, cy * CELL_SIZE, CELL_SIZE, CELL_SIZE)
						_grid_container.draw_rect(r, preview_color)


func _draw_shop_grid() -> void:
	if not _shop_grid_container:
		return
	# Draw empty cell backgrounds
	for gy in SHOP_GRID_ROWS:
		for gx in SHOP_GRID_COLS:
			var rect := Rect2(gx * CELL_SIZE, gy * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			_shop_grid_container.draw_rect(rect, Color(0.15, 0.14, 0.18, 1.0))
			_shop_grid_container.draw_rect(rect, Color(0.28, 0.26, 0.3, 1.0), false, 1.0)

	# Draw shop items
	var font := ThemeDB.fallback_font
	for entry in _shop_placed:
		var item: ItemData = entry["item"]
		var gx: int = entry["x"]
		var gy: int = entry["y"]
		var sz := item.get_grid_size()
		var item_rect := Rect2(gx * CELL_SIZE + 1, gy * CELL_SIZE + 1, sz.x * CELL_SIZE - 2, sz.y * CELL_SIZE - 2)
		var bg_color := ItemData.get_rarity_color(item.rarity) * Color(0.3, 0.3, 0.3, 0.6)
		_shop_grid_container.draw_rect(item_rect, bg_color)
		_shop_grid_container.draw_rect(item_rect, ItemData.get_rarity_color(item.rarity) * Color(1, 1, 1, 0.7), false, 2.0)
		# Item name
		var text := item.display_name.left(8)
		var text_pos := Vector2(gx * CELL_SIZE + 4, gy * CELL_SIZE + sz.y * CELL_SIZE * 0.5)
		_shop_grid_container.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, sz.x * CELL_SIZE - 8, 11, ItemData.get_rarity_color(item.rarity))
		# Price below name
		var price_text := "%dg" % entry["price"]
		var price_pos := Vector2(gx * CELL_SIZE + 4, gy * CELL_SIZE + sz.y * CELL_SIZE * 0.5 + 14)
		_shop_grid_container.draw_string(font, price_pos, price_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x * CELL_SIZE - 8, 10, Color(1.0, 0.85, 0.2))

	# Draw sell highlight when dragging player item over shop grid
	if _dragging and not _drag_from_shop and _drag_item:
		var shop_cell := _get_shop_cell_under_mouse()
		if shop_cell.x >= 0:
			var sz := _drag_item.get_grid_size()
			var sell_color := Color(1.0, 0.85, 0.2, 0.3)
			for dy in sz.y:
				for dx in sz.x:
					var cx := shop_cell.x + dx
					var cy := shop_cell.y + dy
					if cx < SHOP_GRID_COLS and cy < SHOP_GRID_ROWS:
						var r := Rect2(cx * CELL_SIZE, cy * CELL_SIZE, CELL_SIZE, CELL_SIZE)
						_shop_grid_container.draw_rect(r, sell_color)


func _get_shop_cell_under_mouse() -> Vector2i:
	if not _shop_grid_container:
		return Vector2i(-1, -1)
	var local := _shop_grid_container.get_local_mouse_position()
	var gx := int(local.x / CELL_SIZE)
	var gy := int(local.y / CELL_SIZE)
	if gx < 0 or gy < 0 or gx >= SHOP_GRID_COLS or gy >= SHOP_GRID_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _get_shop_entry_at(gx: int, gy: int) -> Dictionary:
	for entry in _shop_placed:
		var item: ItemData = entry["item"]
		var ex: int = entry["x"]
		var ey: int = entry["y"]
		var sz := item.get_grid_size()
		if gx >= ex and gx < ex + sz.x and gy >= ey and gy < ey + sz.y:
			return entry
	return {}


func _on_shop_grid_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _get_shop_cell_under_mouse()
		if cell.x < 0:
			return
		var entry := _get_shop_entry_at(cell.x, cell.y)
		if entry.is_empty():
			return
		_start_drag_from_shop(entry)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Right-click to quick-buy
		var cell := _get_shop_cell_under_mouse()
		if cell.x < 0:
			return
		var entry := _get_shop_entry_at(cell.x, cell.y)
		if entry.is_empty():
			return
		_quick_buy(entry)
		get_viewport().set_input_as_handled()


func _handle_shop_grid_hover() -> void:
	if _dragging or not _in_shop_mode:
		return
	var cell := _get_shop_cell_under_mouse()
	if cell.x < 0:
		return
	var entry := _get_shop_entry_at(cell.x, cell.y)
	if entry.is_empty():
		return
	_show_shop_item_tooltip(entry)


func _process(_delta: float) -> void:
	if visible and _grid_container:
		_grid_container.queue_redraw()
		_handle_grid_hover()
	if visible and _in_shop_mode and _shop_grid_container:
		_shop_grid_container.queue_redraw()
		_handle_shop_grid_hover()


## ─── GRID INTERACTION ───

func _get_grid_cell_under_mouse() -> Vector2i:
	if not _grid_container:
		return Vector2i(-1, -1)
	var local := _grid_container.get_local_mouse_position()
	var gx := int(local.x / CELL_SIZE)
	var gy := int(local.y / CELL_SIZE)
	if gx < 0 or gy < 0 or gx >= GRID_COLS or gy >= GRID_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _handle_grid_hover() -> void:
	if _dragging or not inventory:
		return
	var cell := _get_grid_cell_under_mouse()
	if cell.x < 0:
		if not _tooltip_from_equip:
			_hide_tooltip()
		return
	var entry := inventory.get_entry_at(cell.x, cell.y)
	if entry.is_empty():
		_hide_tooltip()
		return
	_show_item_tooltip(entry["item"], entry.get("stack", 1))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hide_tooltip()


## ─── DRAG AND DROP ───

func _on_grid_gui_input(event: InputEvent) -> void:
	if not inventory:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cell := _get_grid_cell_under_mouse()
		if cell.x < 0:
			return
		var entry := inventory.get_entry_at(cell.x, cell.y)
		if entry.is_empty():
			return
		_start_drag_from_grid(entry)
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var cell := _get_grid_cell_under_mouse()
		if cell.x < 0:
			return
		var entry := inventory.get_entry_at(cell.x, cell.y)
		if entry.is_empty():
			return
		_right_click_item(entry)
		get_viewport().set_input_as_handled()


func _right_click_item(entry: Dictionary) -> void:
	var item: ItemData = entry["item"]
	if _in_shop_mode:
		# Right-click to quick-sell in shop mode
		var sell_price := _get_sell_price(item)
		inventory.remove_entry(entry)
		inventory.gold += sell_price
		inventory.gold_changed.emit(inventory.gold)
		_update_shop_gold()
		_notify_server_gold()
		_refresh()
		return
	inventory.equip_item_from_entry(entry, player_ref)


func _start_drag_from_grid(entry: Dictionary) -> void:
	_dragging = true
	_drag_entry = entry
	_drag_equip_slot = ""
	_drag_from_shop = false
	_drag_shop_entry = {}
	_drag_item = entry["item"]
	_drag_stack = entry.get("stack", 1)
	_hide_tooltip()
	_create_drag_ghost()


func _start_drag_from_equip(slot_name: String) -> void:
	var item: ItemData = inventory.equipment[slot_name]
	if item == null:
		return
	_dragging = true
	_drag_entry = {}
	_drag_equip_slot = slot_name
	_drag_from_shop = false
	_drag_shop_entry = {}
	_drag_item = item
	_drag_stack = 1
	_hide_tooltip()
	_create_drag_ghost()


func _start_drag_from_shop(shop_entry: Dictionary) -> void:
	var item: ItemData = shop_entry["item"]
	var price: int = shop_entry["price"]
	if not inventory or inventory.gold < price:
		return  # Can't afford
	# Create a fresh copy for the drag
	_dragging = true
	_drag_entry = {}
	_drag_equip_slot = ""
	_drag_from_shop = true
	_drag_shop_entry = shop_entry
	_drag_item = _create_item_from_stock(shop_entry["stock_entry"])
	_drag_stack = 1
	_hide_tooltip()
	_create_drag_ghost()


func _create_drag_ghost() -> void:
	if _drag_ghost:
		_drag_ghost.queue_free()
	_drag_ghost = ColorRect.new()
	var sz := _drag_item.get_grid_size()
	_drag_ghost.size = Vector2(sz.x * CELL_SIZE, sz.y * CELL_SIZE)
	_drag_ghost.color = ItemData.get_rarity_color(_drag_item.rarity) * Color(1, 1, 1, 0.5)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 50

	var ghost_label := Label.new()
	ghost_label.text = _drag_item.display_name
	ghost_label.position = Vector2(4, 4)
	ghost_label.add_theme_font_size_override("font_size", 10)
	ghost_label.add_theme_color_override("font_color", ItemData.get_rarity_color(_drag_item.rarity))
	ghost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.add_child(ghost_label)

	add_child(_drag_ghost)
	_update_ghost_position()


func _update_ghost_position() -> void:
	if _drag_ghost:
		_drag_ghost.global_position = get_global_mouse_position() - _drag_ghost.size * 0.5


func _rotate_drag_item() -> void:
	if not _drag_item:
		return
	_drag_item.rotated = !_drag_item.rotated
	# Rebuild ghost with new size
	_create_drag_ghost()


func _finish_drag() -> void:
	if not _dragging:
		return

	var placed := false

	# --- Shop buy: dragging from shop grid to player inventory ---
	if _drag_from_shop:
		# Can only drop on player grid or equip slot
		var target_equip := _get_equip_slot_under_mouse()
		if not target_equip.is_empty():
			placed = _try_buy_to_equip(target_equip)
		if not placed:
			var grid_cell := _get_grid_cell_under_mouse()
			if grid_cell.x >= 0:
				placed = _try_buy_to_grid(grid_cell)
		# If not placed, just cancel (don't drop on ground)
		_end_drag()
		return

	# --- Sell: dragging player item onto shop grid ---
	if _in_shop_mode and not _drag_from_shop:
		var shop_cell := _get_shop_cell_under_mouse()
		if shop_cell.x >= 0:
			_sell_dragged_item()
			_end_drag()
			return

	# Check if mouse is over a valid equip slot
	var target_equip := _get_equip_slot_under_mouse()
	if not target_equip.is_empty():
		placed = _try_drop_on_equip_slot(target_equip)

	# Check if mouse is over the grid
	if not placed:
		var grid_cell := _get_grid_cell_under_mouse()
		if grid_cell.x >= 0:
			placed = _try_drop_on_grid(grid_cell)

	# If not placed on grid or equip → drop on ground
	if not placed:
		_drop_on_ground()

	_end_drag()


func _try_drop_on_grid(grid_cell: Vector2i) -> bool:
	if not _drag_item:
		return false

	if not _drag_equip_slot.is_empty():
		# Dragging from equipment to grid
		if inventory.can_place_at(_drag_item, grid_cell.x, grid_cell.y):
			_remove_equipment_bonuses(_drag_equip_slot)
			inventory.equipment[_drag_equip_slot] = null
			inventory.item_unequipped.emit(_drag_equip_slot)
			inventory.place_item_at(_drag_item, grid_cell.x, grid_cell.y, _drag_stack)
			return true
		return false

	# Dragging within grid — move the entry
	if not _drag_entry.is_empty():
		if inventory.can_place_at(_drag_item, grid_cell.x, grid_cell.y, _drag_entry):
			_drag_entry["x"] = grid_cell.x
			_drag_entry["y"] = grid_cell.y
			inventory.inventory_changed.emit()
			return true
		return false

	return false


func _try_drop_on_equip_slot(slot_name: String) -> bool:
	if not _drag_item:
		return false
	var expected_slot := inventory._get_equip_slot(_drag_item.item_type)
	if expected_slot != slot_name:
		return false  # Wrong slot type

	if not _drag_equip_slot.is_empty():
		# Swapping between equip slots (shouldn't happen, same type)
		return false

	# From grid → equip
	if not _drag_entry.is_empty():
		inventory.equip_item_from_entry(_drag_entry, player_ref)
		return true

	return false


func _drop_on_ground() -> void:
	if not _drag_item:
		return

	if not _drag_equip_slot.is_empty():
		# Remove from equipment
		_remove_equipment_bonuses(_drag_equip_slot)
		inventory.equipment[_drag_equip_slot] = null
		inventory.item_unequipped.emit(_drag_equip_slot)
	elif not _drag_entry.is_empty():
		# Remove from grid
		inventory.remove_entry(_drag_entry)

	drop_item_on_ground.emit(_drag_item)


## ─── SHOP BUY / SELL ───

func _notify_server_gold() -> void:
	if player_ref and player_ref.has_method("sync_gold_to_server"):
		player_ref.sync_gold_to_server()


func _try_buy_to_grid(grid_cell: Vector2i) -> bool:
	if not _drag_item or not _drag_from_shop or _drag_shop_entry.is_empty():
		return false
	var price: int = _drag_shop_entry["price"]
	if inventory.gold < price:
		return false
	var stock_entry: Dictionary = _drag_shop_entry["stock_entry"]
	var item_type: String = stock_entry.get("type", "")
	if item_type == "potion":
		var potion_id: String = stock_entry.get("id", "")
		if not inventory.can_hold_potion(potion_id):
			return false
		inventory.add_potion(potion_id)
		inventory.gold -= price
		inventory.gold_changed.emit(inventory.gold)
		_update_shop_gold()
		_notify_server_gold()
		return true
	# Equipment — place at the specific grid cell
	if not inventory.can_place_at(_drag_item, grid_cell.x, grid_cell.y):
		return false
	inventory.place_item_at(_drag_item, grid_cell.x, grid_cell.y)
	inventory.gold -= price
	inventory.gold_changed.emit(inventory.gold)
	_update_shop_gold()
	_notify_server_gold()
	return true


func _try_buy_to_equip(slot_name: String) -> bool:
	if not _drag_item or not _drag_from_shop or _drag_shop_entry.is_empty():
		return false
	var expected_slot := inventory._get_equip_slot(_drag_item.item_type)
	if expected_slot != slot_name:
		return false
	var price: int = _drag_shop_entry["price"]
	if inventory.gold < price:
		return false
	# Need to place in grid first, then equip from there
	var pos := inventory.find_free_position(_drag_item)
	if pos.x < 0:
		return false
	inventory.place_item_at(_drag_item, pos.x, pos.y)
	var entry := inventory.get_entry_at(pos.x, pos.y)
	if entry.is_empty():
		return false
	inventory.equip_item_from_entry(entry, player_ref)
	inventory.gold -= price
	inventory.gold_changed.emit(inventory.gold)
	_update_shop_gold()
	_notify_server_gold()
	return true


func _sell_dragged_item() -> void:
	if not _drag_item or not inventory:
		return
	var sell_price := _get_sell_price(_drag_item)
	if not _drag_equip_slot.is_empty():
		_remove_equipment_bonuses(_drag_equip_slot)
		inventory.equipment[_drag_equip_slot] = null
		inventory.item_unequipped.emit(_drag_equip_slot)
	elif not _drag_entry.is_empty():
		inventory.remove_entry(_drag_entry)
	inventory.gold += sell_price
	inventory.gold_changed.emit(inventory.gold)
	_update_shop_gold()
	_notify_server_gold()


func _quick_buy(shop_entry: Dictionary) -> void:
	if not inventory:
		return
	var price: int = shop_entry["price"]
	if inventory.gold < price:
		return
	var stock_entry: Dictionary = shop_entry["stock_entry"]
	var item_type: String = stock_entry.get("type", "")
	if item_type == "potion":
		var potion_id: String = stock_entry.get("id", "")
		if not inventory.can_hold_potion(potion_id):
			return
		inventory.add_potion(potion_id)
	else:
		var item := _create_item_from_stock(stock_entry)
		if not inventory.add_item(item):
			return
	inventory.gold -= price
	inventory.gold_changed.emit(inventory.gold)
	_update_shop_gold()
	_notify_server_gold()
	_refresh()


func _show_shop_item_tooltip(shop_entry: Dictionary) -> void:
	var item: ItemData = shop_entry["item"]
	if not _tooltip:
		return
	_tooltip.visible = true
	var text := "[b]%s[/b]\n" % item.display_name
	text += "[color=#%s]%s[/color]\n" % [
		ItemData.get_rarity_color(item.rarity).to_html(false),
		ItemData.Rarity.keys()[item.rarity]
	]
	text += "[color=#FFD700]Price: %d gold[/color]\n" % shop_entry["price"]
	if item.bonus_damage > 0:
		text += "+%.0f Damage\n" % item.bonus_damage
	if item.bonus_defense > 0:
		text += "+%.0f Defense\n" % item.bonus_defense
	if item.bonus_health > 0:
		text += "+%.0f Health\n" % item.bonus_health
	if item.bonus_mana > 0:
		text += "+%.0f Mana\n" % item.bonus_mana
	if item.bonus_strength > 0:
		text += "+%d Strength\n" % item.bonus_strength
	if item.bonus_dexterity > 0:
		text += "+%d Dexterity\n" % item.bonus_dexterity
	if item.bonus_intelligence > 0:
		text += "+%d Intelligence\n" % item.bonus_intelligence
	if item.heal_amount > 0:
		text += "Heals %.0f HP\n" % item.heal_amount
	if item.mana_restore > 0:
		text += "Restores %.0f Mana\n" % item.mana_restore
	text += "\n[color=#AAAAAA]Left-click drag to buy\nRight-click to quick buy[/color]"
	_tooltip_label.text = text
	_tooltip_label.size.y = 200
	_tooltip.size.y = _tooltip_label.get_content_height() + 16
	var vp_size := get_viewport_rect().size
	var tip_pos := get_global_mouse_position() + Vector2(16, 0)
	if tip_pos.x + _tooltip.size.x > vp_size.x:
		tip_pos.x = get_global_mouse_position().x - _tooltip.size.x - 16
	if tip_pos.y + _tooltip.size.y > vp_size.y:
		tip_pos.y = vp_size.y - _tooltip.size.y
	_tooltip.global_position = tip_pos


func _remove_equipment_bonuses(slot_name: String) -> void:
	var item: ItemData = inventory.equipment[slot_name]
	if item and player_ref:
		inventory._remove_stat_bonuses(item, player_ref)


func _end_drag() -> void:
	_dragging = false
	_drag_entry = {}
	_drag_equip_slot = ""
	_drag_from_shop = false
	_drag_shop_entry = {}
	_drag_item = null
	_drag_stack = 1
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null
	_refresh()


func _cancel_drag() -> void:
	# Just end without placing — item stays where it was
	_dragging = false
	_drag_entry = {}
	_drag_equip_slot = ""
	_drag_from_shop = false
	_drag_shop_entry = {}
	_drag_item = null
	_drag_stack = 1
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null


func _get_equip_slot_under_mouse() -> String:
	for slot_name in _equip_slots:
		var panel: Panel = _equip_slots[slot_name]
		var rect := Rect2(panel.global_position, panel.size)
		if rect.has_point(get_global_mouse_position()):
			return slot_name
	return ""


## ─── EQUIPMENT SLOT INTERACTION ───

func _on_equip_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if inventory.equipment.has(slot_name) and inventory.equipment[slot_name] != null:
			_start_drag_from_equip(slot_name)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if inventory.equipment.has(slot_name) and inventory.equipment[slot_name] != null:
			inventory.unequip_item(slot_name, player_ref)
			get_viewport().set_input_as_handled()


func _on_equip_slot_hover(slot_name: String) -> void:
	if _dragging or not inventory:
		return
	if inventory.equipment.has(slot_name) and inventory.equipment[slot_name] != null:
		_tooltip_from_equip = true
		_show_item_tooltip(inventory.equipment[slot_name])


## ─── REFRESH / TOOLTIP ───

func _refresh() -> void:
	if not inventory or not _grid_container:
		return
	# Connect grid input if not yet
	if not _grid_container.gui_input.is_connected(_on_grid_gui_input):
		_grid_container.gui_input.connect(_on_grid_gui_input)

	_update_gold()
	_refresh_equipment_display()
	_grid_container.queue_redraw()


func _refresh_equipment_display() -> void:
	for slot_name in _equip_slots:
		var panel: Panel = _equip_slots[slot_name]
		var item_rect: ColorRect = panel.get_node("ItemRect")
		var item_label: Label = panel.get_node("ItemLabel")
		var slot_label: Label = panel.get_node("SlotLabel")
		var item: ItemData = inventory.equipment.get(slot_name)
		if item:
			item_rect.color = ItemData.get_rarity_color(item.rarity) * Color(0.5, 0.5, 0.5, 0.8)
			item_rect.visible = true
			item_label.text = item.display_name
			item_label.add_theme_color_override("font_color", ItemData.get_rarity_color(item.rarity))
			slot_label.visible = false
		else:
			item_rect.visible = false
			item_label.text = ""
			slot_label.visible = true


func _show_item_tooltip(item: ItemData, stack: int = 1) -> void:
	if not _tooltip:
		return
	_tooltip.visible = true
	var text := "[b]%s[/b]\n" % item.display_name
	text += "[color=#%s]%s[/color]\n" % [
		ItemData.get_rarity_color(item.rarity).to_html(false),
		ItemData.Rarity.keys()[item.rarity]
	]
	text += "Size: %dx%d\n" % [item.grid_w, item.grid_h]
	if item.bonus_damage > 0:
		text += "+%.0f Damage\n" % item.bonus_damage
	if item.bonus_defense > 0:
		text += "+%.0f Defense\n" % item.bonus_defense
	if item.bonus_health > 0:
		text += "+%.0f Health\n" % item.bonus_health
	if item.bonus_mana > 0:
		text += "+%.0f Mana\n" % item.bonus_mana
	if item.bonus_strength > 0:
		text += "+%d Strength\n" % item.bonus_strength
	if item.bonus_dexterity > 0:
		text += "+%d Dexterity\n" % item.bonus_dexterity
	if item.bonus_intelligence > 0:
		text += "+%d Intelligence\n" % item.bonus_intelligence
	if item.heal_amount > 0:
		text += "Heals %.0f HP\n" % item.heal_amount
	if item.mana_restore > 0:
		text += "Restores %.0f Mana\n" % item.mana_restore
	if _in_shop_mode:
		text += "[color=#FFD700]Sell: %d gold[/color]\n" % _get_sell_price(item)
		text += "[color=#AAAAAA]Drag to shop or right-click to sell[/color]"
	_tooltip_label.text = text
	# Fit tooltip height to content
	_tooltip_label.size.y = 200
	_tooltip.size.y = _tooltip_label.get_content_height() + 16
	# Position tooltip near mouse, clamped to screen
	var vp_size := get_viewport_rect().size
	var tip_pos := get_global_mouse_position() + Vector2(16, 0)
	if tip_pos.x + _tooltip.size.x > vp_size.x:
		tip_pos.x = get_global_mouse_position().x - _tooltip.size.x - 16
	if tip_pos.y + _tooltip.size.y > vp_size.y:
		tip_pos.y = vp_size.y - _tooltip.size.y
	_tooltip.global_position = tip_pos


func _hide_tooltip() -> void:
	_tooltip_from_equip = false
	if _tooltip:
		_tooltip.visible = false


func _on_gold_changed(_amount: int) -> void:
	_update_gold()


func _update_gold() -> void:
	if _gold_label and inventory:
		_gold_label.text = "Gold: %d" % inventory.gold
