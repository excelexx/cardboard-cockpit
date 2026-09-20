shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// A turbulent spherical pressure front. Its material fades to black
// under additive blending so the sky remains visible through the whole shell.
uniform float t = 0.0;
uniform vec3 tint : source_color = vec3(1.0,0.25,0.03);
uniform float intensity = 1.7;
varying vec2 ribbon_uv;
void vertex() {
	ribbon_uv = UV;
	float angle = UV.x*6.2831853;
	VERTEX *= 1.0 + (sin(angle*11.0+t*15.0)+sin(angle*23.0-t*19.0))*0.004*t;
}
void fragment() {
	float angle = ribbon_uv.x*6.2831853;
	float across = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),5.0);
	float filaments = 0.35+0.65*pow(0.5+0.5*sin(angle*17.0-t*23.0+sin(angle*7.0+t*11.0)),2.0);
	float gaps = 0.4+0.6*smoothstep(-0.85,0.3,sin(angle*5.0+t*6.0)+sin(angle*9.0-t*5.0)*0.5);
	float body = across*filaments*gaps*pow(1.0-t,1.7);
	ALBEDO = mix(tint,vec3(1.0,0.91,0.75),body*0.4)*body*intensity*4.0;
	ALPHA = 1.0;
}
