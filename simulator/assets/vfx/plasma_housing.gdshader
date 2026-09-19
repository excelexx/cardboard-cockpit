shader_type spatial;
uniform sampler2D palette : source_color, filter_nearest;
void fragment() {
	vec3 source = texture(palette,UV).rgb;
	float brightness = dot(source,vec3(0.2126,0.7152,0.0722));
	vec3 ceramic = vec3(0.76,0.78,0.72);
	vec3 titanium = vec3(0.045,0.075,0.11);
	vec3 color = mix(titanium,ceramic,smoothstep(0.25,0.8,brightness));
	if(source.r > source.b*1.8 && source.r > 0.4) color = vec3(0.65,0.31,0.08);
	ALBEDO = color;
	METALLIC = brightness>0.72 ? 0.25 : 0.7;
	ROUGHNESS = 0.34;
}
