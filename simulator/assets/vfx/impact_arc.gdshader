shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Plasma discharge crawling over a hit bird's silhouette. Each ribbon follows a
// jagged path baked into the mesh (VERTEX = point, NORMAL = path tangent,
// UV.y = distance along the path, UV2 = size/seed); the shader runs a bright
// strike head along each path as "t" advances.

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.06;
uniform float min_width = 0.0013;
uniform float intensity = 1.0;
uniform float strikes = 2.0;
uniform float min_width_scale = 1.0;
uniform vec3 tint : source_color = vec3(0.45, 0.85, 1.0);
uniform vec3 hot : source_color = vec3(0.95, 0.98, 1.0);
uniform float expand = 0.0;

varying float v_s;
varying float v_side;
varying float v_seed;

void vertex() {
	float seed = UV2.y;
	vec3 pos = VERTEX * (1.0 + expand * t);
	vec3 centre = (MODELVIEW_MATRIX * vec4(pos, 1.0)).xyz;
	vec3 tangent = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(tangent, to_eye);
	float sl = length(side);
	side = sl > 0.0005 ? side / sl : normalize(cross(tangent, vec3(0.0, 1.0, 0.0)));
	float w = max(width * UV2.x, length(centre) * min_width);
	v_s = UV.y;
	v_side = UV.x * 2.0 - 1.0;
	v_seed = seed;
	VERTEX = centre + side * v_side * w;
	NORMAL = to_eye;
}

void fragment() {
	float across = exp(-v_side * v_side * 4.2);
	float body = 0.0;
	float core = 0.0;
	for (int i = 0; i < 3; i++) {
		if (float(i) >= strikes) { break; }
		float offset = fract(v_seed * 3.71 + float(i) * 0.37);
		float head = fract(t * (1.35 + float(i) * 0.4) + offset) * 1.3 - 0.15;
		float d = v_s - head;
		float window = exp(-d * d * 150.0) * step(-0.28, d);
		body += window;
		core += window * window;
	}
	float fade = pow(1.0 - t, 1.2);
	float glow = across * (body * 1.4 + core * 2.6) * fade;
	ALBEDO = mix(tint, hot, clamp(core * 1.2, 0.0, 1.0)) * glow * 5.0 * intensity;
	ALPHA = 1.0;
}
