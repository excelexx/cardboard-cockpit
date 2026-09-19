shader_type spatial;
// Aerial photo ground. The photo is ~5 m per pixel, so two bands of procedural
// micro-contrast keep it from turning to mush near the jet, and the surface is
// kept matte: a rough ground plane must not mirror the sky at grazing angles.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D aerial : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.55;
uniform float saturation = 1.22;
uniform float contrast = 1.18;
uniform float gain = 0.74;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 photo = texture(aerial, UV).rgb;
	float luma = dot(photo, vec3(0.299, 0.587, 0.114));
	photo = mix(vec3(luma), photo, saturation);
	photo = (photo - 0.22) * contrast + 0.22;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(600.0, 5200.0, dist);
	float mid = 1.0 - smoothstep(3000.0, 16000.0, dist);
	float fine = texture(detail, world_pos.xz / 46.0).r - 0.5;
	float coarse = texture(detail, world_pos.zx / 310.0 + 0.37).r - 0.5;
	// Built-up pixels are grey; vegetation and soil are coloured. Roof/street
	// breakup belongs on the grey ones, softer mottling on the rest.
	float grey = 1.0 - smoothstep(0.03, 0.14, max(max(photo.r, photo.g), photo.b) - min(min(photo.r, photo.g), photo.b));
	float amount = detail_strength * (fine * near * mix(0.45, 1.0, grey) + coarse * mid * 0.5);
	ALBEDO = clamp(photo * (1.0 + amount) * gain, 0.0, 1.0);
	ROUGHNESS = 0.96;
	SPECULAR = 0.04;
}
