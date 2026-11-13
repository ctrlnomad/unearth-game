extends MultiMeshInstance3D
## The scanner's marks: a ring buffer of dots, one per ray that lands on a
## surface. scripts/ray_gun.gd calls add(); shaders/scan_dots.gdshader fades them.

const DotShader := preload("res://shaders/scan_dots.gdshader")
const COUNT := 7000
const NEVER := -1.0e6

var _next := 0
var _mat: ShaderMaterial


func _ready() -> void:
	add_to_group("scan_dots")
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = COUNT
	_mat = ShaderMaterial.new()
	_mat.shader = DotShader
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -500.0, Vector3.ONE * 1000.0)
	clear()


func add(pos: Vector3, now: float) -> void:
	multimesh.set_instance_transform(_next, Transform3D(Basis(Vector3(now, 0, 0), Vector3.UP, Vector3.BACK), pos))
	_next = (_next + 1) % COUNT


func clear() -> void:
	var buf := PackedFloat32Array()
	buf.resize(COUNT * 12)
	for i in COUNT:
		buf[i * 12] = NEVER
		buf[i * 12 + 5] = 1.0
		buf[i * 12 + 10] = 1.0
	multimesh.buffer = buf
	_next = 0


func _process(_delta: float) -> void:
	var c: Color = (Tuning.v("gun.color") as Color).srgb_to_linear()
	_mat.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
	_mat.set_shader_parameter("now", Tuning.now())
	_mat.set_shader_parameter("life", Tuning.v("gun.dot_life"))
