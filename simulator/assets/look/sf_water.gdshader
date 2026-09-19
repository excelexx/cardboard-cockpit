shader_type spatial;
// Bay and Pacific water: three scrolling swell layers, Fresnel-weighted sky
// reflection, a hard sun glint road at golden hour, turquoise shallows and
// foam where the baked shore map says the waterline is near.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D waves : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 relief_origin = vec2(-60000.0, -70000.0);
uniform float relief_extent = 130000.0;
uniform vec3 deep : source_color = vec3(0.012, 0.070, 0.105);
uniform vec3 shallow : source_color = vec3(0.070, 0.300, 0.300);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 p = world_pos.xz;
	vec3 a = texture(waves, p / 1100.0 + TIME * vec2(0.004, 0.0025)).rgb;
	vec3 b = texture(waves, p / 310.0 + TIME * vec2(-0.008, 0.006)).rgb;
	vec3 c = texture(waves, p / 85.0 + TIME * vec2(0.018, -0.012)).rgb;
	float calm = smoothstep(800.0, 9000.0, dist);
	vec3 n = a * 0.5 + b * mix(0.35, 0.2, calm) + c * mix(0.25, 0.0, calm);
	NORMAL_MAP = n / (0.5 + mix(0.35, 0.2, calm) + mix(0.25, 0.0, calm));
	NORMAL_MAP_DEPTH = mix(0.30, 0.10, calm);
	float shore = texture(relief, (p - relief_origin) / relief_extent).b;
	float surf = texture(detail, p / 55.0 + TIME * vec2(0.012, 0.0)).r;
	float foam = smoothstep(0.86, 1.02, shore + (surf - 0.5) * 0.22) * (1.0 - smoothstep(3000.0, 9000.0, dist));
	vec3 colour = mix(deep, shallow, smoothstep(0.35, 0.95, shore));
	ALBEDO = mix(colour, vec3(0.86, 0.90, 0.90), foam * 0.85);
	ROUGHNESS = mix(0.10, 0.6, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
