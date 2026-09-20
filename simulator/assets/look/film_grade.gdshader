shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Final picture grade, drawn once over the 3D view and under the HUD.
// Darkens the frame edges and adds fine grain so the image reads as graded
// film rather than a raw render. It never brightens anything and leaves the
// middle of the frame untouched, so the forward view stays clean.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float vignette : hint_range(0.0, 0.6) = 0.30;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.42;
uniform float vignette_end : hint_range(0.5, 1.5) = 0.98;
uniform float grain : hint_range(0.0, 0.05) = 0.014;
uniform float fringe : hint_range(0.0, 0.003) = 0.0006;
uniform vec3 shadow_tint : source_color = vec3(0.92, 0.97, 1.06);

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec2 d = SCREEN_UV - 0.5;
	// Aspect-corrected so the falloff is an ellipse that hugs the corners.
	float r = length(d * vec2(1.0, 0.82)) * 1.55;
	float edge = smoothstep(vignette_start, vignette_end, r);

	// A whisper of lens fringe, only where the vignette already lives.
	vec2 ca = d * fringe * edge;
	vec3 col = vec3(
		texture(screen, SCREEN_UV + ca).r,
		texture(screen, SCREEN_UV).g,
		texture(screen, SCREEN_UV - ca).b);

	// Cool the deep shadows slightly so warm sunlight has something to push against.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= mix(shadow_tint, vec3(1.0), smoothstep(0.0, 0.35, luma));

	col *= 1.0 - vignette * edge;

	// Grain is strongest in the mid-tones and fades out of highlights.
	float n = hash(FRAGCOORD.xy + fract(TIME * 7.13) * 911.0) - 0.5;
	col += n * grain * (1.0 - smoothstep(0.55, 1.0, luma));

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
