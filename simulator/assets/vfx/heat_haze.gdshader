shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D screen_copy : hint_screen_texture, filter_linear_mipmap;
uniform float power = 0.0;
void fragment() {
	vec2 centered = UV*2.0-1.0;
	float mask = smoothstep(1.0,0.2,length(centered));
	vec2 distortion = vec2(sin(UV.y*38.0-TIME*18.0),cos(UV.x*27.0+TIME*12.0))*0.0015*power*mask;
	ALBEDO = textureLod(screen_copy,SCREEN_UV+distortion,0.0).rgb;
	ALPHA = mask*power*0.22;
}
