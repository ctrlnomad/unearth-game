extends Node
## Entry point. The 3D game renders into a low-res SubViewport that is scaled up
## with hard pixels; the dev panel (F1) lives in the full-res window on top.
##
## Capture mode (for automated screenshots), args after `--`:
##   --capture=out.png --frames=120 --pos=x,y,z --yaw=deg --pitch=deg
##   --fire --sweep=deg --strafe=m/s --panel (include the dev panel, full-res)
##   --tune=key:value,key:value (override Tuning values for this run)
##   --settle=N (release the trigger N frames before the shot)
##   --fire_frames=N (with --fire: only hold the trigger for the first N frames)
##   --series=step (also save out_000.png, out_001.png... every `step` frames)
##   --level=hall (the old test hall with the ghost gas, instead of the loading bay)
##   --state=play (skip the menu and opening sequence)
##   --options (open the options screen and save the full window)
##   --click (click whatever the crosshair is on, 20 frames in; aim with --yaw/--pitch)
##   --start (press START on the first frame), --intro_t=seconds (jump into the sequence)

const Hall := preload("res://scripts/level.gd")
const LoadingBay := preload("res://scripts/loading_bay.gd")
const Reception := preload("res://scripts/reception.gd")
const Game := preload("res://scripts/game.gd")
const ScanDots := preload("res://scripts/scan_dots.gd")
const Opening := preload("res://scripts/opening.gd")
const OptionsMenu := preload("res://scripts/options_menu.gd")
const Player := preload("res://scripts/player.gd")
const DevPanel := preload("res://scripts/dev_panel.gd")
const PostShader := preload("res://shaders/lofi_post.gdshader")

var container: SubViewportContainer
var game_view: SubViewport
var level: Node3D
var player: CharacterBody3D
var dev_panel: CanvasLayer
var options: CanvasLayer
var opening: Node            # the menu + opening sequence; null in the test hall and after level 1
var game: Node               # rules and HUD (scripts/game.gd)
var dots: Node               # the scanner's marks (scripts/scan_dots.gd)
var touch_mode := false      # set by the first touch: on-screen controls, no mouse capture
var _touches := {}           # touch index -> {role: look/move/fire, start, moved}
var free_mouse := false      # the mouse plays without being captured (browsers that refuse pointer lock, e.g. on an iPad)
var _post: ShaderMaterial
var _crosshair: ColorRect


func _ready() -> void:
	_setup_input()

	container = SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	game_view = SubViewport.new()
	game_view.msaa_3d = Viewport.MSAA_DISABLED
	game_view.audio_listener_enable_3d = true
	container.add_child(game_view)

	var args := _user_args()
	level = Hall.new() if args.get("level", "") == "hall" else LoadingBay.new()
	game_view.add_child(level)
	player = Player.new()
	player.position = level.spawn_point
	game_view.add_child(player)
	dots = ScanDots.new()
	game_view.add_child(dots)
	_add_overlay()

	options = OptionsMenu.new()
	add_child(options)
	dev_panel = DevPanel.new()
	add_child(dev_panel)
	game = Game.new()
	game.main = self
	game.player = player
	game.dots = dots
	add_child(game)

	if level is LoadingBay:
		opening = Opening.new()
		opening.level = level
		opening.player = player
		opening.main = self
		add_child(opening)
		opening.finished.connect(func(): game.begin_level(level, 1))
		if args.get("level", "") == "2":
			start_at(2)
		elif args.get("state", "") == "play":
			opening.skip()

	if args.has("capture"):
		_run_capture(args)
	elif not OS.has_feature("web"):   # a browser only allows capture after a click
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 1 = normal picture, 0 = black.
func set_fade(amount: float) -> void:
	_post.set_shader_parameter("fade", amount)


## Post-pass effects: "cyan" (caught by the gas), "flash", "prox" (a ghost is near).
func set_fx(effect: String, amount: float) -> void:
	_post.set_shader_parameter(effect, amount)


## Skip the menu and opening sequence and start in the given level.
func start_at(number: int) -> void:
	if opening:
		opening.skip()
	if number > 1:
		load_level(number)


## Replace the current level (level 2 is Reception) and put the player at its door.
func load_level(number: int) -> void:
	if opening:
		opening.queue_free()
		opening = null
	game_view.remove_child(level)
	level.queue_free()
	level = Reception.new()
	game_view.add_child(level)
	player.position = level.spawn_point
	player.velocity = Vector3.ZERO
	player.set_aim(0, 0)
	game.begin_level(level, number)


func set_crosshair(shown: bool) -> void:
	_crosshair.visible = shown


func open_options() -> void:
	options.open()


func options_closed() -> bool:
	return not options.visible


func _process(_delta: float) -> void:
	var shrink := int(Tuning.v("look.pixel_scale"))
	if container.stretch_shrink != shrink:
		container.stretch_shrink = shrink

	var rs := RenderingServer
	rs.global_shader_parameter_set("psx_resolution", Vector2(game_view.size))
	rs.global_shader_parameter_set("psx_snap", Vector2(game_view.size) * float(Tuning.v("look.snap")))
	rs.global_shader_parameter_set("psx_affine", float(Tuning.v("look.affine")))
	rs.global_shader_parameter_set("reveal_now", Tuning.now())
	for k in ["hold", "fade", "dissolve", "flash", "flash_decay", "point_scale", "min_pixels"]:
		rs.global_shader_parameter_set("reveal_" + k, float(Tuning.v("reveal." + k)))
	var flash: Color = (Tuning.v("gun.color") as Color).srgb_to_linear()
	rs.global_shader_parameter_set("reveal_flash_color", Vector3(flash.r, flash.g, flash.b))

	_post.set_shader_parameter("color_levels", Tuning.v("look.color_levels"))
	_post.set_shader_parameter("dither_strength", Tuning.v("look.dither"))
	_post.set_shader_parameter("grain", Tuning.v("look.grain"))
	_post.set_shader_parameter("vignette", Tuning.v("look.vignette"))
	# A level can name its own fog and ambient constants (the bay is much bigger than the hall).
	level.environment.fog_density = Tuning.v(level.fog_key if "fog_key" in level else "look.fog")
	level.environment.ambient_light_energy = float(Tuning.v(level.ambient_key if "ambient_key" in level else "look.ambient")) \
			+ (float(level.ambient_boost) if "ambient_boost" in level else 0.0)

	# The trigger: the touch FIRE button, or the mouse while it is captured.
	var held := false
	if touch_mode:
		for touch: Dictionary in _touches.values():
			if touch.role == "fire":
				held = true
	else:
		var captured := _captured()
		held = (free_mouse or captured) and Input.is_action_pressed("fire")
		if captured:
			free_mouse = false
	player.touch_active = touch_mode or free_mouse
	player.gun.fire_held = held and not options.visible and not game.sheet_open()
	game.touch_ui.fire_on = held
	game.touch_ui.visible = touch_mode


## Touch controls. Left side of the screen: thumbstick. FIRE button: trigger, and
## dragging from it also aims. Anywhere else: look. In the menu a tap presses
## the cabin button under the finger.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		touch_mode = true
		var ui: Control = game.touch_ui
		if event.pressed:
			var role := "look"
			if game.state == "play":
				if event.position.distance_to(ui.fire_center()) < ui.fire_radius() * 1.5:
					role = "fire"
				elif event.position.x < ui.size.x * 0.42 and not ui.stick_on:
					role = "move"
					ui.stick_on = true
					ui.stick_origin = event.position
					ui.stick_pos = event.position
			_touches[event.index] = {"role": role, "start": event.position, "moved": 0.0}
		elif _touches.has(event.index):
			var touch: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			if touch.role == "move":
				player.touch_move = Vector2.ZERO
				ui.stick_on = false
			if touch.moved < 20.0:
				_menu_pick(event.position)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var touch: Dictionary = _touches[event.index]
		touch.moved += event.relative.length()
		var ui: Control = game.touch_ui
		if touch.role == "move":
			var v: Vector2 = ((event.position - touch.start) / ui.stick_radius()).limit_length(1.0)
			player.touch_move = v
			ui.stick_pos = touch.start + v * ui.stick_radius()
		elif not options.visible and not game.sheet_open():
			player.look_radians(event.relative * 4.0 / ui.size.y)


## True only while the mouse really is captured. A browser can refuse the
## request (an iPad always does) while Godot still reports the captured mode.
func _captured() -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("!!document.pointerLockElement", true))
	return true


## Press the cabin button at a point on the screen (menu only).
func _menu_pick(screen_pos: Vector2) -> void:
	if opening == null or options.visible or game.sheet_open():
		return
	var p := screen_pos / float(container.stretch_shrink)
	opening.click_ray(player.camera.project_ray_origin(p), player.camera.project_ray_normal(p))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_F1, KEY_QUOTELEFT]:
		dev_panel.visible = not dev_panel.visible
		if dev_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if options.visible or game.sheet_open():
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return   # touches are handled in _input
	if event is InputEventMouseButton and event.pressed:
		touch_mode = false   # a real mouse: back to mouse controls
	elif event is InputEventMouse and touch_mode:
		return
	if _captured():
		if event is InputEventMouseMotion:
			player.look(event.relative)
		elif event.is_action_pressed("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif opening and event.is_action_pressed("fire"):
			opening.click()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # in case an earlier request was refused: ask again
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_menu_pick(event.position)   # in the menu, the click that captures the mouse also presses what it is on
		# A browser may refuse the capture (an iPad never grants it). The mouse then
		# plays uncaptured: move to look, hold the button to fire.
		free_mouse = OS.has_feature("web") and not dev_panel.visible
	elif free_mouse and event is InputEventMouseMotion and not dev_panel.visible and game.state == "play":
		# Not in the menu: there the cursor has to be able to reach the START button.
		player.look(event.relative)


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	game_view.add_child(layer)
	var post := ColorRect.new()
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = PostShader
	post.material = _post
	layer.add_child(post)
	var dot := ColorRect.new()
	_crosshair = dot
	dot.color = Color(1, 1, 1, 0.5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_right = 1
	dot.offset_bottom = 1
	layer.add_child(dot)


func _setup_input() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("run", KEY_SHIFT)
	_bind_key("jump", KEY_SPACE)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", click)


func _bind_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	if OS.has_feature("web"):   # in a browser: ?level=2 or ?state=play on the page address
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		if query is String:
			for pair: String in (query as String).trim_prefix("?").split("&", false):
				var kv := pair.split("=", true, 1)
				out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out


func _run_capture(args: Dictionary) -> void:
	if args.has("pos"):
		var p: PackedFloat64Array = args["pos"].split_floats(",")
		player.position = Vector3(p[0], p[1], p[2])
	if args.has("tune"):   # --tune=reveal.hold:30,figure.speed:0
		for pair in args["tune"].split(","):
			Tuning.set_value(pair.get_slice(":", 0), float(pair.get_slice(":", 1)))
	var yaw := float(args.get("yaw", "0"))
	var pitch := float(args.get("pitch", "0"))
	var sweep := float(args.get("sweep", "0"))
	player.set_aim(yaw, pitch)
	player.gun.force_fire = args.has("fire")
	if opening and args.has("start"):
		opening.press_start()
		opening.t = float(args.get("intro_t", "0"))
	dev_panel.visible = args.has("panel")
	if args.has("options"):
		options.open()
	var frames := int(args.get("frames", "90"))
	var strafe := float(args.get("strafe", "0"))   # metres per second sideways
	var series := int(args.get("series", "0"))
	for i in frames:
		player.position += player.global_basis.x * strafe / 60.0
		if sweep > 0.0:
			player.set_aim(yaw + sin(i * 0.045) * sweep, pitch + sin(i * 0.071) * sweep * 0.6)
		if opening and args.has("click") and i == 20:   # click whatever the crosshair is on
			opening.click()
			print("click -> ", "sequence started" if opening.state == Opening.SEQUENCE else "nothing")
		if i == 10:   # --charge=N fills the first N cells; --ghost=x,z stands a lit ghost there
			for n in mini(int(args.get("charge", "0")), game.batteries.size()):
				game.batteries[n].add_charge(1.0)
			if args.has("ghost"):
				var at: PackedFloat64Array = args["ghost"].split_floats(",")
				var g: Node3D = game.spawn_ghost(Vector3(at[0], 0, at[1]), args.get("ghost_state", "idle"))
				g.flare = 1.0
				g.hold_flare = not args.has("ghost_dark")
		if args.has("fire_frames") and i == int(args["fire_frames"]):
			player.gun.force_fire = false
		await get_tree().process_frame
		if series > 0 and (i + 1) % series == 0:
			await RenderingServer.frame_post_draw
			var shot: String = args["capture"].get_basename() + "_%03d.png" % ((i + 1) / series - 1)
			game_view.get_texture().get_image().save_png(shot)
	player.gun.force_fire = false
	for i in int(args.get("settle", "0")):   # frames with the trigger released
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image
	if args.has("panel") or args.has("options"):
		img = get_viewport().get_texture().get_image()
	else:
		img = game_view.get_texture().get_image()
	img.save_png(args["capture"])
	print("%d fps" % Engine.get_frames_per_second())
	print("game: state %s, level %d, t %.1f, powered %s, cells %s, ghosts %s, player %s" % [game.state, game.level_no, game.level_time, game.powered,
		game.batteries.map(func(b): return snappedf(b.charge, 0.01)),
		game.ghosts.filter(func(g): return is_instance_valid(g)).map(func(g): return [g.state, g.pos.snapped(Vector3.ONE * 0.1)]),
		player.position.snapped(Vector3.ONE * 0.1)])
	for exhibit in get_tree().get_nodes_in_group("exhibit"):
		if "state_name" in exhibit:
			print("%s state: %s" % [exhibit.name, exhibit.state_name])
		print("%s: %.1f%% visible, audio %.0f%%, at %s" % [exhibit.name, exhibit.visible_fraction * 100.0, exhibit.audio_level * 100.0, exhibit.global_position.snapped(Vector3.ONE * 0.1)])
	get_tree().quit()
