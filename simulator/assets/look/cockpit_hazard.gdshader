shader_type spatial;
// Yellow-and-black hazard striping for the emergency handles. The stripe runs in
// cockpit space so a handle and its loop share one continuous diagonal instead
// of each part restarting the pattern.
render_mode cull_back;
uniform float scale = 46.0;
uniform vec3 warn : source_color = vec3(0.92, 0.66, 0.03);
uniform vec3 dark : source_color = vec3(0.038, 0.036, 0.032);
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
	ALBEDO = paint * clamp(bake, vec3(0.16), vec3(1.0));
	ROUGHNESS = mix(0.74, 0.44, band);
	SPECULAR = 0.45;
}
