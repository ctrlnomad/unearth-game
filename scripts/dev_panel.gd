extends CanvasLayer
## Dev mode (F1 or `): a slider for every constant in Tuning, live while you play.
## Click the game to keep playing with the panel open. Save writes res://tuning.cfg.

var _rows := {}         # key -> [slider, spinbox] or [colour picker]
var _stats: Label
var _syncing := false


func _ready() -> void:
	layer = 100
	visible = false

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -390
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.82)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root := VBoxContainer.new()
	panel.add_child(root)
	var title := Label.new()
	title.text = "DEV MODE  ·  F1 hides  ·  click the game to play"
	root.add_child(title)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	_button(buttons, "Save", func(): Tuning.save())
	_button(buttons, "Defaults", func(): Tuning.reset_to_defaults())
	_button(buttons, "Reload saved", func(): Tuning.load_saved())
	_button(buttons, "Hide reveals", func(): get_tree().call_group("reveal", "hide_all"))

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 12)
	root.add_child(_stats)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var section := ""
	for key in Tuning.order:
		var sec := key.get_slice(".", 0)
		if sec != section:
			section = sec
			var header := Label.new()
			header.text = sec.to_upper()
			header.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
			list.add_child(header)
		list.add_child(_make_row(key))
	Tuning.changed.connect(_on_changed)


func _process(_delta: float) -> void:
	if not visible:
		return
	var lines := ["%d fps" % Engine.get_frames_per_second()]
	for exhibit in get_tree().get_nodes_in_group("exhibit"):
		if "state_name" in exhibit:
			lines.append("%-15s %s" % [exhibit.name, exhibit.state_name])
		if exhibit.visible_fraction > 0.0005 or exhibit.audio_level > 0.001:
			lines.append("%-15s visible %5.1f%%  audio %3d%%" % [exhibit.name, exhibit.visible_fraction * 100.0, exhibit.audio_level * 100.0])
	_stats.text = "\n".join(lines)


func _make_row(key: String) -> Control:
	var spec: Array = Tuning.specs[key]
	var row := HBoxContainer.new()
	row.tooltip_text = spec[5]
	var label := Label.new()
	label.text = key.get_slice(".", 1)
	label.tooltip_text = spec[5]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size.x = 120
	row.add_child(label)

	var value: Variant = Tuning.v(key)
	if value is Color:
		var picker := ColorPickerButton.new()
		picker.color = value
		picker.edit_alpha = false
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size.y = 22
		picker.color_changed.connect(func(c): if not _syncing: Tuning.set_value(key, c))
		row.add_child(picker)
		_rows[key] = [picker]
	else:
		var is_int := value is int
		var slider := HSlider.new()
		var spin := SpinBox.new()
		for range_ctrl in [slider, spin]:
			range_ctrl.min_value = spec[2]
			range_ctrl.max_value = spec[3]
			range_ctrl.step = spec[4]
			range_ctrl.value = value
			range_ctrl.value_changed.connect(func(x): _edit(key, x, is_int))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.custom_minimum_size.x = 90
		row.add_child(slider)
		row.add_child(spin)
		_rows[key] = [slider, spin]
	return row


func _edit(key: String, x: float, is_int: bool) -> void:
	if _syncing:
		return
	Tuning.set_value(key, int(x) if is_int else x)


func _on_changed(key: String) -> void:
	_syncing = true
	var value: Variant = Tuning.v(key)
	var widgets: Array = _rows[key]
	if value is Color:
		widgets[0].color = value
	else:
		for w in widgets:
			w.value = value
	_syncing = false


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
