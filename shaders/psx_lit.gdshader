// PS1-style lit surface: vertex snapping, partially affine texture mapping,
// nearest-filtered world-space (triplanar) texture so boxes of any size tile evenly.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

global uniform vec2 psx_snap;           // vertex snap grid, set from Tuning (look.snap)
global uniform float psx_affine;        // 0 = perspective-correct, 1 = full PS1 warp

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tex_scale = 0.25;         // texture repeats per metre

varying vec2 uv_persp;
varying vec3 uv_affine;                 // (uv * w, w): interpolates without perspective correction

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
	vec2 uvw = wn.x > max(wn.y, wn.z) ? wp.zy : (wn.y > wn.z ? wp.xz : wp.xy);
	uvw *= tex_scale;

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 grid = psx_snap * 0.5;
	clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	POSITION = clip;

	uv_persp = uvw;
	uv_affine = vec3(uvw * clip.w, clip.w);
}

void fragment() {
	vec2 uv = mix(uv_persp, uv_affine.xy / uv_affine.z, psx_affine);
	ALBEDO = texture(albedo_tex, uv).rgb * tint;
	ROUGHNESS = 1.0;
}
