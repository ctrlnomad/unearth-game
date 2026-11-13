extends Node
## The rules shared by every level, and the HUD.
##
## A level is a script-built Node3D (loading_bay.gd, reception.gd) that names
## its `battery_spots`, `spawn_point`, `exit_point`, `bounds` and optional
## `ghost_spawns`, and implements set_power(k) and set_exit_door(open). It can
## script its own beats in game_update(game, delta), cell_filled(game, count),
## power_restored(game) and after_caught(game), using the calls below
## (say, hint, spawn_ghost, far_spawn, play, shake, flash).
##
## Loop: charge every power cell with the scanner -> emergency lights and vents
## come on, the vents clear the gas -> the exit opens -> next level.
## A ghost that reaches the Cleaner sends them back to the level door; charged
## cells stay charged.

const Battery := preload("res://scripts/battery.gd")
const Ghost := preload("res://scripts/ghost.gd")
const TouchUI := preload("res://scripts/touch_ui.gd")
const Sfx := preload("res://scripts/sfx.gd")

const VERSION := "0.2"
const LOG := [
	["v0.2 - 2026-11-13 - Moved to Godot", [
		"The game is built in Godot again and exported to the browser, so the laptop game and the iPad build are the same project.",
		"Everything from v0.1 is ported: power cells, scanner dots, ghosts, flares, the vents and Reception.",
		"Touch controls in the Godot build: left thumb moves, right thumb looks, hold FIRE.",
		"The Loading Bay is the original, larger hall with its octagonal ribs and the window on the Earth.",
	]],
	["v0.1 - 2026-11-13 - First browser build", [
		"Menu in the pod, opening sequence, Level 1 (the Loading Bay) and Level 2 (Reception).",
		"Charge power cells with the scanner to restore emergency power.",
		"Ghosts walk toward you, faster while you fire. Hold the beam on one to freeze it.",
		"Scanner rays leave fading dots, so you map the dark by firing. Solar flares light every ghost.",
	]],
]
const INK := Color(0.81, 0.91, 0.92)
const DIM := Color(0.44, 0.56, 0.57)
const AMBER := Color(1.0, 0.7, 0.28)
const GAS := Color(0.31, 0.89, 0.9)

var main: Node
var player: CharacterBody3D
var dots: Node
var level: Node3D
var level_no := 0
var batteries: Array = []
var ghosts: Array = []
var powered := false
var level_time := 0.0
var state := "menu"        # menu, play, caught, leaving, end
var touch_ui: Control

var _powered_t := 0.0
var _state_t := 0.0
var _fade := 1.0
var _shake := 0.0
var _flash := 0.0
var _prox := 0.0
var _geiger := 0.0
var _door_open := 0.0
var _door_sounded := false
var _subs: Array = []
var _sub_until := 0.0
var _hint_until := 0.0
var _sounds := {}
var _hum: AudioStreamPlayer
var _tone: AudioStreamPlayer

var _root: Control
var _obj_title: Label
var _obj: Label
var _cells: Label
var _sub: Label
var _hint: Label
var _menu_tag: Label
var _menu_buttons: HBoxContainer
var _sheet: PanelContainer
var _sheet_title: Label
var _sheet_body: Label
var _sheet_button: Button
var _sheet_action := Callable()


func _ready() -> void:
	_build_hud()
	_hum = _loop(Sfx.hum(86.0), -80.0)
	_tone = _loop(Sfx.hum(220.0, 1.0), -80.0)
	_sounds = {
		"click": _shot(Sfx.click(), -10.0),
		"cell": _shot(Sfx.thud(130.0, 0.5), -6.0),
		"chime": _shot(Sfx.power_down(0.6, 440.0, 880.0), -16.0),
		"sting": _shot(Sfx.power_down(2.6, 300.0, 190.0), -8.0),
		"caught": _shot(Sfx.power_down(3.0, 520.0, 60.0), -6.0),
		"vents": _shot(Sfx.burst(6.0, 0.5, 0.5), -10.0),
		"power": _shot(Sfx.power_down(1.6, 50.0, 110.0), -6.0),
		"freeze": _shot(Sfx.power_down(0.3, 1400.0, 900.0), -16.0),
		"door": _shot(Sfx.burst(1.6, 0.6, 2.2), -9.0),
		"flare": _shot(Sfx.burst(2.5, 0.4, 1.2), -9.0),
		"boom": _shot(Sfx.thud(50.0, 2.2), -3.0),
	}


# ----------------------------------------------------------- level flow ----

func begin_level(lvl: Node3D, number: int) -> void:
	level = lvl
	level_no = number
	batteries.clear()
	ghosts.clear()
	powered = false
	level_time = 0.0
	_door_open = 0.0
	_door_sounded = false
	for spot: Vector3 in level.battery_spots:
		var cell := Battery.new()
		cell.position = spot
		level.add_child(cell)
		cell.filled.connect(_on_cell_filled)
		batteries.append(cell)
	dots.clear()
	state = "play"
	_state_t = 0.0
	_fade = 1.0 if number == 1 else 0.0
	player.gun.enabled = true
	clear_subtitles()
	_set_objective("Restore emergency power: charge the cells")
	_menu_tag.visible = false
	_menu_buttons.visible = false
	touch_ui.playing = true


func say(text: String, seconds := 4.0) -> void:
	_subs.append([text, seconds])


func clear_subtitles() -> void:
	_subs.clear()
	_sub_until = 0.0


func hint(text: String, seconds := 6.0) -> void:
	_hint.text = text
	_hint_until = Tuning.now() + seconds


func play(sound: String) -> void:
	(_sounds[sound] as AudioStreamPlayer).play()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)


func spawn_ghost(at: Vector3, ghost_state := "follow") -> Node3D:
	var g := Ghost.new()
	g.pos = at
	g.state = ghost_state
	g.target = player
	g.bounds = level.bounds
	g.froze.connect(play.bind("freeze"))
	level.add_child(g)
	ghosts.append(g)
	return g


## The level's ghost spawn that is farthest from the player and the other ghosts.
func far_spawn() -> Vector3:
	var best: Vector3 = level.ghost_spawns[0]
	var best_d := -1.0
	for s: Vector3 in level.ghost_spawns:
		var d := s.distance_to(player.global_position)
		for g: Node3D in ghosts:
			if is_instance_valid(g):
				d = minf(d, s.distance_to(g.pos) * 1.5)
		if d > best_d:
			best_d = d
			best = s
	return best


func is_touch() -> bool:
	return main.touch_mode


func _process(delta: float) -> void:
	_state_t += delta
	match state:
		"play":
			_play(delta)
		"caught":
			_caught()
		"leaving":
			_fade = maxf(0.0, _fade - delta * 1.6)
			if _state_t > 0.9:
				_next()
	_shake = maxf(0.0, _shake - delta * 0.6)
	_flash = maxf(0.0, _flash - delta * 0.9)
	if state != "menu":
		if state == "play":
			_fade = minf(1.0, _fade + delta * 1.2)
		main.set_fade(_fade)
		player.shake = _shake
	main.set_fx("flash", _flash)
	main.set_fx("prox", _prox if state == "play" else 0.0)
	_update_hud()


func _play(delta: float) -> void:
	level_time += delta
	var firing: bool = player.gun.firing
	var charging: Node = null
	for cell: Node in batteries:
		if cell.being_charged():
			charging = cell
	_hum.volume_db = lerpf(_hum.volume_db, -17.0 if firing else -80.0, 1.0 - exp(-delta * 18.0))
	_tone.volume_db = lerpf(_tone.volume_db, -22.0 if charging else -80.0, 1.0 - exp(-delta * 14.0))
	if charging:
		_tone.pitch_scale = 0.8 + charging.charge * 1.6

	ghosts = ghosts.filter(func(g): return is_instance_valid(g))
	var near := 99.0
	var here := player.global_position
	for g: Node3D in ghosts:
		g.target_firing = firing
		if g.state == "follow" or g.state == "frozen":
			var d := Vector2(g.pos.x - here.x, g.pos.z - here.z).length()
			near = minf(near, d)
			if g.is_threat() and d < 0.8:
				_get_caught()
				return
	var prox := clampf(1.0 - (near - 1.2) / 7.0, 0.0, 1.0)
	_prox = lerpf(_prox, prox * prox * 0.7, minf(1.0, delta * 4.0))
	_geiger -= delta
	if prox > 0.02 and _geiger <= 0.0:
		play("click")
		_geiger = lerpf(0.5, 0.04, prox) * randf_range(0.6, 1.4)

	if powered:
		var since := level_time - _powered_t
		level.set_power(clampf(since / 2.5, 0.0, 1.0))
		if since > 4.5:
			if not _door_sounded:
				_door_sounded = true
				play("door")
			_door_open = minf(1.0, _door_open + delta / 2.2)
			level.set_exit_door(smoothstep(0.0, 1.0, _door_open))
			var exit: Vector3 = level.exit_point
			if _door_open > 0.7 and Vector2(here.x - exit.x, here.z - exit.z).length() < 2.6:
				state = "leaving"
				_state_t = 0.0
				player.gun.enabled = false
				return
	if level.has_method("game_update"):
		level.game_update(self, delta)


func _on_cell_filled() -> void:
	var count := 0
	for cell: Node in batteries:
		if cell.done:
			count += 1
	play("cell")
	play("chime")
	flash(0.08)
	if level.has_method("cell_filled"):
		level.cell_filled(self, count)
	if count == batteries.size() and not powered:
		powered = true
		_powered_t = level_time
		play("power")
		play("vents")
		shake(0.15)
		for g: Node3D in ghosts:
			if is_instance_valid(g):
				g.vent()
		if level.has_method("power_restored"):
			level.power_restored(self)
		_set_objective("Power restored. Go through the open door")


func _get_caught() -> void:
	state = "caught"
	_state_t = 0.0
	player.cinematic = true
	player.gun.enabled = false
	_hum.volume_db = -80.0
	_tone.volume_db = -80.0
	play("caught")
	clear_subtitles()
	say("It is inside the suit.", 3.0)


func _caught() -> void:
	var k := smoothstep(0.0, 1.0, _state_t / 3.0)
	main.set_fx("cyan", minf(0.92, _state_t / 2.6))
	player.cine_offset = Vector3(0, 0.7 * k, 0)
	player.cine_tilt = Vector3(0.9 * k, 0, 0)
	player.shake = 0.05
	if _state_t < 3.4:
		return
	# Back at the level door. The ghosts scatter to the far corners.
	main.set_fx("cyan", 0.0)
	player.position = level.spawn_point
	player.set_aim(0, 0)
	player.velocity = Vector3.ZERO
	player.cinematic = false
	player.cine_offset = Vector3.ZERO
	player.cine_tilt = Vector3.ZERO
	player.gun.enabled = true
	dots.clear()
	_fade = 0.0
	var live := ghosts.filter(func(g): return is_instance_valid(g) and g.state != "vent")
	ghosts = []
	for g: Node3D in live:
		g.pos = far_spawn()
		g.state = "follow"
		g.immune = 1.0
		g.flare = 0.0
		ghosts.append(g)
	if level.has_method("after_caught"):
		level.after_caught(self)
	state = "play"
	say("...You are back at the door. The charged cells held.", 4.0)


func _next() -> void:
	if level_no == 1:
		main.load_level(2)
		return
	state = "end"
	touch_ui.playing = false
	_obj_title.text = ""
	_obj.text = ""
	_cells.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_sheet("POWER RESTORED",
		"Reception is on emergency power and the vents have cleared the gas. The door to the labs is open.\n\n"
		+ "This is the end of version %s. Next: the Lab, where the Cleaner learns what Omni-23 did to the people who made it." % VERSION,
		"BACK TO THE POD", func(): get_tree().reload_current_scene())


# ------------------------------------------------------------------ HUD ----

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	touch_ui = TouchUI.new()
	_root.add_child(touch_ui)
	_obj_title = _label(DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_obj = _label(INK, HORIZONTAL_ALIGNMENT_LEFT)
	_cells = _label(GAS, HORIZONTAL_ALIGNMENT_LEFT)
	_sub = _label(INK, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _label(AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_tag = _label(DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_menu_tag.text = "UNEARTH v%s - press the START button by the door" % VERSION
	_menu_buttons = HBoxContainer.new()
	_menu_buttons.add_theme_constant_override("separation", 12)
	_root.add_child(_menu_buttons)
	_menu_button("START AT LEVEL 2", func(): main.start_at(2))
	_menu_button("VERSION LOG", _show_log)

	_sheet = PanelContainer.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.008, 0.02, 0.024, 0.95)
	_sheet.add_theme_stylebox_override("panel", bg)
	_sheet.visible = false
	_root.add_child(_sheet)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	_sheet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_sheet_title = Label.new()
	_sheet_title.add_theme_color_override("font_color", GAS)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sheet_title)
	_sheet_body = Label.new()
	_sheet_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_body.add_theme_color_override("font_color", INK)
	_sheet_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet_body.clip_text = true
	_sheet_button = Button.new()   # in the header row, so it is on screen however long the text is
	_sheet_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sheet_button.focus_mode = Control.FOCUS_NONE
	_sheet_button.pressed.connect(func():
		_sheet.visible = false
		if _sheet_action.is_valid():
			_sheet_action.call())
	head.add_child(_sheet_button)
	col.add_child(_sheet_body)


func _label(color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _menu_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_menu_buttons.add_child(b)


func _show_log() -> void:
	var text := ""
	for entry: Array in LOG:
		text += entry[0] + "\n"
		for note: String in entry[1]:
			text += "  - " + note + "\n"
		text += "\n"
	_show_sheet("VERSION LOG", text, "CLOSE", Callable())


func _show_sheet(title: String, body: String, button: String, action: Callable) -> void:
	_sheet_title.text = title
	_sheet_body.text = body
	_sheet_button.text = button
	_sheet_action = action
	_sheet.visible = true


func sheet_open() -> bool:
	return _sheet.visible


func _set_objective(text: String) -> void:
	_obj_title.text = "LEVEL %d - %s" % [level_no, level.level_name]
	_obj.text = text


func _update_hud() -> void:
	var size := _root.size
	var u := size.y / 100.0       # 1% of the screen height
	var now := Tuning.now()
	if now > _sub_until:
		if _subs.is_empty():
			_sub.text = ""
		else:
			var next: Array = _subs.pop_front()
			_sub.text = next[0]
			_sub_until = now + float(next[1])
	if now > _hint_until:
		_hint.text = ""
	var in_menu: bool = state == "menu" and main.opening != null and main.opening.state == 0
	_menu_tag.visible = in_menu
	_menu_buttons.visible = in_menu and not _sheet.visible
	if state == "play" or state == "caught" or state == "leaving":
		var cells := ""
		for cell: Node in batteries:
			cells += "[#] " if cell.done else "[ ] "
		_cells.text = cells
	_place(_obj_title, Vector2(2.5 * u, 2.0 * u), size.x * 0.6, 2.6 * u)
	_place(_obj, Vector2(2.5 * u, 5.2 * u), size.x * 0.6, 3.6 * u)
	_place(_cells, Vector2(2.5 * u, 9.6 * u), size.x * 0.6, 3.4 * u)
	_place(_hint, Vector2(size.x * 0.12, 20.0 * u), size.x * 0.76, 3.4 * u)
	_place(_sub, Vector2(size.x * 0.1, 70.0 * u), size.x * 0.8, 4.2 * u)
	_place(_menu_tag, Vector2(2.5 * u, size.y - 6.0 * u), size.x * 0.55, 2.8 * u)
	for b: Button in _menu_buttons.get_children():
		b.add_theme_font_size_override("font_size", int(2.8 * u))
	_menu_buttons.reset_size()
	_menu_buttons.position = size - _menu_buttons.size - Vector2(2.5 * u, 2.5 * u)
	_sheet_title.add_theme_font_size_override("font_size", int(6.0 * u))
	_sheet_body.add_theme_font_size_override("font_size", int(2.9 * u))
	_sheet_button.add_theme_font_size_override("font_size", int(3.2 * u))


func _place(l: Label, at: Vector2, width: float, font_px: float) -> void:
	l.add_theme_font_size_override("font_size", int(font_px))
	l.add_theme_constant_override("outline_size", int(font_px * 0.3))
	l.position = at
	l.size = Vector2(width, 0)


func _shot(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _loop(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := _shot(stream, db)
	p.autoplay = true
	return p
