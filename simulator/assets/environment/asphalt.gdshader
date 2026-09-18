shader_type spatial;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float grain = fract(sin(dot(floor(world_position.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	float streak = sin(world_position.x * 1.18) * sin(world_position.x * 0.67);
	float wear = exp(-pow(world_position.x / 13.0, 2.0)) * 0.020;
	ALBEDO = vec3(0.105, 0.115, 0.120) + grain * 0.018 + streak * 0.006 - wear;
	ROUGHNESS = 0.96;
}
