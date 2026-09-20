shader_type spatial;
// Refraction behind the nozzle: the exhaust column bends what is behind it. Quad local
// +X runs aft along the plume. The mask hugs the column so the distortion never becomes
// a milky sheet over the view, and the offsets are pure refraction - nothing is added.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D screen_copy : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float power = 0.0;
void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float v = UV.y * 2.0 - 1.0;
	float across = smoothstep(1.0, 0.12, abs(v));
	float along = smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.40, u);
	float mask = across * along;
	float cell = texture(noise, vec2(u * 2.2 - TIME * 1.35, v * 1.1 + TIME * 0.22)).r;
	float fine = texture(noise, vec2(u * 5.4 - TIME * 3.10, v * 2.6 - TIME * 0.50)).r;
	vec2 shift = vec2((cell - 0.5) * 1.6 + (fine - 0.5) * 0.9,
	                  (fine - 0.5) * 1.9 + (cell - 0.5) * 0.8) * 0.0042 * power * mask;
	ALBEDO = textureLod(screen_copy, SCREEN_UV + shift, 0.0).rgb;
	ALPHA = mask * power * 0.30;
}
