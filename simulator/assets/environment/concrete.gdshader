shader_type spatial;
uniform sampler2D aggregate : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(0.48,0.49,0.46,1.0);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p=world_position.xz;
	float grain=texture(aggregate,p/9.0).r;
	float weather=texture(aggregate,p/81.0+0.37).r;
	vec2 edge=min(mod(p,7.0),7.0-mod(p,7.0));
	vec2 aa=max(fwidth(p),vec2(0.012));
	float joint=max(1.0-smoothstep(0.015,aa.x+0.015,edge.x),1.0-smoothstep(0.015,aa.y+0.015,edge.y));
	ALBEDO=tint.rgb*(0.76+grain*0.38+weather*0.28)*(1.0-joint*0.42);
	ROUGHNESS=0.89;
}
