shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}

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
	vec3 grass_detail = texture(grass_texture, world_position.xz / 12.0).rgb;
	vec3 grass_macro = texture(grass_texture, world_position.xz / 1100.0 + vec2(0.4)).rgb;
	float patches=noise2(world_position.xz/170.0)*0.65+noise2(world_position.xz/41.0)*0.35;
	vec3 grass = mix(vec3(0.075,0.115,0.035),vec3(0.19,0.235,0.095),patches)*(0.65+grass_detail*0.85+grass_macro*0.3);
	float forest_zone=smoothstep(6.0,12.0,world_position.y)*(1.0-smoothstep(1500.0,1900.0,world_position.y));
	float canopy=noise2(world_position.xz/23.0)*0.5+noise2(world_position.xz/71.0)*0.3+noise2(world_position.xz/420.0)*0.2;
	vec3 forest=mix(vec3(0.030,0.063,0.037),vec3(0.075,0.13,0.060),canopy);
	forest*=0.65+grass_detail*0.65+grass_macro*0.30;
	grass=mix(grass,forest,forest_zone*0.80);
	vec3 rock = triplanar(rock_texture, world_position / 180.0, weights);
	vec3 rock_macro = triplanar(rock_texture, world_position / 920.0 + vec3(0.3), weights);
	rock = mix(rock, rock_macro, 0.3) * vec3(0.9, 0.92, 0.90);
	float slope = 1.0 - world_normal.y;
	float rocky = max(smoothstep(1650.0, 2450.0, world_position.y), smoothstep(0.22, 0.58, slope));
	vec3 terrain = mix(grass, rock, rocky);
	float shore=(1.0-smoothstep(-2.0,12.0,world_position.y))*(1.0-smoothstep(0.10,0.55,slope));
	float airport_z=min(abs(world_position.z),abs(world_position.z+15000.0));
	float airfield=(1.0-smoothstep(1000.0,1350.0,abs(world_position.x-250.0)))*(1.0-smoothstep(1980.0,2350.0,airport_z));
	shore*=1.0-airfield;
	vec3 beach=mix(vec3(0.14,0.16,0.15),vec3(0.37,0.34,0.25),smoothstep(-8.0,4.0,world_position.y));
	beach=mix(beach,texture(shore_texture,world_position.xz/90.0).rgb,0.6);
	terrain=mix(terrain,beach*(0.8+rock_macro.r*0.3),shore);
	float snowline = 2180.0 + sin(world_position.x * 0.0009) * 100.0 + sin(world_position.z * 0.0014) * 95.0;
	float snow = smoothstep(snowline - 150.0, snowline + 120.0, world_position.y) * (1.0 - smoothstep(0.30, 0.62, slope));
	vec3 snow_color = vec3(0.78, 0.83, 0.84) * (0.88 + rock_macro.r * 0.3);
	ALBEDO = mix(terrain, snow_color, snow);
	vec3 micro=texture(rock_normal,world_position.xz/90.0).rgb*2.0-1.0;
	vec3 detailed_normal=normalize(world_normal+vec3(micro.x,0.0,micro.y)*rocky*0.16);
	NORMAL=normalize((VIEW_MATRIX*vec4(detailed_normal,0.0)).xyz);
	ROUGHNESS = 0.96;
}
