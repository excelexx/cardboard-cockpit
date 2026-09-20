shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled, unshaded, blend_mix, skip_vertex_transform;
// Contour feathers knocked loose by a hit: a handful of quads that tumble away
// along the shot direction, each drawn with a real feather outline (tapered
// vane, central quill, barb striations, frayed trailing edge). One mesh, one
// material, played by the uniform "t".

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float drag = 2.6;
uniform vec3 gravity = vec3(0.0, -6.5, 0.0);
uniform float spin = 7.0;
uniform float size_mul = 1.0;   // scales the shards with the target
uniform float life_scale = 1.0;
uniform vec3 vane_dark : source_color = vec3(0.085, 0.078, 0.072);
uniform vec3 vane_light : source_color = vec3(0.50, 0.47, 0.43);
uniform vec3 tip_colour : source_color = vec3(0.86, 0.84, 0.80);
uniform float exposure = 1.0;

varying vec2 v_quad;
varying float v_local;
varying float v_seed;

float hash11(float p) { return fract(sin(p * 78.233) * 43758.5453); }

void vertex() {
	float seed = UV2.y;
	float size = UV2.x * size_mul;
	float delay = hash11(seed + 1.7) * 0.10;
	float life = life_scale * (0.78 + 0.22 * hash11(seed + 4.3));
	float local = clamp((t - delay) / max(life, 0.001), 0.0, 1.0);
	float alive = step(delay, t) * step(t, delay + life);
	float age = local * life;

	vec3 vel = VERTEX;
	vec3 pos = vel * (1.0 - exp(-drag * age)) / drag + gravity * age * age * 0.5;
	// Feathers flutter sideways as they slow.
	pos += vec3(sin(age * 9.0 + seed * 6.28), 0.0, cos(age * 7.4 + seed * 4.1)) * 0.22 * smoothstep(0.0, 0.5, local);

	vec3 centre = (MODELVIEW_MATRIX * vec4(pos, 1.0)).xyz;
	float angle = seed * 6.2831 + age * spin * (hash11(seed + 9.1) > 0.5 ? 1.0 : -1.0);
	float ca = cos(angle);
	float sa = sin(angle);
	vec2 quad = UV * 2.0 - 1.0;
	vec2 rotated = vec2(quad.x * ca - quad.y * sa, quad.x * sa + quad.y * ca);
	// Edge-on flashes: the quad squashes as it tumbles through the view plane.
	rotated.x *= 0.35 + 0.65 * abs(cos(age * spin * 0.7 + seed * 3.0));

	float s = size * alive;
	v_quad = quad;
	v_local = local;
	v_seed = seed;
	VERTEX = centre + vec3(rotated * s, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float y = v_quad.y;
	float x = v_quad.x;
	// Vane outline: narrow calamus, widest just past the middle, pointed tip.
	float span = sqrt(max(1.0 - y * y * 0.92, 0.0)) * 0.46;
	span *= 0.30 + 0.70 * smoothstep(-1.0, -0.25, y);
	float fray = 0.035 * sin(y * 46.0 + v_seed * 20.0);
	float inside = 1.0 - smoothstep(span - 0.045 + fray, span + 0.01 + fray, abs(x));
	float quill = exp(-x * x * 900.0) * smoothstep(-1.0, -0.7, y);
	float barbs = 0.80 + 0.20 * sin((abs(x) * 22.0 - y * 9.0) * 3.0);

	vec3 colour = mix(vane_dark, vane_light, smoothstep(0.1, 0.95, y) * 0.8 + 0.12);
	colour = mix(colour, tip_colour, smoothstep(0.72, 1.0, y) * 0.75);
	colour = mix(colour, vane_light * 1.3, quill * 0.6);
	colour *= barbs;

	float fade = 1.0 - smoothstep(0.55, 1.0, v_local);
	ALBEDO = colour * exposure;
	ALPHA = clamp(inside * fade, 0.0, 1.0);
}
