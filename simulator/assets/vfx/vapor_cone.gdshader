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
uniform float size = 1.0;           // mode 2 billboard radius, metres
uniform float flip_v = 0.0;
uniform float rim = 0.70;   // >1 collapses the shell to a thin rim: a membrane, not a card
uniform int mode = 0;
uniform vec3 light_dir = vec3(0.0, -0.2, -1.0);
uniform vec3 light_color : source_color = vec3(1.0, 0.88, 0.78);
uniform vec3 shade_color : source_color = vec3(0.66, 0.73, 0.84);
varying vec3 world_normal;
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
		mat4 billboard = mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
		                      INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shell = pow(1.0 - facing, rim);
	float v = mix(UV.y, 1.0 - UV.y, flip_v);
	float wisp = texture(noise, vec2(UV.x * 2.4, v * 1.7 - scroll)).r;
	float fine = texture(noise, vec2(UV.x * 5.8 + 0.4, v * 3.9 - scroll * 2.1)).r;
	// Soft tearing, not a binary cut: a hard threshold on a fractal field reads as popcorn.
	float torn = clamp(wisp * 1.25 + fine * 0.30 - 0.12, 0.0, 1.0);
	// A vortex core is a tight rope of cloud, not a fractal puff: keep mode 2 nearly smooth.
	if (mode == 2) torn = 0.74 + 0.26 * texture(noise, vec2(UV.x * 0.85 + 0.11, v * 0.70 - scroll * 0.4)).r;
	float body;
	if (mode == 2) {
		vec2 p = UV * 2.0 - 1.0;
		// The smoothstep is not decoration: any non-zero alpha reaching the quad border
		// draws the card itself, which is the defect this mode exists to avoid.
		float rr = length(p);
		body = exp(-pow(rr / 0.55, 2.0)) * smoothstep(1.0, 0.62, rr);
	} else if (mode == 1) {
		body = pow(clamp(sheet, 0.0, 1.0), 1.25) * mix(0.50, 1.0, shell);
	} else {
		body = pow(clamp(v, 0.0, 1.0), 2.20) * shell;
	}
	float lit = clamp(dot(normalize(world_normal), -normalize(light_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float scatter = pow(clamp(1.0 - facing, 0.0, 1.0), 2.0) * 0.30;
	ALBEDO = mix(shade_color, light_color, lit) * 1.55 + light_color * scatter;
	ALPHA = clamp(body * torn * amount * humidity, 0.0, ceiling);
}
