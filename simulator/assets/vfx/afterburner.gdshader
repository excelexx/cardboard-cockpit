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
varying float along;

void vertex() {
	if (layer == 1) {
		along = clamp(VERTEX.y + 0.5, 0.0, 1.0);
		VERTEX.xz *= core_radius * (1.0 + (spread - 1.0) * pow(along, 1.30)) * 1.16;
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
		float throat  = exp(-pow(r / 0.40, 2.4));
		float annulus = exp(-pow((r - 0.54) / 0.24, 2.0)) * mix(0.70, 1.34, swirl) * holders;
		float lip = smoothstep(0.99, 0.87, r) * smoothstep(0.70, 0.90, r) * petals;
		vec3 c_throat = mix(vec3(0.76, 0.87, 1.00), vec3(1.00, 0.96, 0.88), reheat);
		vec3 c_gas    = mix(vec3(0.30, 0.52, 1.00), vec3(1.00, 0.42, 0.08), reheat);
		vec3 c_metal  = vec3(1.00, 0.34, 0.07);
		float gain = (0.22 + power * 1.70) * flicker * brightness;
		ALBEDO = (c_throat * throat * 2.00 + c_gas * annulus * 1.35 + c_metal * lip * 1.25) * gain;
		ALPHA = smoothstep(1.00, 0.93, r);
	} else {
		// A thin membrane, not a solid cone: only the silhouette edge of the tube lights up,
		// so from behind it reads as a ring around the core instead of filling it in.
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float rim = pow(1.0 - facing, 2.60);
		float streaks = texture(noise, vec2(UV.x * 2.6, along * 1.5 - TIME * 1.90)).r;
		float wisps   = texture(noise, vec2(UV.x * 6.1 + 0.37, along * 3.4 - TIME * 4.60)).r;
		float grain = mix(0.40, 1.55, clamp(streaks * 0.62 + wisps * 0.38, 0.0, 1.0));
		float reach = pow(1.0 - along, 1.15) * smoothstep(0.0, 0.05, along);
		vec3 flame  = mix(vec3(0.34, 0.55, 1.00), vec3(1.00, 0.48, 0.12), reheat);
		vec3 violet = mix(vec3(0.30, 0.48, 1.00), vec3(0.70, 0.22, 0.98), reheat);
		vec3 blue   = vec3(0.26, 0.45, 1.00);
		vec3 colour = mix(mix(flame, violet, 0.72), blue, smoothstep(0.18, 0.88, along));
		float gain = rim * grain * reach * power * flicker * brightness;
		ALBEDO = colour * gain * 0.85 + flame * gain * (1.0 - smoothstep(0.0, 0.42, along)) * 0.42;
		ALPHA = 1.0;
	}
}
