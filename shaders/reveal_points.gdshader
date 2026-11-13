// Points of a RevealCloud. Each MultiMesh instance is one sample of the image.
// INSTANCE_CUSTOM.r = the last time a ray hit this point. Visibility is derived
// from its age on the GPU, so a reveal fades without any per-frame CPU work.
// Hidden points are pushed outside the clip volume so they cost no fragments.
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform float reveal_now;
global uniform float reveal_hold;         // seconds fully visible after a hit
global uniform float reveal_fade;         // seconds to disappear after that
global uniform float reveal_dissolve;     // 0 = dim to black, 1 = random drop-out
global uniform float reveal_flash;        // glow of fresh hits in the gun colour
global uniform float reveal_flash_decay;
global uniform float reveal_point_scale;  // point size relative to sample spacing
global uniform float reveal_min_pixels;
global uniform vec3 reveal_flash_color;
global uniform vec2 psx_resolution;       // internal render size in pixels

varying float v_age;
varying float v_bright;

void vertex() {
	float age = reveal_now - INSTANCE_CUSTOM.r;
	float vis = 1.0 - clamp((age - reveal_hold) / max(reveal_fade, 0.001), 0.0, 1.0);
	float rnd = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	v_age = age;
	v_bright = mix(vis, 1.0, reveal_dissolve);

	vec4 pivot = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float size = abs(VERTEX.x) * 2.0 * reveal_point_scale;
	float metres_per_px = 2.0 * -pivot.z / (PROJECTION_MATRIX[1][1] * psx_resolution.y);
	float grow = max(1.0, reveal_min_pixels * metres_per_px / size);
	// No vertex snapping here: combined with ~1px quads it made points vanish on
	// Metal. Rendering at the internal resolution already pixelates them.
	vec4 clip = PROJECTION_MATRIX * (pivot + vec4(VERTEX.xy * reveal_point_scale * grow, 0.0, 0.0));
	bool hidden = vis <= 0.0 || rnd >= mix(1.0, vis, reveal_dissolve);
	POSITION = hidden ? vec4(2.0, 2.0, 2.0, 1.0) : clip;
}

void fragment() {
	float flash = reveal_flash * exp(-v_age * reveal_flash_decay);
	ALBEDO = mix(COLOR.rgb, reveal_flash_color, flash) * v_bright;
}
