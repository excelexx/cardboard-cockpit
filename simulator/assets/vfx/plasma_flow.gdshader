shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 plasma_color : source_color = vec4(0.05, 0.72, 1.0, 0.28);
uniform float intensity = 2.8;
uniform float phase = 0.0;
void vertex() {
	float ripple = 1.0 + 0.045 * sin(UV.y * 120.0 - TIME * 14.0 + phase);
	VERTEX.xz *= ripple;
}
void fragment() {
	float helix = pow(max(0.0, cos(UV.x * 12.56637 + UV.y * 100.0 - TIME * 19.0 + phase)), 10.0);
	float secondary = pow(max(0.0, cos(UV.x * 18.8495 - UV.y * 68.0 + TIME * 11.0)), 18.0);
	float flow = 0.5 + 0.5 * sin(UV.y * 180.0 - TIME * 27.0);
	ALBEDO = plasma_color.rgb;
	EMISSION = plasma_color.rgb * intensity * (0.45 + helix * 2.0 + secondary);
	ALPHA = plasma_color.a * (0.2 + helix * 0.85 + secondary * 0.45 + flow * 0.12);
}
