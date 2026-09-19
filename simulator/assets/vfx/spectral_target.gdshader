shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
uniform float confidence=0.0;
uniform float hit=0.0;
uniform float damage=0.0;
uniform float visibility=1.0;
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 float rim=pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),2.4);
 float scan=pow(.5+.5*sin(local_point.y*.45-TIME*4.0),22.0)*.055*confidence;
 vec3 cyan=mix(vec3(.015,.35,.9),vec3(.16,.9,1.0),confidence);
 cyan=mix(cyan,vec3(.8,1.0,1.0),hit*.75);
 EMISSION=cyan*(rim*(2.1+confidence*3.0)+hit*2.0+scan);
 ALBEDO=cyan;
 ALPHA=clamp(rim*(.42+.4*confidence)+hit*.18+scan,0.0,.85)*visibility;
}
