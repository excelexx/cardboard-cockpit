shader_type spatial;
render_mode cull_disabled, alpha_to_coverage;
uniform sampler2D foliage : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D foliage_b : source_color, filter_linear_mipmap_anisotropic;
varying float variation;
void vertex() {
	vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	variation=INSTANCE_CUSTOM.x;
	float height=clamp(VERTEX.y/24.0,0.0,1.0);
	VERTEX.x+=sin(TIME*1.4+world.x*.047+world.z*.025)*height*height*.24;
}
void fragment() {
	vec4 leaf=texture(foliage,UV);
	if(variation>.5) leaf=texture(foliage_b,UV);
	ALBEDO=leaf.rgb*mix(vec3(.76,.88,.77),vec3(.99,.95,.82),variation);
	ALPHA=leaf.a; ALPHA_SCISSOR_THRESHOLD=.40;
	ALPHA_ANTIALIASING_EDGE=.25;
	ALPHA_TEXTURE_COORDINATE=UV*vec2(textureSize(foliage,0));
	ROUGHNESS=.95; BACKLIGHT=leaf.rgb*.16; EMISSION=leaf.rgb*.025;
}
