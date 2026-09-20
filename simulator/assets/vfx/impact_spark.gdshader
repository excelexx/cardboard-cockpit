shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled, skip_vertex_transform;
// Spark and ember shards for weapon impacts. One mesh, one material, one draw
// call per burst: each quad carries its own launch velocity in VERTEX and its
// size/seed in UV2, and the whole spray is played by the single uniform "t"
// (0..1), so effects cost nothing per frame beyond setting that float - and a
// capture harness can step them to an exact moment.

uniform float t : hint_range(0.0, 1.0) = 0.0;
uniform float drag = 3.4;
uniform vec3 gravity = vec3(0.0, -22.0, 0.0);
uniform float streak = 0.030;      // seconds of travel drawn as a streak
uniform float intensity = 1.0;
uniform float min_width = 0.0008;
uniform float min_length = 0.0070;  // keeps a distant spark a streak, not a blob
uniform float size_mul = 1.0;   // scales the shards with the target
uniform vec3 hot_colour : source_color = vec3(1.0, 0.98, 0.90);
uniform vec3 mid_colour : source_color = vec3(1.0, 0.55, 0.12);
uniform vec3 cool_colour : source_color = vec3(0.62, 0.07, 0.02);
uniform float life_scale = 1.0;

varying float v_local;
varying vec2 v_quad;
varying float v_seed;

float hash11(float p) {
	return fract(sin(p * 78.233) * 43758.5453);
}

void vertex() {
	float seed = UV2.y;
	float size = UV2.x * size_mul;
	float delay = hash11(seed + 3.1) * 0.10;
	float life = life_scale * (0.70 + 0.30 * hash11(seed + 7.7));
	float local = clamp((t - delay) / max(life, 0.001), 0.0, 1.0);
	float alive = step(delay, t) * step(t, delay + life);

	vec3 vel = VERTEX;
	float age = local * life;
	// Ballistic with drag, so sparks decelerate instead of flying flat.
	vec3 pos = vel * (1.0 - exp(-drag * age)) / drag + gravity * age * age * 0.5;

	vec3 centre = (MODELVIEW_MATRIX * vec4(pos, 1.0)).xyz;
	vec3 travel = mat3(MODELVIEW_MATRIX) * (vel * exp(-drag * age) + gravity * age);
	float speed = length(travel);
	vec3 dir = speed > 0.001 ? travel / speed : vec3(0.0, 1.0, 0.0);
	vec3 to_eye = normalize(-centre);
	vec3 side = cross(dir, to_eye);
	float sl = length(side);
	side = sl > 0.0005 ? side / sl : normalize(cross(dir, vec3(0.0, 1.0, 0.0)));

	float w = max(size, length(centre) * min_width) * alive;
	float trail = max(size * 1.2 + speed * streak, length(centre) * min_length) * alive;

	v_local = local;
	v_quad = UV * 2.0 - 1.0;
	v_seed = seed;
	// The shard itself sits at the leading corner; the streak hangs behind it.
	float taper = 0.32 + 0.68 * (v_quad.y * 0.5 + 0.5);
	VERTEX = centre + dir * ((v_quad.y - 1.0) * 0.5 * trail) + side * (v_quad.x * w * taper);
	NORMAL = to_eye;
}

void fragment() {
	float across = exp(-v_quad.x * v_quad.x * 3.0);
	// Bright at the head (y = +1), tapering to nothing at the tail.
	float along = pow(clamp(v_quad.y * 0.5 + 0.5, 0.0, 1.0), 1.5);
	along *= 1.0 - smoothstep(0.88, 1.0, v_quad.y) * 0.55;
	float shape = across * along;
	float fade = pow(1.0 - v_local, 1.9);
	float twinkle = 0.70 + 0.30 * sin(v_seed * 54.0 + v_local * 48.0);
	vec3 colour = mix(hot_colour, mid_colour, smoothstep(0.0, 0.16, v_local));
	colour = mix(colour, cool_colour, smoothstep(0.35, 0.95, v_local));
	ALBEDO = colour * shape * fade * twinkle * 3.6 * intensity;
	ALPHA = 1.0;
}
