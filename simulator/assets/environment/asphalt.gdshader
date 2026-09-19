shader_type spatial;
uniform sampler2D aggregate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float airport_z = 0.0;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = vec2(world_position.x, world_position.z-airport_z);
	vec3 detail = texture(aggregate,p/16.0).rgb;
	vec3 macro = texture(aggregate,p/173.0+vec2(0.31)).rgb;
	// Rubber is concentrated in the touchdown zones, not painted over every taxiway.
	float wheel_tracks = exp(-pow((abs(p.x)-5.5)/3.8,2.0));
	float touchdown = exp(-pow((abs(p.y)-1010.0)/255.0,2.0));
	float streaks = 0.45+0.55*sin(p.x*9.0)*sin(p.x*3.1);
	float rubber = wheel_tracks*touchdown*streaks;
	vec2 joint_distance = min(mod(p,vec2(8.0,45.0)),vec2(8.0,45.0)-mod(p,vec2(8.0,45.0)));
	vec2 antialias = max(fwidth(p),vec2(0.025));
	float seams = (1.0-smoothstep(0.015,0.015+antialias.x,joint_distance.x))*0.15;
	ALBEDO = mix(detail,macro,0.22)*vec3(0.40,0.43,0.46)*(1.0-rubber*0.65-seams);
	ROUGHNESS = mix(0.94,0.78,rubber);
}
