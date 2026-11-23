shader_type spatial;
// Yellow-and-black hazard striping for the emergency handles. The stripe runs in
// cockpit space so a handle and its loop share one continuous diagonal instead
// of each part restarting the pattern.
render_mode cull_back;
uniform float scale = 46.0;
uniform vec3 warn : source_color = vec3(0.92, 0.66, 0.03);
// Not 0.038: with the baked-AO floor multiplying in and the world's contrast
// grade clamping everything under ~5% grey to zero, the black half of the
// stripe came out as a hole in the handle rather than as black enamel.
uniform vec3 dark : source_color = vec3(0.072, 0.068, 0.060);
varying float stripe;
varying vec3 bake;

void vertex() {
	stripe = (VERTEX.y * 0.78 + VERTEX.x * 0.62 + VERTEX.z * 0.18) * scale;
	bake = COLOR.rgb;
}

void fragment() {
	float s = fract(stripe);
	float edge = fwidth(stripe) * 1.1 + 0.015;
	float band = smoothstep(0.5 - edge, 0.5 + edge, s);
	vec3 paint = mix(dark, warn, band);
	// Worn, scuffed enamel: the bright half is glossier than the black half.
	ALBEDO = paint * clamp(bake, vec3(0.30), vec3(1.0));
	ROUGHNESS = mix(0.74, 0.44, band);
	SPECULAR = 0.45;
}
