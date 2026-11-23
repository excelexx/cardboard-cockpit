shader_type spatial;
// SPECTRE X-26 skin. Near-black gunmetal with a satin-to-gloss sheen, sawtooth
// panel seams and airflow grime. The hard problem a black jet creates is
// readability: over dark water it disappears. Three things fix that here and
// none of them brighten the paint -- a hand-rolled sky mirror that fires at
// grazing angles, a strong rim, and the separate gold trim mesh.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D livery : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform bool use_livery = false;                 // the F-35B dressing still needs its texture
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_tint : source_color = vec3(0.027, 0.030, 0.039);
uniform float wear = 1.0;
// Godot never hands a spatial shader the environment radiance, so the sky is
// passed in and reflected analytically. Defaults match the golden-hour world.
uniform vec3 sky_high : source_color = vec3(0.24, 0.33, 0.52);
// The MIRROR's low colour is NOT the sky's low colour. Most facets on a chined
// forebody reflect a vector barely above the horizon, so using the warm horizon
// band here painted the whole nose tan and killed the near-black gunmetal. What
// a shallow reflection actually sees at golden hour is cool slate haze.
uniform vec3 mirror_low : source_color = vec3(0.32, 0.30, 0.34);
uniform vec3 ground_tint : source_color = vec3(0.075, 0.068, 0.058);
// A dim warm bounce off the water so the belly is dark, not a void.
uniform vec3 under_bounce : source_color = vec3(0.055, 0.038, 0.022);
uniform float sheen = 1.0;
// Small hung parts (pylons) use the same paint but must never catch an edge
// light: four lit plates under a black wing are the loudest thing on the
// underside. Scaling RIM per material is cheaper than a second shader.
uniform float rim_scale = 1.0;
// ...and the same for the SKY SPECULAR, which is the term that actually lit
// them: with reflected_light_source = SKY a vertical pylon face at metallic
// 0.40 / roughness 0.42 mirrors a sunset straight back, and seen from directly
// below it blew to luminance 0.65 against a fully crushed wing. Neither
// rim_scale nor sheen touches that lobe.
uniform float spec_scale = 1.0;
uniform float rough_bias = 0.0;

varying vec3 local;
varying vec3 local_normal;

void vertex() {
	local = VERTEX;
	local_normal = NORMAL;
}

float hash12(vec2 p) {
	vec3 v = fract(vec3(p.x, p.y, p.x) * 0.1031);
	v += dot(v, v.yzx + 33.33);
	return fract((v.x + v.y) * v.z);
}

void fragment() {
	// WORLD normal first, because every light-direction decision below ("is
	// this facet facing the sun", "is this facet facing the water") has to be
	// asked in world space. `local_normal` is the normal in each
	// MeshInstance3D's OWN space, and the fins, strakes and wings are all
	// mounted on rotated nodes: FinMount alone is Basis(Z,-cant) * Basis(X,
	// tilt) * Basis(Z, PI/2), which sends both fins' local +Y to world
	// (-0.891, +/-0.454, 0). The same local face is genuinely up on one fin and
	// genuinely down on its mirror, so gating on local_normal.y handed one
	// blade the sun-baked matting and the other the warm under-bounce -- one
	// warm tan fin and one cold blue fin on a symmetric pair, measured at 1.6x
	// luminance apart. `local` (the POSITION) still drives the panel grid, so
	// the panel work stays glued to each part.
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Panel grid in model space. Both seam families zig-zag, so every joint is
	// serrated instead of a straight give-away line.
	float zig_x = abs(fract(local.z * 0.34) - 0.5) * 2.0;
	float zig_z = abs(fract(local.x * 0.42) - 0.5) * 2.0;
	vec2 cell = vec2(local.x * 0.42 + zig_x * 0.13, local.z * 0.23 + zig_z * 0.11);
	vec2 seam = abs(fract(cell) - 0.5);
	float joint = 1.0 - smoothstep(0.0, 0.026, min(seam.x, seam.y));
	float panel = hash12(floor(cell) + floor(local.y * 1.7) * 7.0);

	float streak = texture(grain, vec2(local.x * 1.1 + local.y * 0.7, local.z * 0.09)).r;
	float blotch = texture(grain, local.xz * 0.16 + local.y * 0.11).r;
	float fine = texture(grain, local.xz * 2.3 + local.y * 1.9).r;
	float top = smoothstep(-0.2, 0.6, normal_world.y);
	float grime = clamp((streak - 0.52) * 2.2, 0.0, 1.0) * 0.26 + (0.5 - blotch) * 0.10;

	vec3 paint = base_tint;
	if (use_livery) paint = texture(livery, UV).rgb * base_tint * 4.4;
	paint *= 1.0 - grime * wear * mix(1.0, 0.7, top);
	paint *= mix(0.93, 1.06, panel);
	paint *= 1.0 - joint * 0.22;
	paint = mix(paint, paint * vec3(1.07, 1.0, 0.92), top * 0.45);

	// A tight grazing band: a satin sheen that hugs the creases, not a wash
	// that turns the whole upper surface into a mirror.
	float fresnel = pow(1.0 - clamp(dot(normal_world, view_world), 0.0, 1.0), 6.0);
	vec3 refl = reflect(-view_world, normal_world);
	vec3 sky = mix(mirror_low, sky_high, smoothstep(0.02, 0.55, refl.y));
	sky = mix(ground_tint, sky, smoothstep(-0.22, 0.06, refl.y));
	float gloss = mix(0.70, 1.0, panel) * (1.0 - grime * 0.45);

	ALBEDO = paint;
	// A black jet is drawn by its specular, not by its albedo: a harder metal
	// response makes the sun and the fill light carve the creases instead of
	// lifting the paint toward grey.
	//
	// One place that backfires: a FLAT UPPER SURFACE SEEN EDGE-ON. Head-on, the
	// whole forebody deck is grazing at once, and the sun + fill specular lobe
	// smears across all of it and renders a pale silver saucer no matter how
	// black the albedo is. Measured on the deck at head-on: 0.215 luminance
	// against 0.073 for the wing upper surface and 0.165 for the sunlit ground
	// BEHIND it -- the nose was brighter than its own backdrop and read as a
	// smooth pale dome. Forcing EMISSION and RIM to zero moved it by 0.001, so
	// it is the direct specular and nothing else. The matting is therefore
	// gated on BOTH facing up AND being grazed, which is exactly that case and
	// no other: from the chase camera the same deck is seen closer to face-on
	// and keeps its satin. The gate is squared rather than cubed and the matted
	// end points are pushed down, because at a cube the gate only reached 0.73
	// in the very case it exists for. Head-on the forebody deck now measures
	// 0.067-0.080 against 0.161 for the sunlit ground behind it: a dark shape on
	// a bright backdrop instead of a pale dome that matched it.
	float upward = smoothstep(0.30, 0.90, normal_world.y);
	float flat_graze = upward * pow(1.0 - clamp(dot(normal_world, view_world), 0.0, 1.0), 2.0);
	METALLIC = mix(0.40, 0.06, flat_graze) * spec_scale;
	SPECULAR = mix(0.45, 0.06, flat_graze) * spec_scale;
	// Satin by default; individual panels polish, seams and grime go matt. This
	// is the panel-to-panel sheen variation that stops the skin reading as one
	// flat plastic shell.
	// Upper surfaces bake matt in the sun; flanks keep the satin that mirrors
	// the horizon, which is where the aircraft needs its edge highlight.
	float baked = upward * 0.11 + flat_graze * 0.38;
	float rough = clamp(0.42 + rough_bias + baked + (panel - 0.5) * 0.11 + (blotch - 0.5) * 0.14 + (fine - 0.5) * 0.06 + grime * 0.22 + joint * 0.16, 0.24, 0.98);
	ROUGHNESS = rough;
	// A lit edge separates the aircraft from ground and sky, but a full-strength
	// untinted rim under the effects fill light blows flat side panels out to
	// white, so it is tinted toward the paint and eased off where the skin is
	// already being grazed flat-on.
	RIM = mix(0.50, 0.24, flat_graze) * rim_scale;
	RIM_TINT = 0.35;
	// Polished panels throw a sharp sheen, matt ones barely any: the same
	// variation that makes real panel work readable on a black aircraft. The
	// square on gloss is what keeps the matt majority black -- only the polished
	// panels catch the mirror, so the sheen reads as panel work rather than as a
	// wash painted over the whole airframe.
	// Flat upper surfaces mirror the sky straight back at a chase camera and melt
	// into sunlit ground; the flanks and creases are where the sheen earns its
	// keep, so the upward-facing share is held down.
	float down = smoothstep(0.30, 0.90, -normal_world.y);
	EMISSION = sky * fresnel * sheen * gloss * gloss * (1.12 - rough) * 1.15 * (1.0 - upward * 0.45) * (1.0 - flat_graze * 0.48);
	EMISSION += under_bounce * down * 0.30;
}
