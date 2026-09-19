shader_type spatial;
uniform vec4 tint : source_color=vec4(0.28,0.34,0.35,1);
varying vec3 p;
varying vec3 n;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;n=normalize(mat3(MODEL_MATRIX)*NORMAL);}
void fragment(){
 float across=abs(n.x)>0.5?p.z:p.x;
 float aa=max(fwidth(across),0.001);
 float ribs=cos(across*19.0)*exp(-aa*12.0);
 float weather=0.94+0.045*sin(p.y*0.17+sin(across*0.21));
 ALBEDO=tint.rgb*weather*(0.88+ribs*0.12);
 ROUGHNESS=0.48+ribs*0.06;
 METALLIC=0.35;
}
