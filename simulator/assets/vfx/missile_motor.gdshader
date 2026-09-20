shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float core = 0.0;
uniform float plume_length = 2.0;
// Boost-then-sustain: combat_visuals drives this from the real burn window.
uniform float throttle : hint_range(0.0, 2.0) = 1.0;
varying float axial;
void vertex() {
	axial = clamp(.5-VERTEX.y/plume_length,0.0,1.0);
	VERTEX.xz *= 1.0+.075*sin(axial*43.0-TIME*44.0);
}
void fragment() {
	// Turbulent breakup genuinely fluctuates, so TIME stays here.
	float turbulence = .82+.18*sin(axial*55.0-TIME*78.0+sin(UV.x*6.283)*2.0);
	// Shock diamonds are a STANDING wave in the nozzle frame: no TIME term.
	// Cell spacing widens with the pressure ratio proxy (core = boost phase),
	// and amplitude decays downstream as the shear layer eats the core.
	float cells = 54.0/(0.88+0.30*core);
	float diamonds = pow(.5+.5*cos(axial*cells),5.0)*exp(-3.6*axial);
	float soft_edge = pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
	// Aluminised solid propellant: white-hot at the throat cooling to orange.
	// Blue belongs to unburned hydrocarbons in a kerosene afterburner.
	vec3 gas = mix(vec3(1.0,.94,.82),vec3(1.0,.42,.12),smoothstep(.06,.78,axial));
	ALBEDO = mix(gas,vec3(1.0,.88,.62),core);
	EMISSION = ALBEDO*(4.0+core*5.0+diamonds*3.4)*clamp(throttle,0.0,2.0);
	ALPHA = (.36+core*.30)*turbulence*soft_edge*pow(1.0-axial,.7)*clamp(throttle*0.55+0.45,0.0,1.3);
}
