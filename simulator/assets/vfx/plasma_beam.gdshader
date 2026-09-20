shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Continuous plasma beam.
//
// The mesh is a flat strip along local +Y that combat_visuals.gd stretches to
// the shot length; the vertex stage turns it into a ribbon that always faces
// the camera around the beam axis. That matters: a cylinder mesh goes dark when
// you look down its length - exactly the chase view the player flies in - while
// a ribbon gives the true chord through the column from any angle.
//
// Every pattern is computed from METRES ALONG THE BEAM, recovered from
// MODEL_MATRIX, never from the stretched UVs, so a 1900 m shot keeps its detail
// instead of smearing. The colour is one smooth periodic palette sampled by
// (distance - time * flow): violet, magenta, gold and cyan bands hundreds of
// metres long all sit on the beam at once and flow toward the target. Every
// layer samples the SAME palette at the same distance, so core, braid and halo
// always agree.

uniform int layer = 0;            // 0 white-hot core, 1 braided sheath, 2 outer halo
uniform float radius = 0.1;       // half width in metres at close range
uniform float phase = 0.0;
uniform float min_width = 0.0022; // keeps the beam a few pixels wide at any range
uniform float intensity = 1.0;
uniform float wavelength = 210.0; // metres per full palette cycle
uniform float flow_speed = 330.0; // metres/second toward the target
uniform float wobble_amount = 1.0;
uniform vec3 hue_violet : source_color = vec3(0.46, 0.10, 1.00);
uniform vec3 hue_magenta : source_color = vec3(1.00, 0.12, 0.66);
uniform vec3 hue_gold : source_color = vec3(1.00, 0.70, 0.14);
uniform vec3 hue_cyan : source_color = vec3(0.08, 0.92, 1.00);

varying float v_along;
varying float v_len;
varying float v_u;
varying float v_axial;

vec3 palette(float t) {
	float f = fract(t) * 4.0;
	int i = int(f);
	float k = f - float(i);
	k = k * k * (3.0 - 2.0 * k);
	vec3 a = i == 0 ? hue_violet : (i == 1 ? hue_magenta : (i == 2 ? hue_gold : hue_cyan));
	vec3 b = i == 0 ? hue_magenta : (i == 1 ? hue_gold : (i == 2 ? hue_cyan : hue_violet));
	return mix(a, b, k);
}

// Two cycles at different rates keep several hues on screen at once and stop
// the gradient reading as a mechanical repeat.
vec3 flowing_tint(float along) {
	float s = (along - TIME * flow_speed) / wavelength;
	vec3 base = palette(s);
	vec3 second = palette(s * 2.7 + 0.37);
	return normalize(mix(base, second, 0.34) + 0.0001);
}

// Lateral snake of the whole column, in metres. Phase-free on purpose: every
// layer has to snake together or the beam comes apart into ribbons.
vec2 wobble(float along) {
	float a = along * 0.021 - TIME * 2.4;
	float b = along * 0.0073 + TIME * 1.35;
	float c = along * 0.052 - TIME * 5.1;
	float envelope = smoothstep(0.0, 26.0, along) * wobble_amount;
	return vec2(sin(a) * 0.34 + sin(c) * 0.09 + cos(b) * 0.5,
	            cos(a * 1.17) * 0.32 + cos(c * 0.83) * 0.08 + sin(b * 0.9) * 0.46) * envelope;
}

void vertex() {
	float blen = length(MODEL_MATRIX[1].xyz);
	float along = (VERTEX.y + 0.5) * blen;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, VERTEX.y, 0.0, 1.0)).xyz;
	vec3 reference = abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 u1 = normalize(cross(axis, reference));
	vec3 u2 = cross(axis, u1);
	vec2 snake = wobble(along);
	centre += u1 * snake.x + u2 * snake.y;
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(axis, to_eye);
	float sl = length(side);
	side = sl > 0.0005 ? side / sl : u1;
	float dist = length(centre);
	float half_w = max(radius, dist * min_width);
	v_along = along;
	v_len = blen;
	v_u = UV.x * 2.0 - 1.0;
	v_axial = abs(dot(axis, to_eye));
	VERTEX = centre + side * v_u * half_w;
	NORMAL = to_eye;
}

void fragment() {
	// Exact chord through a cylinder of unit radius: brightest through the
	// axis, zero at the edge. This is what makes it read as plasma, and it
	// holds up whether the beam crosses the screen or comes straight at you.
	float chord = sqrt(max(1.0 - v_u * v_u, 0.0));
	// Looking down the beam, the line of sight stays inside the column much
	// longer, so it gets denser rather than disappearing.
	float stretch = 1.0 / sqrt(max(1.0 - v_axial * v_axial, 0.035));
	float along = v_along;
	vec3 tint = flowing_tint(along);
	// Angle around the column that this part of the ribbon stands for, front
	// and back, so helical strands still wrap the way they should.
	float front = asin(clamp(v_u, -1.0, 1.0));
	float back = 3.14159265 - front;

	// Never start inside the muzzle, never overshoot the impact point.
	float ends = smoothstep(0.0, 5.0, along) * (1.0 - smoothstep(v_len - 2.5, v_len - 0.2, along));

	vec3 emitted = vec3(0.0);

	if (layer == 0) {
		// White-hot filament. The palette only bleeds into its shoulders.
		float density = pow(chord, 2.4) * min(stretch, 2.2);
		float packet = pow(0.5 + 0.5 * sin(along * 0.34 - TIME * 42.0 + phase), 5.0);
		float fine = pow(0.5 + 0.5 * sin(along * 1.9 - TIME * 150.0), 3.0);
		float flicker = 0.88 + 0.12 * sin(TIME * 63.0 + along * 0.6);
		vec3 hot = mix(tint * 1.70, vec3(1.0, 0.985, 0.96), 0.16 + 0.44 * pow(chord, 2.2));
		emitted = hot * (0.85 + packet * 2.0 + fine * 0.7) * density * flicker;
	} else if (layer == 1) {
		// Counter-wound plasma strands with turbulence flowing to the target.
		float density = pow(chord, 0.85) * min(stretch, 1.8);
		float turb = sin(along * 0.19 - TIME * 8.0 + phase) * 0.55
		           + sin(along * 0.061 + TIME * 3.2) * 0.9;
		float helix = cos(front * 3.0 - along * 0.30 + TIME * 7.5 + turb + phase);
		float helix_back = cos(back * 3.0 - along * 0.30 + TIME * 7.5 + turb + phase);
		float counter = cos(front * 4.0 + along * 0.21 - TIME * 5.2 - turb * 0.6);
		float strand = pow(max(helix, 0.0), 9.0) + 0.55 * pow(max(helix_back, 0.0), 9.0)
		             + 0.7 * pow(max(counter, 0.0), 13.0);
		float sheet = pow(0.5 + 0.5 * sin(along * 0.9 - TIME * 60.0), 4.0);
		emitted = tint * (0.95 + strand * 3.6 + sheet * 1.1) * density;
		emitted += vec3(1.0, 0.96, 0.92) * strand * density * 0.40;
	} else {
		// Soft halo: keeps the beam readable against bright sky without a veil.
		float density = pow(chord, 1.25) * min(stretch, 1.5);
		float breath = 0.75 + 0.25 * sin(along * 0.05 - TIME * 4.2 + phase);
		emitted = tint * density * breath * 1.05;
	}

	ALBEDO = emitted * ends * intensity;
	ALPHA = 1.0;
}
