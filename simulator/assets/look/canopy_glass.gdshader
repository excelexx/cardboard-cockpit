shader_type spatial;
// Fighter canopy seen from the pilot's seat.
//
// Real acrylic with a gold indium-tin-oxide film is almost invisible head-on and
// announces itself two ways: a whisper of warmth through the film, and the sky
// reflecting hard at grazing angles near the rails and the bow. It is blended,
// not added, so the tint never brightens the view; alpha is about one per cent
// straight ahead and only climbs where the glass turns away from the eye.
//
// There is no scratch layer. Scratches lit by a sun term flared into dashes
// across the forward view, which is the one thing that must stay clean.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 sun_view = vec3(0.0, 0.4, -0.9);
uniform vec3 sun_color : source_color = vec3(1.0, 0.80, 0.58);
uniform vec3 sky_color : source_color = vec3(0.40, 0.53, 0.74);
uniform vec3 gold : source_color = vec3(1.0, 0.80, 0.46);
uniform float strength = 1.0;
uniform float max_alpha = 0.42;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 ray = normalize(VERTEX);
	float facing = clamp(abs(dot(n, -ray)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.2);
	float glint = pow(max(dot(reflect(ray, n * sign(dot(n, -ray))), normalize(sun_view)), 0.0), 170.0);
	// Path length through the film grows as the glass turns away from the eye.
	float film = (1.0 - facing) * 0.26 + 0.030;
	// UV.y runs 0 at the rear hoop to 1 at the nose: the windscreen ahead of the
	// bow is where a reflection would sit on the horizon, so it stays quiet.
	float forward = mix(1.0, 0.0, smoothstep(0.32, 0.80, UV.y));
	// UV.x runs rail to rail over the arch. Fade every cut edge right out, glint
	// included, or the shell ends in a hard diagonal across the sky.
	forward *= smoothstep(0.0, 0.20, UV.x) * smoothstep(1.0, 0.80, UV.x);
	vec3 colour = mix(gold, sky_color, clamp(fresnel * 1.5, 0.0, 1.0));
	colour += sun_color * glint * 2.2;
	float alpha = clamp(film * 0.32 + fresnel * 0.46 + glint * 0.55, 0.0, max_alpha);
	ALPHA = alpha * forward * strength;
	ALBEDO = colour;
}
