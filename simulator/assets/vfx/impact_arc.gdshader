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
	// Real discharge tapers to nothing at both ends. A constant-width ribbon with
	// square ends reads as a cardboard lightning-bolt cutout, which is exactly
	// what these were. UV.y is distance along the path, 0 at the strike.
	float taper = pow(max(sin(3.14159265 * UV.y), 0.0), 0.62);
	float w = max(width * UV2.x * taper, length(centre) * min_width * taper);
	v_s = UV.y;
	v_side = UV.x * 2.0 - 1.0;
	v_seed = seed;
	VERTEX = centre + side * v_side * w;
	NORMAL = to_eye;
}

void fragment() {
	// Sharp across the ribbon: a soft-edged slab of clipped white is exactly what
	// made these read as cardboard lightning-bolt cut-outs.
	float across = exp(-v_side * v_side * 5.2);
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
	// The leader channel: a dim, grainy thread down the whole path, plus a bright
	// root at the strike. Without them only the travelling head is lit, so each
	// arc is a bright segment hanging in mid air beside the bird - the "floating
	// detached cut-out" read - even though every path really is rooted at the hit.
	float channel = (0.15 + 0.25 * fract(sin(v_seed * 91.7 + v_s * 24.0) * 43758.5453))
	              * (1.0 - smoothstep(0.30, 1.0, v_s));
	float root = exp(-v_s * v_s * 90.0);
	float fade = pow(1.0 - t, 1.2);
	// Gain 1.9, not 5.0: at 5.0 every lit pixel clipped to the same flat white, so
	// the ribbons had no falloff and read as painted card.
	float glow = across * (body * 0.85 + core * 1.55 + channel * 0.50 + root * 0.95) * fade;
	ALBEDO = mix(tint, hot, clamp(core * 0.9 + root * 0.5, 0.0, 1.0)) * glow * 3.1 * intensity;
	ALPHA = 1.0;
}
