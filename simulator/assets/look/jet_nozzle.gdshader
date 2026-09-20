shader_type spatial;
// Heat-tinted titanium around the exhaust. Real nozzle petals temper in bands
// as they get hotter toward the exit: grey, straw, violet, then blue.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float heat = 1.0;
uniform float axis_y = -0.30;
uniform float start_z = 5.40;
uniform float end_z = 7.30;
varying vec3 local;

void vertex() { local = VERTEX; }

void fragment() {
	float band = clamp((local.z - start_z) / max(0.001, end_z - start_z), 0.0, 1.0);
	float around = atan(local.x, local.y - axis_y) * 0.92;
	float streak = texture(grain, vec2(around, local.z * 0.75)).r;
	vec3 metal = mix(vec3(0.185, 0.180, 0.175), vec3(0.31, 0.225, 0.105), smoothstep(0.05, 0.45, band));
	metal = mix(metal, vec3(0.205, 0.130, 0.190), smoothstep(0.45, 0.72, band));
	metal = mix(metal, vec3(0.100, 0.135, 0.215), smoothstep(0.72, 1.0, band));
	metal *= mix(0.76, 1.20, streak);
	ALBEDO = metal;
	METALLIC = 0.94;
	SPECULAR = 0.72;
	ROUGHNESS = clamp(0.30 - band * 0.10 + (streak - 0.5) * 0.14, 0.12, 0.55);
	RIM = 0.55;
	EMISSION = vec3(0.95, 0.26, 0.055) * smoothstep(0.82, 1.0, band) * heat * 0.10;
}
