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
uniform vec3 sky_low : source_color = vec3(0.86, 0.66, 0.47);
uniform vec3 ground_tint : source_color = vec3(0.075, 0.068, 0.058);
uniform float sheen = 1.0;

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
	float top = smoothstep(-0.2, 0.6, local_normal.y);
	float grime = clamp((streak - 0.52) * 2.2, 0.0, 1.0) * 0.26 + (0.5 - blotch) * 0.10;

	vec3 paint = base_tint;
	if (use_livery) paint = texture(livery, UV).rgb * base_tint * 4.4;
	paint *= 1.0 - grime * wear * mix(1.0, 0.7, top);
	paint *= mix(0.93, 1.06, panel);
	paint *= 1.0 - joint * 0.22;
	paint = mix(paint, paint * vec3(1.07, 1.0, 0.92), top * 0.45);

	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// A tight grazing band: a satin sheen that hugs the creases, not a wash
	// that turns the whole upper surface into a mirror.
	float fresnel = pow(1.0 - clamp(dot(normal_world, view_world), 0.0, 1.0), 7.0);
	vec3 refl = reflect(-view_world, normal_world);
	vec3 sky = mix(sky_low, sky_high, smoothstep(0.02, 0.55, refl.y));
	sky = mix(ground_tint, sky, smoothstep(-0.22, 0.06, refl.y));
	float gloss = mix(0.70, 1.0, panel) * (1.0 - grime * 0.45);

	ALBEDO = paint;
	METALLIC = 0.26;
	SPECULAR = 0.30;
	// Satin by default; individual panels polish, seams and grime go matt. This
	// is the panel-to-panel sheen variation that stops the skin reading as one
	// flat plastic shell.
	// Upper surfaces bake matt in the sun; flanks keep the satin that mirrors
	// the horizon, which is where the aircraft needs its edge highlight.
	float upward = smoothstep(0.30, 0.90, local_normal.y);
	float baked = upward * 0.13;
	float rough = clamp(0.42 + baked + (panel - 0.5) * 0.11 + (blotch - 0.5) * 0.14 + (fine - 0.5) * 0.06 + grime * 0.22 + joint * 0.16, 0.24, 0.84);
	ROUGHNESS = rough;
	// A lit edge separates the aircraft from ground and sky, but a full-strength
	// rim under the effects fill light blows flat side panels out to white.
	RIM = 0.50;
	RIM_TINT = 0.30;
	// Polished panels throw a sharp sheen, matt ones barely any: the same
	// variation that makes real panel work readable on a black aircraft.
	// Flat upper surfaces mirror the sky straight back at a chase camera and melt
	// into sunlit ground; the flanks and creases are where the sheen earns its
	// keep, so the upward-facing share is held down.
	EMISSION = sky * fresnel * sheen * gloss * (1.12 - rough) * 1.25 * (1.0 - upward * 0.5);
}
