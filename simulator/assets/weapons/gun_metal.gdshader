shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Gunmetal for the rotary cannon and the plasma cannon armour. The photographed
// CC0 steel plate (Poly Haven "Blue Metal Plate") is used for its scratches and
// abrasion structure only: the paint is desaturated away and the surface is
// re-tinted to the key art's near-black graphite with gold trim.
// "heat" builds while firing: the barrels glow from the chamber forward and the
// last span before the muzzle takes a straw-purple-blue oxide, like real
// heat-blued steel.

uniform sampler2D plate_albedo : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D plate_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D plate_arm : filter_linear_mipmap_anisotropic, hint_default_white; // r=AO g=rough b=metal

uniform vec3 base_tint : source_color = vec3(0.048, 0.051, 0.057);
uniform vec3 wear_tint : source_color = vec3(0.33, 0.34, 0.37);
uniform vec3 gold_tint : source_color = vec3(1.0, 0.68, 0.18);
uniform float gold_mix : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.92;
uniform float rough_lo : hint_range(0.0, 1.0) = 0.19;
uniform float rough_hi : hint_range(0.0, 1.0) = 0.54;
uniform float tex_scale = 3.0;
uniform float normal_strength : hint_range(0.0, 3.0) = 0.8;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.55;
uniform float ao_amount : hint_range(0.0, 1.0) = 0.8;

uniform float heat : hint_range(0.0, 1.0) = 0.0;      // set by WeaponModels.set_heat()
uniform float heat_bias : hint_range(0.0, 1.0) = 0.0; // how much this part heats at all
uniform float heat_front = -0.50;                     // object z of the muzzle face
uniform float heat_back = 0.72;                       // object z of the breech end
uniform float blue_span = 0.20;                       // length of the oxide band behind the muzzle
uniform float flute_count = 5.0;                      // barrel count, for the heat banding
uniform float emissive_trim : hint_range(0.0, 8.0) = 0.0;

varying vec3 v_obj;

// Deliberately tops out at a deep orange, not white: barrels that run white-hot
// read as a lamp bolted to the jet instead of steel with heat in it.
vec3 blackbody(float t) {
	vec3 c = vec3(0.75, 0.055, 0.010) * smoothstep(0.05, 0.45, t);
	c += vec3(0.55, 0.170, 0.020) * smoothstep(0.42, 0.80, t);
	c += vec3(0.34, 0.270, 0.110) * smoothstep(0.80, 1.00, t);
	return c;
}

// Iridescent oxide: straw -> bronze -> violet -> steel blue with depth.
vec3 oxide(float d) {
	vec3 straw  = vec3(0.098, 0.084, 0.052);
	vec3 bronze = vec3(0.086, 0.058, 0.038);
	vec3 violet = vec3(0.056, 0.046, 0.074);
	vec3 steel  = vec3(0.038, 0.050, 0.078);
	vec3 c = mix(straw, bronze, smoothstep(0.0, 0.35, d));
	c = mix(c, violet, smoothstep(0.30, 0.66, d));
	c = mix(c, steel, smoothstep(0.60, 1.0, d));
	return c;
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec2 uv = UV * tex_scale;
	vec3 plate = texture(plate_albedo, uv).rgb;
	vec3 arm = texture(plate_arm, uv).rgb;
	float lum = dot(plate, vec3(0.299, 0.587, 0.114));
	// Keep only the plate's light/dark structure: scuffs read bright, pitting dark.
	float structure = clamp((lum - 0.16) / 0.46, 0.0, 1.0);
	float scuff = smoothstep(0.62, 1.0, structure);

	vec3 albedo = mix(base_tint, wear_tint, structure * wear_amount);
	albedo = mix(albedo, wear_tint * 1.5, scuff * wear_amount * 0.55);
	albedo = mix(albedo, gold_tint, gold_mix);

	// Heat-blued oxide over the span just behind the muzzle face.
	float along = clamp((v_obj.z - heat_front) / max(blue_span, 0.001), 0.0, 1.0);
	// The crowned tip stays bare steel; the oxide band sits just behind it.
	float oxide_mask = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.55, 1.0, along)) * heat_bias;
	albedo = mix(albedo, oxide(along) * (0.6 + 0.4 * structure), oxide_mask * 0.70);

	float rough = mix(rough_lo, rough_hi, arm.g);
	rough = mix(rough, rough * 0.55 + 0.10, oxide_mask * 0.7);
	rough = mix(rough, 0.28, gold_mix);

	ALBEDO = albedo;
	METALLIC = mix(metallic_amount, 1.0, gold_mix);
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	SPECULAR = 0.55;
	AO = mix(1.0, arm.r, ao_amount);
	AO_LIGHT_AFFECT = 0.6;
	NORMAL_MAP = texture(plate_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;

	// Barrel heat: builds from the chamber forward, banded so the individual
	// barrels stay legible, and never washes over the silhouette.
	float span = max(heat_back - heat_front, 0.001);
	float t = clamp((v_obj.z - heat_front) / span, 0.0, 1.0);
	// A hot zone behind the clamps that falls away toward the crowns, so the
	// muzzle keeps its dark silhouette and the glow reads as heat in the steel.
	float band = exp(-pow((t - 0.34) / 0.23, 2.0));
	float gradient = band * (0.30 + 0.70 * smoothstep(0.04, 0.26, t));
	float ring = 0.92 + 0.08 * sin(v_obj.z * 190.0);
	float glow = pow(heat, 1.6) * heat_bias * gradient * ring;
	glow *= 0.60 + 0.40 * (1.0 - structure);
	// Weight the glow toward grazing angles so five hot barrels still read as
	// five tubes instead of merging into one orange rod.
	glow *= 0.58 + 0.42 * (1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))));
	EMISSION = blackbody(clamp(heat, 0.0, 1.0)) * glow * 0.22;
	EMISSION += gold_tint * emissive_trim * (0.55 + 0.45 * structure);
}
