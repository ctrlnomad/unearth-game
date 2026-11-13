// A ghost (scripts/ghost.gd): gas in the shape of a person. Invisible until a
// ray or a flare lights it. Each instance's transform holds the point's rest
// position (origin) and, in basis.x, (last hit time, body part, seed).
// The walk, shimmer, freeze glitch and vent dissolve all run here; hit tests on
// the CPU use the rest pose.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 origin;             // feet, world
uniform float yaw;
uniform float phase;
uniform float swing;
uniform float flare;             // 0..1: lit by a solar flare
uniform float glitch;            // 0..1: frozen by the beam
uniform float dissolve;          // 0..1: pulled apart by the vents
uniform float base;              // 0..1: visible without being hit
uniform float now;
uniform float hold = 1.4;
uniform float fade = 1.8;
global uniform vec2 psx_resolution;

varying float v_v;
varying float v_s;

void vertex() {
	vec3 d = MODEL_MATRIX[0].xyz;
	float part = d.y;
	float sd = d.z * 100.0;
	vec3 p = MODEL_MATRIX[3].xyz;
	float a = 0.0;
	float py = 1.48;
	float sw = sin(phase) * swing;
	if (part > 1.5 && part < 2.5) { a = sw; }
	else if (part > 2.5 && part < 3.5) { a = -sw; }
	else if (part > 3.5 && part < 4.5) { a = -sw * 1.1; py = 0.9; }
	else if (part > 4.5) { a = sw * 1.1; py = 0.9; }
	float c = cos(a);
	float s = sin(a);
	p.y -= py;
	p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
	p.y += py;
	p += 0.028 * vec3(sin(now * 3.0 + sd), sin(now * 2.3 + sd * 1.7), cos(now * 2.7 + sd * 2.9));
	float band = fract(sin(floor(p.y * 11.0) * 12.99 + floor(now * 16.0) * 78.2) * 43758.5);
	p.x += step(0.55, band) * glitch * 0.22 * (fract(sd * 7.1) - 0.5) * 2.0;
	vec3 away = vec3((fract(sd * 13.0) - 0.5) * 3.5, 3.0 + 5.0 * fract(sd * 5.0), (fract(sd * 3.0) - 0.5) * 3.5);
	p += away * dissolve * dissolve;
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 world = origin + vec3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy);
	float v = 1.0 - smoothstep(hold, hold + fade, now - d.x);
	v_v = max(max(v, flare), base) * (1.0 - dissolve);
	v_s = fract(sd * 9.0);
	vec4 pivot = VIEW_MATRIX * vec4(world, 1.0);
	float metres_per_px = 2.0 * -pivot.z / (PROJECTION_MATRIX[1][1] * psx_resolution.y);
	float size = max(0.028, 1.1 * metres_per_px) * step(0.02, v_v);
	POSITION = PROJECTION_MATRIX * (pivot + vec4(VERTEX.xy * size, 0.0, 0.0));
}

void fragment() {
	ALBEDO = mix(vec3(0.04, 0.3, 1.0), vec3(0.12, 1.0, 0.9), v_s) * v_v * (0.55 + 0.45 * v_s);
}
