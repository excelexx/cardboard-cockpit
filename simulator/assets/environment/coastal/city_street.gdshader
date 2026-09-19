shader_type spatial;
varying vec2 metres;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){
 metres=vec2(VERTEX.x*length(MODEL_MATRIX[0].xyz),VERTEX.z*length(MODEL_MATRIX[2].xyz));
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 float grain=hash(floor(world.xz*3.0));
 ALBEDO=vec3(.055,.064,.070)*(0.9+grain*.18);
 float line=(1.0-smoothstep(.08,.19,abs(metres.x)))*step(.38,fract(metres.y/12.0));
 ALBEDO=mix(ALBEDO,vec3(.64,.60,.41),line*.7);
 ROUGHNESS=.92;
}
