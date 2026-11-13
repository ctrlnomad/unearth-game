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
var opening: Node            # the menu + opening sequence; null in the test hall
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
	_add_overlay()

	options = OptionsMenu.new()
	add_child(options)
	dev_panel = DevPanel.new()
	add_child(dev_panel)

	if level is LoadingBay:
		opening = Opening.new()
		opening.level = level
		opening.player = player
		opening.main = self
		add_child(opening)
		if args.get("state", "") == "play":
			opening.skip()

	if args.has("capture"):
		_run_capture(args)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## 1 = normal picture, 0 = black.
func set_fade(amount: float) -> void:
	_post.set_shader_parameter("fade", amount)


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
	level.environment.ambient_light_energy = Tuning.v(level.ambient_key if "ambient_key" in level else "look.ambient")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_F1, KEY_QUOTELEFT]:
		dev_panel.visible = not dev_panel.visible
		if dev_panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if options.visible:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			player.look(event.relative)
		elif event.is_action_pressed("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif opening and event.is_action_pressed("fire"):
			opening.click()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	for exhibit in get_tree().get_nodes_in_group("exhibit"):
		if "state_name" in exhibit:
			print("%s state: %s" % [exhibit.name, exhibit.state_name])
		print("%s: %.1f%% visible, audio %.0f%%, at %s" % [exhibit.name, exhibit.visible_fraction * 100.0, exhibit.audio_level * 100.0, exhibit.global_position.snapped(Vector3.ONE * 0.1)])
	get_tree().quit()
