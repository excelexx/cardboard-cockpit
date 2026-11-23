shader_type spatial;
// The afterburner's 3D parts (cone axis +Y, nozzle at y = -0.5).
// layer 1: the translucent sheath - a thin rim-lit membrane that gives the plume a
//          silhouette and its blue/violet outer flame from every angle. The tube is
//          authored at unit radius; the vertex stage bends it to the real profile so
//          the sheath and the axial slice agree on the plume's shape.
// layer 2: the view INTO the nozzle: white-hot throat, the burning annulus, the
//          flame-holder gutters and the twelve petal lips glowing back at you.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float power = 0.5;
uniform float reheat = 1.0;
uniform float core_radius = 0.52;   // metres at the nozzle
uniform float spread = 2.6;         // radius multiplier at the tip
uniform float brightness = 1.0;
uniform int layer = 1;
// Station dissolve and near-camera fade, both matching assets/vfx/afterburner_core.gdshader
// so the membrane and the interior die together instead of the sheath outliving the flame
// and drawing a lone hard outline where the gas has already gone.
uniform float fade_from = 0.54;
uniform float fade_to = 0.97;
uniform float near_fade_in = 3.5;
uniform float near_fade_out = 13.5;
varying float along;

void vertex() {
	if (layer == 1) {
		along = clamp(VERTEX.y + 0.5, 0.0, 1.0);
		// The same axial lump field the core uses on its envelope. Without it the sheath is
		// a mathematically perfect cone, and a fresnel rim on a perfect cone is the crisp
		// straight-sided wedge the review called a cut-out card.
		float lumps = textureLod(noise, vec2(along * 2.35 + 0.51, 0.77 - TIME * 1.05), 0.0).r;
		VERTEX.xz *= core_radius * (1.0 + (spread - 1.0) * pow(along, 2.20)) * 1.16 * (0.88 + 0.26 * lumps);
	}
}

void fragment() {
	float flicker = 0.93 + 0.07 * sin(TIME * 59.0 + along * 27.0) * sin(TIME * 23.0 + 1.7);
	if (layer == 2) {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float a = atan(p.y, p.x);
		float petals  = 0.78 + 0.22 * cos(a * 12.0);              // twelve convergent petals
		float holders = 0.74 + 0.26 * cos(a * 3.0 + 0.4);         // flame-holder gutters
		float swirl = texture(noise, vec2(a * 0.159 + TIME * 0.06, r * 0.9 - TIME * 0.40)).r;
		// A SMALL hot core with a graded wall, not a uniformly lit circle. At r/0.40 and gain
		// 2.0 this drew a 1.3 m white disc that, dead astern, was the whole of the effect -
		// the "flat orange disc" read the integrator rejected for the nozzle.
		float throat  = exp(-pow(r / 0.26, 2.4));
		float annulus = exp(-pow((r - 0.54) / 0.24, 2.0)) * mix(0.70, 1.34, swirl) * holders;
		float lip = smoothstep(0.99, 0.87, r) * smoothstep(0.70, 0.90, r) * petals;
		vec3 c_throat = mix(vec3(0.76, 0.87, 1.00), vec3(1.00, 0.96, 0.88), reheat);
		vec3 c_gas    = mix(vec3(0.30, 0.52, 1.00), vec3(1.00, 0.42, 0.08), reheat);
		vec3 c_metal  = vec3(1.00, 0.34, 0.07);
		float gain = (0.18 + power * 1.12) * flicker * brightness;
		ALBEDO = (c_throat * throat * 1.10 + c_gas * annulus * 1.50 + c_metal * lip * 1.35) * gain;
		ALPHA = smoothstep(1.00, 0.93, r);
	} else {
		// A thin membrane, not a solid cone: only the silhouette edge of the tube lights up,
		// so from behind it reads as a ring around the core instead of filling it in.
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		// A SOFTER rim. At 2.60 the membrane collapsed onto a one-pixel analytic edge and
		// drew the same hard line as the core's boundary, doubling it up; a lower exponent
		// spreads the membrane so it reads as gas thinning out rather than a drawn outline.
		float rim = pow(1.0 - facing, 2.05);
		float streaks = texture(noise, vec2(UV.x * 2.6, along * 1.5 - TIME * 1.90)).r;
		float wisps   = texture(noise, vec2(UV.x * 6.1 + 0.37, along * 3.4 - TIME * 4.60)).r;
		float grain = mix(0.40, 1.55, clamp(streaks * 0.62 + wisps * 0.38, 0.0, 1.0));
		// Fade the sheath out over the first ~14% as well: right at the nozzle the core, the
		// glow disc and the membrane all draw the same silhouette, and three coincident hard
		// edges is what read as a card. Out there the nozzle glow carries the shape.
		float reach = pow(1.0 - along, 2.55) * smoothstep(0.0, 0.14, along);
		float tail = textureLod(noise, vec2(along * 1.9 + 0.13, UV.x * 0.55 - TIME * 0.90), 0.0).r;
		float dissolve = 1.0 - smoothstep(fade_from + 0.20 * tail, fade_to, along);
		// PALETTE LOCK: the sheath used to sit 72% of the way toward violet and then fade to
		// blue, which painted the entire outer flame lavender. Slate blue belongs in the
		// first couple of metres; everything downstream of that is amber.
		vec3 flame  = mix(vec3(0.34, 0.55, 1.00), vec3(1.00, 0.42, 0.075), reheat);
		vec3 amber  = mix(vec3(0.30, 0.48, 1.00), vec3(0.96, 0.27, 0.035), reheat);
		vec3 blue   = vec3(0.26, 0.45, 1.00);
		vec3 colour = mix(blue, mix(flame, amber, smoothstep(0.20, 0.70, along)), smoothstep(0.02, 0.26, along));
		float near = smoothstep(near_fade_in, near_fade_out, length(VERTEX));
		float gain = rim * grain * reach * dissolve * power * flicker * brightness * near;
		// The membrane is the WIDEST thing the burner draws, so it is also the part that
		// turns into a pale wash over the sky. Held down; the core carries the brightness.
		ALBEDO = colour * gain * 0.68 + flame * gain * (1.0 - smoothstep(0.0, 0.42, along)) * 0.36;
		ALPHA = 1.0;
	}
}
