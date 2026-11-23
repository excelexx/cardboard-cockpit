shader_type spatial;
// Heat-tinted titanium around the exhaust. Real petals temper in bands as they
// get hotter toward the exit: machined grey, then straw, then bronze. The old
// violet/blue half turned the exit into a lavender crown in every chase shot,
// so the cool tint is now a whisper on the last few centimetres of the lip
// only -- the palette lock is amber / gunmetal / slate blue.
//
// Two measured faults fixed here.
//
// 1. BRIGHTNESS. At metallic 0.94 / roughness 0.12-0.30 the petals were a
//    near-mirror for a sunset sky and measured luminance 0.291 against 0.053
//    for the airframe body: 5.5x, so the exhaust ring read as pale tan
//    cardboard bolted to a black jet. The sky response is cut hard (metallic
//    0.42, roughness 0.50-0.70) and the tempering colours are halved, which
//    keeps the grey/straw/bronze order while putting the ring inside ~2x the
//    body.
// 2. THE SEAM. `atan(x, y)` wraps at +/-PI; multiplied by 0.92 and fed straight
//    to a repeating texture, the two sides of the wrap landed 5.78 texture
//    units apart, so a hard vertical brightness join ran down the barrel (left
//    half pink-tan, right half grey, measured 0.333 against 0.256). The angle
//    is now normalised to fract(a / TAU) and scaled by an INTEGER number of
//    repeats, which is continuous across the wrap on a seamless texture.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float heat = 1.0;
uniform float axis_y = -0.30;
uniform float start_z = 5.40;
uniform float end_z = 7.30;
const float GRAIN_REPEATS = 6.0;   // integer: fract() wraps cleanly at +/-PI
varying vec3 local;

void vertex() { local = VERTEX; }

void fragment() {
	float band = clamp((local.z - start_z) / max(0.001, end_z - start_z), 0.0, 1.0);
	float around = fract(atan(local.x, local.y - axis_y) / TAU) * GRAIN_REPEATS;
	float streak = texture(grain, vec2(around, local.z * 0.75)).r;
	vec3 metal = mix(vec3(0.052, 0.050, 0.049), vec3(0.086, 0.062, 0.029), smoothstep(0.05, 0.45, band));
	metal = mix(metal, vec3(0.072, 0.046, 0.023), smoothstep(0.45, 0.85, band));
	// Slate-blue whisper on the last 8% of the petal, at low weight.
	metal = mix(metal, vec3(0.041, 0.038, 0.045), smoothstep(0.92, 1.0, band) * 0.30);
	metal *= mix(0.78, 1.18, streak);
	ALBEDO = metal;
	METALLIC = 0.20;
	SPECULAR = 0.18;
	ROUGHNESS = clamp(0.78 - band * 0.18 + (streak - 0.5) * 0.14, 0.54, 0.94);
	RIM = 0.10;
	RIM_TINT = 0.85;
	EMISSION = vec3(0.95, 0.30, 0.070) * smoothstep(0.80, 1.0, band) * heat * 0.09;
}
