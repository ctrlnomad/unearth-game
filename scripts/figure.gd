extends Node3D
## A wandering figure made of reveal points: a boxy PS1-style person. Each body
## part is a RevealCloud parented to an animated "bone", so the points you
## reveal stick to the body as it walks. It wanders between random spots inside
## `area`, pausing to look around. Faces -z. Like the artifacts, it's invisible
## and silent until hit; one audio source follows how much of the whole body is
## visible.

const RevealCloud := preload("res://scripts/reveal_cloud.gd")
const SPACING := 0.022
const LIGHT_DIR := Vector3(0.3, 0.8, -0.5)   # baked shading on the points

const SKIN := Color(0.78, 0.66, 0.56)
const HAIR := Color(0.12, 0.1, 0.09)
const COAT := Color(0.32, 0.34, 0.3)
const TROUSERS := Color(0.27, 0.26, 0.31)
const BOOTS := Color(0.13, 0.11, 0.1)

@export var area := Rect2(-4.5, -30.0, 6.0, 32.0)   # x, z, size x, size z

var visible_fraction := 0.0
var audio_level := 0.0

var _parts: Array = []
var _total_points := 0
var _bones := {}
var _target := Vector3.ZERO
var _pause := 0.0
var _phase := 0.0
var _walk := 0.0          # 0 idle .. 1 walking, smoothed
var _anim_clock := 0.0    # pose updates are held to figure.anim_fps
var _audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("exhibit")
	_rng.seed = hash(name)
	_build_body()
	_audio = RevealCloud.make_audio_player("", hash(name) + 7, Vector3(0, 1.5, 0))
	add_child(_audio)
	_audio.play()
	_audio.stream_paused = true
	_pick_target()


func _process(delta: float) -> void:
	_move(delta)
	_anim_clock += delta
	var step := 1.0 / maxf(float(Tuning.v("figure.anim_fps")), 1.0)
	if _anim_clock >= step:
		_pose()
		_anim_clock = 0.0

	var revealed := 0.0
	for part in _parts:
		revealed += part.visible_fraction * part.point_count
	visible_fraction = revealed / maxf(_total_points, 1.0)
	audio_level = RevealCloud.drive_audio(_audio, audio_level, visible_fraction, delta)


func _move(delta: float) -> void:
	var speed: float = Tuning.v("figure.speed")
	var moving := false
	if _pause > 0.0:
		_pause -= delta
	else:
		var to := _target - position
		to.y = 0.0
		if to.length() < 0.25:
			_pause = _rng.randf_range(0.5, float(Tuning.v("figure.pause")))
			_pick_target()
		else:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-delta * 3.0))
			var forward := -global_basis.z
			var facing := clampf(forward.dot(to.normalized()), 0.0, 1.0)
			position += forward * speed * facing * delta
			moving = facing > 0.3
	_walk = lerpf(_walk, 1.0 if moving else 0.0, 1.0 - exp(-delta * 4.0))
	_phase += delta * TAU * speed / 1.3 * _walk


func _pick_target() -> void:
	_target = Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0,
			_rng.randf_range(area.position.y, area.end.y))


func _pose() -> void:
	var t := Tuning.now()
	var w: float = _walk * float(Tuning.v("figure.stride"))
	var s := sin(_phase)
	_bones.hips.position.y = 0.95 + absf(cos(_phase)) * 0.03 * w - 0.02 * w
	_bones.spine.rotation = Vector3(-0.06 * w + sin(t * 1.4) * 0.015, s * 0.08 * w, 0)
	_bones.head.rotation.y = sin(t * 0.37) * 0.6 * (1.0 - _walk)
	for side in [1.0, -1.0]:
		var swing: float = s * side
		var key := "l" if side > 0.0 else "r"
		_bones["hip_" + key].rotation.x = swing * 0.5 * w
		_bones["knee_" + key].rotation.x = -(0.1 + 0.7 * maxf(0.0, cos(_phase + (0.0 if side > 0.0 else PI)))) * w
		_bones["shoulder_" + key].rotation.x = -swing * 0.4 * w
		_bones["shoulder_" + key].rotation.z = side * -0.06
		_bones["elbow_" + key].rotation.x = 0.2 + 0.25 * maxf(0.0, swing) * w


## Skeleton (hips 0.95 m up) with box-shaped body parts, about 1.85 m tall.
func _build_body() -> void:
	var hips := _bone("hips", self, Vector3(0, 0.95, 0))
	_part(hips, Vector3(0.34, 0.16, 0.2), Vector3(0, 0.02, 0), TROUSERS)
	var spine := _bone("spine", hips, Vector3(0, 0.08, 0))
	_part(spine, Vector3(0.4, 0.52, 0.23), Vector3(0, 0.27, 0), COAT)
	var head := _bone("head", spine, Vector3(0, 0.56, 0))
	_part(head, Vector3(0.09, 0.07, 0.09), Vector3(0, 0.03, 0), SKIN)
	_part(head, Vector3(0.2, 0.24, 0.22), Vector3(0, 0.17, 0), SKIN, _face)
	for side in [1.0, -1.0]:
		var key := "l" if side > 0.0 else "r"
		var shoulder := _bone("shoulder_" + key, spine, Vector3(0.25 * side, 0.48, 0))
		_part(shoulder, Vector3(0.1, 0.32, 0.11), Vector3(0, -0.15, 0), COAT)
		var elbow := _bone("elbow_" + key, shoulder, Vector3(0, -0.31, 0))
		_part(elbow, Vector3(0.09, 0.28, 0.1), Vector3(0, -0.13, 0), COAT)
		_part(elbow, Vector3(0.07, 0.1, 0.08), Vector3(0, -0.31, 0), SKIN)
		var hip := _bone("hip_" + key, hips, Vector3(0.1 * side, -0.02, 0))
		_part(hip, Vector3(0.14, 0.44, 0.15), Vector3(0, -0.22, 0), TROUSERS)
		var knee := _bone("knee_" + key, hip, Vector3(0, -0.44, 0))
		_part(knee, Vector3(0.12, 0.42, 0.13), Vector3(0, -0.21, 0), TROUSERS)
		_part(knee, Vector3(0.12, 0.08, 0.24), Vector3(0, -0.45, -0.04), BOOTS)


func _bone(id: String, parent: Node3D, pos: Vector3) -> Node3D:
	var bone := Node3D.new()
	bone.name = id
	bone.position = pos
	parent.add_child(bone)
	_bones[id] = bone
	return bone


## Samples the surface of a box on a grid, bakes simple shading and noise into
## the colours, and adds it as a RevealCloud on `bone`. `detail` can recolour
## points: func(local_pos, normal, colour) -> colour.
func _part(bone: Node3D, size: Vector3, offset: Vector3, base: Color, detail := Callable()) -> void:
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var light := LIGHT_DIR.normalized()
	var half := size * 0.5
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sgn
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var nu := maxi(1, roundi(size[u] / SPACING))
			var nv := maxi(1, roundi(size[v] / SPACING))
			for i in nu:
				for j in nv:
					var p := Vector3.ZERO
					p[axis] = half[axis] * sgn
					p[u] = ((i + 0.5) / nu - 0.5) * size[u]
					p[v] = ((j + 0.5) / nv - 0.5) * size[v]
					var shade := 0.45 + 0.55 * maxf(0.0, normal.dot(light))
					var c := base * shade * _rng.randf_range(0.85, 1.15)
					if detail.is_valid():
						c = detail.call(p, normal, c)
					positions.append(p + offset)
					colors.append(Color(c.r, c.g, c.b))
	var cloud := RevealCloud.new()
	cloud.has_audio = false
	cloud.set_points(positions, colors, SPACING)
	bone.add_child(cloud)
	_parts.append(cloud)
	_total_points += cloud.point_count


## Head detail: hair on top and back, dark eyes on the front (-z) face.
func _face(p: Vector3, normal: Vector3, c: Color) -> Color:
	if normal.y > 0.5 or normal.z > 0.5 or (absf(normal.x) > 0.5 and (p.y > 0.04 or p.z > 0.0)):
		return HAIR * (c.r / maxf(SKIN.r, 0.01))
	if normal.z < -0.5 and absf(p.y - 0.02) < 0.02 and absf(absf(p.x) - 0.05) < 0.02:
		return Color(0.05, 0.04, 0.04)
	return c
