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
uniform vec3 rim_tint : source_color = vec3(0.42, 0.36, 1.0);
uniform float intensity = 1.0;
uniform float size = 1.0;
uniform float streak = 0.0;
uniform float ring = 0.0;
uniform float ring_radius = 0.7;
uniform float ring_width = 0.10;
uniform int mode = 0;
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
		// A slice of the plume seen END-ON: a small white throat, an orange gas disc and a
		// THIN barrel-shock ring. Stacked along the axis these rings are what reads as a
		// chain of shock cells when the chase camera looks straight up the pipe.
		float centre = exp(-pow(r / 0.28, 2.0));
		float gas    = exp(-pow(r / 0.66, 2.4));
		float barrel = exp(-pow((r - 0.80) / 0.085, 2.0));
		vec3 c = hot * centre * (0.60 + custom.z * 2.60)
		       + tint * gas * 0.85
		       + rim_tint * barrel * (1.60 + custom.z * 3.20);
		ALBEDO = c * custom.y * intensity * edge;
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
