shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Lightning crawling over the plasma column. Rides the same stretched ribbon as
// plasma_beam.gdshader, snakes with the same phase-free wobble so it stays on
// the beam, and shares its palette so the arcs pick up whatever hue is passing
// that stretch. Everything is a function of metres along the beam.

uniform float radius = 0.4;
uniform float phase = 0.0;
uniform float min_width = 0.004;
uniform float intensity = 1.0;
uniform float wavelength = 210.0;
uniform float flow_speed = 330.0;
uniform float arc_count = 4.0;
uniform float wobble_amount = 1.0;
uniform vec3 hue_violet : source_color = vec3(0.46, 0.10, 1.00);
uniform vec3 hue_magenta : source_color = vec3(1.00, 0.12, 0.66);
uniform vec3 hue_gold : source_color = vec3(1.00, 0.70, 0.14);
uniform vec3 hue_cyan : source_color = vec3(0.08, 0.92, 1.00);

varying float v_along;
varying float v_len;
varying float v_u;
varying float v_axial;

vec3 palette(float t) {
	float f = fract(t) * 4.0;
	int i = int(f);
	float k = f - float(i);
	k = k * k * (3.0 - 2.0 * k);
	vec3 a = i == 0 ? hue_violet : (i == 1 ? hue_magenta : (i == 2 ? hue_gold : hue_cyan));
	vec3 b = i == 0 ? hue_magenta : (i == 1 ? hue_gold : (i == 2 ? hue_cyan : hue_violet));
	return mix(a, b, k);
}

vec3 flowing_tint(float along) {
	float s = (along - TIME * flow_speed) / wavelength;
	return normalize(mix(palette(s), palette(s * 2.7 + 0.37), 0.34) + 0.0001);
}

vec2 wobble(float along) {
	float a = along * 0.021 - TIME * 2.4;
	float b = along * 0.0073 + TIME * 1.35;
	float c = along * 0.052 - TIME * 5.1;
	float envelope = smoothstep(0.0, 26.0, along) * wobble_amount;
	return vec2(sin(a) * 0.34 + sin(c) * 0.09 + cos(b) * 0.5,
	            cos(a * 1.17) * 0.32 + cos(c * 0.83) * 0.08 + sin(b * 0.9) * 0.46) * envelope;
}

void vertex() {
	float blen = length(MODEL_MATRIX[1].xyz);
	float along = (VERTEX.y + 0.5) * blen;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0)).xyz;
	vec3 reference = abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 u1 = normalize(cross(axis, reference));
	vec3 u2 = cross(axis, u1);
	vec2 snake = wobble(along);
	centre += u1 * snake.x + u2 * snake.y;
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(axis, to_eye);
	float sl = length(side);
	side = sl > 0.0005 ? side / sl : u1;
	float half_w = max(radius, length(centre) * min_width);
	v_along = along;
	v_len = blen;
	v_u = UV.x * 2.0 - 1.0;
	v_axial = abs(dot(axis, to_eye));
	VERTEX = centre + side * v_u * half_w;
	NORMAL = to_eye;
}

float angular(float a, float b) {
	float d = abs(a - b);
	return min(d, 6.2831853 - d);
}

void fragment() {
	float along = v_along;
	// Discharge rides the surface of the column, so it is strongest where the
	// ribbon stands for the limb rather than the middle.
	float limb = 0.30 + 0.70 * pow(abs(v_u), 0.7);
	float ang = asin(clamp(v_u, -1.0, 1.0));

	float total = 0.0;
	float hot = 0.0;
	for (int i = 0; i < 6; i++) {
		if (float(i) >= arc_count) { break; }
		float seed = float(i) * 2.399963;
		float track = seed * 2.1
			+ 1.35 * sin(along * 0.075 + TIME * 3.1 + seed)
			+ 0.80 * sin(along * 0.026 - TIME * 1.9 + seed * 1.7)
			+ 0.45 * sin(along * 0.31 + TIME * 9.0 + seed * 0.6);
		float d = angular(ang, track);
		float filament = exp(-d * d * 26.0);
		// Short segments racing to the target, restriking at different rates.
		float run = along * 0.042 - TIME * (5.6 + float(i) * 1.13) + seed;
		float segment = pow(0.5 + 0.5 * sin(run), 16.0);
		float restrike = step(0.28, fract(sin(floor(run * 0.1591549) * 12.9898 + seed) * 43758.5453));
		float strike = filament * segment * restrike;
		total += strike;
		hot += filament * filament * segment * restrike;
	}

	float ends = smoothstep(0.0, 6.0, along) * (1.0 - smoothstep(v_len - 3.0, v_len - 0.3, along));
	vec3 tint = flowing_tint(along);
	vec3 emitted = mix(tint, vec3(0.86, 0.94, 1.0), 0.55) * total * 5.5 + vec3(1.0) * hot * 3.0;
	ALBEDO = emitted * ends * intensity * limb;
	ALPHA = 1.0;
}
