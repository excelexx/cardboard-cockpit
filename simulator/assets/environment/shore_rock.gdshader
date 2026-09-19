shader_type spatial;
uniform sampler2D granite : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 p;
varying vec3 n;
void vertex() { p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz; n=normalize(mat3(MODEL_MATRIX)*NORMAL); }
void fragment() {
	vec3 weights=pow(abs(n),vec3(4)); weights/=max(dot(weights,vec3(1)),.001);
	vec3 rock=texture(granite,p.zy*.16).rgb*weights.x+texture(granite,p.xz*.16).rgb*weights.y+texture(granite,p.xy*.16).rgb*weights.z;
	float wet=1.0-smoothstep(-8.5,-4.0,p.y);
	ALBEDO=rock*mix(.82,.43,wet); ROUGHNESS=mix(.87,.30,wet);
}
