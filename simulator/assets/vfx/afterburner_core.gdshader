shader_type spatial;
// The plume's AXIAL SLICE: one camera-facing quad that contains the engine axis.
// A jet is axisymmetric, so a view-facing slice is the honest way to draw its
// interior. Oblique shocks spring off the plume boundary, criss-cross on the axis
// at a bright Mach disk, the boundary swells between crossings, the cells stretch
// and weaken downstream, and past the shock train the gas breaks into turbulent
// streaks racing aft. Local +X is aft: UV.x 0 at the nozzle, 1 at the tip;
// UV.y crosses the plume.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float power = 1.0;          // overall plume strength 0..1
uniform float reheat = 1.0;         // 0 dry thrust (blue-white), 1 full reheat (orange -> violet)
uniform float visibility = 1.0;     // cross-fade against the rear-view disc stack
uniform float cells = 6.0;          // shock cells over the structured length
uniform float core_radius = 0.16;   // plume radius at the nozzle, in quad half-heights
uniform float spread = 2.6;         // radius multiplier at the tip
uniform float brightness = 1.0;

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float v = UV.y * 2.0 - 1.0;

	// Envelope and the standing shock train. The phase is deliberately non-linear in u:
	// real cells grow longer as the jet loses pressure ratio downstream.
	float envelope_r = core_radius * (1.0 + (spread - 1.0) * pow(u, 1.30));
	float drift = texture(noise, vec2(u * 1.70, 0.31)).r;   // breaks the lattice out of perfect regularity
	float phase = cells * u * (1.0 - 0.30 * u);
	float saw = fract(phase + (drift - 0.5) * 0.22);
	float node = abs(saw * 2.0 - 1.0);          // 1 on a Mach disk, 0 mid-cell
	float train = exp(-2.60 * u) * (1.0 + 1.70 * exp(-4.5 * u));   // crisp first cells, gone by mid-plume
	float width = envelope_r * (1.0 + 0.22 * (1.0 - node) * train);

	// Turbulence: glassy over the first cells, ragged and streaky after them.
	float coarse = texture(noise, vec2(u * 0.95 - TIME * 0.80, v * 0.38 + 0.5)).r;
	float fine   = texture(noise, vec2(u * 3.10 - TIME * 2.35, v * 1.25 + 0.21)).r;
	float ragged = smoothstep(0.14, 0.85, u);
	float tatter = mix(0.55, 1.45, texture(noise, vec2(u * 2.9 - TIME * 1.15, v * 0.9 + 0.66)).r);
	float wobble = ((coarse - 0.5) * 0.62 + (fine - 0.5) * 0.38) * 0.58 * envelope_r * ragged;
	float q = abs(v + wobble) / max(width, 1e-4);

	// Radial layers, each with its OWN brightness. Only the axis and the Mach disks are
	// allowed above the glow threshold; the orange, violet and blue layers stay in the
	// range where the AgX grade still holds their colour instead of clipping to white.
	float body     = exp(-pow(q / 0.80, 2.60)) * (0.84 + 0.30 * node);   // the column itself pulses with the cells
	float core     = exp(-pow(q / 0.34, 2.0)) * exp(-1.35 * u);
	float throat   = exp(-pow(q / 0.46, 2.0)) * exp(-u * 7.0);
	float shoulder = exp(-pow((q - 0.72) / 0.36, 2.0));
	float rim      = exp(-pow((q - 1.02) / 0.24, 2.0));
	float disk     = exp(-pow(q / 0.62, 2.0)) * pow(node, 7.0) * train;
	float oblique  = 0.95 * (1.0 - node);
	float shock    = exp(-pow((q - oblique) / (0.060 + 0.20 * u), 2.0)) * train * smoothstep(0.0, 0.04, u);

	float streak = mix(0.70, 1.34, fine) * mix(0.84, 1.16, coarse);
	// Past the shock train the smooth column is taken over by turbulent billows.
	float breakup = mix(1.0, mix(0.45, 1.35, fine * 0.65 + coarse * 0.35), ragged);
	float reach = pow(1.0 - u, 0.95) * smoothstep(1.0, 0.80, u);
	float flicker = 0.94 + 0.06 * sin(TIME * 61.0 + u * 19.0) * sin(TIME * 27.0 + 1.3);
	float cool = mix(1.0, 0.30, u);

	vec3 hot    = mix(vec3(0.84, 0.92, 1.00), vec3(1.00, 0.97, 0.90), reheat);
	vec3 flame  = mix(vec3(0.40, 0.60, 1.00), vec3(1.00, 0.46, 0.09), reheat);
	vec3 violet = mix(vec3(0.34, 0.48, 1.00), vec3(0.78, 0.22, 0.98), reheat);
	vec3 blue   = vec3(0.26, 0.45, 1.00);

	// The column is CONTINUOUS and already above the bloom threshold; the diamonds are
	// brighter nodes inside it, about half as much again, not isolated blobs in a dark gap.
	vec3 emit = flame  * body * streak * breakup * 2.30 * cool
	          + violet * shoulder * streak * tatter * 0.95 * mix(0.45, 1.60, u)
	          + blue   * rim * tatter * 0.70
	          + hot    * core * 2.30
	          + hot    * throat * 1.60
	          + hot    * disk * 3.00
	          + mix(hot, flame, 0.35) * shock * 1.80;
	ALBEDO = emit * reach * flicker * visibility * power * brightness;
	ALPHA = 1.0;
}
