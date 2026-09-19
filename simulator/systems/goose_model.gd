extends RefCounted
class_name GooseModel
## A Canada goose in flight, built from smooth lofted sections: outstretched
## neck, tapered body, wedge tail and two cambered wings with scalloped trailing
## edges. Faces -Z like every other contact. "WingL" and "WingR" pivot at the
## shoulders so combat code can flap them with rotation.z.
const PLUMAGE := preload("res://assets/look/goose_plumage.gdshader")
# z, half width, half height, centre height: bill tip to tail tip.
const SECTIONS: Array = [
	[-3.62,.012,.010,.150],[-3.55,.050,.030,.155],[-3.30,.085,.070,.170],[-3.16,.130,.135,.190],[-3.00,.150,.160,.195],
	[-2.84,.135,.140,.185],[-2.65,.105,.105,.172],[-2.30,.098,.098,.160],[-1.85,.112,.112,.142],[-1.45,.150,.150,.110],
	[-1.22,.230,.225,.070],[-0.95,.360,.345,.020],[-0.55,.500,.470,-.015],[-0.10,.560,.520,-.030],[0.40,.545,.495,-.020],
	[0.85,.455,.400,.000],[1.20,.330,.255,.020],[1.50,.215,.115,.035],[1.78,.120,.040,.050],[1.92,.015,.010,.055]]
static var _grain: NoiseTexture2D

static func create() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new(); body.name = "Body"; body.mesh = _body_mesh(); body.material_override = _material(false)
	root.add_child(body)
	for side: int in [-1,1]:
		var wing := Node3D.new(); wing.name = "WingL" if side<0 else "WingR"
		wing.position = Vector3(side*0.40,0.16,-0.30)
		var surface := MeshInstance3D.new(); surface.mesh = _wing_mesh(float(side)); surface.material_override = _material(true)
		wing.add_child(surface); root.add_child(wing)
	return root

static func _material(wing: bool) -> ShaderMaterial:
	if _grain==null:
		var noise := FastNoiseLite.new(); noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.frequency = 0.035; noise.fractal_octaves = 4
		_grain = NoiseTexture2D.new(); _grain.width = 256; _grain.height = 256; _grain.seamless = true; _grain.generate_mipmaps = true; _grain.noise = noise
	var material := ShaderMaterial.new(); material.shader = PLUMAGE
	material.set_shader_parameter("grain",_grain); material.set_shader_parameter("wing",wing)
	return material

## Resample the hand-placed sections with Catmull-Rom so the loft is smooth.
static func _profile(t: float) -> Array:
	var count: int = SECTIONS.size()
	var f: float = clampf(t,0,1)*(count-1)
	var i: int = mini(int(f),count-2); var u: float = f-i
	var out: Array = []
	for k in range(4):
		var p0: float = SECTIONS[maxi(i-1,0)][k]; var p1: float = SECTIONS[i][k]; var p2: float = SECTIONS[i+1][k]; var p3: float = SECTIONS[mini(i+2,count-1)][k]
		out.append(0.5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u*u*u))
	return out

static func _body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 96; var sides := 24
	for r in range(rings+1):
		var p: Array = _profile(float(r)/rings)
		for s in range(sides):
			var a: float = TAU*float(s)/sides
			# Slightly flat-bottomed ellipse reads as a bird's keel rather than a tube.
			var y: float = sin(a); if y<0: y *= 0.86
			st.set_uv(Vector2(float(s)/sides,float(r)/rings))
			st.add_vertex(Vector3(cos(a)*maxf(p[1],0.001),p[3]+y*maxf(p[2],0.001),p[0]))
	for r in range(rings):
		for s in range(sides):
			var n: int = (s+1)%sides
			var a: int = r*sides+s; var b: int = r*sides+n; var c: int = (r+1)*sides+s; var d: int = (r+1)*sides+n
			st.add_index(a); st.add_index(b); st.add_index(c); st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()
	return st.commit()

## One wing as a closed thin shell. x runs from the shoulder to the tip.
static func _wing_mesh(side: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spans := 40; var chords := 10
	for layer in [1.0,-1.0]:
		for i in range(spans+1):
			var s: float = float(i)/spans
			var x: float = s*3.30
			var lead: float = -0.42+0.55*pow(s,1.6)                       # swept leading edge
			var chord: float = lerpf(1.30,0.34,pow(s,0.85))
			# Scalloped trailing edge: secondaries inboard, longer primaries at the tip.
			chord *= 1.0-0.07*absf(sin(s*PI*11.0))*smoothstep(0.1,0.4,s)
			var droop: float = -0.20*s*s+0.05*sin(s*PI)
			for j in range(chords+1):
				var c: float = float(j)/chords
				var thickness: float = 0.075*(1.0-s*0.75)*sqrt(maxf(c,0.0))*(1.0-c)*2.2
				var camber: float = 0.10*(1.0-s*0.5)*sin(c*PI)
				st.set_uv(Vector2(s,c))
				st.add_vertex(Vector3(side*x,droop+camber+(thickness if layer>0 else -thickness*0.35),lead+c*chord))
	var stride: int = chords+1; var block: int = (spans+1)*stride
	for layer_index in range(2):
		for i in range(spans):
			for j in range(chords):
				var a: int = layer_index*block+i*stride+j; var b: int = a+1; var c: int = a+stride; var d: int = c+1
				var flip: bool = (layer_index==0)==(side>0)
				if flip: st.add_index(a); st.add_index(b); st.add_index(c); st.add_index(b); st.add_index(d); st.add_index(c)
				else: st.add_index(a); st.add_index(c); st.add_index(b); st.add_index(b); st.add_index(c); st.add_index(d)
	st.generate_normals()
	return st.commit()
