shader_type spatial;
// Bird-strike debris. One quad per particle, billboarded but spun by the
// particle's own angle so a burst reads as tumbling feathers rather than a
// cloud of stickers. The silhouette is cut in the fragment stage: a bare
// quill, a lanceolate vane with combed barbs, and a soft down variant.
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled, diffuse_lambert;

uniform vec3 quill_tint : source_color = vec3(0.34, 0.26, 0.20);
uniform vec3 vane_tint : source_color = vec3(0.88, 0.86, 0.80);
// 0.0 = flight feather (vaned, tumbling edge-on), 1.0 = down (soft round puff).
uniform float down_mode : hint_range(0.0, 1.0) = 0.0;
// How much backlight leaks through the vane. Golden hour reads through feathers.
uniform float translucency : hint_range(0.0, 1.0) = 0.38;

void vertex() {
	float angle = INSTANCE_CUSTOM.x;
	// Camera-facing basis, with the particle scale multiplied back in.
	mat4 face = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]);
	mat4 spin = mat4(
		vec4(cos(angle), -sin(angle), 0.0, 0.0),
		vec4(sin(angle), cos(angle), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face * spin;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	// A real feather turns edge-on twice a revolution: squash across the vane
	// instead of vanishing, so it flickers narrow without dropping frames of
	// silhouette. Down is round and never foreshortens.
	float flutter = mix(0.22 + 0.78 * abs(cos(angle * 1.7)), 1.0, down_mode);
	VERTEX.x *= flutter;
}

void fragment() {
	float v = clamp(UV.y, 0.0, 1.0);
	float x = UV.x - 0.5;
	// Vaned flight feather: bare shaft at the root, widest near a third of the
	// way up, tapering to a point.
	float half_width = (0.09 + 0.38 * smoothstep(0.0, 0.28, v)) * (1.0 - smoothstep(0.40, 1.0, v) * 0.94);
	float vane = 1.0 - smoothstep(half_width * 0.78, half_width, abs(x));
	float rachis = 1.0 - smoothstep(0.012, 0.032, abs(x));
	// Barb combing breaks the straight edge without a texture fetch.
	float barbs = 0.70 + 0.30 * sin(abs(x) * 46.0 - v * 21.0);
	float feather_mask = clamp(max(vane * barbs, rachis * (1.0 - smoothstep(0.88, 1.0, v))), 0.0, 1.0);
	// Down: a soft round clump with a ragged rim.
	vec2 d = vec2(x, v - 0.5);
	float radius = length(d) * 2.0;
	float ragged = 1.0 + 0.22 * sin(atan(d.y, d.x) * 7.0);
	float down_mask = 1.0 - smoothstep(0.30, 0.95 * ragged, radius);
	down_mask *= down_mask;

	float mask = mix(feather_mask, down_mask, down_mode);
	if (mask < 0.02) {
		discard;
	}
	vec3 tint = mix(quill_tint, vane_tint, mix(smoothstep(0.05, 0.85, v), 0.72, down_mode));
	ALBEDO = tint * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// Light leaking through the vane: strongest where the vane is thinnest and
	// never on the solid quill, so feathers stay visible against dark water.
	EMISSION = ALBEDO * translucency * (1.0 - rachis * (1.0 - down_mode)) * mix(0.55, 1.0, v);
	ALPHA = mask * COLOR.a;
}
