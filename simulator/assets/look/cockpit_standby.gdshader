shader_type spatial;
// Standby flight display: a small backup attitude face under the main panel.
// Driven by the real pitch and roll so it is alive rather than a painted decal.
render_mode unshaded, cull_back, shadows_disabled;
uniform float pitch = 0.0;
uniform float roll = 0.0;
uniform vec3 sky : source_color = vec3(0.09, 0.32, 0.60);
uniform vec3 ground : source_color = vec3(0.40, 0.23, 0.06);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	vec3 col = vec3(0.012, 0.014, 0.013);
	if (r < 0.88) {
		float c = cos(roll);
		float s = sin(roll);
		vec2 q = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
		float horizon = q.y + pitch * 1.9;
		col = mix(ground, sky, smoothstep(-0.015, 0.015, horizon));
		float rung = abs(fract(horizon * 5.0 + 0.5) - 0.5);
		float ladder = step(rung, 0.030) * step(abs(q.x), 0.32) * step(0.08, abs(horizon));
		col = mix(col, vec3(0.88, 0.91, 0.88), ladder);
		col = mix(col, vec3(0.95, 0.96, 0.92), 1.0 - smoothstep(0.006, 0.018, abs(horizon)));
	}
	col *= smoothstep(0.98, 0.86, r) * 0.85 + 0.15;
	// Fixed aircraft reference, the one thing that never rolls.
	float wing = step(abs(p.y), 0.030) * step(abs(p.x), 0.44) * step(0.12, abs(p.x));
	float centre = 1.0 - smoothstep(0.022, 0.040, r);
	col = mix(col, vec3(1.0, 0.80, 0.10), clamp(wing + centre, 0.0, 1.0));
	ALBEDO = col * 1.25;
}
