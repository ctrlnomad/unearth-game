// The Earth seen through the loading bay window. Lit by its own fake sun
// direction (so we can choose the phase), with a thin blue atmosphere rim.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;

uniform sampler2D surface_tex : source_color, filter_nearest, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);   // world space, towards the sun
uniform float brightness = 1.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float lit = smoothstep(-0.1, 0.35, dot(n, normalize(sun_dir)));
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float rim = pow(1.0 - max(dot(n, view), 0.0), 3.0);
	vec3 c = texture(surface_tex, UV).rgb * lit;
	c += vec3(0.25, 0.5, 1.0) * rim * (0.08 + 0.92 * lit) * 0.7;
	ALBEDO = c * brightness;
}
