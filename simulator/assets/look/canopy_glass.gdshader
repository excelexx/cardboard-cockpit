shader_type spatial;
// Fighter canopy seen from the pilot's seat. Real acrylic is almost invisible
// head-on and shows itself three ways: sky reflecting at grazing angles, a hard
// sun glint sliding over the curve, and fine scratches that flare when the
// pilot looks toward the sun. All three are added light, so the pass is additive.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D scratches : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_view = vec3(0.0, 0.4, -0.9);   // direction to the sun, view space
uniform vec3 sun_color : source_color = vec3(1.0, 0.78, 0.55);
uniform vec3 sky_color : source_color = vec3(0.42, 0.55, 0.72);
uniform float strength = 1.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 ray = normalize(VERTEX);              // eye -> glass, view space
	vec3 to_sun = normalize(sun_view);
	float facing = abs(dot(n, -ray));
	float fresnel = pow(1.0 - facing, 4.0);
	float glint = pow(max(dot(reflect(ray, n * sign(dot(n, -ray))), to_sun), 0.0), 220.0);
	float toward_sun = pow(max(dot(ray, to_sun), 0.0), 5.0);
	float fine = texture(scratches, UV * vec2(9.0, 5.0)).r;
	float haze = texture(scratches, UV * vec2(1.7, 1.1) + 0.31).r;
	float scratch = smoothstep(0.62, 0.95, fine) * 0.55 + haze * 0.10;
	vec3 light = sky_color * fresnel * 0.22
		+ sun_color * (glint * 1.6 + toward_sun * scratch * 0.55 + toward_sun * 0.035);
	ALBEDO = light * strength;
}
