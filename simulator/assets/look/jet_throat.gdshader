shader_type spatial;
// The unlit metal INTERIOR of the exhaust, seen down the pipe. P7A owns the
// flame; this is only the throat, and it must stay dark and graded.
//
// What it replaces: an unshaded constant-emission CylinderMesh with
// CULL_DISABLED. Two things made that read as a sticker. The cull mode meant
// the NEAR wall's outside was drawn on top of the interior, so every pixel of
// the exit returned one colour -- measured over the whole disc, mean RGB
// (1.000, 0.459, 0.205) with per-channel std 0.0009 and red hard-clipped at 1.0
// -- and the energy put it at 10x the airframe body and above the environment's
// glow_hdr_threshold, so it bloomed as well.
//
// Now the front faces are culled, so the camera looks INTO the cone: the small
// capped end deep in the pipe is the hot core and the inner wall grades away
// from it toward the lip. The peak sits under the bloom threshold on purpose --
// the flame in front of it is what is allowed to bloom.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

uniform float power = 1.0;              // throttle, 0..1
uniform float core_peak = 1.02;         // linear peak, deliberately under glow_hdr_threshold
uniform float mouth_radius = 0.56;      // the cone's wide (exit) radius
uniform float pipe_length = 0.70;       // mouth to the capped end
uniform float core_fraction = 0.34;     // hot core as a share of the exit radius
uniform vec3 core_hot : source_color = vec3(1.00, 0.54, 0.22);
uniform vec3 wall_cool : source_color = vec3(0.21, 0.055, 0.016);

varying vec3 local;

void vertex() { local = VERTEX; }

void fragment() {
	// CylinderMesh runs along its own +Y: +half height is the exit mouth,
	// -half height the small cap deep in the pipe. The MeshInstance3D is turned
	// +PI/2 about X so that axis points aft on a nose--Z airframe.
	float half_len = max(0.001, pipe_length * 0.5);
	float depth = clamp(local.y / (half_len * 2.0) + 0.5, 0.0, 1.0);   // 0 deep, 1 at the lip
	float r = length(vec2(local.x, local.z)) / max(0.001, mouth_radius);

	// The cap is the core: graded from its centre out, so it can never be a
	// flat disc even seen dead astern.
	float core = 1.0 - smoothstep(0.015, core_fraction * 1.12, r);
	// The wall falls off fast as it comes toward the lip -- this is the depth
	// cue that was missing entirely.
	float wall = pow(1.0 - depth, 2.3);
	float heat = max(core, wall * 0.38);
	// A little low-frequency unevenness so the metal is not a maths surface.
	heat *= 1.0 - 0.10 * fract(sin(dot(vec2(floor(r * 9.0), floor(depth * 7.0)), vec2(12.99, 78.23))) * 43758.55);

	vec3 tint = mix(wall_cool, core_hot, pow(clamp(heat, 0.0, 1.0), 0.62));
	ALBEDO = tint * heat * core_peak * clamp(power, 0.0, 1.0);
	ALPHA = 1.0;
}
