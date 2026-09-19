shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float power = 0.4;
void fragment() {
	float bands = pow(max(0.0,cos(UV.y*38.0-TIME*22.0)),5.0);
	float breakup = 0.65+0.35*sin(UV.x*42.0+UV.y*97.0-TIME*40.0);
	float envelope = pow(1.0-UV.y,1.3);
	vec3 blue = mix(vec3(0.04,0.20,0.95),vec3(0.9,0.96,1.0),bands*envelope);
	ALBEDO = blue;
	EMISSION = blue*(2.0+power*4.0);
	ALPHA = envelope*breakup*(0.25+power*0.5);
}
