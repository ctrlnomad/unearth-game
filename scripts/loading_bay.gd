extends "res://scripts/level_kit.gd"
## Level 1: the Loading Bay of Meridian Labs, plus the Cleaner's single-use
## ship docked at its entry wall (the menu and opening sequence happen in the
## ship's cabin; scripts/opening.gd drives them through the hooks below).
##
## Layout (metres). The bay is a long octagonal hall running along -z:
##   cross-section PROFILE (x, y), length z = 0 (entry wall) .. -56 (far wall).
##   Left wall (x = -18): the giant window, z -10..-46, y 6..14.
##   Right wall (x = +18): "MERIDIAN LABS / LOADING BAY".
##   Entry wall (z = 0): hexagonal docking door, centre (0, 1.1).
## The ship's cabin sits outside the entry wall, z 0.95..4.4, floor at y = 0.

const MotesShader := preload("res://shaders/motes.gdshader")
const PlanetShader := preload("res://shaders/planet.gdshader")
const Sfx := preload("res://scripts/sfx.gd")

const PROFILE: Array[Vector2] = [
	Vector2(-13, 0), Vector2(13, 0), Vector2(18, 6), Vector2(18, 14),
	Vector2(13, 20), Vector2(-13, 20), Vector2(-18, 14), Vector2(-18, 6)]
const LENGTH := 56.0
const WINDOW_Z0 := -46.0
const WINDOW_Z1 := -10.0
const DOOR_CENTER := Vector2(0, 1.1)
const DOOR_R := 1.1
const BUTTON_LAYER := 2

# Read by main.gd.
var environment: Environment
var fog_key := "bay.fog"
var ambient_key := "bay.ambient"
var spawn_point := Vector3(0, 0, -5.5)       # where the Cleaner lands / skip-menu start
var seat_position := Vector3(0, 0, 2.95)     # the Cleaner's place in the cabin

# Driven by opening.gd.
var cabin_power := 1.0                       # 0 = cabin lights dead

var _cabin: Node3D
var _lamp: OmniLight3D
var _lamp_lens: StandardMaterial3D
var _emergency: OmniLight3D
var _buttons := {}                           # name -> {mat, label, color}
var _hover := ""
var _ship_door: Array[Node3D] = []           # [upper, lower]
var _station_door: Array[Node3D] = []
var _sun: DirectionalLight3D
var _haze: FogMaterial
var _motes: MultiMeshInstance3D
var _motes_mat: ShaderMaterial
var _mote_count := -1
var _earth: MeshInstance3D
var _ship: Node3D                            # the ship seen from outside, after it leaves
var _departed := -1.0                        # seconds since the ship let go, -1 = still docked
var _exploded := false
var _flash: OmniLight3D
var _fireball: MeshInstance3D
var _chunks: Array = []                      # [node, velocity, spin]
var _boom_t := 0.0
var _clock := 0.0
var _flicker := 1.0


func _ready() -> void:
	_build_environment()
	_build_bay()
	_build_props()
	_build_space()
	_build_cabin()
	_build_motes()
	var tone := AudioStreamPlayer.new()
	tone.stream = Sfx.drone()
	tone.volume_db = -26.0
	tone.autoplay = true
	add_child(tone)


func _process(delta: float) -> void:
	_clock += delta
	_haze.density = Tuning.v("bay.haze")
	_sun.light_energy = Tuning.v("bay.sun")
	var elevation := deg_to_rad(float(Tuning.v("bay.sun_height")))
	var dir := Vector3(1, 0, -0.25).normalized() * cos(elevation) + Vector3.DOWN * sin(elevation)
	_sun.look_at_from_position(Vector3.ZERO, dir)
	_earth.rotate_object_local(Vector3.UP, delta * 0.004)

	if int(Tuning.v("bay.motes")) != _mote_count:
		_fill_motes()
	var glow: Color = (Tuning.v("gas.color") as Color).srgb_to_linear()
	_motes_mat.set_shader_parameter("glow_color", Vector3(glow.r, glow.g, glow.b))
	_motes_mat.set_shader_parameter("glow", Tuning.v("bay.mote_glow"))
	_motes_mat.set_shader_parameter("particle_size", Tuning.v("bay.mote_size"))
	_motes_mat.set_shader_parameter("min_pixels", Tuning.v("gas.min_pixels"))
	_motes_mat.set_shader_parameter("drift", Tuning.v("bay.mote_drift"))
	_motes_mat.set_shader_parameter("pulse", Tuning.v("bay.mote_pulse"))
	_motes_mat.set_shader_parameter("clock", _clock * float(Tuning.v("bay.mote_speed")))

	if _cabin:
		_update_cabin(delta)
	if _departed >= 0.0:
		_departed += delta
		_update_departure(delta)


# ---------------------------------------------------------------- hooks ----

## 0 = shut, 1 = open. The two halves slide up and down into the wall.
func set_ship_door(open: float) -> void:
	_slide(_ship_door, open)


func set_station_door(open: float) -> void:
	_slide(_station_door, open)


func _slide(halves: Array[Node3D], open: float) -> void:
	if halves.is_empty() or not is_instance_valid(halves[0]):
		return
	halves[0].position.y = open * 1.02
	halves[1].position.y = -open * 1.02


## Which cabin button the ray points at ("" for none).
func button_at(origin: Vector3, dir: Vector3) -> String:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0, BUTTON_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_meta("button", "") if not hit.is_empty() else ""


func set_hover(button: String) -> void:
	_hover = button


## The ship lets go: the cabin is removed and the ship appears outside, where
## it drifts past the window and explodes.
func depart() -> void:
	if _departed >= 0.0:
		return
	if _cabin:
		_cabin.queue_free()
		_cabin = null
	set_station_door(0.0)
	_departed = 0.0


# ------------------------------------------------------------------ bay ----

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.62, 0.8)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.012, 0.018, 0.026)
	# Haze, so the light from the window reads as shafts.
	# Only inside the bay (a FogVolume): haze outside would hide space behind a glowing wall.
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0
	_haze = FogMaterial.new()
	_haze.albedo = Color(0.75, 0.86, 1.0)
	var haze_volume := FogVolume.new()
	haze_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	haze_volume.size = Vector3(36, 20, LENGTH)
	haze_volume.position = Vector3(0, 10, -LENGTH * 0.5)
	haze_volume.material = _haze
	add_child(haze_volume)
	environment.volumetric_fog_anisotropy = 0.15
	environment.volumetric_fog_length = 90.0
	environment.volumetric_fog_ambient_inject = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(0.78, 0.88, 1.0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 110.0
	_sun.shadow_bias = 0.06
	_sun.light_volumetric_fog_energy = 1.0
	add_child(_sun)


func _build_bay() -> void:
	var panel := material("panel")
	var deck := material("deck")
	var dark := material("dark")
	var hazard := material("hazard", Color.WHITE, 0.5)
	var z0 := -LENGTH
	var n := PROFILE.size()
	for i in n:
		var a := PROFILE[i]
		var b := PROFILE[(i + 1) % n]
		var mat := deck if i == 0 else (dark if i == 4 else panel)
		if i == 6:   # the window wall: solid only before and after the window
			slab(self, a, b, WINDOW_Z1, 0.0, 1.0, mat)
			slab(self, a, b, z0, WINDOW_Z0, 1.0, mat)
		else:
			slab(self, a, b, z0, 0.0, 1.0, mat)
	# Ribs: portal frames every 6 m. On the window wall they are the mullions.
	var rib_z := -4.0
	while rib_z > z0:
		for i in range(1, n):
			if i == 2 and rib_z < -12.0 and rib_z > -44.0:
				continue   # keep the right wall clear where the lettering is
			slab(self, PROFILE[i], PROFILE[(i + 1) % n], rib_z - 0.3, rib_z + 0.3, 0.7, dark, true, false)
		rib_z -= 6.0
	# Window sill and header, and something solid so nobody walks into space.
	box(self, Vector3(-18.2, 5.85, -28), Vector3(1.0, 0.3, 36), dark, false)
	box(self, Vector3(-18.2, 14.15, -28), Vector3(1.0, 0.3, 36), dark, false)
	var glass := StaticBody3D.new()
	glass.position = Vector3(-18.6, 10, -28)
	var glass_shape := CollisionShape3D.new()
	var glass_box := BoxShape3D.new()
	glass_box.size = Vector3(1, 8, 36)
	glass_shape.shape = glass_box
	glass.add_child(glass_shape)
	add_child(glass)

	# Entry wall with the hexagonal docking door, and its frame on the bay side.
	wall_with_hex_hole(self, Rect2(-20, -1, 40, 22), DOOR_CENTER, DOOR_R, 0.0, 0.6, panel)
	hex_ring(self, DOOR_CENTER, DOOR_R, 0.28, -0.18, 0.0, hazard)
	hex_ring(self, DOOR_CENTER, DOOR_R + 0.28, 0.5, -0.1, 0.0, dark)
	box(self, Vector3(0, 3.1, -0.12), Vector3(1.2, 0.1, 0.2), glow_material(Color(1.0, 0.8, 0.5)), false)
	_light(Vector3(0, 3.0, -1.2), Color(1.0, 0.78, 0.5), 0.9, 9.0)
	var door_mat := material("dark", Color(1.25, 1.25, 1.3), 0.5)
	_station_door = [
		prism(self, half_hexagon(DOOR_CENTER, DOOR_R + 0.06, true), 0.2, 0.4, door_mat),
		prism(self, half_hexagon(DOOR_CENTER, DOOR_R + 0.06, false), 0.2, 0.4, door_mat)]

	# Far wall: the big cargo door, shut.
	box(self, Vector3(0, 10, z0 - 0.5), Vector3(40, 22, 1), panel)
	var big := Vector2(0, 4.7)
	prism(self, hexagon(big, 5.0), z0, z0 + 0.2, material("dark", Color(1.2, 1.2, 1.25)), false)
	hex_ring(self, big, 5.0, 0.6, z0, z0 + 0.45, hazard)
	hex_ring(self, big, 5.6, 0.7, z0, z0 + 0.3, dark)
	box(self, Vector3(0, 4.7, z0 + 0.24), Vector3(9.9, 0.12, 0.1), material("dark", Color(0.3, 0.3, 0.3)), false)
	box(self, Vector3(0, 10.4, z0 + 0.3), Vector3(0.5, 0.25, 0.2), glow_material(Color(1.0, 0.08, 0.04)), false)
	_light(Vector3(0, 10.2, z0 + 1.6), Color(1.0, 0.1, 0.05), 1.4, 16.0)

	# The few lights that still work: cold strips up on the ribs.
	for spot: Vector3 in [Vector3(15.2, 15.6, -4), Vector3(-15.2, 15.6, -52), Vector3(15.2, 15.6, -28)]:
		box(self, spot, Vector3(1.6, 0.12, 0.3), glow_material(Color(0.75, 0.9, 1.0)), false,
				Vector3(0, 0, -50 if spot.x > 0 else 50))
		_light(spot + Vector3(-signf(spot.x) * 1.2, -1.0, 0), Color(0.6, 0.78, 1.0), 1.6, 20.0)

	# Painted on the right wall, facing the window.
	paint(self, "MERIDIAN LABS", Vector3(17.97, 10.3, -28), Vector3(0, -90, 0), 2.3, Color(0.05, 0.06, 0.08), "wall")
	paint(self, "LOADING BAY", Vector3(17.97, 7.3, -28), Vector3(0, -90, 0), 1.05, Color(0.05, 0.06, 0.08), "wall")
	box(self, Vector3(17.96, 8.5, -28), Vector3(0.04, 0.1, 24.0), material("dark", Color(0.3, 0.3, 0.3)), false)


func _light(pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	add_child(light)
	return light


## Stand-ins for the unloading equipment: two tracks, carts with containers, a
## stack of containers and an overhead crane.
func _build_props() -> void:
	var dark := material("dark")
	var steel := material("dark", Color(1.6, 1.6, 1.7), 0.5)
	for track_x: float in [-4.0, 4.0]:
		for side: float in [-0.8, 0.8]:
			box(self, Vector3(track_x + side, 0.08, -28), Vector3(0.12, 0.16, 52), steel, false)
		var z := -2.5
		while z > -54.0:
			box(self, Vector3(track_x, 0.03, z), Vector3(2.3, 0.06, 0.3), dark, false)
			z -= 1.5
		box(self, Vector3(track_x, 0.5, -54.4), Vector3(2.2, 1.0, 0.5), material("hazard", Color.WHITE, 0.5))
	_cart(Vector3(-4, 0, -17), Color(1, 1, 1))
	_cart(Vector3(4, 0, -31), Color(0.75, 0.85, 1.0))
	_cart(Vector3(4, 0, -45), Color(1, 0.9, 0.8))
	_container(Vector3(10.3, 1.3, -21), 8.0, Color(1, 1, 1))
	_container(Vector3(10.6, 1.3, -24.2), -4.0, Color(0.7, 0.8, 1.0))
	_container(Vector3(10.4, 3.9, -22.4), 3.0, Color(1.0, 0.85, 0.7))
	_container(Vector3(-9.5, 1.3, -44), 84.0, Color(0.8, 0.9, 1.0))
	box(self, Vector3(9.5, 0.55, -8), Vector3(1.8, 1.1, 0.9), steel)                    # console stand-in
	box(self, Vector3(9.5, 1.25, -8.2), Vector3(1.6, 0.4, 0.3), dark, false, Vector3(-30, 0, 0))

	# Overhead crane: rails along both walls, a bridge across, a hook hanging down.
	for x: float in [-17.4, 17.4]:
		box(self, Vector3(x, 14.6, -28), Vector3(0.5, 0.5, 54), steel, false)
	box(self, Vector3(0, 15.0, -45), Vector3(34.8, 0.9, 1.3), material("hazard", Color(0.8, 0.8, 0.8), 0.25), false)
	box(self, Vector3(4, 14.3, -45), Vector3(1.6, 0.7, 1.8), steel, false)
	pipe(self, Vector3(4, 14.0, -45), Vector3(4, 5.6, -45), 0.05, dark)
	box(self, Vector3(4, 5.3, -45), Vector3(0.7, 0.7, 0.5), material("hazard", Color.WHITE, 0.5), false)


func _cart(pos: Vector3, tint: Color) -> void:
	box(self, pos + Vector3(0, 0.35, 0), Vector3(2.5, 0.3, 6.4), material("dark"))
	_container(pos + Vector3(0, 1.8, 0), 0.0, tint)


func _container(center: Vector3, yaw: float, tint: Color) -> void:
	box(self, center, Vector3(2.4, 2.6, 6.0), material("cargo", tint, 0.5), true, Vector3(0, yaw, 0))


# ---------------------------------------------------------------- space ----

func _build_space() -> void:
	# Stars: single pixels a long way off.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for i in 1400:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		points.append(p * 2500.0)
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.1
		colors.append(Color(b, b, b * rng.randf_range(0.85, 1.15)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var star_mesh := ArrayMesh.new()
	star_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.vertex_color_use_as_albedo = true
	star_mat.use_point_size = true
	star_mat.point_size = 1.0
	star_mat.disable_fog = true
	var stars := MeshInstance3D.new()
	stars.mesh = star_mesh
	stars.material_override = star_mat
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)

	# The original Earth, out past the window.
	var sphere := SphereMesh.new()
	sphere.radius = 95.0
	sphere.height = 190.0
	sphere.radial_segments = 28
	sphere.rings = 14
	var earth_mat := ShaderMaterial.new()
	earth_mat.shader = PlanetShader
	earth_mat.set_shader_parameter("surface_tex", _earth_texture())
	earth_mat.set_shader_parameter("sun_dir", Vector3(0.35, 0.55, 0.75).normalized())
	_earth = MeshInstance3D.new()
	_earth.mesh = sphere
	_earth.material_override = earth_mat
	_earth.position = Vector3(-600, 250, -330)
	_earth.rotation_degrees = Vector3(18, 40, -23)
	_earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_earth)

	_ship = _build_ship_exterior()
	_ship.visible = false
	add_child(_ship)


func _earth_texture() -> ImageTexture:
	var land := FastNoiseLite.new()
	land.noise_type = FastNoiseLite.TYPE_SIMPLEX
	land.fractal_octaves = 4
	land.frequency = 1.1
	land.seed = 8
	var cloud := FastNoiseLite.new()
	cloud.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cloud.fractal_octaves = 3
	cloud.frequency = 2.3
	cloud.seed = 21
	var img := Image.create(192, 96, false, Image.FORMAT_RGB8)
	for y in 96:
		var lat := (0.5 - (y + 0.5) / 96.0) * PI
		for x in 192:
			var lon := (x + 0.5) / 192.0 * TAU
			var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var h := land.get_noise_3dv(p)
			var c: Color
			if h > 0.04:
				c = Color(0.1, 0.27, 0.09).lerp(Color(0.42, 0.33, 0.17), clampf((h - 0.04) * 4.0, 0.0, 1.0))
			else:
				c = Color(0.02, 0.07, 0.24).lerp(Color(0.05, 0.22, 0.42), clampf(1.0 + h * 5.0, 0.0, 1.0))
			if absf(lat) > 1.22 + h * 0.3:
				c = Color(0.85, 0.9, 0.95)
			var w := cloud.get_noise_3dv(p + Vector3(3, 0, 0))
			c = c.lerp(Color(0.92, 0.94, 0.96), smoothstep(0.12, 0.45, w) * 0.85)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## The Cleaner's ship from outside: a boxy pod. Only ever seen small, through
## the window, so it is a handful of primitives.
func _build_ship_exterior() -> Node3D:
	var root := Node3D.new()
	var hull := StandardMaterial3D.new()
	hull.albedo_texture = texture("rust")
	hull.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hull.uv1_scale = Vector3(2, 2, 2)
	hull.roughness = 1.0
	hull.disable_fog = true
	hull.emission_enabled = true          # earthshine: its sunlit side faces away from us
	hull.emission_texture = texture("rust")
	hull.emission_energy_multiplier = 0.9
	var parts := [
		[Vector3(0, 0, 0), Vector3(3.9, 2.9, 4.6)],          # cabin
		[Vector3(0, 0, -3.0), Vector3(2.6, 2.2, 1.5)],       # docking collar
		[Vector3(-2.4, -0.4, 0.6), Vector3(1.0, 1.4, 3.0)],  # tanks
		[Vector3(2.4, -0.4, 0.6), Vector3(1.0, 1.4, 3.0)],
		[Vector3(-0.9, 0, 3.0), Vector3(1.2, 1.2, 1.5)],     # engines
		[Vector3(0.9, 0, 3.0), Vector3(1.2, 1.2, 1.5)],
		[Vector3(0, 1.9, 0.5), Vector3(0.15, 1.0, 0.15)],    # antenna
	]
	for part: Array in parts:
		var mesh := BoxMesh.new()
		mesh.size = part[1]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = part[0]
		mi.material_override = hull
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.scale = Vector3.ONE * 1.6   # a little larger than life so it reads at 225p
	return root


func _update_departure(delta: float) -> void:
	var t := _departed - float(Tuning.v("bay.ship_delay"))
	var drift: float = Tuning.v("bay.ship_drift")
	if not _exploded:
		_ship.visible = t >= 0.0
		var u := clampf(t / drift, 0.0, 1.0)
		_ship.position = Vector3(-30, 14, -4).lerp(Vector3(-75, 40, -52), u)
		_ship.rotation = Vector3(0.11, 0.07, 0.05) * maxf(t, 0.0) + Vector3(0.2, 0.5, 0)
		if t >= drift:
			_explode()
		return
	_boom_t += delta
	_flash.light_energy = 14.0 * exp(-_boom_t * 1.6)
	var k := _boom_t / 0.9
	_fireball.visible = k < 1.0
	_fireball.scale = Vector3.ONE * (1.0 + 16.0 * sqrt(minf(k, 1.0)))
	(_fireball.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.75, 0.45) * pow(maxf(1.0 - k, 0.0), 1.5)
	for chunk: Array in _chunks:
		chunk[0].position += chunk[1] * delta
		chunk[0].rotation += chunk[2] * delta


func _explode() -> void:
	_exploded = true
	var at := _ship.position
	_ship.visible = false

	_flash = OmniLight3D.new()
	_flash.position = at
	_flash.light_color = Color(1.0, 0.8, 0.55)
	_flash.omni_range = 220.0
	_flash.omni_attenuation = 0.4
	_flash.shadow_enabled = true
	add_child(_flash)

	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	var ball_mat := StandardMaterial3D.new()
	ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ball_mat.disable_fog = true
	_fireball = MeshInstance3D.new()
	_fireball.mesh = ball
	_fireball.material_override = ball_mat
	_fireball.position = at
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fireball)

	# Sparks.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.disable_fog = true
	quad.material = spark_mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.8))
	ramp.add_point(0.25, Color(1.0, 0.5, 0.12))
	ramp.set_color(ramp.get_point_count() - 1, Color(0, 0, 0))
	var sparks := CPUParticles3D.new()
	sparks.mesh = quad
	sparks.amount = 260
	sparks.lifetime = 7.0
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 16.0
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 1.6
	sparks.color_ramp = ramp
	sparks.position = at
	add_child(sparks)
	sparks.emitting = true

	# Pieces of hull tumbling away.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var hull := StandardMaterial3D.new()
	hull.albedo_texture = texture("rust")
	hull.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hull.disable_fog = true
	hull.emission_enabled = true          # earthshine: its sunlit side faces away from us
	hull.emission_texture = texture("rust")
	hull.emission_energy_multiplier = 0.9
	for i in 9:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(rng.randf_range(0.6, 2.6), rng.randf_range(0.3, 1.8), rng.randf_range(0.6, 2.8))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = hull
		mi.position = at
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var v := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf_range(1.5, 7.0)
		_chunks.append([mi, v + Vector3(-1.9, 1.1, -2.0), Vector3(rng.randfn(), rng.randfn(), rng.randfn())])


# ---------------------------------------------------------------- cabin ----

func _build_cabin() -> void:
	_cabin = Node3D.new()
	add_child(_cabin)
	var hull := material("rust", Color.WHITE, 0.5)
	var floor_mat := material("rust", Color(0.55, 0.55, 0.6), 0.5)
	var patch := material("rust", Color(0.75, 0.95, 1.05), 1.0)
	var dark := material("dark", Color(0.8, 0.8, 0.8), 0.5)
	var hazard := material("hazard", Color(0.9, 0.9, 0.9), 1.0)
	var w := 1.75    # half width
	var h := 2.5
	var front := 0.95
	var back := 4.4
	var mid := (front + back) * 0.5
	var depth := back - front
	box(_cabin, Vector3(0, -0.1, mid), Vector3(w * 2 + 0.4, 0.2, depth + 0.4), floor_mat)
	box(_cabin, Vector3(0, h + 0.1, mid), Vector3(w * 2 + 0.4, 0.2, depth + 0.4), hull)
	box(_cabin, Vector3(-w - 0.1, h * 0.5, mid), Vector3(0.2, h, depth), hull)
	box(_cabin, Vector3(w + 0.1, h * 0.5, mid), Vector3(0.2, h, depth), hull)
	box(_cabin, Vector3(0, h * 0.5, back + 0.1), Vector3(w * 2 + 0.4, h, 0.2), hull)
	wall_with_hex_hole(_cabin, Rect2(-w - 0.2, -0.2, w * 2 + 0.4, h + 0.4), DOOR_CENTER, DOOR_R, 0.7, front, hull)
	hex_ring(_cabin, DOOR_CENTER, DOOR_R, 0.32, 0.55, 0.75, dark)          # docking collar
	hex_ring(_cabin, DOOR_CENTER, DOOR_R + 0.02, 0.13, front, front + 0.04, hazard)

	# The door: two halves, with the title painted on the upper one.
	var door_mat := material("rust", Color(1.25, 1.2, 1.1), 0.5)
	var upper := prism(_cabin, half_hexagon(DOOR_CENTER, DOOR_R + 0.05, true), 0.78, 0.9, door_mat)
	var lower := prism(_cabin, half_hexagon(DOOR_CENTER, DOOR_R + 0.05, false), 0.78, 0.9, door_mat)
	_ship_door = [upper, lower]
	paint(upper, "UNEARTH", Vector3(0, 1.57, 0.906), Vector3.ZERO, 0.33, Color(0.86, 0.82, 0.72))
	box(upper, Vector3(0, 1.16, 0.905), Vector3(1.9, 0.05, 0.012), hazard, false)
	box(lower, Vector3(0, 1.04, 0.905), Vector3(1.9, 0.05, 0.012), hazard, false)
	box(lower, Vector3(0, 0.62, 0.91), Vector3(0.5, 0.12, 0.03), dark, false)   # handle

	# Tired details: pipes, a patch plate, a locker, grab bars.
	var pipe_mat := material("rust", Color(0.8, 0.7, 0.6), 1.0)
	pipe(_cabin, Vector3(-1.55, 2.3, front), Vector3(-1.55, 2.3, back), 0.07, pipe_mat)
	pipe(_cabin, Vector3(-1.38, 2.36, front), Vector3(-1.38, 2.36, back), 0.035, pipe_mat)
	pipe(_cabin, Vector3(1.6, 2.25, front), Vector3(1.6, 2.25, back), 0.09, pipe_mat)
	pipe(_cabin, Vector3(-w, 2.28, 1.12), Vector3(w, 2.28, 1.12), 0.05, pipe_mat)
	pipe(_cabin, Vector3(1.6, 2.25, 1.9), Vector3(1.6, 0.0, 1.9), 0.04, pipe_mat)
	box(_cabin, Vector3(-w + 0.012, 1.35, 2.3), Vector3(0.024, 0.75, 1.1), patch, false)
	box(_cabin, Vector3(-w + 0.02, 0.6, 3.4), Vector3(0.04, 0.5, 0.7), patch, false)
	box(_cabin, Vector3(w - 0.2, 0.75, 3.7), Vector3(0.4, 1.5, 0.9), material("rust", Color(0.6, 0.7, 0.75), 1.0))
	box(_cabin, Vector3(-0.6, h - 0.012, 3.2), Vector3(0.9, 0.024, 0.8), patch, false)
	var bar := material("hazard", Color(0.9, 0.8, 0.5), 2.0)
	pipe(_cabin, Vector3(-1.5, 0.75, front + 0.07), Vector3(-1.5, 1.6, front + 0.07), 0.025, bar)

	# Ceiling lamp in a cage: the only real light, and it is not healthy.
	_lamp_lens = glow_material(Color(1.0, 0.72, 0.4))
	box(_cabin, Vector3(0.25, h - 0.07, 2.2), Vector3(0.22, 0.1, 0.34), _lamp_lens, false)
	box(_cabin, Vector3(0.25, h - 0.02, 2.2), Vector3(0.32, 0.04, 0.44), dark, false)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0.25, h - 0.35, 2.2)
	_lamp.light_color = Color(1.0, 0.62, 0.34)
	_lamp.omni_range = 4.6
	_lamp.omni_attenuation = 1.7
	_lamp.shadow_enabled = true
	_cabin.add_child(_lamp)

	# Control panel beside the door: the menu.
	var px := 1.47
	box(_cabin, Vector3(px, 1.28, front + 0.03), Vector3(0.5, 0.78, 0.06), dark, false)
	_button("start", "START", Vector3(px, 1.44, front + 0.08), Color(1.0, 0.72, 0.25))
	_button("options", "OPTIONS", Vector3(px, 1.16, front + 0.08), Color(0.55, 0.8, 0.9))
	box(_cabin, Vector3(px - 0.17, 1.61, front + 0.065), Vector3(0.04, 0.04, 0.02), glow_material(Color(1.0, 0.1, 0.05)), false)
	_emergency = OmniLight3D.new()
	_emergency.position = Vector3(px - 0.2, 1.61, front + 0.4)
	_emergency.light_color = Color(1.0, 0.12, 0.06)
	_emergency.omni_range = 4.5
	_emergency.light_energy = 0.0
	_cabin.add_child(_emergency)


func _button(id: String, text: String, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = BUTTON_LAYER
	body.collision_mask = 0
	body.set_meta("button", id)
	_cabin.add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.44, 0.23, 0.08)
	shape.shape = box_shape
	body.add_child(shape)
	var mat := glow_material(color)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.44, 0.2, 0.04)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var label := paint(body, text, Vector3(0, -0.005, 0.022), Vector3.ZERO, 0.095, Color.BLACK, "stencil", false)
	_buttons[id] = {"mat": mat, "label": label, "color": color, "body": body}


func _update_cabin(delta: float) -> void:
	# The lamp dips now and then on its own.
	if randf() < delta * 1.5:
		_flicker = randf_range(0.35, 0.9)
	_flicker = lerpf(_flicker, 1.0, 1.0 - exp(-delta * 9.0))
	var k := cabin_power * lerpf(1.0, _flicker, float(Tuning.v("cabin.flicker")))
	_lamp.light_energy = float(Tuning.v("cabin.lamp")) * k
	_lamp_lens.albedo_color = Color(1.0, 0.72, 0.4) * (0.04 + 0.96 * k)
	_emergency.light_energy = 0.35 * (1.0 - cabin_power)
	for id: String in _buttons:
		var b: Dictionary = _buttons[id]
		var lit := 0.32 if id != _hover else (0.85 + 0.15 * sin(_clock * 9.0))
		(b.mat as StandardMaterial3D).albedo_color = (b.color as Color) * (lit * cabin_power + 0.015)
		(b.body as Node3D).position.z = 1.03 if id != _hover else 1.04


# ---------------------------------------------------------------- motes ----

func _build_motes() -> void:
	_motes_mat = ShaderMaterial.new()
	_motes_mat.shader = MotesShader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	_motes = MultiMeshInstance3D.new()
	_motes.multimesh = mm
	_motes.material_override = _motes_mat
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.custom_aabb = AABB(Vector3(-22, -2, -LENGTH - 4), Vector3(44, 26, LENGTH + 8))
	add_child(_motes)
	_fill_motes()


func _fill_motes() -> void:
	_mote_count = int(Tuning.v("bay.motes"))
	var mm := _motes.multimesh
	mm.instance_count = 0
	mm.instance_count = _mote_count
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var outline := PackedVector2Array(PROFILE)
	var i := 0
	while i < _mote_count:
		var p := Vector2(rng.randf_range(-17.5, 17.5), rng.randf_range(0.4, 19.5))
		if not Geometry2D.is_point_in_polygon(p, outline):
			continue
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, p.y, rng.randf_range(-LENGTH + 1.0, -1.0))))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
		i += 1
