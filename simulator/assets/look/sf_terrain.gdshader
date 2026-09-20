shader_type spatial;
// Aerial-photo ground for the Bay Area. The photo is ~5 m per pixel and the
// source mesh is coarse and flat-shaded, so this shader supplies what both lack:
// smooth relief normals baked from the 50 m height grid, procedural surface
// breakup near the jet (canopy on vegetation, strata on steep rock, roof/street
// grain on built-up grey), and a matte response so a huge ground plane never
// mirrors the sky at grazing angles.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D aerial : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
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
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 photo = texture(aerial, UV).rgb;
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
	vec3 colour = photo * (1.0 + amount);
	colour = mix(colour, colour * vec3(0.80, 0.92, 0.74), green * 0.35);
	float cloud = texture(detail, (world_pos.xz + cloud_wind * TIME) / 5200.0 + 0.61).r;
	float shade = 1.0 - cloud_shade * smoothstep(0.42, 0.80, cloud);
	// Cloud shadow is a light effect, so it cools as it darkens.
	colour *= mix(vec3(1.0), vec3(0.92, 0.96, 1.06), (1.0 - shade) / max(cloud_shade, 0.001)) * shade;
	ALBEDO = clamp(colour * gain, 0.0, 1.0);

	// Relief normal with a little crown/rock bump so slopes catch the low sun.
	vec2 bump = vec2(clump - 0.5, fine - 0.5) * (green * 0.55 + steep * 0.35) * near;
	vec3 n = normalize(vec3(tilt.x + bump.x, 0.0, tilt.y + bump.y) + vec3(0.0, sqrt(max(0.0, 1.0 - dot(tilt, tilt))), 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 0.96;
	SPECULAR = 0.04;
}
