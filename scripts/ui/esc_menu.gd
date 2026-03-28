extends Control

## In-game escape menu. Does NOT pause the game.
## Contains: Resume, Options, Return to Title, Quit Game.
## Options sub-panel: audio volumes, camera zoom, mouse sensitivity.

signal closed

# --- Main menu panel ---
var _main_panel: PanelContainer
var _options_panel: PanelContainer

# --- Options state ---
var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _camera_sens_slider: HSlider


var _main_center: CenterContainer
var _options_center: CenterContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size

	# Semi-transparent backdrop that blocks clicks to the world
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Each panel gets its own full-rect CenterContainer
	_main_center = CenterContainer.new()
	_main_center.set_anchors_preset(PRESET_FULL_RECT)
	_main_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_center)

	_options_center = CenterContainer.new()
	_options_center.set_anchors_preset(PRESET_FULL_RECT)
	_options_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_options_center)

	_build_main_panel()
	_build_options_panel()
	_show_main()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _options_panel.visible:
			_show_main()
		else:
			_close()
		get_viewport().set_input_as_handled()
		return
	# Consume any remaining unhandled input so clicks don't reach the game world
	get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()


# --- Main Panel ---

func _build_main_panel() -> void:
	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(280, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.15, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.5, 0.3, 0.8)
	_main_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var btn_resume := _make_button("Resume")
	btn_resume.pressed.connect(_close)
	vbox.add_child(btn_resume)

	var btn_options := _make_button("Options")
	btn_options.pressed.connect(_show_options)
	vbox.add_child(btn_options)

	var btn_title := _make_button("Return to Title")
	btn_title.pressed.connect(_on_return_to_title)
	vbox.add_child(btn_title)

	var btn_quit := _make_button("Quit Game")
	btn_quit.pressed.connect(_on_quit)
	vbox.add_child(btn_quit)

	_main_panel.add_child(vbox)
	_main_center.add_child(_main_panel)


# --- Options Panel ---

func _build_options_panel() -> void:
	_options_panel = PanelContainer.new()
	_options_panel.custom_minimum_size = Vector2(360, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.15, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.5, 0.3, 0.8)
	_options_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Master Volume
	_master_slider = _add_slider_row(vbox, "Master Volume", _get_bus_volume_linear("Master"))
	_master_slider.value_changed.connect(_on_master_volume_changed)

	# Music Volume
	var music_bus := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_music_slider = _add_slider_row(vbox, "Music Volume", _get_bus_volume_linear(music_bus))
	_music_slider.value_changed.connect(_on_music_volume_changed)

	# SFX Volume
	var sfx_bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_sfx_slider = _add_slider_row(vbox, "SFX Volume", _get_bus_volume_linear(sfx_bus))
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)

	vbox.add_child(HSeparator.new())

	# Camera follow speed
	_camera_sens_slider = _add_slider_row(vbox, "Camera Speed", 0.5, 0.1, 1.0)
	_camera_sens_slider.value_changed.connect(_on_camera_speed_changed)
	# Initialize from current camera if available
	var camera := get_viewport().get_camera_3d()
	if camera and "follow_speed" in camera:
		_camera_sens_slider.value = camera.follow_speed / 24.0  # normalize: 24 = max

	vbox.add_child(HSeparator.new())

	# Fullscreen toggle
	var fs_check := CheckBox.new()
	fs_check.text = "  Fullscreen"
	fs_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_check.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(fs_check)

	# V-Sync toggle
	var vsync_check := CheckBox.new()
	vsync_check.text = "  V-Sync"
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	vsync_check.toggled.connect(_on_vsync_toggled)
	vbox.add_child(vsync_check)

	vbox.add_child(HSeparator.new())

	var btn_back := _make_button("Back")
	btn_back.pressed.connect(_show_main)
	vbox.add_child(btn_back)

	_options_panel.add_child(vbox)
	_options_center.add_child(_options_panel)
	_options_center.visible = false


# --- Helpers ---

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size.y = 36
	return btn


func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float, min_val: float = 0.0, max_val: float = 1.0) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(200, 20)
	parent.add_child(slider)
	return slider


func _show_main() -> void:
	_main_center.visible = true
	_options_center.visible = false


func _show_options() -> void:
	_main_center.visible = false
	_options_center.visible = true


# --- Callbacks ---

func _on_return_to_title() -> void:
	# Disconnect from server and go to main menu / lobby
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if GameManager.is_online_mode:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_quit() -> void:
	get_tree().quit()


func _get_bus_volume_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.001, 1.0)))


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume("Master", value)


func _on_music_volume_changed(value: float) -> void:
	var bus := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_set_bus_volume(bus, value)


func _on_sfx_volume_changed(value: float) -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_set_bus_volume(bus, value)


func _on_camera_speed_changed(value: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and "follow_speed" in camera:
		camera.follow_speed = value * 24.0  # 0.0 – 24.0 range


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_vsync_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
