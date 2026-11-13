extends RefCounted
## The human figure the gas coagulates into: a small boxy skeleton (11 bones)
## with one short procedural animation. The gas assigns each particle to a body
## part and a point on that part's box; pose() gives the bone transforms for a
## moment of the animation, and both the CPU (hit tests) and the shader place
## particles with them.
##
## Figure space: feet on y = 0, facing +z, about 1.75 m tall.

const BONE_COUNT := 11
enum { HIPS, CHEST, HEAD, UPPER_ARM_L, FORE_ARM_L, UPPER_ARM_R, FORE_ARM_R, THIGH_L, SHIN_L, THIGH_R, SHIN_R }

# parent, joint position in the parent's space
const BONES := [
	[-1, Vector3(0, 0.95, 0)],          # hips
	[HIPS, Vector3(0, 0.15, 0)],        # chest
	[CHEST, Vector3(0, 0.33, 0)],       # head
	[CHEST, Vector3(0.21, 0.28, 0)],    # upper arm L
	[UPPER_ARM_L, Vector3(0, -0.28, 0)],
	[CHEST, Vector3(-0.21, 0.28, 0)],   # upper arm R
	[UPPER_ARM_R, Vector3(0, -0.28, 0)],
	[HIPS, Vector3(0.1, -0.02, 0)],     # thigh L
	[THIGH_L, Vector3(0, -0.45, 0)],
	[HIPS, Vector3(-0.1, -0.02, 0)],    # thigh R
	[THIGH_R, Vector3(0, -0.45, 0)],
]

# Each bone's box in bone space: centre, size.
const BOXES := [
	[Vector3(0, 0.02, 0), Vector3(0.32, 0.22, 0.18)],
	[Vector3(0, 0.15, 0), Vector3(0.38, 0.34, 0.2)],
	[Vector3(0, 0.13, 0.01), Vector3(0.19, 0.25, 0.22)],
	[Vector3(0, -0.13, 0), Vector3(0.1, 0.28, 0.1)],
	[Vector3(0, -0.14, 0), Vector3(0.085, 0.28, 0.085)],
	[Vector3(0, -0.13, 0), Vector3(0.1, 0.28, 0.1)],
	[Vector3(0, -0.14, 0), Vector3(0.085, 0.28, 0.085)],
	[Vector3(0, -0.22, 0), Vector3(0.14, 0.45, 0.14)],
	[Vector3(0, -0.23, 0), Vector3(0.11, 0.48, 0.11)],
	[Vector3(0, -0.22, 0), Vector3(0.14, 0.45, 0.14)],
	[Vector3(0, -0.23, 0), Vector3(0.11, 0.48, 0.11)],
]

## The animation, on a 0..1 timeline (stretched to gas.perform seconds).
## Keys per bone: [time, euler radians (x = forward/back, y = turn, z = sideways)].
## Placeholder memory: it stands with its head bowed, looks up towards you,
## reaches a hand out, holds it, then lets it fall.
const KEYS := {
	HIPS: [[0.0, Vector3(0, 0, 0)], [0.5, Vector3(0, 0.1, 0)], [1.0, Vector3(0, 0, 0)]],
	CHEST: [[0.0, Vector3(0.25, 0, 0)], [0.3, Vector3(0.05, 0, 0)], [0.55, Vector3(0.12, -0.1, 0)], [1.0, Vector3(0.2, 0, 0)]],
	HEAD: [[0.0, Vector3(0.55, 0, 0)], [0.25, Vector3(0.5, 0, 0)], [0.4, Vector3(-0.1, 0.15, 0)], [0.75, Vector3(-0.05, 0, 0.12)], [1.0, Vector3(0.45, 0, 0)]],
	UPPER_ARM_L: [[0.0, Vector3(0, 0, 0.08)], [1.0, Vector3(0.05, 0, 0.1)]],
	FORE_ARM_L: [[0.0, Vector3(-0.1, 0, 0)], [1.0, Vector3(-0.15, 0, 0)]],
	UPPER_ARM_R: [[0.0, Vector3(0, 0, -0.08)], [0.4, Vector3(-0.05, 0, -0.08)], [0.6, Vector3(-1.35, 0.15, -0.1)], [0.8, Vector3(-1.3, 0.15, -0.1)], [1.0, Vector3(-0.1, 0, -0.08)]],
	FORE_ARM_R: [[0.0, Vector3(-0.1, 0, 0)], [0.4, Vector3(-0.15, 0, 0)], [0.6, Vector3(-0.25, 0, 0)], [0.8, Vector3(-0.2, 0, 0)], [1.0, Vector3(-0.1, 0, 0)]],
	THIGH_L: [[0.0, Vector3(0, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	SHIN_L: [[0.0, Vector3(0, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	THIGH_R: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(-0.15, 0, 0)], [1.0, Vector3(0, 0, 0)]],
	SHIN_R: [[0.0, Vector3(0, 0, 0)], [0.55, Vector3(0.2, 0, 0)], [1.0, Vector3(0, 0, 0)]],
}


## World transforms of all bones at timeline position u (0..1), for a figure
## standing at `root` (feet) turned by `yaw` radians. `sway` is a small idle
## breathing/swaying amount in radians.
static func pose(u: float, root: Vector3, yaw: float, sway: float, clock: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(BONE_COUNT)
	var base := Transform3D(Basis(Vector3.UP, yaw), root)
	for b in BONE_COUNT:
		var e := _sample(KEYS[b], u)
		if b == HIPS or b == CHEST:
			e += Vector3(sin(clock * 1.1) * sway, 0, sin(clock * 0.7 + b) * sway)
		var local := Transform3D(Basis.from_euler(e), BONES[b][1])
		var parent: int = BONES[b][0]
		out[b] = (base if parent < 0 else out[parent]) * local
	return out


static func _sample(keys: Array, u: float) -> Vector3:
	if u <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var t := smoothstep(0.0, 1.0, (u - a[0]) / (b[0] - a[0]))
			return (a[1] as Vector3).lerp(b[1], t)
	return keys[-1][1]


## A random point on the figure's surface: [bone index, offset in bone space].
## Parts are picked in proportion to their surface area.
static func sample_point(rng: RandomNumberGenerator) -> Array:
	var areas: Array[float] = []
	var total := 0.0
	for box in BOXES:
		var s: Vector3 = box[1]
		var a := 2.0 * (s.x * s.y + s.y * s.z + s.x * s.z)
		areas.append(a)
		total += a
	var pick := rng.randf() * total
	var b := 0
	while b < BONE_COUNT - 1 and pick > areas[b]:
		pick -= areas[b]
		b += 1
	var centre: Vector3 = BOXES[b][0]
	var size: Vector3 = BOXES[b][1]
	# Uniform point in the box, then pushed onto a random face (weighted by area).
	var p := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5) * size
	var fx := size.y * size.z
	var fy := size.x * size.z
	var fz := size.x * size.y
	var f := rng.randf() * (fx + fy + fz)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var inset := rng.randf() * 0.015   # a thin shell rather than a hard surface
	if f < fx:
		p.x = side * (size.x * 0.5 - inset)
	elif f < fx + fy:
		p.y = side * (size.y * 0.5 - inset)
	else:
		p.z = side * (size.z * 0.5 - inset)
	return [b, centre + p]
