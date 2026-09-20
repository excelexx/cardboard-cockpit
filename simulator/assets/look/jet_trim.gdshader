shader_type spatial;
// Edge trim. The ribbon meshes carry their colour per vertex: gold along the
// real creases, a subdued blood red on the fins. Alpha is how hot the strip
// glows, so one material serves both a lit metal strip and matt paint.
render_mode diffuse_burley, specular_schlick_ggx;
uniform float energy = 0.40;

void fragment() {
	ALBEDO = COLOR.rgb * 0.26;
	METALLIC = 0.72;
	ROUGHNESS = 0.24;
	SPECULAR = 0.85;
	RIM = 0.4;
	EMISSION = COLOR.rgb * COLOR.a * energy;
}
