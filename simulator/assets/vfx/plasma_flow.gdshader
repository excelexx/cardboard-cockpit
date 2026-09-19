shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 plasma_color : source_color = vec4(0.04, 0.60, 1.0, 0.26);
uniform float intensity = 2.4;
uniform float phase = 0.0;
void vertex() {
	float ripple = 1.0 + 0.025 * sin(UV.y * 120.0 - TIME * 12.0 + phase);
	VERTEX.xz *= ripple;
}
void fragment() {
	// Fine counterwound filaments surround a contained white-hot core.
	float helix = pow(max(0.0, cos(UV.x * 12.56637 + UV.y * 88.0 - TIME * 15.0 + phase)), 18.0);
	float secondary = pow(max(0.0, cos(UV.x * 18.8495 - UV.y * 61.0 + TIME * 9.0 + phase)), 26.0);
	float packet = pow(0.5 + 0.5 * sin(UV.y * 56.0 - TIME * 20.0 + phase), 8.0);
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float ends = smoothstep(0.0,0.025,UV.y) * smoothstep(0.0,0.035,1.0-UV.y);
	vec3 color = mix(plasma_color.rgb,vec3(0.65,0.90,1.0),helix * 0.65);
	ALBEDO = color;
	EMISSION = color * intensity * (0.25 + helix * 1.4 + secondary * 0.6 + packet * 0.3);
	ALPHA = ends * plasma_color.a * (0.10 + edge * 0.2 + helix * 0.65 + secondary * 0.3 + packet * 0.12);
}
