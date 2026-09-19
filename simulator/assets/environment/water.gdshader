shader_type spatial;
render_mode cull_disabled;

varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float wave_a = sin(world_position.x * 0.065 + world_position.z * 0.025 + TIME * 0.65);
	float wave_b = sin(world_position.x * 0.021 - world_position.z * 0.12 + TIME * 0.95);
	float sparkle = pow(max(0.0, wave_a * wave_b), 12.0);
	ALBEDO = mix(vec3(0.018, 0.10, 0.13), vec3(0.09, 0.23, 0.24), wave_a * 0.075 + 0.10) + sparkle * 0.075;
	ROUGHNESS = 0.25 + wave_b * 0.07;
	METALLIC = 0.30;
	NORMAL_MAP = vec3(0.5 + wave_a * 0.035, 0.5 + wave_b * 0.025, 1.0);
	NORMAL_MAP_DEPTH = 0.6;
}
