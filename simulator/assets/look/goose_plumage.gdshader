shader_type spatial;
// Canada goose plumage painted from model-space position, so the procedural
// mesh needs no texture: black bill, head and neck with the white chinstrap,
// pale breast, barred brown back and flanks, white rump, black tail. Wings are
// dark with pale feather edges and let a little low sun through.
//
// ONE material is shared by the entire flock (see systems/goose_model.gd), so
// everything that varies per bird arrives as an INSTANCE uniform. Duplicating
// this material per goose would break batching across the skein.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform bool wing = false;
// 0 = untouched, 1 = badly hit. Thins the wing vanes and soots a patch:
// feathers shed, they do not crack like armour plate.
instance uniform float damage : hint_range(0.0, 1.0) = 0.0;
// Spanwise wing flex, metres at the tip. Driven from the wing's angular
// velocity so the tips lag the roots through a beat instead of the whole
// surface rotating like a rigid plank.
instance uniform float flex = 0.0;
const float SPAN = 3.30;
varying vec3 local;
varying float tipward;

void vertex() {
	local = VERTEX;
	if (wing) {
		float s = clamp(abs(VERTEX.x) / SPAN, 0.0, 1.0);
		tipward = s;
		// Quadratic in span: the shoulder holds station, the primaries trail.
		VERTEX.y += flex * s * s;
		// A whipped tip also washes out (twists nose-down), which is what makes
		// the outer feathers separate on the downstroke.
		VERTEX.z += flex * s * s * 0.22;
	} else {
		tipward = 0.0;
	}
}

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
		// Damage widens the gaps between vanes: the wing goes ragged and darker
		// toward the trailing edge, where primaries are lost first.
		float shed = damage * smoothstep(0.1, 0.8, local.z) * smoothstep(0.25, 0.95, tipward);
		colour = mix(colour, black, vanes * (0.35 + damage * 0.40) + smoothstep(2.0, 3.2, span) * 0.75);
		colour = mix(colour, black * 1.6, shed * 0.65);
		BACKLIGHT = vec3(0.16, 0.10, 0.05) * (1.0 - shed * 0.5);
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
		// Cheek patch, widened about 20% over the first pass: at the flock's
		// working range it is the one mark that says "Canada goose" rather than
		// "dark bird", so it has to survive a 600 m read.
		float strap = smoothstep(-2.74, -2.83, z) * (1.0 - smoothstep(-3.13, -3.20, z)) * smoothstep(0.30, 0.22, local.y) * smoothstep(0.030, 0.070, abs(local.x));
		colour = mix(colour, white * 1.1, strap);
		float eye = 1.0 - smoothstep(0.018, 0.028, distance(vec3(abs(local.x), local.y, z), vec3(0.128, 0.245, -3.03)));
		colour = mix(colour, vec3(0.002), eye);
		// Sooted flank where the rounds went through.
		colour *= 1.0 - 0.40 * damage * smoothstep(-0.9, 0.4, z) * smoothstep(0.35, -0.1, local.y);
		ROUGHNESS = mix(0.9, 0.18, eye);
	}
	ALBEDO = colour * (0.85 + fibre * 0.3);
	if (wing) { ROUGHNESS = 0.88; }
	SPECULAR = 0.10;
	// Feather sheen. Model-space and therefore scale independent, so the
	// silhouette still holds at the flock's working range. Kept weak and tinted
	// all the way to the albedo so the edge never picks up a cold sky-blue
	// halo; the warmth comes from the emission term below, on the sun side.
	RIM = 0.06;
	RIM_TINT = 1.0;
	float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.34, 0.22, 0.09) * edge * 0.16;
}
