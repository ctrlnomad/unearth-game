// Particles of the gas (scripts/gas.gd). Each MultiMesh instance is one
// particle; its instance transform origin is its rest offset from the core
// (the MultiMeshInstance3D is top_level at the world origin).
// A particle follows the core's recent path (trail) with its own lag, then gets
// the slow spin + flowing swirl on top. gas.gd evaluates the SAME maths on the
// CPU for ray hits: keep trail_at()/gas_pos() in sync with _trail_at() and
// _particle_pos() there.
// Coagulation: each particle also has a spot on the figure (gas_figure.gd):
// the bone in INSTANCE_CUSTOM.a and the offset in the instance basis x column.
// `form` blends particles from gas to figure (staggered), `scatter` bursts them
// outward while dispersing. Mirror of Gas._shape().
// INSTANCE_CUSTOM: r = last time a ray hit it, g = seed, b = lag factor, a = bone.
// Unhit particles are pushed outside the clip volume, so the idle gas is
// invisible and costs no fragments.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

const int TRAIL_N = 96;          // gas.gd TRAIL_N
const float TRAIL_DT = 1.0 / 30.0;

uniform vec3 trail[96];          // [0] = core now, [k] = core k-1 samples before trail_age0
uniform float trail_age0;
uniform float lag;               // gas.lag, seconds
uniform float breath;            // scale of the rest offsets
uniform float now;
uniform float churn_clock;
uniform float spin_clock;
uniform float swirl;
uniform vec3 glow_color;         // linear
uniform float glow;
uniform float flash;
uniform float flash_decay;
uniform float hold;
uniform float fade;
uniform float particle_size;
uniform float min_pixels;
uniform float flicker;
uniform float show_all;          // debug: draw every particle at this visibility
uniform vec3 bones[44];          // 11 bones x (basis x, basis y, basis z, origin), world
uniform float form;              // 0 = gas, 1 = figure
uniform float scatter;           // metres of outward burst right now
uniform float figure_jitter;
uniform float figure_glow;
uniform float charge;            // glow multiplier from built-up energy
global uniform vec2 psx_resolution;

varying float v_bright;

vec3 trail_at(float lag_s) {
	float l = clamp(lag_s, 0.0, float(TRAIL_N - 2) * TRAIL_DT);
	if (l <= trail_age0) {
		return mix(trail[0], trail[1], l / max(trail_age0, 0.0001));
	}
	float k = (l - trail_age0) / TRAIL_DT + 1.0;
	int i = min(int(k), TRAIL_N - 2);
	return mix(trail[i], trail[i + 1], k - float(i));
}

vec3 gas_pos(vec3 b, float s) {
	b *= breath;
	float a = spin_clock * (0.6 + 0.8 * s);
	float c = cos(a);
	float sn = sin(a);
	vec3 p = vec3(b.x * c - b.z * sn, b.y, b.x * sn + b.z * c);
	vec3 flow = vec3(
		sin(churn_clock + p.y * 1.7 + s * 6.283),
		0.5 * sin(churn_clock * 0.7 + p.x * 1.3 + s * 12.1),
		sin(churn_clock * 0.85 + p.z * 1.5 + s * 3.7));
	return p + flow * swirl;
}

void vertex() {
	float age = now - INSTANCE_CUSTOM.r;
	float vis = 1.0 - clamp((age - hold) / max(fade, 0.001), 0.0, 1.0);
	float s = INSTANCE_CUSTOM.g;
	float lagk = INSTANCE_CUSTOM.b;
	int bi = int(INSTANCE_CUSTOM.a + 0.5);

	// World position of the instance = its rest offset (instance node at origin).
	vec3 rest = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 world = trail_at(lag * lagk) + gas_pos(rest, s);

	// Figure.
	float d = (clamp(lagk * 0.5, 0.0, 1.0) * 0.7 + s * 0.3) * 0.6;
	float pf = smoothstep(d, d + 0.4, form);
	if (pf > 0.0 || scatter > 0.0) {
		vec3 o = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		vec3 fig = bones[bi * 4] * o.x + bones[bi * 4 + 1] * o.y + bones[bi * 4 + 2] * o.z + bones[bi * 4 + 3];
		fig += figure_jitter * vec3(sin(churn_clock * 2.0 + s * 31.0), sin(churn_clock * 1.7 + s * 17.0), sin(churn_clock * 2.3 + s * 7.0));
		world = mix(world, fig, pf);
		vec3 out_dir = fig - bones[3];
		float len = length(out_dir);
		if (len > 0.0001) {
			world += out_dir / len * scatter * (0.5 + s);
		}
	}
	float shown = max(max(vis, show_all), figure_glow * pf);
	vec4 pivot = VIEW_MATRIX * vec4(world, 1.0);

	float metres_per_px = 2.0 * -pivot.z / (PROJECTION_MATRIX[1][1] * psx_resolution.y);
	float size = max(particle_size, min_pixels * metres_per_px);
	vec4 clip = PROJECTION_MATRIX * (pivot + vec4(VERTEX.xy * size, 0.0, 0.0));

	float twinkle = 1.0 - flicker * (0.5 + 0.5 * sin(now * 7.0 + s * 40.0));
	v_bright = shown * glow * charge * twinkle + vis * flash * exp(-age * flash_decay);
	POSITION = shown <= 0.0 ? vec4(2.0, 2.0, 2.0, 1.0) : clip;
}

void fragment() {
	ALBEDO = glow_color * v_bright;
}
