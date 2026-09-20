shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Soft turbulent fire rolling into soot; ten world-space puffs form one volume.
uniform float t = 0.0;
uniform float size = 20.0;
uniform float seed = 0.0;
uniform float opacity = 0.64;
uniform float warmth = 1.0;
varying vec2 p;
void vertex() {
	float extent = size * mix(0.35,1.75,pow(t,0.55));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz)*extent,0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz)*extent,0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz)*extent,0.0),MODEL_MATRIX[3]);
	p = UV*2.0-1.0;
}
float hash(vec2 q) {return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 q) {
	vec2 i=floor(q);vec2 f=fract(q);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	float angle = t*1.8 + seed;
	vec2 q = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p;
	q.y -= t*0.6;
	float n = noise(q*3.4+seed)*0.55 + noise(q*7.1-seed)*0.30 + noise(q*14.0+seed)*0.15;
	float r = length(p);
	float density = 1.0-smoothstep(0.25,0.94,r+n*0.32-0.13);
	float fire = exp(-t*7.0)*warmth*(0.35+0.65*n)*(1.0-smoothstep(0.25,0.85,r));
	vec3 soot = mix(vec3(0.055,0.048,0.043),vec3(0.28,0.25,0.23),n);
	vec3 hot = mix(vec3(1.0,0.065,0.006),vec3(1.0,0.73,0.20),n*n);
	ALBEDO = mix(soot,hot,clamp(fire*2.2,0.0,1.0));
	EMISSION = hot*fire*2.2;
	ALPHA = density*opacity*smoothstep(0.0,0.035,t)*(1.0-smoothstep(0.40,1.0,t));
}
