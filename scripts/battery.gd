extends StaticBody3D
## A power cell. Scanner rays charge it (scripts/ray_gun.gd calls add_charge);
## it keeps what it is given. Yellow so it is easy to spot, with a red light on
## top until it is full; the gauge fills cyan.

signal filled

var charge := 0.0
var done := false

var _hit_t := -9.0
var _fills: Array[Node3D] = []
var _led: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.33
	cyl.height = 1.25
	shape.shape = cyl
	shape.position.y = 0.625
	add_child(shape)
	var dark := _flat(Color(0.16, 0.16, 0.17), false)
	_cyl(0.36, 0.12, 0.06, dark)
	_cyl(0.27, 0.95, 0.62, _flat(Color(0.95, 0.74, 0.1), false, Color(0.12, 0.09, 0.0)))
	_cyl(0.3, 0.08, 0.15, dark)
	_cyl(0.3, 0.08, 1.1, dark)
	var slot_mat := _flat(Color(0.01, 0.03, 0.035), true)
	var fill_mat := _flat(Color(0.2, 0.9, 0.95), true)
	for i in 4:
		var side := Node3D.new()
		side.rotation.y = i * PI * 0.5
		add_child(side)
		_box(side, Vector3(0, 0.62, 0.275), Vector3(0.12, 0.74, 0.02), slot_mat)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0.27, 0.288)
		pivot.scale.y = 0.001
		side.add_child(pivot)
		_box(pivot, Vector3(0, 0.5, 0), Vector3(0.08, 1.0, 0.02), fill_mat)
		_fills.append(pivot)
	_led = _flat(Color(1.0, 0.15, 0.08), true)
	_box(self, Vector3(0, 1.2, 0), Vector3(0.1, 0.1, 0.1), _led)
	_light = OmniLight3D.new()
	_light.position.y = 1.5
	_light.light_color = Color(0.25, 0.9, 0.95)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	add_child(_light)


func add_charge(amount: float) -> void:
	if done:
		return
	_hit_t = Tuning.now()
	charge = minf(charge + amount, 1.0)
	if charge >= 1.0:
		done = true
		filled.emit()


func being_charged() -> bool:
	return not done and Tuning.now() - _hit_t < 0.15


func _process(delta: float) -> void:
	for f in _fills:
		f.scale.y = maxf(0.7 * charge, 0.001)
	if done:
		_led.albedo_color = Color(0.25, 1.0, 0.9)
	else:
		_led.albedo_color = Color(1.0, 0.15, 0.08) if fmod(Tuning.now() * 1.6 + position.x, 1.0) < 0.5 else Color(0.08, 0.01, 0.0)
	var want := 1.1 if done else (0.4 * charge if being_charged() else 0.0)
	_light.light_energy = lerpf(_light.light_energy, want, 1.0 - exp(-delta * 6.0))


func _flat(color: Color, unshaded: bool, emission := Color.BLACK) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission != Color.BLACK:
		mat.emission_enabled = true
		mat.emission = emission
	return mat


func _cyl(radius: float, height: float, y: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = y
	add_child(mi)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
