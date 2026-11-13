extends RefCounted
## Generated stand-in sound effects (16 kHz mono), until real audio exists.
## Everything returns an AudioStreamWAV built from maths, so there are no assets.

const RATE := 16000


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## Low-passed noise. `k` is the filter coefficient: small = deep rumble, large = hiss.
static func _noise(n: int, k: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		lp += (rng.randf() * 2.0 - 1.0 - lp) * k
		lp2 += (lp - lp2) * k
		out[i] = lp2
	var peak := 0.0001
	for x in out:
		peak = maxf(peak, absf(x))
	for i in n:
		out[i] /= peak
	return out


## Looping heavy rumble (the cabin shaking). The tail is crossfaded into the head.
static func rumble(seconds := 3.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var fade := RATE / 4
	var src := _noise(n + fade, 0.02, 11)
	var rattle := _noise(n + fade, 0.25, 12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := src[i] * 0.8 + rattle[i] * 0.12 * (0.5 + 0.5 * sin(TAU * 9.0 * t))
		if i < fade:
			var w := float(i) / fade
			x = x * w + (src[n + i] * 0.8 + rattle[n + i] * 0.12) * (1.0 - w)
		out[i] = x
	return _wav(out, true)


## Looping electrical hum (whole cycles per loop, so it is seamless).
static func hum(base := 55.0, seconds := 2.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var f := roundf(base * seconds) / seconds
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.22 + sin(TAU * f * 3.0 * t) * 0.12 \
				+ sin(TAU * f * 7.0 * t) * 0.03
	return _wav(out, true)


## Looping room tone: a very low drone with slow beating, for the bay.
static func drone(seconds := 8.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var air := _noise(n, 0.01, 31)
	var out := PackedFloat32Array()
	out.resize(n)
	var f1 := roundf(41.0 * seconds) / seconds
	var f2 := roundf(61.6 * seconds) / seconds
	var beat := 1.0 / seconds
	for i in n:
		var t := float(i) / RATE
		var edge := minf(1.0, minf(float(i), float(n - i)) / (RATE * 0.5))
		out[i] = sin(TAU * f1 * t) * 0.35 * (0.7 + 0.3 * sin(TAU * beat * t)) \
				+ sin(TAU * f2 * t) * 0.2 * (0.6 + 0.4 * sin(TAU * beat * 2.0 * t + 1.0)) \
				+ air[i] * 0.25 * edge
	return _wav(out, true)


## Decaying burst of noise: k small = dull thump, k large = hiss of air.
static func burst(seconds: float, k: float, decay: float, seed_value := 5) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var out := _noise(n, k, seed_value)
	for i in n:
		var t := float(i) / RATE
		out[i] *= exp(-t * decay) * minf(1.0, t * 200.0)
	return _wav(out, false)


## Heavy metallic thud: a falling sine plus a dull noise hit.
static func thud(freq := 70.0, seconds := 0.7) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var hit := _noise(n, 0.08, 7)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += (freq * (0.45 + 0.55 * exp(-t * 9.0))) / RATE
		out[i] = sin(TAU * phase) * exp(-t * 7.0) * 0.9 + hit[i] * exp(-t * 22.0) * 0.6
	return _wav(out, false)


## Short switch click.
static func click() -> AudioStreamWAV:
	var n := int(0.07 * RATE)
	var out := _noise(n, 0.5, 3)
	for i in n:
		var t := float(i) / RATE
		out[i] = out[i] * exp(-t * 90.0) * 0.7 + sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.4
	return _wav(out, false)


## Power winding down: a tone sliding from `from` to `to` Hz.
static func power_down(seconds := 1.4, from := 190.0, to := 28.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var u := float(i) / n
		phase += lerpf(from, to, sqrt(u)) / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		out[i] = (sin(TAU * phase) * 0.6 + saw * 0.15) * (1.0 - u) * minf(1.0, u * 40.0)
	return _wav(out, false)
