shader_type spatial;
// Shock diamonds STAND STILL relative to the nozzle: they are a standing wave pinned
// to the exit plane, not a pattern that convects aft. Only the turbulent breakup moves.
// Cell spacing widens with nozzle pressure ratio; amplitude decays downstream.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float power = 0.4;
uniform float pressure_ratio = 1.0;
void fragment() {
	float spacing = mix(31.0, 19.0, clamp(pressure_ratio, 0.0, 1.0));
	float bands = pow(max(0.0, cos(UV.y*spacing)), 5.0) * exp(-2.4*(1.0-UV.y));
	float breakup = 0.65+0.35*sin(UV.x*42.0+UV.y*97.0-TIME*40.0);
	float envelope = pow(UV.y,1.3);
	vec3 base = mix(vec3(.10,.27,1.0),vec3(1.0,.46,.12),.30+envelope*.5);
	vec3 blue = mix(base,vec3(1.0,.93,.72),bands*envelope);
	ALBEDO = blue;
	EMISSION = blue*(2.0+power*4.0);
	ALPHA = envelope*breakup*(0.25+power*0.5);
}
