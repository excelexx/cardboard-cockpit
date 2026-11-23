shader_type spatial;
// SPECTRE X-26 canopy: a gold-tinted conductive film over the transparency.
//
// A StandardMaterial3D cannot do this. A gold metal gets its colour from F0,
// and Schlick drives F toward white at grazing angles -- which is exactly the
// angle a canopy is usually seen at, so a "gold" canopy renders powder blue the
// moment it is not facing you. Adding a clearcoat made it worse: a second,
// untinted specular lobe on top. Here the mirror is analytic and the film
// multiplies it, so every angle returns gold.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 film : source_color = vec3(0.92, 0.64, 0.24);
uniform vec3 sky_high : source_color = vec3(0.30, 0.40, 0.62);
uniform vec3 mirror_low : source_color = vec3(0.42, 0.35, 0.30);
uniform vec3 ground_tint : source_color = vec3(0.085, 0.072, 0.058);
uniform vec3 interior : source_color = vec3(0.014, 0.013, 0.015);
uniform float strength = 0.50;
uniform float floor_mix = 0.22;   // the film still returns gold face-on

void fragment() {
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = clamp(dot(normal_world, view_world), 0.0, 1.0);
	float grazing = pow(1.0 - facing, 3.0);
	vec3 refl = reflect(-view_world, normal_world);
	vec3 sky = mix(mirror_low, sky_high, smoothstep(0.0, 0.50, refl.y));
	sky = mix(ground_tint, sky, smoothstep(-0.25, 0.05, refl.y));
	// Dark from outside: the cockpit behind the glass swallows almost everything
	// the film lets through.
	ALBEDO = interior;
	METALLIC = 0.0;
	SPECULAR = 0.22;
	ROUGHNESS = 0.17;
	RIM = 0.25;
	RIM_TINT = 1.0;
	EMISSION = sky * film * mix(floor_mix, 1.0, grazing) * strength;
}
