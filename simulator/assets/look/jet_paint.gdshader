shader_type spatial;
// Low-observable fighter paint over the livery texture. Real RAM coating is a
// satin, faintly metallic grey that is never uniform: panels differ slightly in
// sheen, grime streaks aft along the airflow, and edges polish. All of it is
// derived from model-space position so it needs no extra UVs or textures.
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D livery : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wear = 1.0;
varying vec3 local;
varying vec3 local_normal;
void vertex() { local = VERTEX; local_normal = NORMAL; }
void fragment() {
	vec3 paint = texture(livery, UV).rgb;
	// Streaks run nose to tail (model Z); stretch the noise 12:1 along it.
	float streak = texture(grain, vec2(local.x * 1.1 + local.y * 0.7, local.z * 0.09)).r;
	float blotch = texture(grain, local.xz * 0.16 + local.y * 0.11).r;
	float fine = texture(grain, local.xz * 2.3 + local.y * 1.9).r;
	float top = smoothstep(-0.2, 0.6, local_normal.y);
	float grime = clamp((streak - 0.52) * 2.2, 0.0, 1.0) * 0.20 + (0.5 - blotch) * 0.10;
	paint *= 1.0 - grime * wear * mix(1.0, 0.7, top);
	paint = mix(paint, paint * vec3(1.04, 1.0, 0.95), top * 0.5);   // sun-faded upper surfaces
	ALBEDO = paint * 0.92;
	METALLIC = 0.38;
	SPECULAR = 0.5;
	ROUGHNESS = clamp(0.40 + (blotch - 0.5) * 0.22 + (fine - 0.5) * 0.10 + grime * 0.25, 0.22, 0.75);
}
