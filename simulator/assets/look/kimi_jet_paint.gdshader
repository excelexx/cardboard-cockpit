shader_type spatial;
// "Reaper" skin for the KimiAirframe stealth proposal.
//
// A black jet over dark water is a readability problem first and a paint job
// second. The strategy here, in order of importance:
//   1. a hand-rolled sky mirror that fires at grazing angles (Godot never hands
//      a spatial shader the environment radiance, so the sky is reflected
//      analytically), so the flanks always carry a slice of the horizon;
//   2. a strong rim so the silhouette separates from hills, water and sky;
//   3. gold trim that is real geometry - ribbons laid on actual edges, driven
//      through vertex colour (COLOR.r) so the emission follows the airframe's
//      creases exactly instead of some projected stripe;
//   4. sawtooth panel seams and per-panel tone/roughness drift, so the skin
//      reads as many faceted plates, not one plastic shell;
//   5. heat-tempered metal around the nozzle (COLOR.g), running from blued
//      steel to straw with a faint ember right at the petal tips.
// COLOR.b darkens - it paints the weapon-bay door outlines and access panels.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_tint : source_color = vec3(0.023, 0.026, 0.033);
uniform vec3 sky_high : source_color = vec3(0.30, 0.42, 0.64);
uniform vec3 sky_low : source_color = vec3(0.72, 0.47, 0.26);
uniform vec3 ground_tint : source_color = vec3(0.070, 0.064, 0.054);
uniform vec3 gold : source_color = vec3(1.0, 0.70, 0.24);
uniform float gold_energy = 2.6;
uniform float sheen = 0.60;

varying vec3 lp;   // model-space position
varying vec3 ln;   // model-space normal

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float hash12(vec2 p) {
	vec3 v = fract(vec3(p.x, p.y, p.x) * 0.1031);
	v += dot(v, v.yzx + 33.33);
	return fract((v.x + v.y) * v.z);
}

void fragment() {
	vec3 nrm = normalize(ln);

	// Sawtooth panel grid: both seam families zig-zag, so every joint on the
	// skin is serrated like the key art's edges instead of a straight line.
	float zig_x = abs(fract(lp.z * 0.30) - 0.5) * 2.0;
	float zig_z = abs(fract(lp.x * 0.38) - 0.5) * 2.0;
	vec2 cell = vec2(lp.x * 0.38 + zig_x * 0.12, lp.z * 0.26 + zig_z * 0.10);
	vec2 seam = abs(fract(cell) - 0.5);
	float joint = 1.0 - smoothstep(0.0, 0.022, min(seam.x, seam.y));
	float panel = hash12(floor(cell) + floor(lp.y * 1.3) * 5.0);

	float streak = texture(grain, vec2(lp.x * 0.9 + lp.y * 0.6, lp.z * 0.07)).r;
	float blotch = texture(grain, lp.xz * 0.14 + lp.y * 0.09).r;
	float fine = texture(grain, lp.xz * 2.1 + lp.y * 1.7).r;
	float topness = smoothstep(-0.1, 0.7, nrm.y);
	float grime = clamp((streak - 0.52) * 2.0, 0.0, 1.0) * 0.24 + (0.5 - blotch) * 0.10;

	vec3 paint = base_tint * mix(0.92, 1.08, panel);
	paint *= 1.0 - grime * mix(1.0, 0.65, topness);
	paint *= 1.0 - joint * 0.20;
	paint *= 1.0 - COLOR.b * 0.55;

	// Heat tempering around the nozzle: blued steel into straw bronze.
	float heat = clamp(COLOR.g, 0.0, 1.0);
	vec3 temper = mix(vec3(0.045, 0.055, 0.085), vec3(0.150, 0.095, 0.045), smoothstep(0.30, 0.95, heat));
	paint = mix(paint, temper, heat * 0.85);

	// Gold trim: albedo goes brassy so the strips still read when unlit.
	paint = mix(paint, gold * 0.30, COLOR.r);

	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(normal_world, view_world), 0.0, 1.0), 6.0);
	vec3 refl = reflect(-view_world, normal_world);
	vec3 sky = mix(sky_low, sky_high, smoothstep(0.02, 0.55, refl.y));
	sky = mix(ground_tint, sky, smoothstep(-0.22, 0.06, refl.y));
	float gloss = mix(0.72, 1.0, panel) * (1.0 - grime * 0.40);

	ALBEDO = paint;
	METALLIC = 0.32 + heat * 0.35;
	SPECULAR = 0.30;
	// Satin skin; individual panels polish or go matt, seams and grime go matt,
	// the hot barrel stays smooth so it throws a hard highlight.
	ROUGHNESS = clamp(0.40 + topness * 0.12 + (panel - 0.5) * 0.12 + (blotch - 0.5) * 0.14
			+ (fine - 0.5) * 0.06 + grime * 0.20 + joint * 0.15 - heat * 0.18, 0.22, 0.85);
	RIM = 1.0;
	RIM_TINT = 0.12;
	vec3 emit = sky * fresnel * sheen * gloss;
	emit += gold * COLOR.r * gold_energy;
	emit += vec3(1.0, 0.32, 0.08) * pow(heat, 3.0) * 0.8;
	EMISSION = emit;
}
