shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
vec3 triplanar(sampler2D source, vec3 point, vec3 weights) {
	return texture(source, point.zy).rgb * weights.x + texture(source, point.xz).rgb * weights.y + texture(source, point.xy).rgb * weights.z;
}
void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec3 grass_a = texture(grass_texture, world_position.xz / 38.0).rgb;
	vec3 grass_b = texture(grass_texture, mat2(vec2(0.8,-0.6),vec2(0.6,0.8))*world_position.xz / 57.0 + vec2(0.37,0.21)).rgb;
	vec3 grass_detail = mix(grass_a,grass_b,0.45+sin(world_position.x*0.002+world_position.z*0.003)*0.25);
	vec3 grass_macro = texture(grass_texture, world_position.xz / 1100.0 + vec2(0.4)).rgb;
	vec3 grass = mix(grass_detail, grass_macro, 0.28) * vec3(0.46, 0.68, 0.57);
	vec3 rock = triplanar(rock_texture, world_position / 100.0, weights);
	vec3 rock_macro = triplanar(rock_texture, world_position / 920.0 + vec3(0.3), weights);
	rock = mix(rock, rock_macro, 0.3) * vec3(0.66, 0.72, 0.78);
	float slope = 1.0 - world_normal.y;
	float rocky = max(smoothstep(500.0, 1300.0, world_position.y), smoothstep(0.13, 0.45, slope));
	vec3 terrain = mix(grass, rock, rocky);
	float snowline = 1830.0 + sin(world_position.x * 0.0009) * 100.0 + sin(world_position.z * 0.0014) * 95.0;
	float snow = smoothstep(snowline - 150.0, snowline + 120.0, world_position.y) * (1.0 - smoothstep(0.30, 0.62, slope));
	vec3 snow_color = vec3(0.78, 0.83, 0.84) * (0.88 + rock_macro.r * 0.3);
	ALBEDO = mix(terrain, snow_color, snow);
	ROUGHNESS = 0.90;
	float detail_height = dot(grass_detail,vec3(0.33));
	NORMAL_MAP = normalize(vec3(dFdx(detail_height)*0.18,dFdy(detail_height)*0.18,1.0))*0.5+0.5;
	NORMAL_MAP_DEPTH = 0.45;
}
