extends CanvasLayer
## Options screen, opened from the OPTIONS button in the cabin. Settings are
## the player's own (not dev tuning), saved to user://options.cfg.

signal closed

const SAVE_PATH := "user://options.cfg"
const AMBER := Color(1.0, 0.72, 0.25)

var _sens: HSlider
var _volume: HSlider
var _fullscreen: CheckButton


func _ready() -> void:
	layer = 50
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.035, 0.96)
	style.border_color = AMBER.darkened(0.45)
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	rows.custom_minimum_size.x = 460
	panel.add_child(rows)

	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", AMBER)
	rows.add_child(title)

	_sens = _slider(rows, "MOUSE SENSITIVITY", 0.02, 1.0, 0.01)
	_volume = _slider(rows, "VOLUME", 0.0, 1.0, 0.01)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "FULLSCREEN"
	_fullscreen.add_theme_color_override("font_color", AMBER.darkened(0.15))
	rows.add_child(_fullscreen)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size.y = 40
	back.pressed.connect(close)
	rows.add_child(back)

	_load()
	_sens.value_changed.connect(func(_x): _apply())
	_volume.value_changed.connect(func(_x): _apply())
	_fullscreen.toggled.connect(func(_x): _apply())
	_apply(false)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	_save()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _slider(parent: Control, text: String, lo: float, hi: float, step: float) -> HSlider:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", AMBER.darkened(0.15))
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.y = 24
	parent.add_child(slider)
	return slider


func _apply(window_too := true) -> void:
	Tuning.set_value("player.mouse_sens", _sens.value)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_volume.value, 0.0001)))
	if window_too:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen.button_pressed else DisplayServer.WINDOW_MODE_WINDOWED)


func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	_sens.value = cfg.get_value("options", "mouse_sens", Tuning.v("player.mouse_sens"))
	_volume.value = cfg.get_value("options", "volume", 0.8)
	_fullscreen.button_pressed = cfg.get_value("options", "fullscreen", false)
	if _fullscreen.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("options", "mouse_sens", _sens.value)
	cfg.set_value("options", "volume", _volume.value)
	cfg.set_value("options", "fullscreen", _fullscreen.button_pressed)
	cfg.save(SAVE_PATH)
