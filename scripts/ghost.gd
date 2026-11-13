extends Node3D
## A ghost: the gas wearing the shape of one of the crew. It cannot be seen
## until scanner rays or a solar flare light it. It has no eyes: it walks toward
## the Cleaner, faster while the scanner is firing. Holding the beam on it
## freezes it for a few seconds. scripts/game.gd checks whether it has reached
## the player.
##
## The points live in a MultiMesh that stays at the world origin; the ghost's
## position and facing go to shaders/ghost_points.gdshader as uniforms.

signal froze

const GhostShader := preload("res://shaders/ghost_points.gdshader")
const COUNT := 800
const NEVER := -1.0e6
# centre, size: head, torso, left arm, right arm, left leg, right leg
const PARTS := [
	[Vector3(0, 1.68, 0), Vector3(0.24, 0.26, 0.24)], [Vector3(0, 1.2, 0), Vector3(0.46, 0.62, 0.26)],
	[Vector3(-0.32, 1.17, 0), Vector3(0.13, 0.64, 0.15)], [Vector3(0.32, 1.17, 0), Vector3(0.13, 0.64, 0.15)],
	[Vector3(-0.12, 0.45, 0), Vector3(0.17, 0.9, 0.19)], [Vector3(0.12, 0.45, 0), Vector3(0.17, 0.9, 0.19)]]
const BOX_MIN := Vector3(-0.6, 0.0, -0.4)
const BOX_MAX := Vector3(0.6, 1.95, 0.4)

var pos := Vector3.ZERO
var yaw := 0.0
var state := "follow"          # idle (stands and watches), follow, frozen, vent
var flare := 0.0               # 1 = fully lit by a flare; decays
var hold_flare := false        # keep the flare lit (scripted reveals)
var target: Node3D             # the player
var target_firing := false
var bounds := Rect2()
var immune := 0.0

var _rest := PackedVector3Array()
var _part := PackedFloat32Array()
var _seed := PackedFloat32Array()
var _hit := PackedFloat32Array()
var _mm: MultiMesh
var _mat: ShaderMaterial
var _phase := 0.0
var _swing := 0.0
var _beam := 0.0
var _struck := false
var _frozen := 0.0
var _glitch := 0.0
var _base := 0.0
var _dissolve := 0.0


func _ready() -> void:
	add_to_group("reveal")
	_phase = randf() * TAU
	var areas: Array[float] = []
	var total := 0.0
	for p: Array in PARTS:
		var s: Vector3 = p[1]
		areas.append(s.x * s.y + s.y * s.z + s.x * s.z)
		total += areas[-1]
	for id in PARTS.size():
		var n := COUNT - _rest.size() if id == PARTS.size() - 1 else int(round(COUNT * areas[id] / total))
		var c: Vector3 = PARTS[id][0]
		var s: Vector3 = PARTS[id][1]
		for k in n:
			var u := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
			if randf() < 0.82:   # mostly on the surface, some inside for body
				u[randi() % 3] = -0.5 if randf() < 0.5 else 0.5
			_rest.append(c + u * s)
			_part.append(float(id))
			_seed.append(randf())
			_hit.append(NEVER)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = quad
	_mm.instance_count = _rest.size()
	for i in _rest.size():
		_write(i)
	_mat = ShaderMaterial.new()
	_mat.shader = GhostShader
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3.ONE * -500.0, Vector3.ONE * 1000.0)
	mmi.top_level = true
	add_child(mmi)
	mmi.global_transform = Transform3D.IDENTITY
	_push()


func _write(i: int) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis(Vector3(_hit[i], _part[i], _seed[i]), Vector3.UP, Vector3.BACK), _rest[i]))


func world_center() -> Vector3:
	return pos + Vector3(0, 1, 0)


## Same interface as RevealCloud, so the ray gun treats ghosts like any exhibit.
## Rays pass through the gas, so this never shortens the ray (returns -1).
func raycast_reveal(origin: Vector3, dir: Vector3, max_dist: float, _radius: float, _penetration: float, now: float) -> float:
	if state == "vent":
		return -1.0
	var c := cos(yaw)
	var s := sin(yaw)
	var r := origin - pos
	var lo := Vector3(r.x * c - r.z * s, r.y, r.x * s + r.z * c)
	var ld := Vector3(dir.x * c - dir.z * s, dir.y, dir.x * s + dir.z * c)
	# Slab test against the body's box first: most rays miss.
	var tn := -INF
	var tf := INF
	for axis in 3:
		var inv := 1.0 / (ld[axis] if absf(ld[axis]) > 1e-9 else 1e-9)
		var t1 := (BOX_MIN[axis] - lo[axis]) * inv
		var t2 := (BOX_MAX[axis] - lo[axis]) * inv
		tn = maxf(tn, minf(t1, t2))
		tf = minf(tf, maxf(t1, t2))
	if tf < tn or tf < 0.0 or tn > max_dist:
		return -1.0
	var any := false
	for i in _rest.size():
		var v := _rest[i] - lo
		var tp := v.dot(ld)
		if tp < 0.0 or tp > max_dist:
			continue
		if v.length_squared() - tp * tp < 0.02:
			_hit[i] = now
			_write(i)
			any = true
	if any:
		_struck = true
	return -1.0


func vent() -> void:
	if state != "vent":
		state = "vent"
		hold_flare = false


func release() -> void:
	hold_flare = false
	if state == "idle":
		state = "follow"


func is_threat() -> bool:
	return state == "follow"


func _process(delta: float) -> void:
	if not hold_flare:
		flare = maxf(0.0, flare - delta / 3.5)
	if state == "vent":
		_dissolve = minf(1.0, _dissolve + delta / 2.6)
		_base = 0.8
		_push()
		if _dissolve >= 1.0:
			queue_free()
		return
	_beam = _beam + delta if _struck else maxf(0.0, _beam - delta * 0.6)
	_struck = false
	immune = maxf(0.0, immune - delta)
	var speed := 0.0
	if state == "frozen":
		_frozen -= delta
		_glitch = 1.0
		_base = 0.55
		if _frozen <= 0.0:
			state = "follow"
			immune = 2.5
			_beam = 0.0
	else:
		_glitch = maxf(0.0, _glitch - delta * 3.0)
		_base = maxf(0.0, _base - delta * 0.5)
		var to := Vector3.ZERO
		if is_instance_valid(target):
			to = target.global_position - pos
			to.y = 0.0
		if state == "follow":
			if _beam > float(Tuning.v("ghost.freeze_after")) and immune <= 0.0:
				state = "frozen"
				_frozen = Tuning.v("ghost.freeze_time")
				froze.emit()
			elif to.length() > 0.01:
				speed = float(Tuning.v("ghost.hunt")) if target_firing else float(Tuning.v("ghost.walk"))
				pos += to.normalized() * speed * delta
				yaw = atan2(to.x, to.z)
		elif state == "idle" and to.length() > 0.01:
			yaw = atan2(to.x, to.z)
	if bounds.size != Vector2.ZERO:
		pos.x = clampf(pos.x, bounds.position.x, bounds.end.x)
		pos.z = clampf(pos.z, bounds.position.y, bounds.end.y)
	_phase += speed * delta * 3.2
	_swing = lerpf(_swing, 0.55 if speed > 0.0 else 0.04, minf(1.0, delta * 5.0))
	_push()


func _push() -> void:
	_mat.set_shader_parameter("origin", pos)
	_mat.set_shader_parameter("yaw", yaw)
	_mat.set_shader_parameter("phase", _phase)
	_mat.set_shader_parameter("swing", _swing)
	_mat.set_shader_parameter("flare", flare)
	_mat.set_shader_parameter("glitch", _glitch)
	_mat.set_shader_parameter("dissolve", _dissolve)
	_mat.set_shader_parameter("base", _base)
	_mat.set_shader_parameter("now", Tuning.now())
