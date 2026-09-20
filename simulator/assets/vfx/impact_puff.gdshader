shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled, unshaded, blend_mix;
// Singed-feather puff: a small, short-lived smudge of down and smoke. Alpha
// blended and capped small on screen so nothing smears across the view.

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float size = 1.0;
uniform float grow = 2.2;
uniform float seed = 0.0;
uniform vec3 smoke_colour : source_color = vec3(0.16, 0.145, 0.135);
uniform vec3 lit_colour : source_color = vec3(0.52, 0.42, 0.33);
uniform float opacity = 0.7;

varying vec2 v_uv;

void vertex() {
	float scale = size * mix(0.55, grow, pow(t, 0.6));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * scale, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * scale, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * scale, 0.0),
		MODEL_MATRIX[3]);
	v_uv = UV * 2.0 - 1.0;
}

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = v_uv;
	float r = length(p);
	float swirl = t * 1.4;
	vec2 q = vec2(p.x * cos(swirl) - p.y * sin(swirl), p.x * sin(swirl) + p.y * cos(swirl));
	float n = value_noise(q * 2.6 + seed) * 0.6 + value_noise(q * 6.1 - seed) * 0.4;
	float body = (1.0 - smoothstep(0.30, 0.95, r + n * 0.32 - 0.16));
	float fade = (1.0 - smoothstep(0.15, 1.0, t));
	ALBEDO = mix(smoke_colour, lit_colour, clamp(n * 1.3 - 0.15, 0.0, 1.0));
	ALPHA = clamp(body * fade * opacity, 0.0, 1.0);
}
