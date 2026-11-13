// Full-screen pass at the internal resolution: ordered dither, colour-depth
// reduction, film grain and a vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float color_levels = 20.0;
uniform float dither_strength = 1.0;
uniform float grain = 0.035;
uniform float vignette = 0.45;
uniform float fade = 1.0;        // 0 = black (the opening sequence knocks the picture out)
uniform float cyan = 0.0;        // 0..1: the gas takes the Cleaner; the picture floods cyan
uniform float flash = 0.0;       // white flash (solar flare, explosion)
uniform float prox = 0.0;        // 0..1: a ghost is close; cyan creeps in at the edges

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	float b = BAYER[p.y * 4 + p.x] / 16.0 - 0.5;
	c += (hash(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5) * grain;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette * 2.0;
	float n = hash(FRAGCOORD.xy * 1.7 + fract(TIME) * 37.0);
	c += vec3(0.0, 0.5, 0.55) * prox * smoothstep(0.1, 0.5, dot(d, d) * 1.6) * (0.5 + 0.5 * n);
	c = mix(c, vec3(0.08, 0.85, 0.9) * (0.35 + 0.65 * n), cyan);
	c += flash * vec3(1.0, 0.97, 0.9);
	c *= fade;
	c += b * dither_strength / color_levels;
	c = floor(c * color_levels + 0.5) / color_levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
