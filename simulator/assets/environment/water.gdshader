shader_type spatial;
render_mode cull_disabled;

varying vec3 world_position;
uniform bool glacial = false;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
float hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
// Value plus analytic derivatives: irregular wind ripples without a checkerboard.
vec3 wave_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	vec2 u=f*f*(3.0-2.0*f), du=6.0*f*(1.0-f);
	float a=hash(i), b=hash(i+vec2(1,0)), c=hash(i+vec2(0,1)), d=hash(i+vec2(1));
	float k=a-b-c+d;
	return vec3(a+(b-a)*u.x+(c-a)*u.y+k*u.x*u.y,du.x*(b-a+k*u.y),du.y*(c-a+k*u.x));
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p=world_position.xz;
	vec3 swell=wave_noise(p*0.018+vec2(TIME*0.04,TIME*0.025));
	vec3 ripple=wave_noise(p*0.19+vec2(-TIME*0.09,TIME*0.13));
	vec3 fine=wave_noise(p*0.73+vec2(TIME*0.2,-TIME*0.16));
	float distance_fade=1.0-smoothstep(200.0,2000.0,length(VERTEX));
	vec2 gradient=swell.yz*0.026+ripple.yz*0.024+fine.yz*0.011*distance_fade;
	NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(-gradient.x,1.0,-gradient.y)),0.0)).xyz);
	float depth=texture(scene_depth,SCREEN_UV).r;
	vec4 below=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);
	below/=below.w;
	float thickness=max(0.0,VERTEX.z-below.z);
	float shallow=exp(-thickness*0.12);
	vec3 deep_color=glacial ? vec3(0.012,0.10,0.15) : vec3(0.009,0.028,0.036);
	ALBEDO=mix(deep_color,vec3(0.075,0.19,0.16),shallow);
	float foam=(1.0-smoothstep(0.15,1.4,thickness)) * smoothstep(0.32,0.7,ripple.x);
	ALBEDO=mix(ALBEDO,vec3(0.55,0.62,0.60),foam*0.75);
	ROUGHNESS=0.22+foam*0.5;
	METALLIC=0.0;
	SPECULAR=0.5;
}
