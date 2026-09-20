shader_type spatial;
// Bay and Pacific water. Three scrolling swell layers whose finest octave never
// dies out, roughness that RISES with distance to stand in for the sub-texel
// slope the mipmaps destroy (that is what turns a six-degree specular blob into
// a sun road kilometres long), open-water whitecaps, turquoise shallows, a
// separate freshwater tint for the inland reservoirs, and drifting cloud shade.
// Distant water is deliberately held darker than the horizon sky so the horizon
// stays a hard line instead of a smear.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D waves : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 relief_origin = vec2(-60000.0, -70000.0);
uniform float relief_extent = 130000.0;
uniform vec3 deep : source_color = vec3(0.009, 0.048, 0.078);
uniform vec3 shallow : source_color = vec3(0.048, 0.160, 0.178);
uniform vec3 lake : source_color = vec3(0.045, 0.085, 0.075);
uniform vec3 sun_direction = vec3(-0.903, 0.174, -0.329);   // world space, toward the sun
uniform vec3 sun_tint : source_color = vec3(1.0, 0.66, 0.38);
uniform float glitter = 0.55;
uniform vec2 cloud_wind = vec2(9.0, -3.0);
uniform float cloud_shade = 0.16;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = world_pos.xz;
	vec3 a = texture(waves, p / 1100.0 + TIME * vec2(0.004, 0.0025)).rgb;
	vec3 b = texture(waves, p / 310.0 + TIME * vec2(-0.008, 0.006)).rgb;
	vec3 c = texture(waves, p / 85.0 + TIME * vec2(0.018, -0.012)).rgb;
	float calm = smoothstep(800.0, 9000.0, dist);
	// Inland water: still, fresh, and nowhere near sea level.
	float fresh = smoothstep(3.0, 25.0, world_pos.y);
	float wb = mix(0.35, 0.22, calm);
	float wc = mix(0.25, 0.08, calm) * (1.0 - fresh * 0.6);
	vec3 n = a * 0.5 + b * wb + c * wc;
	n = n / (0.5 + wb + wc);
	// The water surfaces are horizontal, so the tangent frame is known: build the
	// world normal directly and keep it for the glitter term below.
	vec3 tangent_n = n * 2.0 - 1.0;
	float depth = mix(0.32, 0.17, calm) * mix(1.0, 0.45, fresh);
	vec3 wn = normalize(vec3(tangent_n.x * depth, 1.0, tangent_n.y * depth));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float shore = texture(relief, (p - relief_origin) / relief_extent).b;
	float surf = texture(detail, p / 55.0 + TIME * vec2(0.012, 0.0)).r;
	// Shore surf comes from a sea-level map, so reservoirs must not get any.
	float foam = smoothstep(0.86, 1.02, shore + (surf - 0.5) * 0.22)
		* (1.0 - smoothstep(3000.0, 9000.0, dist)) * (1.0 - fresh);
	// Central Bay runs 15-25 kt most afternoons: whitecaps everywhere, not just at the beach.
	float crest = smoothstep(0.72, 0.97, b.g * 0.55 + c.g * 0.55 + (surf - 0.5) * 0.4)
		* (1.0 - smoothstep(7000.0, 18000.0, dist)) * (1.0 - fresh);
	foam = max(foam, crest * 0.38);

	vec3 colour = mix(deep, shallow, smoothstep(0.35, 0.95, shore) * (1.0 - fresh));
	colour = mix(colour, lake, fresh);
	// Drifting cloud shade, same tap the ground uses. Near-free, and it stops the
	// open water reading as one flat sheet out to the horizon.
	float shade = 1.0 - cloud_shade * smoothstep(0.42, 0.80, texture(detail, (p + cloud_wind * TIME) / 5200.0 + 0.61).r);
	ALBEDO = mix(colour * shade, vec3(0.86, 0.90, 0.90), foam * 0.85);
	// Roughness must climb with range or the mipmapped normals leave a mirror.
	ROUGHNESS = max(mix(0.055, 0.30, smoothstep(400.0, 14000.0, dist)), foam * 0.6);
	// Far water loses reflectance as well as sharpness, which is what keeps the
	// horizon a line instead of a seam between two equally bright golds.
	SPECULAR = mix(0.6, 0.24, smoothstep(2000.0, 18000.0, dist));
	METALLIC = 0.0;

	// The sun road, drawn by hand so it survives the distance where the shading
	// normals have already been averaged away. Warm, narrow near the camera and
	// stretched toward the horizon, and it never leaves the water.
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 half_v = normalize(view + normalize(sun_direction));
	float ndh = max(dot(wn, half_v), 0.0);
	float spread = mix(0.055, 0.26, smoothstep(300.0, 16000.0, dist));
	float alpha = spread * spread;
	float denominator = ndh * ndh * (alpha * alpha - 1.0) + 1.0;
	float lobe = (alpha * alpha) / (3.14159265 * denominator * denominator);
	float fresnel = mix(0.04, 1.0, pow(1.0 - max(dot(wn, view), 0.0), 5.0));
	float sparkle = 0.75 + 0.5 * texture(detail, p / 22.0 + TIME * vec2(0.03, -0.02)).r;
	EMISSION = sun_tint * min(lobe, 26.0) * glitter * fresnel * sparkle * shade * (1.0 - fresh * 0.75);

	// Hold the far water under the horizon sky: the grazing sky reflection would
	// otherwise match it exactly and the horizon line would disappear.
	AO = mix(1.0, 0.34, smoothstep(1500.0, 16000.0, dist));
	AO_LIGHT_AFFECT = 0.0;
}
