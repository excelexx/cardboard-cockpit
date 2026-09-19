shader_type spatial;
render_mode cull_disabled;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float height(vec2 p,float footprint) {
	p += vec2(TIME*.7,TIME*.23);
	return noise(p*.13)*.42*(1.0-smoothstep(.3,.8,footprint*.13))+noise(p*.43+vec2(7.3))*.12*(1.0-smoothstep(.3,.8,footprint*.43))+noise(p*1.07)*.026*(1.0-smoothstep(.3,.8,footprint*1.07));
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p=world_position.xz;
	float footprint=max(length(dFdx(p)),length(dFdy(p)));
	float h=height(p,footprint);
	vec3 normal_world=normalize(vec3((h-height(p+vec2(.2,0),footprint))*2.8,1.0,(h-height(p+vec2(0,.2),footprint))*2.8));
	NORMAL=normalize((VIEW_MATRIX*vec4(normal_world,0.0)).xyz);
	float centre=1030.0+sin(p.y*.00034)*170.0+sin(p.y*.00091)*60.0;
	float width=113.0+470.0*exp(-pow((p.y+7000.0)/2550.0,2.0))+200.0*exp(-pow((p.y+19000.0)/2300.0,2.0));
	float shallows=smoothstep(width-65.0,width+70.0,abs(p.x-centre));
	ALBEDO=mix(vec3(.008,.041,.054),vec3(.048,.115,.106),shallows);
	METALLIC=0.0; ROUGHNESS=.14+smoothstep(1.0,15.0,footprint)*.13+shallows*.04; SPECULAR=.55;
}
