// Ambient gas motes in the loading bay (scripts/loading_bay.gd): faint cyan
// points that wander around a home position and pulse like fireflies.
// Purely decorative, so all motion is here and nothing is mirrored on the CPU.
// INSTANCE_CUSTOM: r = seed, g = phase, b = speed variation.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 glow_color;         // linear
uniform float glow;
uniform float particle_size;
uniform float min_pixels;
uniform float drift;             // metres a mote wanders from home
uniform float clock;             // seconds, already scaled by bay.mote_speed
uniform float pulse;             // 0 = steady glow, 1 = full firefly pulsing
global uniform vec2 psx_resolution;

varying float v_bright;

void vertex() {
	float s = INSTANCE_CUSTOM.r;
	float ph = INSTANCE_CUSTOM.g * 6.283;
	float t = clock * (0.5 + INSTANCE_CUSTOM.b);
	vec3 home = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 world = home + drift * vec3(
		sin(t + ph) + 0.5 * sin(t * 0.37 + s * 20.0),
		0.6 * sin(t * 0.8 + ph * 1.7),
		cos(t * 0.9 + ph * 0.6) + 0.5 * sin(t * 0.23 + s * 9.0));
	vec4 pivot = VIEW_MATRIX * vec4(world, 1.0);
	float metres_per_px = 2.0 * -pivot.z / (PROJECTION_MATRIX[1][1] * psx_resolution.y);
	float size = max(particle_size, min_pixels * metres_per_px);
	POSITION = PROJECTION_MATRIX * (pivot + vec4(VERTEX.xy * size, 0.0, 0.0));
	float p = 0.5 + 0.5 * sin(clock * (1.2 + 2.0 * s) + ph * 3.0);
	v_bright = glow * mix(1.0, p * p * p, pulse);
}

void fragment() {
	ALBEDO = glow_color * v_bright;
}
