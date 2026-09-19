shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float core = 0.0;
uniform float plume_length = 2.0;
varying float axial;
void vertex() {
	axial = clamp(.5-VERTEX.y/plume_length,0.0,1.0);
	VERTEX.xz *= 1.0+.075*sin(axial*43.0-TIME*44.0);
}
void fragment() {
	float turbulence = .82+.18*sin(axial*55.0-TIME*78.0+sin(UV.x*6.283)*2.0);
	float diamonds = pow(.5+.5*cos(axial*38.0-TIME*12.0),5.0);
	float soft_edge = pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
	vec3 gas = mix(vec3(.28,.48,.95),vec3(1.0,.44,.12),smoothstep(.12,.90,axial));
	ALBEDO = mix(gas,vec3(1.0,.86,.58),core);
	EMISSION = ALBEDO*(.5+diamonds*.6);
	ALPHA = (.26+core*.20)*turbulence*soft_edge*pow(1.0-axial,.7);
}
