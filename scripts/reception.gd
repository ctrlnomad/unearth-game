extends "res://scripts/level_kit.gd"
## Level 2: Reception. A dark lobby, 22 x 5 x 30 m along -z, with a long window
## on the right wall that looks at the pale sun. This is where the Cleaner first
## meets the gas in a person's shape: the first ghost is a scripted reveal behind
## the desk, and every cell charged wakes another. Solar flares light all of
## them for a moment. scripts/game.gd runs the shared rules and calls the hooks
## at the bottom.

const W := 11.0        # half width
const LENGTH := 30.0
const H := 5.0

# Read by main.gd and game.gd.
var environment: Environment
var fog_key := "rec.fog"
var ambient_key := "rec.ambient"
var ambient_boost := 0.0
var level_name := "RECEPTION"
var spawn_point := Vector3(0, 0, -2)
var exit_point := Vector3(-6, 0, -28.6)
var bounds := Rect2(-W + 0.5, -LENGTH + 0.5, W * 2 - 1.0, LENGTH - 1.0)
var battery_spots: Array[Vector3] = [Vector3(0, 0, -10.6), Vector3(-9.3, 0, -22.6), Vector3(9, 0, -27), Vector3(8.8, 0, -2.6)]
var ghost_spawns: Array[Vector3] = [Vector3(-9, 0, -27.5), Vector3(9, 0, -27.5), Vector3(-9.5, 0, -2.5), Vector3(9.5, 0, -2.5), Vector3(0, 0, -28), Vector3(-9.5, 0, -15)]

var _sun: DirectionalLight3D
var _door: Node3D
var _emergency: Array[OmniLight3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _flare_glow := 0.0
var _next_flare := INF
var _warned := false
var _revealed := false
var _released := false
var _reveal_t := 0.0
var _first: Node3D
var _stage := 0
var _flare_said := false
var _rumble: AudioStreamPlayer


func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.6, 0.72)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.008, 0.012, 0.016)
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	_build()
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = preload("res://scripts/sfx.gd").rumble()
	_rumble.volume_db = -80.0
	_rumble.autoplay = true
	add_child(_rumble)


func _build() -> void:
	var wall := material("panel", Color(0.85, 0.85, 0.82))
	var carpet := material("dark", Color(1.3, 1.45, 1.7), 0.5)
	var dark := material("dark")
	var steel := material("dark", Color(1.6, 1.6, 1.7), 0.5)
	var z0 := -LENGTH
	var mid := -LENGTH * 0.5
	box(self, Vector3(0, -0.5, mid), Vector3(W * 2 + 2, 1, LENGTH + 2), carpet)
	box(self, Vector3(0, H + 0.5, mid), Vector3(W * 2 + 2, 1, LENGTH + 2), dark)
	box(self, Vector3(0, H * 0.5, 0.5), Vector3(W * 2 + 2, H, 1), wall)
	box(self, Vector3(0, H * 0.5, z0 - 0.5), Vector3(W * 2 + 2, H, 1), wall)
	box(self, Vector3(-W - 0.5, H * 0.5, mid), Vector3(1, H, LENGTH), wall)
	# Right wall with the window, z -24..-6, y 1.2..4.2.
	box(self, Vector3(W + 0.5, H * 0.5, -3), Vector3(1, H, 6), wall)
	box(self, Vector3(W + 0.5, H * 0.5, -27), Vector3(1, H, 6), wall)
	box(self, Vector3(W + 0.5, 0.6, -15), Vector3(1, 1.2, 18), wall)
	box(self, Vector3(W + 0.5, 4.6, -15), Vector3(1, 0.8, 18), wall)
	var glass := StaticBody3D.new()
	glass.position = Vector3(W + 0.6, 2.7, -15)
	var glass_shape := CollisionShape3D.new()
	var glass_box := BoxShape3D.new()
	glass_box.size = Vector3(1, 3, 18)
	glass_shape.shape = glass_box
	glass.add_child(glass_shape)
	add_child(glass)
	var z := -6.0
	while z >= -24.0:
		box(self, Vector3(W - 0.1, H * 0.5, z), Vector3(0.3, H, 0.3), dark)
		z -= 4.5
	for spot: Vector3 in [Vector3(-5, 0, -7), Vector3(5, 0, -7), Vector3(-5, 0, -21), Vector3(5, 0, -21)]:
		box(self, spot + Vector3(0, H * 0.5, 0), Vector3(0.9, H, 0.9), wall)

	# The desk, with two dead screens.
	box(self, Vector3(0, 0.55, -13), Vector3(7, 1.1, 1.3), steel)
	box(self, Vector3(0, 1.14, -13), Vector3(7.4, 0.08, 1.6), dark, false)
	box(self, Vector3(-3.5, 0.55, -14.6), Vector3(1.3, 1.1, 2.4), steel)
	box(self, Vector3(3.5, 0.55, -14.6), Vector3(1.3, 1.1, 2.4), steel)
	box(self, Vector3(-1.6, 1.45, -13.2), Vector3(0.8, 0.5, 0.06), dark, false)
	box(self, Vector3(1.8, 1.45, -13.2), Vector3(0.8, 0.5, 0.06), dark, false)
	# Waiting benches, planters, kiosks, a crate somebody never collected.
	box(self, Vector3(-8.6, 0.23, -12), Vector3(3.2, 0.45, 0.9), dark)
	box(self, Vector3(-8.6, 0.23, -18), Vector3(3.2, 0.45, 0.9), dark)
	box(self, Vector3(7.2, 0.23, -14), Vector3(0.9, 0.45, 3.2), dark)
	box(self, Vector3(7.6, 0.45, -4.4), Vector3(1.1, 0.9, 1.1), material("rust"))
	box(self, Vector3(-8, 0.45, -5), Vector3(1.1, 0.9, 1.1), material("rust"))
	box(self, Vector3(-2.5, 0.95, -25), Vector3(0.9, 1.9, 0.5), steel)
	box(self, Vector3(2.5, 0.95, -25.5), Vector3(0.9, 1.9, 0.5), steel)
	box(self, Vector3(-8.5, 0.4, -25.5), Vector3(2.4, 0.8, 1.0), material("cargo", Color(1.0, 0.85, 0.7), 0.5))

	# Entry door (shut behind the Cleaner) and the door on to the labs.
	prism(self, hexagon(Vector2(0, 2.0), 1.7), -0.2, 0.0, material("dark", Color(1.2, 1.2, 1.25)), false)
	hex_ring(self, Vector2(0, 2.0), 1.7, 0.3, -0.3, 0.0, dark)
	var c := Vector2(-6, 2.1)
	prism(self, hexagon(c, 1.75), z0, z0 + 0.04, glow_material(Color(0.3, 0.5, 0.55)), false)
	_door = prism(self, hexagon(c, 1.8), z0 + 0.04, z0 + 0.22, material("dark", Color(1.3, 1.3, 1.35)), false)
	hex_ring(self, c, 1.8, 0.3, z0, z0 + 0.4, material("hazard", Color.WHITE, 0.5))

	paint(self, "MERIDIAN LABS", Vector3(3.4, 3.7, z0 + 0.03), Vector3.ZERO, 0.8, Color(0.05, 0.06, 0.08), "wall")
	paint(self, "RECEPTION", Vector3(3.4, 2.6, z0 + 0.03), Vector3.ZERO, 0.42, Color(0.05, 0.06, 0.08), "wall")
	paint(self, "WATCH THE FLARES", Vector3(-W + 0.03, 2.3, -15), Vector3(0, 90, 0), 0.55, Color(0.55, 0.3, 0.06), "stencil", false)

	# The pale sun, and its light through the window.
	var sphere := SphereMesh.new()
	sphere.radius = 34.0
	sphere.height = 68.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var sun_mat := glow_material(Color(0.95, 0.92, 0.82))
	sun_mat.disable_fog = true
	var disc := MeshInstance3D.new()
	disc.mesh = sphere
	disc.material_override = sun_mat
	disc.position = Vector3(300, 70, -15)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.94, 0.82)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	_sun.look_at_from_position(Vector3.ZERO, Vector3(-1, -0.28, 0.05))

	# One strip light still works, by the door you came in through.
	box(self, Vector3(0, H - 0.08, -3), Vector3(1.4, 0.1, 0.25), glow_material(Color(0.6, 0.72, 0.8)), false)
	var strip := OmniLight3D.new()
	strip.position = Vector3(0, H - 0.6, -3)
	strip.light_color = Color(0.6, 0.78, 1.0)
	strip.light_energy = 0.7
	strip.omni_range = 9.0
	add_child(strip)
	for spot: Vector3 in [Vector3(-5, 4.6, -6), Vector3(5, 4.6, -14), Vector3(-5, 4.6, -22), Vector3(3, 4.6, -27)]:
		var lens := glow_material(Color(0.06, 0.01, 0.01))
		box(self, spot + Vector3(0, 0.3, 0), Vector3(0.5, 0.12, 0.5), lens, false)
		_lamps.append(lens)
		var light := OmniLight3D.new()
		light.position = spot
		light.light_color = Color(1.0, 0.16, 0.08)
		light.omni_range = 16.0
		light.light_energy = 0.0
		add_child(light)
		_emergency.append(light)


func _process(delta: float) -> void:
	_flare_glow = maxf(0.0, _flare_glow - delta * 0.35)
	_sun.light_energy = 0.25 + _flare_glow * 3.0


# ---------------------------------------------------------------- hooks ----

## 0 = dark, 1 = emergency power on.
func set_power(k: float) -> void:
	var pulse := 0.75 + 0.25 * sin(Tuning.now() * 3.0)
	for light in _emergency:
		light.light_energy = 2.2 * k * pulse
	for lens in _lamps:
		lens.albedo_color = Color(1.0, 0.25, 0.15) * (0.06 + 0.94 * k * pulse)
	ambient_boost = 0.35 * k


func set_exit_door(open: float) -> void:
	_door.position.y = open * 3.9


func game_update(game: Node, delta: float) -> void:
	var first_cell: Node = game.batteries[0]
	if _stage == 0 and game.level_time > 2.0:
		_stage = 1
		game.say("Reception. Same job: charge the cells, get the lights on.", 4.5)
	if not _revealed and not game.powered and first_cell.charge > 0.45:
		_revealed = true
		_reveal_t = game.level_time
		_first = game.spawn_ghost(Vector3(0, 0, -14.9), "idle")
		_first.flare = 1.0
		_first.hold_flare = true
		game.play("sting")
		game.shake(0.12)
		game.clear_subtitles()
		game.say("...Someone is standing behind the desk.", 3.0)
	if _revealed and not _released and game.level_time > _reveal_t + 3.0:
		_released = true
		if is_instance_valid(_first):
			_first.release()
		_next_flare = game.level_time + 24.0
		game.say("It is not someone. It is the gas, wearing one of them.", 4.5)
		game.hint("It walks toward you, faster while you fire. Hold the beam on it to freeze it. Do not let it touch you.", 10.0)
	if game.powered:
		_rumble.volume_db = -80.0
		return
	var tf: float = _next_flare - float(game.level_time)
	if tf < 3.0:
		_rumble.volume_db = linear_to_db(clampf((3.0 - tf) / 3.0, 0.001, 1.0) * 0.6)
		game.shake(0.02 * (3.0 - tf))
		_flare_glow = maxf(_flare_glow, (3.0 - tf) / 3.0 * 0.5)
	if tf <= 0.0:
		_next_flare = game.level_time + float(Tuning.v("flare.every"))
		_flare_glow = 1.0
		_rumble.volume_db = -80.0
		game.flash(0.3)
		game.play("flare")
		for g: Node in game.ghosts:
			g.flare = 1.0
		if not _flare_said:
			_flare_said = true
			game.say("A flare from the pale sun. It lights all of them.", 4.5)


## A cell has just filled; `count` cells are full now.
func cell_filled(game: Node, count: int) -> void:
	if count >= game.batteries.size() or not _released:
		return
	game.spawn_ghost(game.far_spawn(), "follow")
	if game.ghosts.size() == 2:
		game.say("The power is waking more of it.", 3.5)


func power_restored(game: Node) -> void:
	game.say("Emergency power. The vents are taking it.", 4.0)


func after_caught(game: Node) -> void:
	if _next_flare < INF:
		_next_flare = game.level_time + 14.0
