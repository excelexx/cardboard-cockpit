shader_type spatial;
uniform vec4 stone : source_color = vec4(0.48,0.49,0.47,1.0);
uniform sampler2D masonry_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D masonry_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float glazing = 0.0;
uniform vec3 tint : source_color = vec3(0.48,0.49,0.47);
varying vec3 p;
varying vec3 n;
varying float seed;
float hash(vec2 v){return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453);}
void vertex(){
 p=VERTEX*vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 n=NORMAL;
 seed=hash(MODEL_MATRIX[3].xz);
}
void fragment(){
 vec2 facade=vec2(abs(n.x)>0.5?p.z:p.x,p.y);
 // Per-building bay widths and floor heights avoid one repeated window stamp.
 vec2 cell=facade/vec2(mix(2.8,4.4,seed),mix(3.1,3.8,fract(seed*7.0)));
 vec2 f=fract(cell);
 vec2 aa=max(fwidth(cell),vec2(0.002));
 float window=smoothstep(0.25-aa.x,0.25+aa.x,f.x)*(1.0-smoothstep(0.72-aa.x,0.72+aa.x,f.x));
 window*=smoothstep(0.22-aa.y,0.22+aa.y,f.y)*(1.0-smoothstep(0.77-aa.y,0.77+aa.y,f.y));
 window*=1.0-smoothstep(0.4,0.8,abs(n.y));
 float room=hash(floor(cell)+seed*91.0);
 vec3 masonry=tint*mix(0.72,1.12,seed);
 masonry=mix(masonry,vec3(0.21,0.18,0.15),step(0.68,seed)*0.30);
 vec3 scan=texture(masonry_texture,facade/8.0).rgb;
 masonry*=mix(vec3(0.9),scan*1.6,0.45);
 float band=(1.0-smoothstep(0.035,0.075,f.y))*(1.0-abs(n.y));
 masonry=mix(masonry,masonry*0.65,band*0.65);
 float sill=smoothstep(0.18,0.205,f.y)*(1.0-smoothstep(0.215,0.235,f.y));
 masonry+=vec3(0.06)*sill*(1.0-abs(n.y));
 vec3 glass=mix(vec3(0.025,0.038,0.044),vec3(0.11,0.15,0.16),room);
 float blinds=step(0.65,room)*step(0.55,f.y);
 glass=mix(glass,vec3(0.24,0.25,0.23),blinds*0.55);
 ALBEDO=mix(masonry,glass,window);
 float curtain=glazing*(1.0-smoothstep(0.4,0.8,abs(n.y)));
 float mullion=(1.0-smoothstep(0.018,0.035,min(f.x,1.0-f.x)))+(1.0-smoothstep(0.015,0.035,min(f.y,1.0-f.y)));
 ALBEDO=mix(ALBEDO,mix(vec3(0.065,0.15,0.19),vec3(0.23,0.30,0.33),clamp(mullion,0.0,1.0)),curtain);
 ROUGHNESS=mix(0.83,0.23,window);
 METALLIC=window*0.32;
 ROUGHNESS=mix(ROUGHNESS,0.22,curtain);
 METALLIC=mix(METALLIC,0.55,curtain);
 // Recessed window shading without additional geometry on distant buildings.
 AO=1.0-window*(1.0-curtain)*0.24;
 AO_LIGHT_AFFECT=0.35;
 NORMAL_MAP=texture(masonry_normal,facade/8.0).rgb;
 NORMAL_MAP_DEPTH=(1.0-window)*(1.0-curtain)*0.45;
 EMISSION=vec3(1.0,0.66,0.31)*window*step(0.985,room)*0.08;
}
