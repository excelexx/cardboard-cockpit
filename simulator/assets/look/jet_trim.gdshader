shader_type spatial;
// Edge trim. The ribbon meshes carry their colour per vertex: gold along the
// real creases. Alpha is how hot the strip glows, so one material serves both a
// lit metal strip and matt paint.
//
// A 40-60 mm strip is nearly always seen at a grazing angle, and that is where
// a PBR gold dies. Schlick drives F toward WHITE as the view grazes, whatever
// F0 is, so METALLIC 0.78 / SPECULAR 0.90 rendered the chine pinstripe as a
// neutral white line: measured peak (0.576, 0.541, 0.502) head-on, blue/red
// 0.87 on a strip whose own blue/red is 0.13. RIM_TINT cannot help, because the
// offender is the specular lobe, not the rim.
//
// So the trim does what the canopy does: it turns the engine's untinted lobes
// OFF (metallic 0, specular 0, rim 0) and rolls its own mirror, multiplied by
// the strip's colour. Every angle now returns gold, and the diffuse term under
// the low sun keeps it a warm metal rather than a decal.
render_mode diffuse_burley, specular_schlick_ggx;

// Intensity is part of the colour here. AgX desaturates the bright end hard,
// so a strip that reaches sRGB (0.965, 0.678, 0.345) reads cream even though
// its LINEAR blue/red is a correct 0.106; pulling the whole strip down about
// 40% keeps the same gold through the tonemapper.
uniform float energy = 0.14;
uniform vec3 sky_high : source_color = vec3(0.26, 0.35, 0.54);
uniform vec3 mirror_low : source_color = vec3(0.38, 0.33, 0.31);
uniform vec3 ground_tint : source_color = vec3(0.085, 0.072, 0.056);
uniform float mirror = 0.62;

void fragment() {
	vec3 gold = COLOR.rgb;
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = clamp(dot(normal_world, view_world), 0.0, 1.0);
	float grazing = pow(1.0 - facing, 2.6);
	vec3 refl = reflect(-view_world, normal_world);
	vec3 sky = mix(mirror_low, sky_high, smoothstep(0.0, 0.50, refl.y));
	sky = mix(ground_tint, sky, smoothstep(-0.25, 0.05, refl.y));

	ALBEDO = gold * 0.24;
	METALLIC = 0.0;
	SPECULAR = 0.0;       // no untinted dielectric lobe anywhere, at any angle
	ROUGHNESS = 0.48;
	RIM = 0.0;
	// The mirror is multiplied by the strip's own colour, so the grazing case
	// -- the one that used to go white -- is the one that goes MOST gold.
	EMISSION = sky * gold * mix(0.40, 0.98, grazing) * mirror + gold * COLOR.a * energy;
}
