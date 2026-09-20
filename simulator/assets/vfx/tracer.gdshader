shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// One 25 mm round in flight. The mesh is a flat strip along local Z that the
// vertex stage turns into an axis-aligned billboard, so every round reads as a
// LINE from any angle instead of a blob, and one shared mesh + one shared
// material serve every live shot (combat.gd stretches scale.z as the round
// clears the muzzle - that stretch is picked up from MODELVIEW).

uniform float width = 0.075;        // half width at the shoulder, metres
uniform float min_width = 0.0016;   // radians-ish: keeps a distant round a few pixels wide
uniform float head_z = -1.6;        // object z of the round itself
uniform float head_radius = 0.34;   // metres, the incandescent head
uniform float intensity = 1.0;
uniform float flicker_rate = 120.0;
uniform vec3 head_colour : source_color = vec3(1.0, 0.97, 0.88);
uniform vec3 mid_colour : source_color = vec3(1.0, 0.62, 0.16);
uniform vec3 tail_colour : source_color = vec3(0.85, 0.12, 0.03);
uniform float tail_power = 1.05;

varying float v_t;
varying float v_side;
varying float v_axial;
varying float v_width;
varying float v_seed;

void vertex() {
	float zscale = length(MODELVIEW_MATRIX[2].xyz);
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(axis, to_eye);
	float len = length(side);
	side = len > 0.0005 ? side / len : normalize(cross(axis, vec3(0.0, 1.0, 0.0)));

	float t = UV.y;
	// Monotonic taper: widest at the round, finest at the end of the streak. Any
	// flare at the head turns the tracer into a trumpet bell.
	float profile = mix(1.0, 0.13, pow(t, 0.72));
	float w = max(width, length(centre) * min_width) * profile;

	v_t = t;
	v_side = UV.x * 2.0 - 1.0;
	v_axial = (VERTEX.z - head_z) * zscale;
	v_width = w;
	v_seed = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.0173, 0.0411, 0.0269)));

	VERTEX = centre + side * v_side * w;
	NORMAL = to_eye;
}

void fragment() {
	float across = exp(-v_side * v_side * 3.4);
	float streak = across * pow(max(1.0 - v_t, 0.0), tail_power) * (0.35 + 0.65 * exp(-v_t * 2.2));
	// Round incandescent head, measured in metres so it stays a dot, not a slab.
	float r2 = v_axial * v_axial + (v_side * v_width) * (v_side * v_width);
	float head = exp(-r2 / (head_radius * head_radius));

	vec3 colour = mix(head_colour, mid_colour, smoothstep(0.02, 0.26, v_t));
	colour = mix(colour, tail_colour, smoothstep(0.26, 0.85, v_t));
	float flicker = 0.82 + 0.18 * sin(TIME * flicker_rate + v_seed * 62.8);

	float glow = streak * 2.2 + head * 5.5;
	ALBEDO = mix(colour, head_colour, clamp(head * 1.4, 0.0, 1.0)) * glow * intensity * flicker;
	ALPHA = 1.0;
}
