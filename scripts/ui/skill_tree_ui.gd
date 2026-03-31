extends Control
class_name SkillTreeUI

## Full-screen skill tree panel. Shows 3 branches side by side,
## each with 6 nodes in a vertical chain. Click to allocate points.

var _panel: Panel
var _title_label: Label
var _points_label: Label
var _close_btn: Button
var _branch_containers: Array[VBoxContainer] = []
var _node_buttons: Dictionary = {}  # node_id -> Button
var _node_rank_labels: Dictionary = {}  # node_id -> Label
var _node_data: Dictionary = {}  # node_id -> node dict

var _tooltip_panel: PanelContainer
var _tooltip_name: Label
var _tooltip_desc: Label
var _tooltip_rank: Label
var _tooltip_effects: Label

var skill_manager: SkillManager


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()


func open(sm: SkillManager) -> void:
	skill_manager = sm
	if skill_manager and not skill_manager.skill_tree_changed.is_connected(_refresh):
		skill_manager.skill_tree_changed.connect(_refresh)
	# Center the panel in the viewport
	var vp_size := get_viewport_rect().size
	var panel_w := 880.0
	var panel_h := 620.0
	_panel.position = Vector2((vp_size.x - panel_w) * 0.5, (vp_size.y - panel_h) * 0.5)
	_panel.size = Vector2(panel_w, panel_h)
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	# Darken background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.1, 0.97)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.55, 0.45, 0.25, 0.9)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# Title
	_title_label = Label.new()
	_title_label.text = tr("Skill Tree")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(0, 8)
	_title_label.size = Vector2(880, 26)
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_panel.add_child(_title_label)

	# Skill points display
	_points_label = Label.new()
	_points_label.text = tr("Skill Points: 0")
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.position = Vector2(0, 34)
	_points_label.size = Vector2(880, 20)
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	_panel.add_child(_points_label)

	# Close button
	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.position = Vector2(846, 6)
	_close_btn.size = Vector2(28, 28)
	_close_btn.pressed.connect(close)
	_panel.add_child(_close_btn)

	# Branch columns — 3 side by side
	var branches_hbox := HBoxContainer.new()
	branches_hbox.position = Vector2(16, 60)
	branches_hbox.size = Vector2(848, 540)
	branches_hbox.add_theme_constant_override("separation", 12)
	_panel.add_child(branches_hbox)

	for i in 3:
		var branch_panel := PanelContainer.new()
		branch_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var branch_sb := StyleBoxFlat.new()
		branch_sb.bg_color = Color(0.1, 0.09, 0.13, 0.8)
		branch_sb.corner_radius_top_left = 6
		branch_sb.corner_radius_top_right = 6
		branch_sb.corner_radius_bottom_left = 6
		branch_sb.corner_radius_bottom_right = 6
		branch_sb.content_margin_left = 8
		branch_sb.content_margin_right = 8
		branch_sb.content_margin_top = 8
		branch_sb.content_margin_bottom = 8
		branch_sb.border_width_left = 1
		branch_sb.border_width_right = 1
		branch_sb.border_width_top = 1
		branch_sb.border_width_bottom = 1
		branch_sb.border_color = Color(0.35, 0.3, 0.25, 0.5)
		branch_panel.add_theme_stylebox_override("panel", branch_sb)
		branches_hbox.add_child(branch_panel)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		branch_panel.add_child(vbox)
		_branch_containers.append(vbox)

	# Tooltip panel
	_build_tooltip()


func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 50
	_tooltip_panel.visible = false

	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	ts.corner_radius_top_left = 4
	ts.corner_radius_top_right = 4
	ts.corner_radius_bottom_left = 4
	ts.corner_radius_bottom_right = 4
	ts.content_margin_left = 10
	ts.content_margin_right = 10
	ts.content_margin_top = 6
	ts.content_margin_bottom = 6
	ts.border_width_left = 1
	ts.border_width_right = 1
	ts.border_width_top = 1
	ts.border_width_bottom = 1
	ts.border_color = Color(0.6, 0.5, 0.3, 0.8)
	_tooltip_panel.add_theme_stylebox_override("panel", ts)

	var tvbox := VBoxContainer.new()
	tvbox.add_theme_constant_override("separation", 3)
	tvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 15)
	_tooltip_name.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_tooltip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvbox.add_child(_tooltip_name)

	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 12)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tooltip_desc.custom_minimum_size = Vector2(200, 0)
	_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvbox.add_child(_tooltip_desc)

	_tooltip_rank = Label.new()
	_tooltip_rank.add_theme_font_size_override("font_size", 12)
	_tooltip_rank.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	_tooltip_rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvbox.add_child(_tooltip_rank)

	_tooltip_effects = Label.new()
	_tooltip_effects.add_theme_font_size_override("font_size", 11)
	_tooltip_effects.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	_tooltip_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvbox.add_child(_tooltip_effects)

	_tooltip_panel.add_child(tvbox)
	add_child(_tooltip_panel)


func _refresh() -> void:
	if not skill_manager:
		return
	_node_buttons.clear()
	_node_rank_labels.clear()
	_node_data.clear()

	var trees := SkillTreeData.get_trees_for_class(skill_manager.character_class)
	_points_label.text = tr("Skill Points: %d") % skill_manager.skill_points

	# Set title based on class
	var class_names := [tr("Warrior"), tr("Mage"), tr("Rogue")]
	var cls_idx: int = clampi(skill_manager.character_class, 0, 2)
	_title_label.text = tr("%s Skill Tree") % class_names[cls_idx]

	for i in mini(trees.size(), 3):
		_populate_branch(_branch_containers[i], trees[i])

	# Update HUD skill bar when tree changes
	_update_hud_skill_bar()


func _populate_branch(container: VBoxContainer, branch: Dictionary) -> void:
	# Clear old children
	for child in container.get_children():
		child.queue_free()

	# Branch title
	var title := Label.new()
	title.text = tr(branch.get("branch_name", "Branch"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	var bc: Color = branch.get("branch_color", Color.WHITE)
	title.add_theme_color_override("font_color", bc)
	container.add_child(title)

	# Branch description
	var desc := Label.new()
	desc.text = tr(branch.get("branch_description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(desc)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.35, 0.3, 0.5)
	container.add_child(sep)

	# Nodes
	var nodes: Array = branch.get("nodes", [])
	for node: Dictionary in nodes:
		var node_id: String = node["id"]
		_node_data[node_id] = node
		var rank: int = skill_manager.get_node_rank(node_id)
		var max_rank: int = node.get("max_rank", 1)
		var can_alloc: bool = skill_manager.can_allocate(node_id)
		var is_active: bool = node.get("type", "passive") == "active"

		# Node row: button + rank label
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var btn := Button.new()
		var short_name: String = node.get("name", "?")
		btn.text = tr(short_name)
		btn.custom_minimum_size = Vector2(200, 36)
		btn.tooltip_text = ""  # We use custom tooltip

		# Color based on state
		var node_color: Color = node.get("icon_color", Color.WHITE)
		var btn_sb := StyleBoxFlat.new()
		btn_sb.corner_radius_top_left = 4
		btn_sb.corner_radius_top_right = 4
		btn_sb.corner_radius_bottom_left = 4
		btn_sb.corner_radius_bottom_right = 4
		btn_sb.border_width_left = 2
		btn_sb.border_width_right = 2
		btn_sb.border_width_top = 2
		btn_sb.border_width_bottom = 2

		if rank >= max_rank:
			# Maxed out
			btn_sb.bg_color = node_color.darkened(0.4)
			btn_sb.border_color = Color(0.9, 0.8, 0.3, 0.8)
		elif rank > 0:
			# Partially invested
			btn_sb.bg_color = node_color.darkened(0.5)
			btn_sb.border_color = node_color.lightened(0.2)
		elif can_alloc:
			# Available
			btn_sb.bg_color = Color(0.15, 0.13, 0.18, 0.9)
			btn_sb.border_color = node_color.darkened(0.2)
		else:
			# Locked
			btn_sb.bg_color = Color(0.1, 0.1, 0.1, 0.7)
			btn_sb.border_color = Color(0.3, 0.3, 0.3, 0.5)

		btn.add_theme_stylebox_override("normal", btn_sb)

		# Hover style
		var hover_sb := btn_sb.duplicate()
		hover_sb.bg_color = hover_sb.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", hover_sb)

		btn.add_theme_font_size_override("font_size", 12)

		# Active skills get a different text color
		if is_active:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		elif rank > 0:
			btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		elif not can_alloc:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		btn.pressed.connect(_on_node_pressed.bind(node_id))
		btn.mouse_entered.connect(_on_node_hover.bind(node_id, btn))
		btn.mouse_exited.connect(_on_node_unhover)
		hbox.add_child(btn)
		_node_buttons[node_id] = btn

		# Rank label
		var rank_lbl := Label.new()
		rank_lbl.text = "%d/%d" % [rank, max_rank]
		rank_lbl.add_theme_font_size_override("font_size", 12)
		if rank >= max_rank:
			rank_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		elif rank > 0:
			rank_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		else:
			rank_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		hbox.add_child(rank_lbl)
		_node_rank_labels[node_id] = rank_lbl

		container.add_child(hbox)


func _on_node_pressed(node_id: String) -> void:
	if not skill_manager:
		return
	if skill_manager.allocate_point(node_id):
		_refresh()


func _on_node_hover(node_id: String, btn: Button) -> void:
	var node: Dictionary = _node_data.get(node_id, {})
	if node.is_empty():
		return
	_tooltip_name.text = tr(node.get("name", "?"))
	_tooltip_desc.text = tr(node.get("description", ""))

	var rank: int = skill_manager.get_node_rank(node_id) if skill_manager else 0
	var max_rank: int = node.get("max_rank", 1)
	_tooltip_rank.text = tr("Rank: %d / %d") % [rank, max_rank]

	var effects: Dictionary = node.get("effects", {})
	var eff_lines := ""
	for key in effects:
		if key == "skill_id":
			eff_lines += tr("Unlocks: %s") % str(effects[key]).capitalize() + "\n"
		else:
			var per_rank: float = effects[key]
			var total: float = per_rank * max(rank, 1)
			eff_lines += tr("%s: +%s per rank") % [key.replace("_", " ").capitalize(), str(per_rank)] + "\n"
	_tooltip_effects.text = eff_lines.strip_edges()

	# Prereqs
	var requires: Array = node.get("requires", [])
	if requires.size() > 0:
		var req_names: Array = []
		for req_id: String in requires:
			var req_node: Dictionary = _node_data.get(req_id, {})
			req_names.append(tr(req_node.get("name", req_id)))
		_tooltip_effects.text += "\n" + tr("Requires: %s") % ", ".join(req_names)

	_tooltip_panel.visible = true

	# Position near button
	var btn_rect: Rect2 = btn.get_global_rect()
	var tp_size := _tooltip_panel.size
	var xpos := btn_rect.position.x + btn_rect.size.x + 10
	var ypos := btn_rect.position.y
	# Clamp to viewport
	var vp_size := get_viewport_rect().size
	if xpos + tp_size.x > vp_size.x:
		xpos = btn_rect.position.x - tp_size.x - 10
	if ypos + tp_size.y > vp_size.y:
		ypos = vp_size.y - tp_size.y - 10
	_tooltip_panel.global_position = Vector2(xpos, ypos)


func _on_node_unhover() -> void:
	_tooltip_panel.visible = false


func _update_hud_skill_bar() -> void:
	# Find the HUD and refresh its skill slot display
	var hud = get_parent()
	if hud and hud.has_method("_refresh_skill_slots"):
		hud._refresh_skill_slots()
