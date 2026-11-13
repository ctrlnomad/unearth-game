extends Node3D
## A hidden artifact built from an image + depth map (ported from the web
## prototype). Invisible and silent until the ray gun hits it: each hit point
## shows for reveal.hold seconds, then fades over reveal.fade (done on the GPU
## in reveal_points.gdshader). The artifact's audio follows how much of it is
## visible right now: it fades in as you uncover it and out as the reveal decays.
##
## Local space: x centred, y up from 0, the image faces +z and nearer parts
## stick out towards +z. Don't scale the node; set width instead.
##
## Points can also come from code: call set_points() before adding the node
## (figure.gd does this for each body part, with has_audio off so the figure
## owns one audio source for the whole body).

const PointShader := preload("res://shaders/reveal_points.gdshader")
const NEVER := -1.0e6
const BUCKET := 0.05        # seconds per bucket of the hit-time histogram
const REFRESH := 0.05       # don't re-stamp a point hit more recently than this
const EMPTY: Array = []

@export var image_path := ""
@export var depth_path := ""
@export var audio_path := ""          # optional; empty = generated placeholder loop
@export var width := 2.0              # metres
@export var relief := 0.5             # metres between nearest and farthest kept depth
@export var resolution := 200         # samples along the longest image side
@export var depth_threshold := 0.65   # depth maps here are dark = near; brighter is background
@export var has_audio := true

var point_count := 0
var visible_fraction := 0.0
var audio_level := 0.0

var _positions := PackedVector3Array()
var _hit_time := PackedFloat32Array()
var _grid := {}                       # Vector3i -> Array of point indices
var _cell := 0.06
var _aabb := AABB()
var _buckets := {}                    # bucket index -> number of points last hit then
var _mm: MultiMesh
var _audio: AudioStreamPlayer3D
var _given_colors := PackedColorArray()
var _given_spacing := 0.0


func _ready() -> void:
	add_to_group("reveal")
	if image_path != "":
		_build_from_image()
	else:
		_finish_build(_given_colors, _given_spacing)
	if has_audio:
		add_to_group("exhibit")
		_audio = make_audio_player(audio_path, hash(name), _aabb.get_center())
		add_child(_audio)
		_audio.play()
		_audio.stream_paused = true


func _process(delta: float) -> void:
	visible_fraction = _visible_fraction(Tuning.now())
	if has_audio:
		audio_level = drive_audio(_audio, audio_level, visible_fraction, delta)


## Points in local space with sRGB colours; `spacing` is the typical distance
## between neighbours (sets point size and the hit grid). Call before add_child.
func set_points(positions: PackedVector3Array, colors: PackedColorArray, spacing: float) -> void:
	_positions = positions
	_given_colors = colors
	_given_spacing = spacing


## Shared by artifacts and figures: smooth the level towards the visible
## fraction (audio.* constants) and apply it to the player. Returns the new level.
static func drive_audio(player: AudioStreamPlayer3D, level: float, fraction: float, delta: float) -> float:
	var full_at: float = Tuning.v("audio.full_at")
	var target := pow(clampf(fraction / full_at, 0.0, 1.0), float(Tuning.v("audio.curve")))
	var tau: float = Tuning.v("audio.attack") if target > level else Tuning.v("audio.release")
	level = target if tau <= 0.0 else lerpf(level, target, 1.0 - exp(-delta / tau))
	player.volume_db = linear_to_db(maxf(level, 0.00001)) + float(Tuning.v("audio.max_db"))
	player.stream_paused = level < 0.001
	return level


static func make_audio_player(path: String, seed_value: int, pos: Vector3) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path) if path != "" else make_placeholder_loop(seed_value)
	player.position = pos
	player.unit_size = 6.0
	player.max_distance = 40.0
	player.volume_db = -80.0
	return player


## Reveal the points within `radius` of the ray. Returns the distance to the
## first point hit, or -1. Called by the ray gun for every ray.
func raycast_reveal(origin: Vector3, dir: Vector3, max_dist: float, radius: float, penetration: float, now: float) -> float:
	var inv := global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var span := _ray_box(o, d, _aabb.grow(radius))
	var t := maxf(span.x, 0.0)
	var t_end := minf(span.y, max_dist)
	if t > t_end:
		return -1.0

	var reach := ceili(radius / _cell)
	var r2 := radius * radius
	var visited := {}
	var first := -1.0
	while t <= t_end:
		var c := Vector3i(((o + d * t) / _cell).floor())
		for x in range(-reach, reach + 1):
			for y in range(-reach, reach + 1):
				for z in range(-reach, reach + 1):
					var key := c + Vector3i(x, y, z)
					if visited.has(key):
						continue
					visited[key] = true
					for idx in _grid.get(key, EMPTY):
						var q := _positions[idx] - o
						var along := q.dot(d)
						if along < 0.0 or (q - d * along).length_squared() > r2:
							continue
						if first < 0.0 or along < first:
							first = along
						if along <= first + penetration:
							_hit(idx, now)
		if first >= 0.0:
			t_end = minf(t_end, first + penetration + _cell)
		t += _cell * 0.5
	return first


func world_center() -> Vector3:
	return global_transform * _aabb.get_center()


## Hide everything again (dev panel button).
func hide_all() -> void:
	_hit_time.fill(NEVER)
	_buckets.clear()
	var buf := _mm.buffer
	for i in point_count:
		buf[i * 20 + 16] = NEVER
	_mm.buffer = buf


func _hit(idx: int, now: float) -> void:
	var old := _hit_time[idx]
	if now - old < REFRESH:
		return
	if old > NEVER:
		var ob := int(floor(old / BUCKET))
		if _buckets.has(ob):
			_buckets[ob] -= 1
			if _buckets[ob] <= 0:
				_buckets.erase(ob)
	var nb := int(floor(now / BUCKET))
	_buckets[nb] = _buckets.get(nb, 0) + 1
	_hit_time[idx] = now
	_mm.set_instance_custom_data(idx, Color(now, 0, 0, 0))


## Same visibility curve as the shader, summed over the hit-time histogram.
func _visible_fraction(now: float) -> float:
	if point_count == 0 or _buckets.is_empty():
		return 0.0
	var hold: float = Tuning.v("reveal.hold")
	var fade: float = maxf(float(Tuning.v("reveal.fade")), 0.001)
	var total := 0.0
	var expired := []
	for b: int in _buckets:
		var age := now - (b + 0.5) * BUCKET
		var vis := 1.0 - clampf((age - hold) / fade, 0.0, 1.0)
		if vis <= 0.0:
			expired.append(b)
		else:
			total += _buckets[b] * vis
	for b in expired:
		_buckets.erase(b)
	return total / point_count


func _build_from_image() -> void:
	var img := _load_image(image_path)
	var dep := _load_image(depth_path)
	var s := float(resolution) / maxi(img.get_width(), img.get_height())
	var w := maxi(1, roundi(img.get_width() * s))
	var h := maxi(1, roundi(img.get_height() * s))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	dep.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var spacing := width / w
	var height := spacing * h
	var colors := PackedColorArray()
	for y in h:
		for x in w:
			var depth := dep.get_pixel(x, y).r
			if depth > depth_threshold:
				continue
			_positions.append(Vector3((x + 0.5) * spacing - width * 0.5, height - (y + 0.5) * spacing,
					(1.0 - depth / depth_threshold) * relief))
			colors.append(img.get_pixel(x, y))
	_finish_build(colors, spacing)


## Builds the hit grid, bounds and MultiMesh from _positions + sRGB colours.
func _finish_build(colors: PackedColorArray, spacing: float) -> void:
	point_count = _positions.size()
	_hit_time.resize(point_count)
	_hit_time.fill(NEVER)
	_cell = maxf(spacing * 2.0, 0.04)
	_aabb = AABB(_positions[0], Vector3.ZERO) if point_count > 0 else AABB()
	for i in point_count:
		var p := _positions[i]
		_aabb = _aabb.expand(p)
		var key := Vector3i((p / _cell).floor())
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)

	# Instance buffer: 12 floats transform (3x4 rows), 4 colour, 4 custom.
	var buf := PackedFloat32Array()
	buf.resize(point_count * 20)
	for i in point_count:
		var o := i * 20
		var p := _positions[i]
		var c := colors[i].srgb_to_linear()
		buf[o] = 1.0
		buf[o + 3] = p.x
		buf[o + 5] = 1.0
		buf[o + 7] = p.y
		buf[o + 10] = 1.0
		buf[o + 11] = p.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1.0
		buf[o + 16] = NEVER

	var quad := QuadMesh.new()
	quad.size = Vector2(spacing, spacing)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = point_count
	_mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = _aabb.grow(spacing * 4.0)
	var mat := ShaderMaterial.new()
	mat.shader = PointShader
	mi.material_override = mat
	add_child(mi)


func _load_image(path: String) -> Image:
	var img := (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Slab test. Returns (t_enter, t_exit); t_enter > t_exit means a miss.
static func _ray_box(o: Vector3, d: Vector3, box: AABB) -> Vector2:
	var t0 := -INF
	var t1 := INF
	for a in 3:
		if absf(d[a]) < 1e-8:
			if o[a] < box.position[a] or o[a] > box.end[a]:
				return Vector2(1, 0)
		else:
			var ta := (box.position[a] - o[a]) / d[a]
			var tb := (box.end[a] - o[a]) / d[a]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


## Stand-in for a real recording until we have one: a muffled low drone under a
## buzzy, syllable-gated "voice", 16 kHz mono, looping. Seeded per artifact.
static func make_placeholder_loop(seed_value: int, seconds := 4.0, rate := 16000) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(seconds * rate)
	var drone := roundf(rng.randf_range(45.0, 90.0) * seconds) / seconds  # whole cycles per loop
	var pitch := rng.randf_range(95.0, 160.0)
	var syllables := int(seconds * rng.randf_range(3.0, 5.0))
	var amps := PackedFloat32Array()
	for i in syllables:
		amps.append(rng.randf_range(0.4, 1.0) if rng.randf() > 0.3 else 0.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var voice_lp := 0.0
	var hiss_lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var low := sin(TAU * drone * t) * 0.6 + sin(TAU * drone * 2.0 * t) * 0.25 + sin(TAU * drone * 3.01 * t) * 0.1
		var pos := t / seconds * syllables
		var env := amps[int(pos) % syllables] * sin(PI * (pos - floorf(pos)))
		phase = fmod(phase + (pitch * (1.0 + 0.08 * sin(TAU * 0.5 * t))) / rate, 1.0)
		voice_lp += (phase * 2.0 - 1.0 - voice_lp) * 0.12
		hiss_lp += (rng.randf() * 2.0 - 1.0 - hiss_lp) * 0.3
		var sample := clampf(low * 0.3 + voice_lp * env * 0.9 + hiss_lp * 0.05, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav
