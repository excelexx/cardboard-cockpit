shader_type spatial;
// Cover glass over the panoramic display. Purely additive and deliberately
// faint: the display has to stay readable, but a screen with no reflection at
// all reads as a decal pasted on the panel rather than glass in a recess.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 sun_view = vec3(-0.5, 0.4, -0.75);
uniform vec3 sky_tint : source_color = vec3(0.34, 0.45, 0.62);
uniform vec3 sun_color : source_color = vec3(1.0, 0.80, 0.58);
uniform float strength = 1.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 ray = normalize(VERTEX);
	float facing = clamp(abs(dot(n, -ray)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 5.0);
	// The coaming's own reflection: a soft wash toward the top of the glass.
	float hood = smoothstep(0.62, 0.0, UV.y) * 0.055;
	float glint = pow(max(dot(reflect(ray, n), normalize(sun_view)), 0.0), 120.0);
	vec3 light = sky_tint * (fresnel * 0.38 + hood) + sun_color * glint * 0.45;
	ALBEDO = light * strength;
}
