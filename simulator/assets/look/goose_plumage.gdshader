shader_type spatial;
// Low-detail plumage: colors evaluated per vertex, no feather texture or sheen.
render_mode diffuse_lambert, specular_disabled, vertex_lighting, shadows_disabled;
uniform bool wing = false;
instance uniform float damage : hint_range(0.0, 1.0) = 0.0;
instance uniform float flex = 0.0;
varying vec3 plumage;
void vertex() {
	vec3 black = vec3(0.018, 0.018, 0.020);
	vec3 white = vec3(0.80, 0.78, 0.72);
	vec3 brown = vec3(0.20, 0.14, 0.09);
	if (wing) {
		float span = clamp(abs(VERTEX.x) / 3.30, 0.0, 1.0);
		plumage = mix(brown, black, span);
		VERTEX.y += flex * span * span;
		VERTEX.z += flex * span * span * 0.22;
	} else {
		plumage = VERTEX.y < -0.12 ? vec3(0.40, 0.35, 0.29) : brown;
		if (VERTEX.z > 1.05) plumage = white;
		if (VERTEX.z > 1.50 || VERTEX.z < -1.30) plumage = black;
		if (VERTEX.z < -2.75 && VERTEX.z > -3.20 && abs(VERTEX.x) > 0.065 && VERTEX.y < 0.25) plumage = white;
	}
	plumage *= 1.0 - damage * 0.35;
}
void fragment() {
	ALBEDO = plumage;
	ROUGHNESS = 1.0;
}
