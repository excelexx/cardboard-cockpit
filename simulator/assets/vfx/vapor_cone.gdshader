shader_type spatial;
// Condensation that HUGS the airframe - never a veil across the screen.
// mode 0: the transonic shock cloud (Prandtl-Glauert). A cone whose apex sits forward and
//         which opens aft over the rear fuselage; it blooms across Mach 1 and dissolves
//         once the jet is clearly supersonic. Drawn as a thin rim-lit membrane so it reads
//         as a shell of vapour, not a fog card.
// mode 1: the wing/LERX sheet under G - a shallow blister of cloud lying on the wing upper
//         surface, torn into wisps so its edges never form a hard card.
// mode 2: a camera-facing wingtip-vortex puff. Procedural, because a photographic smoke
//         sprite shows its own square texture border once it is scaled up to 6 m.
// Lit by the scene's key light through a wrap term plus forward scatter, so the vapour
// takes the golden-hour colour instead of reading as flat grey paint.
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float amount = 0.0;         // 0..1 master gate (Mach band, or G)
uniform float humidity = 1.0;
uniform float ceiling = 0.50;       // hard alpha cap - the anti-veil guard
uniform float scroll = 0.0;
uniform float bulge = 0.55;
uniform float size = 1.0;           // mode 2 billboard half-height, metres
uniform float stretch = 1.0;        // mode 2: how much longer the puff is along the airframe axis
// Escape hatch only: mode 0 now normalises its own coordinate (see `v` below), so nothing
// has to set this. Left in because it is the cheapest way to invert the shell for a test.
uniform float flip_v = 0.0;
uniform float rim = 0.70;   // >1 collapses the shell to a thin rim: a membrane, not a card
uniform int mode = 0;
uniform vec3 light_dir = vec3(0.0, -0.2, -1.0);
uniform vec3 light_color : source_color = vec3(1.0, 0.88, 0.78);
uniform vec3 shade_color : source_color = vec3(0.66, 0.73, 0.84);
varying vec3 world_normal;
varying vec3 axis_view;
varying float sheet;

void vertex() {
	if (mode == 1) {
		float b = sin(UV.x * PI) * sin(UV.y * PI);
		VERTEX.y += b * bulge;
		NORMAL = normalize(vec3(-cos(UV.x * PI) * sin(UV.y * PI) * bulge,
		                        1.0,
		                        -sin(UV.x * PI) * cos(UV.y * PI) * bulge));
		sheet = b;
	} else {
		sheet = 1.0;
	}
	if (mode == 2) {
		// A vortex core is a ROPE, not a ball. This is an AXIS-ALIGNED billboard: the quad's
		// local X runs along the airframe's own aft axis (the node's basis is set to the
		// aircraft basis) and is `stretch` times longer than its width, so each puff is an
		// elongated wisp streaming off the tip. A plain camera-aligned square billboard is
		// what made these read as detached white orbs floating beside the jet.
		vec3 axis = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
		vec3 eye = normalize(INV_VIEW_MATRIX[2].xyz);
		vec3 side = cross(axis, eye);
		float grip = length(side);
		// Looking straight down the rope the cross product degenerates; fall back to the
		// camera's own right vector so the quad never collapses to a line.
		side = (grip < 0.02) ? normalize(INV_VIEW_MATRIX[0].xyz) : side / grip;
		vec3 look = normalize(cross(side, axis));
		mat4 billboard = mat4(vec4(axis * size * stretch, 0.0), vec4(side * size, 0.0),
		                      vec4(look * size, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The cone's own axis, in view space, for the broadside test in fragment().
	axis_view = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shell = pow(1.0 - facing, rim);
	// MODE 0 COORDINATE, measured not assumed: Godot's CylinderMesh SIDE surface gives UV.y
	// in [0, 0.5] (not [0, 1]) with UV.y = 0 at the TOP - the wide end. fighter_effects
	// rotates this cone by Basis(RIGHT, PI/2), which sends local +Y to +Z, i.e. AFT, so the
	// wide flare is aft and reads UV.y = 0. Taking UV.y raw therefore built the shell inside
	// out - densest at the narrow FORWARD apex, gone at the flare, the exact inverse of a
	// Prandtl-Glauert cone - and capped its alpha at 0.5^2.20 = 0.218, which made the
	// `ceiling` uniform dead code. Normalise here so the shell is dense where the cone opens.
	float raw = (mode == 0) ? 1.0 - clamp(UV.y * 2.0, 0.0, 1.0) : UV.y;
	float v = mix(raw, 1.0 - raw, flip_v);
	// LOW-frequency mask. Cloud has one big soft shape with a couple of tears in it; a mask
	// sampled at wing scale reads as speckle, i.e. as dirt on the paint rather than vapour.
	// The wing sheet (mode 1) is the worst offender because it lies flat on a lit surface.
	// Mode 0 gets its OWN, much higher frequency: at wing scale the shell's mask was barely
	// one and a half cycles around the cone, i.e. effectively uniform, so the cone rendered
	// as a moulded glass shape with a drawn silhouette. Modes 1 and 2 keep their old numbers.
	vec2 mask_freq = (mode == 1) ? vec2(1.20, 0.86) : ((mode == 0) ? vec2(2.90, 2.00) : vec2(1.56, 1.10));
	vec2 fine_freq = (mode == 1) ? vec2(2.85, 1.95) : ((mode == 0) ? vec2(6.60, 4.40) : vec2(3.77, 2.54));
	float wisp = texture(noise, vec2(UV.x * mask_freq.x, v * mask_freq.y - scroll)).r;
	float fine = texture(noise, vec2(UV.x * fine_freq.x + 0.4, v * fine_freq.y - scroll * 2.1)).r;
	// Soft tearing, not a binary cut: a hard threshold on a fractal field reads as popcorn.
	float torn = clamp(wisp * 1.25 + fine * ((mode == 1) ? 0.14 : 0.30) - 0.06, 0.0, 1.0);
	// The shell is torn HARD - large parts of it must reach ZERO. A shock front tumbling over
	// an airframe is ragged; an even wall of it is a glass cone with a drawn outline.
	if (mode == 0) torn = clamp(wisp * 1.85 + fine * 0.65 - 0.78, 0.0, 1.0);
	// A vortex core is a tight rope of cloud, not a fractal puff: keep mode 2 nearly smooth.
	if (mode == 2) torn = 0.74 + 0.26 * texture(noise, vec2(UV.x * 0.85 + 0.11, v * 0.70 - scroll * 0.4)).r;
	float body;
	if (mode == 2) {
		vec2 p = UV * 2.0 - 1.0;
		// The smoothstep is not decoration: any non-zero alpha reaching the quad border
		// draws the card itself, which is the defect this mode exists to avoid.
		float rr = length(p);
		body = exp(-pow(rr / 0.58, 2.0)) * smoothstep(1.0, 0.66, rr);
	} else if (mode == 1) {
		body = pow(clamp(sheet, 0.0, 1.0), 1.25) * mix(0.50, 1.0, shell);
	} else {
		// A Prandtl-Glauert cone is a BROADSIDE read. Seen end-on its whole 7.5 m wall
		// projects onto the jet, every fragment is at grazing incidence so the fresnel
		// `shell` term saturates, and the "thin membrane" fills the disc: from the chase
		// camera that rendered as a grey ball swallowing the airframe - exactly the veil the
		// brief forbids. So it fades out as the view lines up with its axis, and is left
		// alone from abeam, where the effect actually reads.
		float axial = abs(dot(normalize(axis_view), normalize(VIEW)));
		float broadside = 1.0 - smoothstep(0.52, 0.88, axial);
		// Peak just short of the open end, not AT it: a cone drawn right out to its rim
		// silhouettes as a clean hard ellipse, which reads as a glass cone rather than
		// condensation. The last sixth of the shell tapers away into nothing.
		float profile = pow(clamp(v, 0.0, 1.0), 1.75) * smoothstep(1.0, 0.82, v);
		body = profile * shell * broadside;
	}
	float lit = clamp(dot(normalize(world_normal), -normalize(light_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float scatter = pow(clamp(1.0 - facing, 0.0, 1.0), 2.0) * 0.20;
	// This is a blend_mix surface, so ALBEDO is what the sheet drags the backdrop TOWARD at
	// the alpha weight. At 1.55 it dragged everything behind it to clipped white, which is
	// why "capped" vapour still read as opaque chalk paint stuck on the airframe. Under 1.0
	// the DENSITY is carried by alpha, where the `ceiling` cap can actually govern it.
	ALBEDO = mix(shade_color, light_color, lit) * 0.92 + light_color * scatter;
	ALPHA = clamp(body * torn * amount * humidity, 0.0, ceiling);
}
