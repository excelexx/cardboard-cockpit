shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Plasma cannon surfaces. mode 0 = armoured housing (dark graphite, gold trim,
// seams that wake up as the weapon spools), 1 = capacitor coil / rail (charge
// pulses run forward along it), 2 = emitter throat (white-hot while firing).
// "charge" 0..1 is the spool-up, "firing" 0..1 is the discharge.

uniform int mode = 0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float firing : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D plate_albedo : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D plate_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D plate_arm : filter_linear_mipmap_anisotropic, hint_default_white;
uniform float tex_scale = 2.6;
uniform float normal_strength : hint_range(0.0, 3.0) = 0.7;
uniform vec3 base_tint : source_color = vec3(0.040, 0.043, 0.050);
uniform vec3 wear_tint : source_color = vec3(0.30, 0.31, 0.34);
uniform vec3 gold_tint : source_color = vec3(1.0, 0.68, 0.18);
uniform float gold_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec3 energy_cold : source_color = vec3(0.24, 0.10, 0.85);
uniform vec3 energy_hot : source_color = vec3(0.30, 0.95, 1.0);
uniform float muzzle_z = -0.52;
uniform float breech_z = 0.9;
uniform float seam_gain = 1.0;

varying vec3 v_obj;

void vertex() { v_obj = VERTEX; }

void fragment() {
	float span = max(breech_z - muzzle_z, 0.001);
	float run = clamp((v_obj.z - muzzle_z) / span, 0.0, 1.0); // 0 at the muzzle, 1 at the breech
	vec3 energy = mix(energy_cold, energy_hot, clamp(charge * 0.65 + firing * 0.9, 0.0, 1.0));

	vec3 albedo = vec3(0.0);
	float metal = 0.0;
	float rough = 1.0;
	float ao = 1.0;
	vec3 emitted = vec3(0.0);

	if (mode == 0) {
		vec2 uv = UV * tex_scale;
		vec3 plate = texture(plate_albedo, uv).rgb;
		vec3 arm = texture(plate_arm, uv).rgb;
		float lum = dot(plate, vec3(0.299, 0.587, 0.114));
		float structure = clamp((lum - 0.16) / 0.46, 0.0, 1.0);
		albedo = mix(base_tint, wear_tint, structure * 0.5);
		albedo = mix(albedo, gold_tint, gold_mix);
		metal = mix(0.90, 1.0, gold_mix);
		rough = clamp(mix(0.18, 0.52, arm.g) * (1.0 - gold_mix * 0.4), 0.04, 1.0);
		ao = arm.r;
		NORMAL_MAP = texture(plate_normal, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
		// Cooling seams between the armour plates glow as the weapon spools.
		float seam = pow(max(sin(UV.x * 25.13274), 0.0), 90.0);
		float pulse = 0.55 + 0.45 * sin(run * 26.0 - TIME * 7.0 - charge * 8.0);
		// Only the sleeves nearest the emitter light up, and only once spooling.
		float wake = smoothstep(0.10, 0.75, charge) * pow(1.0 - run, 2.0);
		emitted = energy * seam * pulse * wake * seam_gain * 2.6
			+ gold_tint * gold_mix * (0.10 + 0.55 * charge) * 0.8;
	} else if (mode == 1) {
		// Capacitor ring: current circulates, and packets race forward along the
		// rails, so no element of the weapon sits at a flat constant glow.
		float around = atan(v_obj.y, v_obj.x);
		float circulate = pow(0.5 + 0.5 * sin(around * 3.0 - TIME * (2.5 + 9.0 * charge) + run * 18.0), 3.0);
		float packet = pow(0.5 + 0.5 * sin(run * 30.0 + TIME * (4.0 + 22.0 * charge)), 6.0);
		float band = 0.22 + 0.55 * circulate + 0.45 * packet;
		float level = smoothstep(0.0, 0.85, charge);
		float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		albedo = energy * 0.05;
		metal = 0.55;
		rough = 0.24;
		emitted = energy * band * (0.06 + 0.94 * level) * (1.1 + firing * 6.0) * (0.55 + 0.75 * rim);
	} else {
		// Emitter throat.
		float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
		float boil = 0.62 + 0.38 * sin(v_obj.x * 60.0 + v_obj.y * 47.0 - TIME * 16.0);
		float level = 0.22 + 0.78 * smoothstep(0.0, 1.0, charge);
		metal = 0.0;
		rough = 1.0;
		emitted = mix(energy, vec3(1.0, 0.97, 0.94), clamp(firing * 0.85 + charge * 0.25, 0.0, 1.0))
			* (level * (0.9 + rim * 1.3) * boil) * (1.6 + firing * 9.0);
	}

	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.55;
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
	EMISSION = emitted;
}
