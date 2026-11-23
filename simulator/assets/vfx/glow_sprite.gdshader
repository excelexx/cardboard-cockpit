shader_type spatial;
// Camera-facing light. mode 0: the nozzle flare - a hot core, a tight bloom skirt and
// a subtle cool anamorphic streak, as in the key art. mode 1: the ignition shock ring.
// mode 2: one slice of the plume seen END-ON, instanced along the axis by a MultiMesh -
// this is what carries the burner when the chase camera looks straight up the plume and
// the axial slice collapses to nothing. Per-instance: x = radius, y = intensity,
// z = Mach-disk flash, w = station along the plume.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 hot : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 streak_tint : source_color = vec3(0.55, 0.74, 1.0);
uniform vec3 rim_tint : source_color = vec3(0.44, 0.55, 0.86);   // slate blue, per the palette lock
uniform float intensity = 1.0;
uniform float size = 1.0;
uniform float streak = 0.0;
uniform float ring = 0.0;
uniform float ring_radius = 0.7;
uniform float ring_width = 0.10;
uniform int mode = 0;
// Near-camera opacity fade for the mode 2 stack, matching afterburner_core.gdshader.
uniform float near_fade_in = 3.5;
uniform float near_fade_out = 11.0;
varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
	float s = (mode == 2) ? custom.x : size;
	mat4 billboard = mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = smoothstep(1.0, 0.72, r);
	if (mode == 2) {
		// A slice of the plume seen END-ON. EVERY term here is an ANNULUS, not a filled disc:
		// dead astern a dozen of these project concentrically, and filled discs summed on top
		// of each other is exactly how this view collapsed into one featureless orange-white
		// bullseye. As rings they stack into a chain of shock cells up the pipe, which is the
		// only reason the stack exists.
		//   centre: the white-hot throat, drawn ONLY on a Mach disk (custom.z). It used to
		//           carry a flat 0.60 on every slice, so a dozen slices summed to a clipped
		//           white core no matter what the rest of the shader did.
		//   Every ring is CONCENTRIC, so any term near r = 0 is summed by all of them at the
		//   same handful of pixels. The white throat therefore has to be small and cheap per
		//   ring (it was 3.10, which six rings turned into a clipped white core no matter
		//   what the annuli did); the nozzle interior carries the hot middle instead.
		// ...and only the FIRST cells carry one at all (custom.w is the station along the
		// plume): six rings each donating a white throat is a clipped white core by itself.
		float centre = exp(-pow(r / 0.20, 2.0)) * custom.z * (1.0 - custom.w);
		float gas    = exp(-pow((r - 0.60) / 0.24, 2.0));
		float barrel = exp(-pow((r - 0.87) / 0.065, 2.0));
		vec3 c = hot * centre * 1.10
		       + tint * gas * 0.66
		       + rim_tint * barrel * (1.15 + custom.z * 2.10);
		float near = smoothstep(near_fade_in, near_fade_out, length(VERTEX));
		ALBEDO = c * custom.y * intensity * edge * near;
	} else {
		// A tight core with a WIDE but dim bloom skirt: a big soft flare that never becomes
		// a white ball over the airframe, plus a low anamorphic streak as in the key art.
		float core  = exp(-r * r * 88.0);
		float inner = exp(-r * r * 9.0) * 0.20;
		float skirt = exp(-r * 3.2) * 0.12;
		float line  = exp(-pow(p.y * 17.0, 2.0)) * exp(-abs(p.x) * 1.65) * streak;
		float band  = exp(-pow((r - ring_radius) * 13.0, 2.0)) * ring;
		vec3 c = mix(tint, hot, clamp(core * 1.1, 0.0, 1.0)) * (core * 2.40 + inner + skirt + band)
		       + streak_tint * line * 0.70;
		ALBEDO = c * intensity * edge;
	}
	ALPHA = 1.0;
}
