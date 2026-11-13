extends Node3D
## Building blocks for levels made from script: boxes, slabs along a profile
## edge, prisms extruded from a 2D polygon (walls with holes, hexagonal doors),
## generated pixel textures, and painted wall text.
## Everything uses the PSX shader's world-space texturing, so no UVs are needed.

const PsxShader := preload("res://shaders/psx_lit.gdshader")

var _textures := {}
var _fonts := {}


## PSX-lit material from one of the generated textures (see texture()).
func material(kind: String, tint := Color.WHITE, repeats_per_metre := 0.25) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PsxShader
	mat.set_shader_parameter("albedo_tex", texture(kind))
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("tex_scale", repeats_per_metre)
	return mat


## Flat glowing material (indicator lights, lamp lenses).
func glow_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


## Axis-aligned (or rotated) box with a matching collider.
func box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, collide := true, rot_deg := Vector3.ZERO) -> Node3D:
	var node: Node3D = StaticBody3D.new() if collide else Node3D.new()
	node.position = center
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	if collide:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		node.add_child(shape)
	# Subdivided so vertex snapping and affine warping stay subtle on big faces.
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.subdivide_width = mini(int(size.x / 2.0), 24)
	mesh.subdivide_height = mini(int(size.y / 2.0), 24)
	mesh.subdivide_depth = mini(int(size.z / 2.0), 24)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	node.add_child(mi)
	return node


## A box lying along the 2D edge a -> b (in the XY plane), running z0..z1.
## Its face sits exactly on the edge and it thickens to the right of a -> b
## (outward for a counter-clockwise profile), or to the left if `inward`.
func slab(parent: Node3D, a: Vector2, b: Vector2, z0: float, z1: float, thick: float, mat: Material, inward := false, collide := true) -> Node3D:
	var d := b - a
	var n := Vector2(d.y, -d.x).normalized() * (-1.0 if inward else 1.0)
	var mid := (a + b) * 0.5 + n * thick * 0.5
	return box(parent, Vector3(mid.x, mid.y, (z0 + z1) * 0.5), Vector3(d.length(), thick, absf(z1 - z0)), mat, collide,
			Vector3(0, 0, rad_to_deg(d.angle())))


## A 2D polygon (XY plane, no holes) extruded from z0 to z1.
func prism(parent: Node3D, poly: PackedVector2Array, z0: float, z1: float, mat: Material, collide := true) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		push_warning("prism: polygon could not be triangulated")
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		_tri(st, Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(c.x, c.y, z1), Vector3.BACK)
		_tri(st, Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(c.x, c.y, z0), Vector3.FORWARD)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var d := (q - p).normalized()
		var n2 := Vector2(d.y, -d.x)
		if Geometry2D.is_point_in_polygon((p + q) * 0.5 + n2 * 0.01, poly):
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0)
		_tri(st, Vector3(p.x, p.y, z0), Vector3(q.x, q.y, z0), Vector3(q.x, q.y, z1), n)
		_tri(st, Vector3(p.x, p.y, z0), Vector3(q.x, q.y, z1), Vector3(p.x, p.y, z1), n)
	var mesh := st.commit()
	var node: Node3D = StaticBody3D.new() if collide else Node3D.new()
	parent.add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	node.add_child(mi)
	if collide:
		var shape := CollisionShape3D.new()
		var trimesh := mesh.create_trimesh_shape()
		trimesh.backface_collision = true
		shape.shape = trimesh
		node.add_child(shape)
	return node


## Godot's front faces wind clockwise; order the triangle to face along n.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Cylinder between two points (pipes, cables, rails).
func pipe(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material, sides := 6) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = sides
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = (from + to) * 0.5
	var dir := (to - from).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.quaternion = Quaternion(Vector3.UP, dir)
	return mi


## Flat-top hexagon (a vertex on the left and right), counter-clockwise.
static func hexagon(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(center + Vector2(cos(i * PI / 3.0), sin(i * PI / 3.0)) * r)
	return pts


## The upper (or lower) half of a flat-top hexagon, for doors that split along
## the middle.
static func half_hexagon(center: Vector2, r: float, upper: bool) -> PackedVector2Array:
	var h := r * sqrt(3.0) * 0.5 * (1.0 if upper else -1.0)
	return PackedVector2Array([
		center + Vector2(-r, 0), center + Vector2(r, 0),
		center + Vector2(r * 0.5, h), center + Vector2(-r * 0.5, h)])


## A wall (rectangle `rect` in XY) with a flat-top hexagonal hole, z0..z1.
## Built as an upper and a lower piece that meet at the hexagon's middle.
func wall_with_hex_hole(parent: Node3D, rect: Rect2, center: Vector2, r: float, z0: float, z1: float, mat: Material) -> void:
	var h := r * sqrt(3.0) * 0.5
	var x0 := rect.position.x
	var x1 := rect.end.x
	var y0 := rect.position.y
	var y1 := rect.end.y
	prism(parent, PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, center.y), center + Vector2(r, 0),
		center + Vector2(r * 0.5, -h), center + Vector2(-r * 0.5, -h), center + Vector2(-r, 0), Vector2(x0, center.y)]),
		z0, z1, mat)
	prism(parent, PackedVector2Array([
		Vector2(x0, center.y), center + Vector2(-r, 0), center + Vector2(-r * 0.5, h), center + Vector2(r * 0.5, h),
		center + Vector2(r, 0), Vector2(x1, center.y), Vector2(x1, y1), Vector2(x0, y1)]),
		z0, z1, mat)


## A raised hexagonal ring (door frame) around `center`, z0..z1.
func hex_ring(parent: Node3D, center: Vector2, r: float, width: float, z0: float, z1: float, mat: Material) -> void:
	var pts := hexagon(center, r)
	for i in 6:
		slab(parent, pts[i], pts[(i + 1) % 6], z0, z1, width, mat, false, false)


## Text painted on a surface. `height` is the capital-letter height in metres.
## The text faces +z before `rot_deg` is applied.
func paint(parent: Node3D, text: String, pos: Vector3, rot_deg: Vector3, height: float, color: Color, font_kind := "stencil", shaded := true) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font(font_kind)
	label.font_size = 96
	label.pixel_size = height / (96.0 * 0.7)
	label.outline_size = 0
	label.modulate = color
	label.shaded = shaded
	label.double_sided = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	label.rotation_degrees = rot_deg
	parent.add_child(label)
	return label


func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var sys := SystemFont.new()
	sys.font_weight = 700
	var spaced := FontVariation.new()
	spaced.base_font = sys
	match kind:
		"wall":   # big geometric lettering
			sys.font_names = PackedStringArray(["Futura", "Avenir Next", "Helvetica Neue", "Arial"])
			spaced.spacing_glyph = 10
		_:        # condensed, painted-on
			sys.font_names = PackedStringArray(["DIN Condensed", "Avenir Next Condensed", "Impact", "Arial Narrow", "Arial"])
			spaced.spacing_glyph = 4
	_fonts[kind] = spaced
	return spaced


## Generated 64px seamless pixel textures.
func texture(kind: String) -> ImageTexture:
	if _textures.has(kind):
		return _textures[kind]
	var a := _noise_image(0.08, 1)
	var b := _noise_image(0.035, 2)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var n := a.get_pixel(x, y).r
			var m := b.get_pixel(x, y).r
			var seam := x % 32 == 0 or y % 32 == 0
			var c: Color
			match kind:
				"panel":   # cold wall panels
					var v := n * 0.3 + 0.38
					if seam:
						v *= 0.5
					if (x % 32 == 3 or x % 32 == 29) and (y % 32 == 3 or y % 32 == 29):
						v *= 0.45
					c = Color(v * 0.86, v * 0.93, v)
				"deck":    # floor plates with diamond tread
					var v := n * 0.25 + 0.3
					if (x + y) % 8 == 0 or (x - y + 64) % 8 == 0:
						v *= 0.72
					if seam:
						v *= 0.45
					c = Color(v * 0.9, v * 0.95, v)
				"dark":    # structural steel
					var v := n * 0.2 + 0.2
					if y % 16 == 0:
						v *= 0.6
					c = Color(v * 0.9, v * 0.95, v)
				"rust":    # the ship: tired steel with rust blooms and rivets
					var rust := smoothstep(0.42, 0.68, m + (n - 0.5) * 0.35)
					c = Color(0.2, 0.2, 0.21).lerp(Color(0.36, 0.16, 0.06), rust) * (0.55 + n * 0.6)
					if seam:
						c = c.darkened(0.55)
					if (x % 32 == 4 or x % 32 == 28) and y % 8 == 4 or (y % 32 == 4 or y % 32 == 28) and x % 8 == 4:
						c = c.lightened(0.18)
				"cargo":   # corrugated container
					var v := (0.62 if x % 8 < 4 else 0.82) * (0.7 + n * 0.4)
					var rust := smoothstep(0.55, 0.75, m)
					c = (Color(0.75, 0.56, 0.12) * v).lerp(Color(0.32, 0.15, 0.06), rust * 0.8)
					if y % 32 == 0:
						c = c.darkened(0.5)
				"hazard":  # yellow and black chevrons
					var v := 0.75 + n * 0.3
					c = (Color(0.8, 0.62, 0.08) if ((x + y) / 8) % 2 == 0 else Color(0.07, 0.07, 0.07)) * v
				_:
					c = Color(n, n, n)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_textures[kind] = tex
	return tex


func _noise_image(freq: float, seed_value: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = freq
	noise.seed = seed_value
	var img := noise.get_seamless_image(64, 64)
	img.convert(Image.FORMAT_RGB8)
	return img
