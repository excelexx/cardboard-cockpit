extends RefCounted
class_name GooseModel
## A Canada goose in flight, built from smooth lofted sections: outstretched
## neck, tapered body, wedge tail and two cambered wings with scalloped trailing
## edges. Faces -Z like every other contact. "WingL" and "WingR" pivot at the
## shoulders so combat code can flap them with rotation.z.
##
## EVERY mesh and EVERY material is built once and shared by the whole flock.
## create() is a node allocation, not a mesh build, so a twelve-bird skein costs
## twelve Node3D/MeshInstance3D allocations instead of twelve SurfaceTool runs.
## Per-bird variation (damage, wing flex) rides on instance shader parameters,
## never on a duplicated material - duplicating would break batching again.
const PLUMAGE := preload("res://assets/look/goose_plumage.gdshader")
# z, half width, half height, centre height: bill tip to tail tip.
const SECTIONS: Array = [
	[-3.62,.012,.010,.150],[-3.55,.050,.030,.155],[-3.30,.085,.070,.170],[-3.16,.130,.135,.190],[-3.00,.150,.160,.195],
	[-2.84,.135,.140,.185],[-2.65,.105,.105,.172],[-2.30,.098,.098,.160],[-1.85,.112,.112,.142],[-1.45,.150,.150,.110],
	[-1.22,.230,.225,.070],[-0.95,.360,.345,.020],[-0.55,.500,.470,-.015],[-0.10,.560,.520,-.030],[0.40,.545,.495,-.020],
	[0.85,.455,.400,.000],[1.20,.330,.255,.020],[1.50,.215,.115,.035],[1.78,.120,.040,.050],[1.92,.015,.010,.055]]

## Lightweight detail ladder: 512, 240, and 152 triangles per bird.
const LOD_LEVELS: Array = [
	{"rings":24,"sides":8,"spans":8,"chords":2},
	{"rings":16,"sides":6,"spans":6,"chords":1},
	{"rings":10,"sides":6,"spans":4,"chords":1}]
## Swap down past these distances, swap back up at LOD_UP: the gap is the
## hysteresis that stops a bird flickering between levels on the boundary.
const LOD_DOWN: Array = [500.0,1200.0]
const LOD_UP: Array = [420.0,1050.0]
## Kept for distance-policy compatibility; low-detail birds never cast shadows.
const SHADOW_DISTANCE := 500.0
const WING_SPAN := 3.30

static var _body_lod: Array[ArrayMesh] = []
static var _wing_lod: Array = []            # [lod][0]=left wing, [1]=right wing
static var _body_material: ShaderMaterial
static var _wing_material: ShaderMaterial
static var _build_ms := 0.0

## Build every shared mesh and material. Called automatically by the first
## create(); call it during a loading screen to keep that cost off the flock's
## first frame. Idempotent.
static func prewarm() -> void:
	if not _body_lod.is_empty(): return
	var started := Time.get_ticks_usec()
	_ensure_materials()
	for level: int in range(LOD_LEVELS.size()):
		var spec: Dictionary = LOD_LEVELS[level]
		_body_lod.append(_body_mesh(int(spec.rings),int(spec.sides)))
		_wing_lod.append([_wing_mesh(-1.0,int(spec.spans),int(spec.chords)),_wing_mesh(1.0,int(spec.spans),int(spec.chords))])
	_build_ms = float(Time.get_ticks_usec()-started)/1000.0

static func build_milliseconds() -> float: return _build_ms

static func create(lod: int = 0) -> Node3D:
	prewarm()
	var level: int = clampi(lod,0,LOD_LEVELS.size()-1)
	var root := Node3D.new(); root.name = "Goose"
	var body := MeshInstance3D.new(); body.name = "Body"
	body.mesh = _body_lod[level]; body.material_override = _body_material
	root.add_child(body)
	for side: int in [-1,1]:
		var wing := Node3D.new(); wing.name = "WingL" if side<0 else "WingR"
		wing.position = Vector3(side*0.40,0.16,-0.30)
		var surface := MeshInstance3D.new(); surface.name = "Feathers"
		surface.mesh = _wing_lod[level][0 if side<0 else 1]
		surface.material_override = _wing_material
		wing.add_child(surface); root.add_child(wing)
	root.set_meta("lod",level)
	_apply_shadows(root,false)
	return root

## Swap a live bird between detail levels. A mesh pointer swap, nothing rebuilt.
static func set_lod(root: Node3D, lod: int) -> bool:
	if root==null or not is_instance_valid(root): return false
	var level: int = clampi(lod,0,LOD_LEVELS.size()-1)
	if int(root.get_meta("lod",-1))==level: return false
	prewarm()
	var body := root.get_node_or_null("Body") as MeshInstance3D
	if body!=null: body.mesh = _body_lod[level]
	for side: int in [-1,1]:
		var pivot := root.get_node_or_null("WingL" if side<0 else "WingR")
		if pivot==null: continue
		var surface := pivot.get_node_or_null("Feathers") as MeshInstance3D
		if surface!=null: surface.mesh = _wing_lod[level][0 if side<0 else 1]
	root.set_meta("lod",level)
	_apply_shadows(root,false)
	return true

static func current_lod(root: Node3D) -> int:
	return int(root.get_meta("lod",0)) if root!=null and is_instance_valid(root) else 0

## Level a bird at this range should be drawn at, given the level it is on now.
static func lod_for_distance(distance: float, present: int) -> int:
	var wanted := present
	if present<LOD_DOWN.size() and distance>float(LOD_DOWN[present]): wanted = present+1
	elif present>0 and distance<float(LOD_UP[present-1]): wanted = present-1
	return clampi(wanted,0,LOD_LEVELS.size()-1)

static func triangles(lod: int) -> int:
	var spec: Dictionary = LOD_LEVELS[clampi(lod,0,LOD_LEVELS.size()-1)]
	return int(spec.rings)*int(spec.sides)*2+int(spec.spans)*int(spec.chords)*8

static func _apply_shadows(root: Node3D, on: bool) -> void:
	for geometry: Node in [root.get_node_or_null("Body"),root.get_node_or_null("WingL/Feathers"),root.get_node_or_null("WingR/Feathers")]:
		if geometry is GeometryInstance3D:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _ensure_materials() -> void:
	if _body_material==null: _body_material = _material(false)
	if _wing_material==null: _wing_material = _material(true)

static func body_material() -> ShaderMaterial:
	_ensure_materials(); return _body_material

static func wing_material() -> ShaderMaterial:
	_ensure_materials(); return _wing_material

static func _material(wing: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new(); material.shader = PLUMAGE
	material.set_shader_parameter("wing",wing)
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

static func _body_mesh(rings: int, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
static func _wing_mesh(side: float, spans: int, chords: int) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The scallop is an 11-cycle ripple: below ~20 spans it aliases into a
	# ragged edge, so the coarse levels keep a clean trailing edge instead.
	var scallop: float = 0.07 if spans>=20 else 0.0
	for layer in [1.0,-1.0]:
		for i in range(spans+1):
			var s: float = float(i)/spans
			var x: float = s*WING_SPAN
			var lead: float = -0.42+0.55*pow(s,1.6)                       # swept leading edge
			var chord: float = lerpf(1.30,0.34,pow(s,0.85))
			# Scalloped trailing edge: secondaries inboard, longer primaries at the tip.
			chord *= 1.0-scallop*absf(sin(s*PI*11.0))*smoothstep(0.1,0.4,s)
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
