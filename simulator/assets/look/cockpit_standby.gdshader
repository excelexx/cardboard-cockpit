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
	// The bezel inside the glass, not a hole. At 0.012 the world grade (AgX then
	// adjustment_contrast 1.12, which clamps anything under ~5% grey to zero)
	// turned the four corners of this face into pure black squares.
	// An attitude indicator shows the WORLD, so the horizon rotates opposite to
	// the aircraft: at right-wing-down the sky swings left. `q.y` is therefore
	// the height above the horizon measured along the world up vector
	// (-sin roll, cos roll), and `q.x` the distance along the wing line
	// (cos roll, sin roll). This is the same convention the panoramic PFD uses
	// (ui/cockpit_instruments.gd: down = (sin bank, cos bank)); the two faces
	// are visible in one frame and used to disagree in every banked turn.
	//
	// All of it is computed unconditionally and then masked by the dial's rim.
	// Inside an `if (r < 0.88)` the fwidth() calls below sit in non-uniform
	// control flow, and on the quads that straddle the rim their derivatives are
	// undefined - which is what drew a ring of white dashes right round the edge
	// of the face.
	float c = cos(roll);
	float s = sin(roll);
	vec2 q = vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
	float horizon = q.y + pitch * 1.9;
	vec3 face = mix(ground, sky, smoothstep(-0.015, 0.015, horizon));
	// The whole face is about 90 pixels across at the game's field of view, so
	// every edge on it is drawn against its own screen-space derivative. Hard
	// steps at five rungs per unit aliased into a field of white speckles that
	// read as dirt on the glass rather than as a pitch ladder; at two per unit,
	// anti-aliased, it reads as the ladder it is.
	float aa = fwidth(horizon) * 0.9 + 0.004;
	float rung = abs(fract(horizon * 2.0 + 0.5) - 0.5) / 2.0;
	float ladder = (1.0 - smoothstep(0.012, 0.012 + aa, rung))
		* (1.0 - smoothstep(0.30, 0.30 + fwidth(q.x) * 2.0, abs(q.x)))
		* smoothstep(0.10, 0.10 + aa * 2.0, abs(horizon));
	face = mix(face, vec3(0.88, 0.91, 0.88), ladder);
	face = mix(face, vec3(0.95, 0.96, 0.92), 1.0 - smoothstep(0.008, 0.008 + aa, abs(horizon)));
	// The bezel inside the glass, not a hole. At 0.012 the world grade (AgX then
	// adjustment_contrast 1.12, which clamps anything under ~5% grey to zero)
	// turned the four corners of this face into pure black squares.
	vec3 col = mix(face, vec3(0.055, 0.060, 0.058),
		smoothstep(0.87, 0.87 + fwidth(r) * 1.5 + 0.012, r));
	col *= smoothstep(0.98, 0.86, r) * 0.85 + 0.15;
	// Fixed aircraft reference, the one thing that never rolls.
	float bar = fwidth(p.y) + 0.002;
	float wing = (1.0 - smoothstep(0.026, 0.026 + bar, abs(p.y)))
		* (1.0 - smoothstep(0.44, 0.44 + bar * 2.0, abs(p.x)))
		* smoothstep(0.12, 0.12 + bar * 2.0, abs(p.x));
	float centre = 1.0 - smoothstep(0.022, 0.040, r);
	col = mix(col, vec3(1.0, 0.80, 0.10), clamp(wing + centre, 0.0, 1.0));
	ALBEDO = col * 1.25;
}
