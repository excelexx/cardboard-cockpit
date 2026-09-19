shader_type spatial;
uniform sampler2D masonry : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(0.68,0.64,0.57,1.0);
uniform bool glass_tower = false;
varying vec3 p;
varying vec3 n;
void vertex() { p=VERTEX; n=NORMAL; }
float hash(vec2 q) { return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 uv=vec2(abs(n.x)>0.5?p.z:p.x,p.y);
	vec2 grid=uv/vec2(glass_tower?2.5:3.8,3.2);
	vec2 cell=fract(grid);
	float window=step(0.19,cell.x)*step(cell.x,0.81)*step(0.24,cell.y)*step(cell.y,0.82);
	if(glass_tower) window=step(0.055,cell.x)*step(cell.x,0.945)*step(0.06,cell.y)*step(cell.y,0.93);
	float variation=hash(floor(grid));
	float detail=1.0-smoothstep(0.25,1.0,max(fwidth(grid.x),fwidth(grid.y)));
	window=mix(glass_tower?0.85:0.32,window,detail);
	variation=mix(0.5,variation,detail);
	vec3 wall=texture(masonry,uv/7.0).rgb*tint.rgb*1.35;
	vec3 glass=mix(vec3(0.055,0.105,0.13),vec3(0.29,0.38,0.42),variation);
	float frame=step(0.165,cell.x)*step(cell.x,0.835)*step(0.215,cell.y)*step(cell.y,0.845);
	ALBEDO=mix(mix(wall,vec3(0.36,0.36,0.33),frame),glass,window);
	if(abs(n.y)>0.6) ALBEDO=vec3(0.18,0.20,0.20);
	ROUGHNESS=mix(0.88,0.48,window);
	METALLIC=window*0.12;
}
