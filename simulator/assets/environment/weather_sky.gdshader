shader_type sky;

// Original, static cloud sky: no geometry, external textures, or per-frame radiance updates.
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.17;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(-0.32, 0.92, 0.22);
uniform vec3 zenith_color : source_color = vec3(0.20, 0.43, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.81, 0.92);
uniform vec3 cloud_color : source_color = vec3(0.91, 0.94, 0.96);
uniform vec3 overcast_color : source_color = vec3(0.73, 0.77, 0.81);

float cloud_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(cell), cloud_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(cloud_hash(cell + vec2(0.0, 1.0)), cloud_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

float cloud_shape(vec2 p) {
	float value = 0.0;
	float amplitude = 0.53;
	for (int octave = 0; octave < 4; octave++) {
		value += cloud_noise(p) * amplitude;
		p = p * 2.03 + vec2(11.8, 4.1);
		amplitude *= 0.5;
	}
	return value;
}

void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 blue_sky = mix(horizon_color, zenith_color, pow(elevation, 0.43));
	vec3 grey_sky = overcast_color * mix(0.89, 1.08, pow(elevation, 0.55));
	vec3 sky_color = mix(blue_sky, grey_sky, overcast);
	// Projection onto a high cloud deck keeps cloud shapes consistent in every direction.
	vec2 cloud_uv = EYEDIR.xz / (max(elevation, 0.04) + 0.10) * 2.8 + vec2(18.1, 32.6);
	float shape = cloud_shape(cloud_uv);
	float coverage = smoothstep(0.78 - cloud_cover * 0.66, 0.93 - cloud_cover * 0.66, shape);
	coverage *= smoothstep(0.01, 0.14, elevation);
	vec3 lit_cloud = mix(cloud_color * (0.76 + shape * 0.24), overcast_color * (0.81 + shape * 0.33), overcast);
	sky_color = mix(sky_color, lit_cloud, coverage * mix(0.92, 0.85, overcast));
	float sun_alignment = max(dot(EYEDIR, normalize(sun_direction)), 0.0);
	float sun_halo = pow(sun_alignment, 160.0) * 0.20;
	float sun_disc = smoothstep(0.99993, 0.99997, sun_alignment) * 8.0;
	sky_color += vec3(1.0, 0.95, 0.84) * (sun_halo + sun_disc) * (1.0 - overcast) * (1.0 - coverage);
	COLOR = mix(horizon_color * 0.38, sky_color, smoothstep(-0.10, 0.0, EYEDIR.y));
}
