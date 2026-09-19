shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 cloud_color : source_color = vec4(0.95, 0.96, 0.97, 0.70);
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float result = 0.0;
	float strength = 0.5;
	for (int i = 0; i < 5; i++) {
		result += noise(p) * strength;
		p = p * 2.02 + vec2(3.7, 9.2);
		strength *= 0.5;
	}
	return result;
}
void vertex() {
	// Screen-facing clouds keep their world position and their natural soft silhouette.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * vec2(5.0, 2.5) + vec2(seed, 0.0);
	float detail = fbm(p);
	float edge = pow(abs(UV.x * 2.0 - 1.0), 4.0) + pow(abs(UV.y * 2.0 - 1.0), 2.0);
	float shape = smoothstep(0.25, 0.68, detail + 0.30 - edge * 0.60);
	float light = 0.78 + 0.22 * smoothstep(0.0, 0.8, UV.y + detail * 0.25);
	ALBEDO = cloud_color.rgb * light;
	ALPHA = shape * cloud_color.a;
}
