shader_type spatial;
// Canada goose plumage painted from model-space position, so the procedural
// mesh needs no texture: black bill, head and neck with the white chinstrap,
// pale breast, barred brown back and flanks, white rump, black tail. Wings are
// dark with pale feather edges and let a little low sun through.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform bool wing = false;
varying vec3 local;
void vertex() { local = VERTEX; }
void fragment() {
	vec3 black = vec3(0.012, 0.012, 0.014);
	vec3 white = vec3(0.80, 0.78, 0.72);
	vec3 brown = vec3(0.115, 0.080, 0.055);
	vec3 pale = vec3(0.40, 0.35, 0.29);
	float fibre = texture(grain, vec2(local.x * 0.9, local.z * 0.35)).r;
	vec3 colour;
	if (wing) {
		float span = abs(local.x);
		// Rows of feathers: coverts near the leading edge, long flight feathers behind.
		float rows = smoothstep(0.35, 0.5, fract(local.z * 2.6 + fibre * 0.25));
		float vanes = smoothstep(0.86, 1.0, abs(sin(span * 13.0 + local.z * 2.2 + fibre * 1.5)));
		colour = mix(brown * 1.05, brown * 0.38, smoothstep(-0.3, 0.5, local.z));
		colour = mix(colour, pale * 0.7, (1.0 - rows) * 0.22 * (1.0 - smoothstep(0.2, 0.7, local.z)));
		colour = mix(colour, black, vanes * 0.35 + smoothstep(2.0, 3.2, span) * 0.75);
		BACKLIGHT = vec3(0.16, 0.10, 0.05);
	} else {
		float z = local.z;
		float barring = smoothstep(0.30, 0.55, fract(z * 3.2 + fibre * 0.35 + abs(local.x) * 0.6));
		vec3 back = mix(brown * 0.85, brown * 1.35, barring);
		float belly = smoothstep(-0.12, -0.42, local.y);
		colour = mix(back, pale, belly * 0.8);
		colour = mix(colour, pale * 1.15, smoothstep(-0.70, -1.05, z) * smoothstep(0.30, -0.05, local.y));                 // breast
		colour = mix(colour, white, smoothstep(1.05, 1.2, z) * (1.0 - smoothstep(1.42, 1.5, z)) + belly * smoothstep(0.7, 1.2, z)); // rump, vent
		colour = mix(colour, black, smoothstep(1.42, 1.52, z));                       // tail
		colour = mix(colour, black, smoothstep(-1.22, -1.38, z));                     // neck, head, bill
		float strap = smoothstep(-2.78, -2.86, z) * (1.0 - smoothstep(-3.10, -3.16, z)) * smoothstep(0.27, 0.20, local.y) * smoothstep(0.035, 0.075, abs(local.x));
		colour = mix(colour, white * 1.1, strap);
		float eye = 1.0 - smoothstep(0.018, 0.028, distance(vec3(abs(local.x), local.y, z), vec3(0.128, 0.245, -3.03)));
		colour = mix(colour, vec3(0.002), eye);
		ROUGHNESS = mix(0.9, 0.18, eye);
	}
	ALBEDO = colour * (0.85 + fibre * 0.3);
	if (wing) { ROUGHNESS = 0.88; }
	SPECULAR = 0.10;
	RIM = 0.10;        // faint feather sheen against the sky
	RIM_TINT = 0.9;
}
