extends Node3D
## Test level: a dark brutalist hall with pillars. Right now it holds only the gas cloud.
## Hall spans x -12..12, y 0..8, z -32..8. The player starts near z = 4 facing -z.

const RevealCloud := preload("res://scripts/reveal_cloud.gd")
const Figure := preload("res://scripts/figure.gd")
const Gas := preload("res://scripts/gas.gd")
const PsxShader := preload("res://shaders/psx_lit.gdshader")
const RELICS := "res://assets/relics/"
const SHOW_EXHIBITS := false   # image artifacts + figure; off for the gas prototype

var environment: Environment
var spawn_point := Vector3(0, 0.1, 4)
var _concrete: ShaderMaterial


func _ready() -> void:
	_build_environment()
	_concrete = _make_concrete()

	_box(Vector3(0, -0.5, -12), Vector3(24, 1, 40))     # floor
	_box(Vector3(0, 8.5, -12), Vector3(24, 1, 40))      # ceiling
	_box(Vector3(-12.5, 4, -12), Vector3(1, 8, 40))     # walls
	_box(Vector3(12.5, 4, -12), Vector3(1, 8, 40))
	_box(Vector3(0, 4, -32.5), Vector3(24, 8, 1))
	_box(Vector3(0, 4, 8.5), Vector3(24, 8, 1))
	for z in [-4.0, -12.0, -20.0]:
		for x in [-6.0, 6.0]:
			_box(Vector3(x, 4, z), Vector3(1.4, 8, 1.4))  # pillars

	var shaft := SpotLight3D.new()
	shaft.position = Vector3(0, 7.9, -14)
	shaft.rotation_degrees = Vector3(-90, 0, 0)
	shaft.light_color = Color(0.6, 0.7, 0.9)
	shaft.light_energy = 1.2
	shaft.spot_range = 12.0
	shaft.spot_angle = 22.0
	add_child(shaft)

	if SHOW_EXHIBITS:
		_place_exhibits()

	var gas := Gas.new()
	gas.name = "gas"
	gas.position = Vector3(0, 2.2, -6)
	add_child(gas)


## The image artifacts, the tiger-skull plinth and the wandering figure. Off
## while we work on the gas (SHOW_EXHIBITS).
func _place_exhibits() -> void:
	_box(Vector3(2.5, 0.5, -5.4), Vector3(0.8, 1, 0.8))   # plinth
	# name, extension, base position, facing (yaw degrees, 0 = +z), width m, relief m, depth threshold
	_relic("sarcophagus", "png", Vector3(0, 0, -31.8), 0, 3.4, 0.6, 0.65)
	_relic("sphinx", "png", Vector3(-11.8, 0.3, -16), 90, 4.0, 0.8, 0.65)
	_relic("sun_god_ra", "png", Vector3(11.8, 0.3, -16), -90, 4.0, 0.8, 0.65)
	_relic("fossil", "jpeg", Vector3(-11.8, 1.0, -26), 90, 4.5, 0.5, 0.65)
	_relic("anubis_head", "png", Vector3(11.8, 1.0, -26), -90, 3.5, 0.6, 0.65)
	_relic("armour", "jpg", Vector3(-11.8, 0.2, -6), 90, 2.4, 0.5, 0.65)
	_relic("anubis_profile", "png", Vector3(11.8, 0.8, -6), -90, 3.5, 0.6, 0.65)
	_relic("tiger_skull", "jpg", Vector3(2.5, 1.0, -5.3), 0, 0.9, 0.3, 0.65)
	var figure := Figure.new()
	figure.name = "figure"
	figure.position = Vector3(0, 0, -10)
	add_child(figure)


func _relic(id: String, ext: String, pos: Vector3, yaw: float, width: float, relief: float, threshold: float) -> void:
	var cloud := RevealCloud.new()
	cloud.name = id
	cloud.image_path = RELICS + id + "." + ext
	cloud.depth_path = RELICS + id + "_depth.png"
	cloud.width = width
	cloud.relief = relief
	cloud.depth_threshold = threshold
	cloud.position = pos
	cloud.rotation_degrees.y = yaw
	add_child(cloud)


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.03, 0.03, 0.035)
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


## 64px seamless concrete: value noise, panel seams every 32px, form-tie holes.
func _make_concrete() -> ShaderMaterial:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 0.08
	var img := noise.get_seamless_image(64, 64)
	img.convert(Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := img.get_pixel(x, y).r * 0.35 + 0.35
			if x % 32 == 0 or y % 32 == 0:
				v *= 0.55
			if (x % 32 == 8 or x % 32 == 24) and (y % 32 == 8 or y % 32 == 24):
				v *= 0.4
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	var mat := ShaderMaterial.new()
	mat.shader = PsxShader
	mat.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(img))
	return mat


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	# Subdivided so vertex snapping and affine warping stay subtle on big faces.
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = int(size.x / 2.0)
	mesh.subdivide_height = int(size.y / 2.0)
	mesh.subdivide_depth = int(size.z / 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _concrete
	body.add_child(mi)
