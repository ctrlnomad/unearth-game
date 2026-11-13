extends Node
## The menu and the opening sequence, both played from the Cleaner's eyes in
## the ship's cabin (scripts/loading_bay.gd builds it).
##
## MENU: the camera sits still, facing the ship's door. The player can look
## around a little and click START or OPTIONS on the panel beside the door.
## SEQUENCE, after START (all timings are in Tuning, section "intro"):
##   lights die -> the cabin shakes, lightly then violently -> it stops dead
##   -> the doors open and the Cleaner is thrown into the loading bay
##   -> lies there, gets up -> the player takes over.
## The whole sequence is a function of `t`, so capture mode can jump into it.

signal finished

const Sfx := preload("res://scripts/sfx.gd")

enum { MENU, SEQUENCE, DONE }

var level: Node3D
var player: CharacterBody3D
var main: Node
var state := MENU
var t := 0.0

var _flash_until := 0.0
var _done_events := {}
var _hum: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _one_shots := {}


func _ready() -> void:
	player.cinematic = true
	player.position = level.seat_position
	player.set_aim(0, 0)
	player.look_center = Vector2.ZERO
	player.gun.enabled = false
	_hum = _player(Sfx.hum(), -24.0, true)
	_rumble = _player(Sfx.rumble(), -80.0, true)
	_one_shots = {
		"click": _player(Sfx.click(), -8.0),
		"power_down": _player(Sfx.power_down(), -10.0),
		"clunk": _player(Sfx.thud(95.0, 0.5), -6.0),
		"hiss": _player(Sfx.burst(1.6, 0.6, 2.2), -9.0),
		"impact": _player(Sfx.thud(60.0, 0.9), -2.0),
		"door_shut": _player(Sfx.thud(80.0, 0.6), -10.0),
	}


func _process(delta: float) -> void:
	player.look_limit = Vector2(Tuning.v("menu.look_yaw"), Tuning.v("menu.look_pitch"))
	match state:
		MENU:
			player.fov_override = Tuning.v("menu.fov")
			var cam: Camera3D = player.camera
			level.set_hover(level.button_at(cam.global_position, -cam.global_basis.z) if main.options_closed() else "")
		SEQUENCE:
			t += delta
			_sequence(delta)


## A click while the mouse is captured (main.gd routes it here).
func click() -> void:
	if state != MENU:
		return
	var cam: Camera3D = player.camera
	match level.button_at(cam.global_position, -cam.global_basis.z):
		"start":
			press_start()
		"options":
			_play("click")
			main.open_options()


func press_start() -> void:
	if state != MENU:
		return
	state = SEQUENCE
	t = 0.0
	level.set_hover("")
	main.set_crosshair(false)
	_play("click")
	_play("power_down")


## Go straight to the player standing in the bay (capture mode, --state=play).
func skip() -> void:
	level.set_ship_door(0.0)
	level.depart()
	player.position = level.spawn_point
	_hand_over()


func _sequence(delta: float) -> void:
	# Marks, in seconds after START.
	var shake_start: float = Tuning.v("intro.dark_time")
	var shake_end: float = shake_start + float(Tuning.v("intro.shake_time"))
	var doors: float = shake_end + float(Tuning.v("intro.hold"))
	var door_time: float = Tuning.v("intro.door_time")
	var thrown: float = doors + door_time * 0.7
	var impact: float = thrown + float(Tuning.v("intro.throw_time"))
	var rise: float = impact + float(Tuning.v("intro.down_time"))
	var control: float = rise + float(Tuning.v("intro.getup_time"))

	# Shaking: a little at first, then violent, then nothing.
	var amp := 0.0
	if t > shake_start and t < shake_end:
		amp = pow((t - shake_start) / (shake_end - shake_start), 2.2)
	var jolt := 0.0
	if t >= impact:
		jolt = exp(-(t - impact) * 7.0) * 0.6
	var shake := (amp + jolt) * float(Tuning.v("intro.shake_amount"))
	var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)) * shake
	var tilt := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.8

	# Cabin lights: flicker and die; during the shaking they spark back for an instant.
	var power := 1.0
	if t > 0.7:
		power = 0.0
	elif t > 0.15:
		power = 1.0 if randf() < 0.5 else 0.08
	if amp > 0.12 and randf() < amp * 7.0 * delta:
		_flash_until = t + randf_range(0.04, 0.13)
	if t < _flash_until:
		power = randf_range(0.3, 1.0)
	level.cabin_power = power
	_hum.volume_db = -24.0 if t < 0.7 else -80.0
	_rumble.volume_db = linear_to_db(maxf(pow(amp, 0.6) * 0.9, 0.0001))

	if _once("stop", t >= shake_end):
		_play("clunk")
	if _once("doors", t >= doors):
		_play("hiss")

	# Doors: both open; the station's closes again once the Cleaner is through.
	var open := smoothstep(0.0, 1.0, (t - doors) / door_time)
	level.set_ship_door(open)
	level.set_station_door(open * (1.0 - smoothstep(0.0, 1.0, (t - impact - 0.9) / 0.7)))
	if _once("shut", t >= impact + 1.5):
		_play("door_shut")
		level.depart()

	# The Cleaner's body.
	var seat: Vector3 = level.seat_position
	var land: Vector3 = level.spawn_point
	var eye_drop := 0.0     # how far the eyes are below standing height
	var roll := 0.0
	var pitch := 0.0
	var pos := seat
	if t >= thrown and t < impact:
		var u := (t - thrown) / (impact - thrown)
		pos = seat.lerp(land, pow(u, 1.3))
		eye_drop = 1.25 * u * u * u
		roll = 1.2 * u * u
		pitch = -0.5 * sin(u * PI) - 0.2 * u
	elif t >= impact and t < rise:
		pos = land
		eye_drop = 1.25
		roll = 1.2
		pitch = -0.2 + 0.03 * sin((t - impact) * 2.2)
	elif t >= rise:
		pos = land
		var u := clampf((t - rise) / (control - rise), 0.0, 1.0)
		var knees := smoothstep(0.0, 0.45, u)     # roll over, push up to hands and knees
		var stand := smoothstep(0.58, 1.0, u)     # a breath, then stand
		eye_drop = lerpf(lerpf(1.25, 0.75, knees), 0.0, stand)
		roll = lerpf(1.2, 0.12, knees) * (1.0 - stand)
		pitch = lerpf(lerpf(-0.2, -0.65, knees), 0.0, stand)
		player.fov_override = lerpf(float(Tuning.v("menu.fov")), float(Tuning.v("look.fov")), stand)
	if _once("impact", t >= impact):
		_play("impact")
	player.position = pos
	player.cine_offset = offset + Vector3(0, -eye_drop, 0)
	player.cine_tilt = tilt + Vector3(pitch, 0, roll)

	# The hit knocks the picture dark; it comes back while lying on the floor.
	var fade := 1.0
	if t >= impact:
		fade = lerpf(0.05, 1.0, smoothstep(0.0, 1.0, (t - impact) / (rise - impact)))
	main.set_fade(fade)

	if t >= control:
		_hand_over()


func _hand_over() -> void:
	state = DONE
	level.cabin_power = 1.0
	player.cinematic = false
	player.cine_offset = Vector3.ZERO
	player.cine_tilt = Vector3.ZERO
	player.fov_override = 0.0
	player.look_limit = Vector2.ZERO
	player.velocity = Vector3.ZERO
	player.gun.enabled = true
	_hum.stop()
	_rumble.stop()
	main.set_fade(1.0)
	main.set_crosshair(true)
	set_process(false)
	finished.emit()


func _once(event: String, condition: bool) -> bool:
	if not condition or _done_events.has(event):
		return false
	_done_events[event] = true
	return true


func _player(stream: AudioStream, db: float, autoplay := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.autoplay = autoplay
	add_child(p)
	return p


func _play(sound: String) -> void:
	(_one_shots[sound] as AudioStreamPlayer).play()
