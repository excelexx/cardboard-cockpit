shader_type spatial;
// Aerial-photo ground for the Bay Area. The photo is ~5 m per pixel and the
// source mesh is coarse and flat-shaded, so this shader supplies what both lack:
// smooth relief normals baked from the 50 m height grid, procedural surface
// breakup near the jet (canopy on vegetation, strata on steep rock, roof/street
// grain on built-up grey), and a matte response so a huge ground plane never
// mirrors the sky at grazing angles.
render_mode diffuse_burley, specular_schlick_ggx;
// One sampler, wrapping. Surfaces whose own UVs stay inside the tile ask for
// the clamp by hand (wrap_uv = 0) so the photo's edge never bleeds round; the
// airport's tiled ground and marking strips ask for the wrap (wrap_uv = 1) and
// so share this grade instead of falling back to their raw source material.
uniform sampler2D aerial : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wrap_uv = 0.0;
uniform sampler2D relief : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 relief_origin = vec2(-60000.0, -70000.0);
uniform float relief_extent = 130000.0;
uniform float detail_strength = 0.9;
uniform float saturation = 1.2;
uniform float contrast = 1.16;
uniform float gain = 0.74;
// Drifting cloud shade. The panorama overhead is genuinely broken cumulus; with
// perfectly even ground under it the whole basin reads as a flat map.
uniform vec2 cloud_wind = vec2(9.0, -3.0);
uniform float cloud_shade = 0.26;
// Shallows. FlightGear's coarse ground mesh reaches out over the bay where the
// water polygons do not - south of the 28R threshold that is the whole
// foreground of the landing - and out there the aerial photo IS water. A flat
// photograph of water lying beside live water reads as a painted slab with a
// hard edge, which is exactly what it looked like. So sea-level fragments whose
// photo is water-coloured take the water response instead: ripple normal,
// sheen, and the same hand-drawn sun road the water shader uses. Asphalt and
// grass never qualify - only a photo pixel that is teal in BOTH green and blue.
uniform sampler2D waves : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sun_direction = vec3(-0.903, 0.174, -0.329);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.66, 0.38);
uniform float wet_level = 1.9;   // metres: above this nothing is shallows
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = UV;
	if (wrap_uv < 0.5) {
		vec2 half_texel = 0.5 / vec2(textureSize(aerial, 0));
		uv = clamp(uv, half_texel, 1.0 - half_texel);
	}
	vec3 photo = texture(aerial, uv).rgb;
	float luma = dot(photo, vec3(0.299, 0.587, 0.114));
	photo = mix(vec3(luma), photo, saturation);
	photo = (photo - 0.22) * contrast + 0.22;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(900.0, 6500.0, dist);
	float mid = 1.0 - smoothstep(2500.0, 15000.0, dist);

	vec3 map = texture(relief, (world_pos.xz - relief_origin) / relief_extent).rgb;
	vec2 tilt = map.rg * 2.0 - 1.0;
	float steep = clamp(length(tilt) * 1.9, 0.0, 1.0);

	float chroma = max(max(photo.r, photo.g), photo.b) - min(min(photo.r, photo.g), photo.b);
	float built = 1.0 - smoothstep(0.03, 0.12, chroma);
	float green = smoothstep(0.0, 0.06, photo.g - max(photo.r, photo.b) * 0.96) * (1.0 - built);

	float fine = texture(detail, world_pos.xz / 170.0).r;
	float clump = texture(detail, world_pos.zx / 640.0 + 0.37).r;
	float coarse = texture(detail, world_pos.xz / 2600.0 + 0.11).r;
	// Tree crowns: dark gaps between lit clumps. Rock: banding along the fall line.
	float canopy = (fine * 0.6 + clump * 0.7 - 0.62) * green;
	float strata = (texture(detail, vec2(world_pos.y / 9.0, (world_pos.x + world_pos.z) / 260.0)).r - 0.5) * steep * (1.0 - green);
	float grain = (fine - 0.5) * mix(0.35, 1.0, built);
	float amount = detail_strength * ((grain + canopy * 1.5 + strata * 1.2) * near + (coarse - 0.5) * 0.45 * mid);
	float teal = smoothstep(0.02, 0.10, min(photo.g - photo.r, photo.b - photo.r));
	float wet = teal * (1.0 - smoothstep(0.35, wet_level, world_pos.y));
	vec3 colour = photo * (1.0 + amount * (1.0 - wet));
	colour = mix(colour, colour * vec3(0.80, 0.92, 0.74), green * 0.35);
	colour = mix(colour, colour * vec3(0.74, 0.90, 0.98), wet * 0.7);
	float cloud = texture(detail, (world_pos.xz + cloud_wind * TIME) / 5200.0 + 0.61).r;
	float shade = 1.0 - cloud_shade * smoothstep(0.42, 0.80, cloud);
	// Cloud shadow is a light effect, so it cools as it darkens.
	colour *= mix(vec3(1.0), vec3(0.92, 0.96, 1.06), (1.0 - shade) / max(cloud_shade, 0.001)) * shade;
	ALBEDO = clamp(colour * gain, 0.0, 1.0);

	// Relief normal with a little crown/rock bump so slopes catch the low sun.
	vec2 bump = vec2(clump - 0.5, fine - 0.5) * (green * 0.55 + steep * 0.35) * near;
	vec3 n = normalize(vec3(tilt.x + bump.x, 0.0, tilt.y + bump.y) + vec3(0.0, sqrt(max(0.0, 1.0 - dot(tilt, tilt))), 0.0));
	ROUGHNESS = 0.96;
	SPECULAR = 0.04;
	if (wet > 0.002) {
		vec3 swell = texture(waves, world_pos.xz / 310.0 + TIME * vec2(-0.008, 0.006)).rgb * 0.6
			+ texture(waves, world_pos.xz / 85.0 + TIME * vec2(0.018, -0.012)).rgb * 0.4;
		vec3 ripple = swell * 2.0 - 1.0;
		vec3 wn = normalize(vec3(ripple.x * 0.26, 1.0, ripple.y * 0.26));
		n = normalize(mix(n, wn, wet));
		ROUGHNESS = mix(0.96, 0.10, wet);
		SPECULAR = mix(0.04, 0.50, wet);
		// The same GGX sun road as sf_water, so the seam between a shallows
		// polygon and the water beside it stops being a straight line.
		vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 half_v = normalize(view + normalize(sun_direction));
		float ndh = max(dot(wn, half_v), 0.0);
		float spread = mix(0.06, 0.20, smoothstep(300.0, 16000.0, dist));
		float ga = spread * spread;
		float den = ndh * ndh * (ga * ga - 1.0) + 1.0;
		float lobe = (ga * ga) / (3.14159265 * den * den);
		// Same soft shoulder as sf_water, for the same reason: a hard min() left
		// a saturated plateau with a rim on it that the glow pass turned into a
		// veil over the shoreline.
		float road = lobe / (1.0 + lobe / 19.0);
		float aligned = smoothstep(0.90, 0.995, dot(reflect(-view, wn), normalize(sun_direction)));
		EMISSION = sun_tint * road * 0.38 * wet * shade * mix(0.10, 1.0, aligned);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
