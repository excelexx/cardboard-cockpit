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
// PLUME-STATION DISSOLVE - the primary anti-beam control, and the one that works in the
// view the owner actually judged. The near-camera fade below CANNOT fire from the game's
// chase rig (it sits 22-26 m back, so the plume tip is still ~11 m from the lens and
// `near` never leaves 1.0), yet that is exactly the view where reheat read as "one
// continuous HEAVY beam". So the plume dissolves by its own station instead: past
// `fade_from` it breaks up and by `fade_to` nothing is left. Raise fade_from to lengthen
// the visible flame, never to make it solid again.
uniform float fade_from = 0.54;
uniform float fade_to = 0.97;
// Near-camera OPACITY fade, in metres. Kept as a SECOND line of defence for a genuinely
// close pass (a wing camera, the replay orbit); it is not what tames the chase view.
uniform float near_fade_in = 3.5;
uniform float near_fade_out = 13.5;

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float v = UV.y * 2.0 - 1.0;

	// Envelope and the standing shock train. The phase is deliberately non-linear in u:
	// real cells grow longer as the jet loses pressure ratio downstream.
	// `lumps` breathes the ENVELOPE ITSELF along the axis. Without it the plume boundary is
	// a perfectly smooth analytic curve, which is what made the silhouette read as a
	// straight-sided cut-out card rather than gas.
	float lumps = texture(noise, vec2(u * 2.35 + 0.51, 0.77 - TIME * 1.05)).r;
	float envelope_r = core_radius * (1.0 + (spread - 1.0) * pow(u, 2.20)) * (0.84 + 0.34 * lumps);
	float drift = texture(noise, vec2(u * 1.70, 0.31)).r;   // breaks the lattice out of perfect regularity
	float phase = cells * u * (1.0 - 0.30 * u);
	float saw = fract(phase + (drift - 0.5) * 0.22);
	float node = abs(saw * 2.0 - 1.0);          // 1 on a Mach disk, 0 mid-cell
	float train = exp(-3.10 * u) * (1.0 + 1.70 * exp(-4.5 * u));   // crisp first cells, gone by mid-plume
	float width = envelope_r * (1.0 + 0.22 * (1.0 - node) * train);

	// Turbulence: glassy over the first cells, ragged and streaky after them.
	float coarse = texture(noise, vec2(u * 0.95 - TIME * 0.80, v * 0.38 + 0.5)).r;
	float fine   = texture(noise, vec2(u * 3.10 - TIME * 2.35, v * 1.25 + 0.21)).r;
	float ragged = smoothstep(0.14, 0.85, u);
	// `wobble` is the only thing that breaks the plume boundary, so it may never be zero.
	// It used to be multiplied by `ragged` alone, which is ~0 below u = 0.3: the first three
	// metres of edge were a perfect analytic curve, i.e. the hard straight line the review
	// picked out. A floor keeps even the first cells broken.
	float edge_break = mix(0.52, 1.0, ragged);
	float tatter = mix(0.55, 1.45, texture(noise, vec2(u * 2.9 - TIME * 1.15, v * 0.9 + 0.66)).r);
	float wobble = ((coarse - 0.5) * 0.62 + (fine - 0.5) * 0.38) * 0.74 * envelope_r * edge_break;
	float q = abs(v + wobble) / max(width, 1e-4);

	// Radial layers, each with its OWN brightness. Only the axis and the Mach disks are
	// allowed above the glow threshold; the orange, violet and blue layers stay in the
	// range where the AgX grade still holds their colour instead of clipping to white.
	// STARVED HARD on purpose. The previous weight was (0.25 + 0.75 * node), which only
	// starved mid-cell to a QUARTER - it never went dark, so at game distance the diamonds
	// smeared into one bar. A near-zero floor under a steep power of `node` is what makes
	// the gaps between the diamonds genuinely black.
	float cell = 0.03 + 0.97 * pow(node, 2.55);
	float body     = exp(-pow(q / 0.80, 2.60)) * cell;
	float core     = exp(-pow(q / 0.34, 2.0)) * exp(-2.10 * u);
	float throat   = exp(-pow(q / 0.46, 2.0)) * exp(-u * 7.0);
	float shoulder = exp(-pow((q - 0.72) / 0.36, 2.0));
	float rim      = exp(-pow((q - 1.02) / 0.24, 2.0));
	// Narrower radially as well as in u: at 0.62 each Mach disk was a wide round blob that
	// clipped to white and swallowed its own amber. A Mach disk is a THIN normal shock.
	float disk     = exp(-pow(q / 0.50, 2.0)) * pow(node, 7.0) * train;
	float oblique  = 0.95 * (1.0 - node);
	float shock    = exp(-pow((q - oblique) / (0.060 + 0.20 * u), 2.0)) * train * smoothstep(0.0, 0.04, u);

	float streak = mix(0.70, 1.34, fine) * mix(0.84, 1.16, coarse);
	// Past the shock train the smooth column is taken over by turbulent billows.
	float breakup = mix(1.0, mix(0.45, 1.35, fine * 0.65 + coarse * 0.35), ragged);
	// Hard taper.
	float reach = pow(1.0 - u, 2.60);
	// ...and the station dissolve, torn by noise so the tail breaks into wisps instead of
	// ending at the quad's edge. The visible flame is the first half of the plume; the rest
	// is a few fading diamonds.
	float tail = texture(noise, vec2(u * 1.9 + 0.13, v * 0.55 - TIME * 0.90)).r;
	float dissolve = 1.0 - smoothstep(fade_from + 0.20 * tail, fade_to, u);
	float flicker = 0.94 + 0.06 * sin(TIME * 61.0 + u * 19.0) * sin(TIME * 27.0 + 1.3);
	// How much colour survives downstream. Too low and the tail greys out into steam; the
	// gaps stay dark because `body` is cell-modulated, not because the tail is colourless.
	float cool = mix(1.0, 0.52, u);

	// PALETTE LOCK: amber, gunmetal, slate blue. The shoulder used to be a violet weighted
	// mix(0.45, 1.60, u) - i.e. it got STRONGER with distance and peaked at the tip, which is
	// why every review render came back a lavender sausage. Downstream the plume is amber;
	// blue-white lives in the throat, the core and the rim over the first couple of metres.
	// Deeper, more saturated amber. Additive over a bright sky, a pale orange turns into the
	// grey-beige the review saw; the hue only survives the blend if it starts saturated.
	vec3 hot    = mix(vec3(0.84, 0.92, 1.00), vec3(1.00, 0.96, 0.87), reheat);
	vec3 flame  = mix(vec3(0.40, 0.60, 1.00), vec3(1.00, 0.40, 0.055), reheat);
	vec3 amber  = mix(vec3(0.34, 0.48, 1.00), vec3(0.98, 0.29, 0.045), reheat);
	vec3 blue   = vec3(0.26, 0.45, 1.00);
	float first_metres = 1.0 - smoothstep(0.05, 0.22, u);   // the first ~2 m of a 9.4 m plume
	// Kimi's "white-blue core in the first 2 m only" applied to the COLOUR, not just to the
	// intensity. MEASURED: with the axis and the Mach disks tinted `hot` over the whole
	// plume, the bright half of the flame sampled rgb(197,185,181) - a white bar with an
	// orange fringe, which is the "grey-beige/white rather than amber" the review reported.
	// Past the first couple of metres the axis and the disks are amber like everything else.
	vec3 axis_hue = mix(flame, hot, first_metres);

	// The column is DELIBERATELY starved: the diamonds carry the brightness and the body is
	// a dim envelope between them, so the eye reads separate shock cells with dark gaps
	// rather than one heavy beam. If this ever looks like a solid bar again, cut `cell` and
	// `reach` further - do NOT add another layer on top.
	vec3 emit = flame  * body * streak * breakup * 0.90 * cool
	          + amber  * shoulder * streak * tatter * 1.35 * mix(1.00, 0.42, u) * (0.16 + 0.84 * pow(node, 1.7))
	          + blue   * rim * tatter * 0.70 * first_metres
	          + axis_hue * core * 1.80
	          + hot      * throat * 1.55
	          + axis_hue * disk * 2.35
	          + mix(axis_hue, flame, 0.35) * shock * 1.80;
	float near = smoothstep(near_fade_in, near_fade_out, length(VERTEX));
	ALBEDO = emit * reach * dissolve * flicker * visibility * power * brightness * near;
	ALPHA = 1.0;
}
