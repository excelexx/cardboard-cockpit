shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap;
uniform sampler2D front_clouds : source_color, filter_linear_mipmap;
void sky() {
	vec3 d=normalize(EYEDIR);
	float azimuth=atan(d.x,-d.z);
	float elevation=asin(d.y);
	vec2 spherical=vec2(.5+azimuth/(2.0*PI),.5-elevation/PI)+vec2(.03,.045);
	vec3 surround=texture(panorama,vec2(fract(spherical.x),clamp(spherical.y,0.0,1.0))).rgb*.50;
	vec2 front_uv=vec2(.5+azimuth/radians(140.0),1.0-elevation/radians(65.0));
	vec3 front=texture(front_clouds,clamp(front_uv,vec2(0),vec2(1))).rgb*.78;
	float weight=(1.0-smoothstep(radians(60.0),radians(74.0),abs(azimuth)))*smoothstep(-.15,.02,d.y);
	vec3 sunlight=normalize(vec3(.459,.208,-.864));
	float disk=smoothstep(.99995,.99999,dot(d,sunlight));
	COLOR=mix(surround,front,weight)+vec3(1,.83,.60)*disk*4.0;
}
