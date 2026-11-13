extends Node3D
## The first gas: already loose in the hall when you arrive. It has a centre, a
## dense core that moves around the room like a ghost: it glides, stops and
## hovers, darts off, and now and then drifts up to the player and away again.
## The rest of the cloud thins out around that core and trails behind it, so
## when the core moves the gas stretches into wisps that catch up later.
##
## Invisible until the ray gun passes through it. Every particle a ray touches
## glows a faint cyan for gas.hold seconds, then fades over gas.fade. Rays pass
## straight through the gas, so one beam lights a line through the cloud.
##
## How the trailing works: the core's recent path is kept as a trail of
## positions (TRAIL_N samples, TRAIL_DT apart). Each particle follows the core
## with a lag that grows with its distance from the core, so the core is tight
## and the edges lag behind. On top of that, particles spin slowly and flow
## along a swirl. All of this runs in gas_points.gdshader; ray hits evaluate the
## same maths on the CPU (_particle_pos / _trail_at), so keep the two in sync.
##
## Coagulation: rays that hit the gas build up energy (gas.energy_needed
## seconds of sustained hits; it leaks away at gas.energy_decay). When it's full,
## the gas stops, pulls together into a human figure (gas_figure.gd) over
## gas.form seconds, plays a short animation over gas.perform, then bursts apart
## and drifts back into gas over gas.disperse. Each particle has a fixed spot on
## the figure (bone + offset), so the figure moves with the animation.
##
## The node's position is the core. Rebuilds when gas.count, gas.size,
## gas.squash, gas.core or gas.core_size change.

const GasShader := preload("res://shaders/gas_points.gdshader")
const GasFigure := preload("res://scripts/gas_figure.gd")
const NEVER := -1.0e6
const REFRESH := 0.05           # don't re-stamp a particle hit more recently than this
const TRAIL_N := 96             # must match the shader's trail[] size
const TRAIL_DT := 1.0 / 30.0    # seconds between trail samples (96 samples = 3.2 s)
const MAX_LAG := (TRAIL_N - 2) * TRAIL_DT
const ROAM_MIN := Vector3(-8.5, 1.2, -27.0)   # where the core may go
const ROAM_MAX := Vector3(8.5, 5.0, 4.0)

enum { GLIDE, HOVER, DART, APPROACH }
const STATE_NAMES := ["glide", "hover", "dart", "approach"]
enum { SEQ_NONE, SEQ_FORM, SEQ_PERFORM, SEQ_DISPERSE }
const SEQ_NAMES := ["", "forming", "figure", "dispersing"]

var visible_fraction := 0.0     # share of particles glowing right now (dev panel)
var audio_level := 0.0          # no audio yet; here so the dev panel can list the gas
var state_name := "hover"

var _rest := PackedVector3Array()
var _seed := PackedFloat32Array()
var _lag_k := PackedFloat32Array()  # per-particle lag, in units of gas.lag
var _bone := PackedInt32Array()     # body part on the figure
var _fig_off := PackedVector3Array()  # spot on that part, bone space
var _stagger := PackedFloat32Array()  # 0 = joins the figure first, 1 = last
var _hit_time := PackedFloat32Array()
var _cur := PackedVector3Array()    # current world positions, filled lazily when a ray needs them
var _cur_frame := -1
var _radius := 1.0
var _mm: MultiMesh
var _mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _stat_timer := 0.0

# Clocks that drive the inner motion (shared with the shader).
var _clock := 0.0
var _churn := 0.0
var _spin := 0.0
var _breath := 1.0

# The core's path.
var _trail := PackedVector3Array()
var _trail_age0 := 0.0          # seconds since trail[1] was sampled

# Ghost behaviour.
var _state := HOVER
var _state_left := 2.0
var _target := Vector3.ZERO
var _base := Vector3.ZERO       # core position before the wobble
var _vel := Vector3.ZERO

# Coagulation.
var energy := 0.0               # seconds of sustained hits
var _seq := SEQ_NONE
var _seq_t := 0.0
var _cooldown := 0.0
var _form := 0.0                # 0 = gas, 1 = figure
var _scatter := 0.0             # outward burst while dispersing
var _fig_root := Vector3.ZERO
var _fig_yaw := 0.0
var _bones: Array[Transform3D] = []
var _bone_cols := PackedVector3Array()


func _ready() -> void:
	add_to_group("reveal")    # the ray gun tests everything in this group
	add_to_group("exhibit")   # listed in the dev panel and capture output
	_rng.seed = 7
	_base = position
	_trail.resize(TRAIL_N)
	_trail.fill(global_position)
	_bone_cols.resize(GasFigure.BONE_COUNT * 4)
	_fig_root = Vector3(_base.x, 0.0, _base.z)
	_pose(0.0)

	_mat = ShaderMaterial.new()
	_mat.shader = GasShader
	var mmi := MultiMeshInstance3D.new()
	mmi.top_level = true      # instance origins are rest offsets; the shader places them
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles are moved in the shader, so the culling box must cover the room.
	mmi.custom_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	add_child(mmi)
	mmi.global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE   # scaled to gas.particle_size in the shader
	_mm.mesh = quad
	mmi.multimesh = _mm
	_build()
	Tuning.changed.connect(_on_tuning_changed)


func _process(delta: float) -> void:
	_clock += delta
	_churn += delta * float(Tuning.v("gas.churn"))
	_spin += delta * float(Tuning.v("gas.spin"))
	_breath = 1.0 + float(Tuning.v("gas.breath")) * sin(_clock * 0.9)
	_update_energy(delta)
	if _seq == SEQ_NONE:
		_ghost(delta)
	else:
		_vel = _vel.lerp(Vector3.ZERO, 1.0 - exp(-delta * 3.0))
		_base += _vel * delta
		position = _base
		_sequence(delta)
	_record_trail(delta)
	var phase: String = "" if _seq == SEQ_NONE else SEQ_NAMES[_seq] + "  ·  "
	state_name = "%s%s  ·  energy %d%%" % [phase, STATE_NAMES[_state], roundi(100.0 * energy / maxf(float(Tuning.v("gas.energy_needed")), 0.001))]

	var glow: Color = (Tuning.v("gas.color") as Color).srgb_to_linear()
	_mat.set_shader_parameter("now", Tuning.now())
	_mat.set_shader_parameter("trail", _trail)
	_mat.set_shader_parameter("trail_age0", _trail_age0)
	_mat.set_shader_parameter("lag", float(Tuning.v("gas.lag")))
	_mat.set_shader_parameter("breath", _breath)
	_mat.set_shader_parameter("churn_clock", _churn)
	_mat.set_shader_parameter("spin_clock", _spin)
	_mat.set_shader_parameter("swirl", float(Tuning.v("gas.swirl")))
	_mat.set_shader_parameter("glow_color", Vector3(glow.r, glow.g, glow.b))
	for k in ["glow", "flash", "flash_decay", "hold", "fade", "particle_size", "min_pixels", "flicker", "show_all", "figure_glow", "figure_jitter"]:
		_mat.set_shader_parameter(k, float(Tuning.v("gas." + k)))
	_mat.set_shader_parameter("bones", _bone_cols)
	_mat.set_shader_parameter("form", _form)
	_mat.set_shader_parameter("scatter", _scatter * float(Tuning.v("gas.scatter")))
	_mat.set_shader_parameter("charge", _charge())

	_stat_timer -= delta
	if _stat_timer <= 0.0:
		_stat_timer = 0.1
		visible_fraction = _glowing_fraction(Tuning.now())


## Light every particle within gas.hit_radius of the ray. Rays pass through the
## gas, so this always returns -1 (the gun doesn't shorten the beam).
func raycast_reveal(origin: Vector3, dir: Vector3, max_dist: float, _radius_unused: float, _penetration: float, now: float) -> float:
	var hit_r: float = Tuning.v("gas.hit_radius")
	# Cheap reject: is the ray anywhere near the core's recent path?
	var reach := _radius * _breath + float(Tuning.v("gas.swirl")) * 1.2 + hit_r
	var near := _form > 0.0 or _scatter > 0.0
	for k in range(0, TRAIL_N, 4):
		if near:
			break
		var v := _trail[k] - origin
		var t := clampf(v.dot(dir), 0.0, max_dist)
		if (v - dir * t).length_squared() < reach * reach:
			near = true
			break
	if not near:
		return -1.0
	_update_positions()
	var r2 := hit_r * hit_r
	var any := false
	for i in _cur.size():
		var v := _cur[i] - origin
		var t := v.dot(dir)
		if t < 0.0 or t > max_dist:
			continue
		if v.length_squared() - t * t < r2:
			any = true
			if now - _hit_time[i] > REFRESH:
				_hit_time[i] = now
				_mm.set_instance_custom_data(i, Color(now, _seed[i], _lag_k[i], _bone[i]))
	if any and _seq == SEQ_NONE and _cooldown <= 0.0:
		energy += 1.0 / maxf(float(Tuning.v("gun.rate")), 1.0)
	return -1.0


func world_center() -> Vector3:
	return global_position


## Dev panel "Hide reveals".
func hide_all() -> void:
	for i in _hit_time.size():
		_hit_time[i] = NEVER
		_mm.set_instance_custom_data(i, Color(NEVER, _seed[i], _lag_k[i], _bone[i]))


# --- motion shared with the shader -------------------------------------------

## Same maths as trail_at() in gas_points.gdshader.
func _trail_at(lag_s: float) -> Vector3:
	var l := clampf(lag_s, 0.0, MAX_LAG)
	if l <= _trail_age0:
		return _trail[0].lerp(_trail[1], l / maxf(_trail_age0, 0.0001))
	var k := (l - _trail_age0) / TRAIL_DT + 1.0
	var i := mini(int(k), TRAIL_N - 2)
	return _trail[i].lerp(_trail[i + 1], k - float(i))


## Same maths as gas_pos() in gas_points.gdshader.
func _particle_pos(b: Vector3, s: float, swirl: float) -> Vector3:
	b *= _breath
	var a := _spin * (0.6 + 0.8 * s)
	var c := cos(a)
	var sn := sin(a)
	var p := Vector3(b.x * c - b.z * sn, b.y, b.x * sn + b.z * c)
	var flow := Vector3(
		sin(_churn + p.y * 1.7 + s * 6.283),
		0.5 * sin(_churn * 0.7 + p.x * 1.3 + s * 12.1),
		sin(_churn * 0.85 + p.z * 1.5 + s * 3.7))
	return p + flow * swirl


func _update_positions() -> void:
	var frame := Engine.get_process_frames()
	if frame == _cur_frame:
		return
	_cur_frame = frame
	var swirl: float = Tuning.v("gas.swirl")
	var lag: float = Tuning.v("gas.lag")
	var shaping := _form > 0.0 or _scatter > 0.0
	var jitter: float = Tuning.v("gas.figure_jitter")
	var scatter: float = _scatter * float(Tuning.v("gas.scatter"))
	for i in _rest.size():
		var p := _trail_at(lag * _lag_k[i]) + _particle_pos(_rest[i], _seed[i], swirl)
		if shaping:
			p = _shape(p, i, jitter, scatter)
		_cur[i] = p


## Same maths as the figure part of vertex() in gas_points.gdshader.
func _shape(gas_p: Vector3, i: int, jitter: float, scatter: float) -> Vector3:
	var s := _seed[i]
	var d := _stagger[i] * 0.6
	var pf := smoothstep(d, d + 0.4, _form)
	var fig := _bones[_bone[i]] * _fig_off[i]
	fig += jitter * Vector3(sin(_churn * 2.0 + s * 31.0), sin(_churn * 1.7 + s * 17.0), sin(_churn * 2.3 + s * 7.0))
	var p := gas_p.lerp(fig, pf)
	var out := fig - _bones[GasFigure.HIPS].origin
	if out.length() > 0.0001:
		p += out / out.length() * scatter * (0.5 + s)
	return p


func _record_trail(delta: float) -> void:
	_trail_age0 += delta
	while _trail_age0 >= TRAIL_DT:
		_trail_age0 -= TRAIL_DT
		# Shift: the old trail[0] (the live position) becomes the newest sample.
		for k in range(TRAIL_N - 1, 0, -1):
			_trail[k] = _trail[k - 1]
	_trail[0] = global_position


# --- shape ------------------------------------------------------------------

## Rest offsets from the core: a tight core (gas.core of the particles), a
## looser body around it and a few far wisps. Lag grows with distance from the
## core, so the outside trails behind when the core moves.
func _build() -> void:
	var count := int(Tuning.v("gas.count"))
	var size: float = Tuning.v("gas.size")
	var squash: float = Tuning.v("gas.squash")
	var core_frac: float = Tuning.v("gas.core")
	var core_size: float = Tuning.v("gas.core_size")
	_rest.resize(count)
	_seed.resize(count)
	_lag_k.resize(count)
	_bone.resize(count)
	_fig_off.resize(count)
	_stagger.resize(count)
	_hit_time.resize(count)
	_cur.resize(count)
	_cur_frame = -1
	_mm.instance_count = count
	_radius = 0.0
	for i in count:
		var r := _rng.randf()
		var sigma := size * core_size
		if r >= core_frac:
			sigma = size * (0.9 if r > 0.9 else 0.42)
		var b := Vector3(_rng.randfn(0.0, sigma), _rng.randfn(0.0, sigma * squash), _rng.randfn(0.0, sigma))
		var s := _rng.randf()
		_rest[i] = b
		_seed[i] = s
		_lag_k[i] = clampf(b.length() / size, 0.0, 2.0) * (0.6 + 0.8 * s)
		var spot: Array = GasFigure.sample_point(_rng)
		_bone[i] = spot[0]
		_fig_off[i] = spot[1]
		_stagger[i] = clampf(_lag_k[i] * 0.5, 0.0, 1.0) * 0.7 + s * 0.3   # core first, wisps last
		_hit_time[i] = NEVER
		_radius = maxf(_radius, b.length())
		# Origin = rest offset in the gas; basis x column = spot on the figure
		# (the shader reads both; the quad is billboarded so the basis isn't used for drawing).
		_mm.set_instance_transform(i, Transform3D(Basis(_fig_off[i], Vector3.UP, Vector3.BACK), b))
		_mm.set_instance_custom_data(i, Color(NEVER, s, _lag_k[i], _bone[i]))


# --- ghost behaviour -----------------------------------------------------------

func _ghost(delta: float) -> void:
	_state_left -= delta
	var want := Vector3.ZERO
	var steer := 1.5
	match _state:
		GLIDE, APPROACH:
			var to := _target - _base
			var arrive := clampf(to.length() / 2.0, 0.15, 1.0)   # ease in on arrival
			want = to.normalized() * float(Tuning.v("gas.drift")) * arrive
			steer = 0.6
			if to.length() < 0.4 or _state_left <= 0.0:
				_after_move()
		DART:
			var to := _target - _base
			want = to.normalized() * float(Tuning.v("gas.dart_speed"))
			steer = 5.0
			if to.length() < 0.3 or _state_left <= 0.0:
				_after_move()
		HOVER:
			steer = 1.2
			if _state_left <= 0.0:
				_next_move()
	_vel = _vel.lerp(want, 1.0 - exp(-delta * steer))
	_base = (_base + _vel * delta).clamp(ROAM_MIN, ROAM_MAX)

	# Small restless wobble on top, so even a hovering core is never still.
	var w: float = Tuning.v("gas.wobble")
	var c := _clock
	position = _base + w * Vector3(sin(c * 1.3) + 0.5 * sin(c * 3.1), 0.6 * sin(c * 0.9 + 1.0), sin(c * 1.1 + 2.0) + 0.4 * sin(c * 2.7))


func _after_move() -> void:
	if _rng.randf() < 0.65:
		_set_state(HOVER, _rng.randf_range(0.8, float(Tuning.v("gas.hover"))))
	else:
		_next_move()


func _next_move() -> void:
	var r := _rng.randf()
	var cam := get_viewport().get_camera_3d()
	if cam and _state != APPROACH and r < float(Tuning.v("gas.curiosity")):
		# Drift up to the player and stop a little way off.
		var eye := cam.global_position
		var away := (_base - eye)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		_target = (eye + away * _rng.randf_range(2.2, 3.2) + Vector3.UP * _rng.randf_range(0.0, 0.6)).clamp(ROAM_MIN, ROAM_MAX)
		_set_state(APPROACH, 10.0)
	elif r < 0.75:
		_target = Vector3(
			_rng.randf_range(ROAM_MIN.x, ROAM_MAX.x),
			_rng.randf_range(ROAM_MIN.y + 0.3, ROAM_MAX.y - 1.0),
			_rng.randf_range(ROAM_MIN.z, ROAM_MAX.z))
		_set_state(GLIDE, 14.0)
	else:
		var dir := Vector3(_rng.randfn(), _rng.randfn() * 0.3, _rng.randfn()).normalized()
		_target = (_base + dir * _rng.randf_range(2.0, 4.0)).clamp(ROAM_MIN, ROAM_MAX)
		_set_state(DART, _rng.randf_range(0.6, 1.2))


func _set_state(s: int, duration: float) -> void:
	_state = s
	_state_left = duration
	state_name = STATE_NAMES[s]


# --- coagulation ---------------------------------------------------------------

func _update_energy(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _seq != SEQ_NONE:
		return
	energy = maxf(energy - delta * float(Tuning.v("gas.energy_decay")), 0.0)
	if energy >= float(Tuning.v("gas.energy_needed")):
		_start_figure()


func _start_figure() -> void:
	_seq = SEQ_FORM
	_seq_t = 0.0
	# Stand on the floor under the core, facing the player.
	_fig_root = Vector3(clampf(_base.x, -10.5, 10.5), 0.0, clampf(_base.z, -30.5, 6.5))
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to := cam.global_position - _fig_root
		_fig_yaw = atan2(to.x, to.z)
	_fig_yaw += deg_to_rad(float(Tuning.v("gas.face_offset")))
	_pose(0.0)


func _sequence(delta: float) -> void:
	_seq_t += delta
	match _seq:
		SEQ_FORM:
			var t := _seq_t / maxf(float(Tuning.v("gas.form")), 0.01)
			_form = smoothstep(0.0, 1.0, minf(t, 1.0))
			_pose(0.0)
			if t >= 1.0:
				_seq = SEQ_PERFORM
				_seq_t = 0.0
		SEQ_PERFORM:
			var t := _seq_t / maxf(float(Tuning.v("gas.perform")), 0.01)
			_form = 1.0
			_pose(minf(t, 1.0))
			if t >= 1.0:
				_seq = SEQ_DISPERSE
				_seq_t = 0.0
		SEQ_DISPERSE:
			var t := _seq_t / maxf(float(Tuning.v("gas.disperse")), 0.01)
			_form = 1.0 - smoothstep(0.0, 1.0, minf(t, 1.0))
			_scatter = sin(PI * minf(t, 1.0))
			_pose(1.0)
			if t >= 1.0:
				_seq = SEQ_NONE
				_form = 0.0
				_scatter = 0.0
				energy = 0.0
				_cooldown = Tuning.v("gas.cooldown")
				_cur_frame = -1


func _pose(u: float) -> void:
	_bones = GasFigure.pose(u, _fig_root, _fig_yaw, float(Tuning.v("gas.sway")), _clock)
	for b in GasFigure.BONE_COUNT:
		var t: Transform3D = _bones[b]
		_bone_cols[b * 4] = t.basis.x
		_bone_cols[b * 4 + 1] = t.basis.y
		_bone_cols[b * 4 + 2] = t.basis.z
		_bone_cols[b * 4 + 3] = t.origin
	_cur_frame = -1


## Glow multiplier: the gas brightens as energy builds.
func _charge() -> float:
	var k := 1.0 if _seq != SEQ_NONE else clampf(energy / maxf(float(Tuning.v("gas.energy_needed")), 0.001), 0.0, 1.0)
	return 1.0 + float(Tuning.v("gas.charge_glow")) * k


func _glowing_fraction(now: float) -> float:
	if _hit_time.is_empty():
		return 0.0
	var window: float = float(Tuning.v("gas.hold")) + float(Tuning.v("gas.fade")) * 0.5
	var n := 0
	for t in _hit_time:
		if now - t < window:
			n += 1
	return float(n) / float(_hit_time.size())


func _on_tuning_changed(key: String) -> void:
	if key in ["gas.count", "gas.size", "gas.squash", "gas.core", "gas.core_size"]:
		_build()
