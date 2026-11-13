extends Node3D
## Hold-to-fire scanner, a child of the camera. Each ray is a physics raycast
## from the camera (so it matches the crosshair) that stops at walls; every
## RevealCloud in front of that reveals the points around the ray. Tracers and
## impact marks are drawn as 1-pixel lines.

const MODEL_OFFSET := Vector3(0.13, -0.12, -0.24)
const MODEL_SCALE := 0.5

var force_fire := false   # capture mode holds the trigger
var enabled := true       # false = holstered out of view and unable to fire (menu, opening sequence)
var _drawn := 1.0
var _accum := 0.0
var _tracers: Array = []  # [to, colour, born]; drawn from the live muzzle so beams stay attached while moving
var _sparks: Array = []   # [pos, colour, born]
var _lines := ImmediateMesh.new()
var _model: Node3D
var _muzzle: Node3D
var _light: OmniLight3D
var _glow: StandardMaterial3D
var _kick := 0.0


func _ready() -> void:
	_build_model()
	var lines := MeshInstance3D.new()
	lines.mesh = _lines
	lines.top_level = true
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	lines.material_override = mat
	add_child(lines)
	lines.global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	var now := Tuning.now()
	_drawn = lerpf(_drawn, 1.0 if enabled else 0.0, 1.0 - exp(-delta * 4.0))
	_model.visible = _drawn > 0.02
	var firing := enabled and (force_fire or (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("fire")))
	if firing:
		_accum += delta * float(Tuning.v("gun.rate"))
		# Nearest first, so a closer cloud (e.g. the figure) shortens the ray
		# before anything behind it gets revealed.
		var clouds := get_tree().get_nodes_in_group("reveal")
		var eye := get_viewport().get_camera_3d().global_position
		clouds.sort_custom(func(a, b): return eye.distance_squared_to(a.world_center()) < eye.distance_squared_to(b.world_center()))
		while _accum >= 1.0:
			_accum -= 1.0
			_fire_ray(now, clouds)
	else:
		_accum = 0.0

	var base: Color = Tuning.v("gun.color")
	_glow.albedo_color = base if firing else base.darkened(0.65)
	_light.light_color = base
	_light.omni_range = Tuning.v("gun.light_range")
	var energy: float = float(Tuning.v("gun.light_energy")) * randf_range(0.7, 1.1) if firing else 0.0
	_light.light_energy = lerpf(_light.light_energy, energy, 1.0 - exp(-delta * 25.0))
	_kick = lerpf(_kick, 1.0 if firing else 0.0, 1.0 - exp(-delta * 20.0))
	_model.position = MODEL_OFFSET + Vector3(randf_range(-1, 1), randf_range(-1, 1), 2.0) * 0.004 * _kick \
			+ Vector3(0, -0.3, 0) * (1.0 - _drawn)
	_draw_lines(now)


func _fire_ray(now: float, clouds: Array) -> void:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.global_position
	var basis := cam.global_basis
	var spread := deg_to_rad(float(Tuning.v("gun.spread")))
	var a := randf() * TAU
	var r := sqrt(randf()) * spread
	var dir := (-basis.z + basis.x * cos(a) * r + basis.y * sin(a) * r).normalized()

	var max_range: float = Tuning.v("gun.range")
	var dist := max_range
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		dist = origin.distance_to(hit.position)

	var brush: float = Tuning.v("gun.brush")
	var penetration: float = Tuning.v("reveal.penetration")
	for cloud in clouds:
		var t: float = cloud.raycast_reveal(origin, dir, dist, brush, penetration, now)
		if t >= 0.0:
			dist = t

	var end := origin + dir * dist
	var colour := _vary(Tuning.v("gun.color"))
	_tracers.append([end, colour, now])
	if dist < max_range:
		_sparks.append([end, colour, now])


func _vary(c: Color) -> Color:
	var amount: float = Tuning.v("gun.color_random")
	return Color(
		clampf(c.r + (randf() - 0.5) * amount, 0, 1),
		clampf(c.g + (randf() - 0.5) * amount, 0, 1),
		clampf(c.b + (randf() - 0.5) * amount, 0, 1))


func _draw_lines(now: float) -> void:
	_lines.clear_surfaces()
	var tracer_life: float = Tuning.v("gun.tracer_life")
	var spark_life: float = Tuning.v("gun.spark_life")
	_tracers = _tracers.filter(func(t): return now - t[2] < tracer_life)
	_sparks = _sparks.filter(func(s): return now - s[2] < spark_life)
	if _tracers.is_empty() and _sparks.is_empty():
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var muzzle := _muzzle.global_position
	for t in _tracers:
		var k: float = 1.0 - (now - t[2]) / tracer_life
		var c: Color = t[1]
		c.a = k
		_lines.surface_set_color(c)
		_lines.surface_add_vertex(muzzle)
		c.a = k * 0.3
		_lines.surface_set_color(c)
		_lines.surface_add_vertex(t[0])
	for s in _sparks:
		var c: Color = s[1]
		c.a = 1.0 - (now - s[2]) / spark_life
		_lines.surface_set_color(c)
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			_lines.surface_add_vertex(s[0] - axis * 0.03)
			_lines.surface_add_vertex(s[0] + axis * 0.03)
	_lines.surface_end()


func _build_model() -> void:
	_model = Node3D.new()
	_model.position = MODEL_OFFSET
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.16, 0.17)
	metal.roughness = 0.6
	metal.metallic = 0.3
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_part(Vector3(0, 0, 0), Vector3(0.07, 0.09, 0.22), metal)            # body
	_part(Vector3(0, 0.01, -0.2), Vector3(0.035, 0.035, 0.2), metal)     # barrel
	_part(Vector3(0, -0.08, 0.06), Vector3(0.05, 0.12, 0.05), metal)     # grip
	_part(Vector3(0.037, 0, -0.02), Vector3(0.005, 0.02, 0.14), _glow)   # emitter strip
	_part(Vector3(0, 0.01, -0.302), Vector3(0.025, 0.025, 0.006), _glow) # tip
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, -0.31)
	_model.add_child(_muzzle)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.1, -1.2)   # ahead of the gun so it lights the room, not the model
	_light.light_energy = 0.0
	add_child(_light)


func _part(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mi)
