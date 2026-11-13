// Marks left by the scanner on every surface (scripts/scan_dots.gd): they flash
// when a ray lands, settle to a dim dot and fade, so firing maps the dark.
// Each instance's transform holds its position and, in basis.x.x, its birth time
// (instance custom data loses precision in the web renderer, the transform does not).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 color;              // linear
uniform float now;
uniform float life = 34.0;
global uniform vec2 psx_resolution;

varying float v_a;

void vertex() {
	float age = now - MODEL_MATRIX[0][0];
	v_a = (1.0 - smoothstep(life * 0.45, life, age)) * (0.5 + 0.5 * exp(-age * 5.0));
	vec4 pivot = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	float metres_per_px = 2.0 * -pivot.z / (PROJECTION_MATRIX[1][1] * psx_resolution.y);
	float size = max(0.018, metres_per_px) * step(0.01, v_a);
	POSITION = PROJECTION_MATRIX * (pivot + vec4(VERTEX.xy * size, 0.0, 0.0));
}

void fragment() {
	ALBEDO = color * v_a;
}
