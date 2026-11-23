shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// One 25 mm round in flight. The mesh is a flat strip along local Z that the
// vertex stage turns into an axis-aligned billboard, so every round reads as a
// LINE from any angle instead of a blob, and one shared mesh + one shared
// material serve every live shot (combat.gd stretches scale.z as the round
// clears the muzzle - that stretch is picked up from MODELVIEW).
//
// The strip is lofted from AHEAD of the round (UV.y goes slightly negative) so
// the whole incandescent head gaussian sits inside the geometry: the nose
// tapers off in an ogive instead of being cropped flat by the leading vertex.
//
// One mesh can carry several copies of the strip, offset along Z, so a single
// draw call paints a live round plus its visual-only ghost rounds and the burst
// reads as a 55-60 rounds/s ladder. UV2.x is that copy's own head offset in
// object Z, UV2.y a per-copy seed.

uniform float width = 0.075;        // half width at the shoulder, metres
uniform float min_width = 0.0016;   // radians-ish: keeps a distant round a few pixels wide
uniform float head_z = -1.6;        // object z of the round itself
uniform float head_radius = 0.34;   // metres, the incandescent head
uniform float nose_uv = 0.0494;     // how far UV.y runs negative ahead of the head
uniform float intensity = 1.0;
uniform float range_gain = 2.2;     // extra brightness at range_full metres
uniform float range_full = 700.0;
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
varying float v_gain;

void vertex() {
	float zscale = length(MODELVIEW_MATRIX[2].xyz);
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(axis, to_eye);
	float len = length(side);
	side = len > 0.0005 ? side / len : normalize(cross(axis, vec3(0.0, 1.0, 0.0)));

	// UV.y is 0 at this copy's head and 1 at the end of its streak; it is
	// NEGATIVE over the nose lofted ahead of the head.
	float t = UV.y;
	float tail = clamp(t, 0.0, 1.0);
	// Monotonic taper: widest at the round, finest at the end of the streak. Any
	// flare at the head turns the tracer into a trumpet bell.
	float profile = mix(1.0, 0.13, pow(tail, 0.72));
	// Elliptical ogive over the nose, so the leading end rounds off to a point
	// instead of stopping at a flat-cropped bar. Exactly 1.0 from the head back,
	// so there is no width step at the head-to-tail junction.
	float run = clamp(1.0 + t / max(nose_uv, 0.0001), 0.0, 1.0);
	profile *= sqrt(max(run * (2.0 - run), 0.0));
	float w = max(width, length(centre) * min_width) * profile;

	v_t = tail;
	v_side = UV.x * 2.0 - 1.0;
	// Distance from THIS copy's own head, in metres, so every round in the mesh
	// gets its own incandescent tip.
	v_axial = (VERTEX.z - (head_z + UV2.x)) * zscale;
	v_width = w;
	v_seed = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.0173, 0.0411, 0.0269)) + UV2.y * 0.3797);
	// Against a bright sunset an additive streak two stops over the sky just
	// dissolves; lift it with range so the far end of the burst still reads.
	v_gain = 1.0 + range_gain * smoothstep(0.0, range_full, length(centre));

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

	float glow = streak * 3.4 + head * 6.0;
	ALBEDO = mix(colour, head_colour, clamp(head * 1.4, 0.0, 1.0)) * glow * intensity * flicker * v_gain;
	ALPHA = 1.0;
}
