shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
// Billboard bloom used for muzzle coronas, impact flashes, plasma contact
// coronas and kill shockwaves. mode: 0 flash, 1 expanding ring, 2 sizzling
// corona. Driven by "t" (0..1) so nothing has to tick it per frame.

uniform int mode = 0;
uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float size = 1.0;
uniform float grow = 1.0;          // final size multiple at t=1
uniform float intensity = 1.0;
uniform float spokes = 6.0;
uniform float spin = 0.0;
uniform float loop = 0.0;   // 1 = a continuous corona driven by TIME, no fade
uniform vec3 core_colour : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 edge_colour : source_color = vec3(1.0, 0.48, 0.12);

varying vec2 v_uv;

void vertex() {
	float scale = size * mix(1.0, grow, pow(t, mode == 1 ? 0.55 : 0.75));
	// Camera-facing, ignoring the parent's own rotation.
	mat4 billboard = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz) * scale, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz) * scale, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * scale, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = billboard;
	v_uv = UV * 2.0 - 1.0;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.31, 289.11))) * 43758.5453);
}

void fragment() {
	float r = length(v_uv);
	float a = atan(v_uv.y, v_uv.x) + spin;
	float body = 0.0;
	vec3 colour = core_colour;

	if (mode == 0) {
		// Flash: hot core, soft halo, a few asymmetric spikes.
		float core = exp(-r * r * 15.0);
		float halo = exp(-r * r * 3.0) * 0.45;
		float spike = pow(max(cos(a * spokes + sin(a * 3.0) + TIME * 9.0 * loop), 0.0), 26.0) * exp(-r * 4.0) * 0.30;
		body = (core + halo + spike) * mix(pow(1.0 - t, 1.6), 0.85 + 0.15 * sin(TIME * 37.0), loop);
		colour = mix(edge_colour, core_colour, clamp(core * 1.6, 0.0, 1.0));
	} else if (mode == 1) {
		// Shockwave: a thin ring that expands and thins out.
		float radius = mix(0.18, 0.92, pow(t, 0.55));
		float thickness = mix(0.10, 0.035, t);
		float ring = exp(-pow((r - radius) / thickness, 2.0));
		float ripple = 0.75 + 0.25 * sin(a * 9.0 + t * 12.0);
		body = ring * ripple * pow(1.0 - t, 1.3);
		colour = mix(core_colour, edge_colour, smoothstep(0.0, 0.7, t));
	} else {
		// Corona: a turbulent sizzling disc with licking filaments.
		float anim = mix(t * 26.0, TIME * 11.0, loop);
		// Gentle licking, not a sea urchin.
		float lick = 0.88 + 0.12 * sin(a * 5.0 + anim + hash21(vec2(floor(a * 3.0), 1.0)) * 6.28);
		float edge = 0.30 + 0.34 * lick;
		float disc = 1.0 - smoothstep(edge * 0.35, edge, r);
		float fringe = exp(-pow((r - edge) / 0.22, 2.0)) * lick;
		float core = exp(-r * r * 22.0);
		body = (disc * 0.45 + fringe * 0.70 + core * 2.2) * mix(pow(1.0 - t, 1.25), 1.0, loop);
		colour = mix(edge_colour, core_colour, clamp(core * 1.5 + disc * 0.25, 0.0, 1.0));
	}

	float cut = 1.0 - smoothstep(0.92, 1.0, r);
	ALBEDO = colour * body * intensity * 2.2 * cut;
	ALPHA = 1.0;
}
