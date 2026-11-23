extends RefCounted
class_name WeaponVisuals
## Everything the weapons draw: tracers, the plasma bolt, the continuous beam
## and its muzzle/impact blooms. The public names, signatures and node contracts
## are the ones combat.gd, combat_visuals.gd and fighter_effects.gd already
## call - emissive(), cylinder(), missile(), projectile(), beam(),
## align_beam(), energy_sheath() - only what they return got rebuilt.
##
## The beam is a stack of stretched cylinders. Everything it draws is computed
## from METRES ALONG THE BEAM, recovered in the shader from MODEL_MATRIX, so a
## 1900 m shot keeps its detail instead of smearing the UVs. Its colour comes
## from one periodic palette sampled by (distance - time * flow), which puts
## amber, white-hot, slate blue and violet-whisper on the beam at the same time
## and scrolls them toward the target. Those four stops are the locked palette
## and they are duplicated in plasma_beam.gdshader / plasma_flow.gdshader: change
## one, change all three.
const Shapes = preload("res://systems/model_utils.gd")
const TRACER_SHADER := "res://assets/vfx/tracer.gdshader"
const BEAM_SHADER := "res://assets/vfx/plasma_beam.gdshader"
const ARC_SHADER := "res://assets/vfx/plasma_flow.gdshader"
const BLOOM_SHADER := "res://assets/vfx/impact_bloom.gdshader"
const THROAT_SHADER := "res://assets/vfx/plasma_housing.gdshader"

# The beam palette, kept in step with plasma_beam.gdshader / plasma_flow.gdshader:
# amber, white-hot, slate blue, violet whisper.
const HUES: Array[Color] = [Color(1.00, 0.70, 0.14), Color(1.00, 0.94, 0.85), Color(0.24, 0.42, 0.78), Color(0.42, 0.24, 0.72)]
const BEAM_WAVELENGTH := 210.0
const BEAM_FLOW := 330.0
const TRACER_HEAD := -1.60
const TRACER_TAIL := 6.90
## Strip lofted AHEAD of the round so the whole incandescent head gaussian is
## inside the geometry and the nose tapers off instead of being cropped flat.
const TRACER_NOSE := 0.34
const TRACER_NOSE_UV := 0.04
## Visual-only ghost rounds baked into the same mesh. Balance and collision stay
## on the live round; this only makes a burst look like the 60 rounds/s it is.
## combat.gd fires a 2-round packet every Tune.GUN_INTERVAL (.0333 s) at
## Tune.GUN_MUZZLE_SPEED (1040 m/s), so packets sit 34.63 m apart; two ghosts
## put a round every 11.54 m, which is the ladder a gatling actually paints.
const GHOST_ROUNDS := 2
const GHOST_SPACING := 11.54

static var _tracer_meshes: Dictionary = {}
static var _tracer_material: ShaderMaterial
static var _bolt_materials: Dictionary = {}

static func emissive(color: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color,alpha); mat.emission_enabled = true; mat.emission = color
	mat.emission_energy_multiplier = energy; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha<1:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat

static func cylinder(parent: Node3D, radius: float, length: float, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new(); var mesh := CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = length; mesh.radial_segments = 32
	node.mesh = mesh; node.material_override = material; node.position = at; node.rotation.x = PI/2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node); return node

static func missile(in_flight: bool = false) -> Node3D:
	var root: Node3D = load("res://assets/sourced_flight/missile.gltf").instantiate()
	root.name = "MICA26"
	root.scale = Vector3.ONE*(1.7 if in_flight else 1.2)
	if in_flight:
		# Narrow tapered motor plume leaves the seeker, body and fins readable.
		for layer in range(2):
			var plume := MeshInstance3D.new(); var cone := CylinderMesh.new()
			cone.top_radius = .10 if layer==0 else .040; cone.bottom_radius = .004
			cone.height = 2.0 if layer==0 else 1.05; cone.radial_segments = 20
			plume.mesh = cone; plume.rotation.x = -PI/2
			plume.position.z = 1.46+cone.height*.5
			plume.name = "Ignition" if layer==0 else "MotorFlame"
			var gas := ShaderMaterial.new(); gas.shader = load("res://assets/vfx/missile_motor.gdshader")
			gas.set_shader_parameter("core",float(layer)); gas.set_shader_parameter("plume_length",cone.height); plume.material_override = gas
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(plume)
	return root

# ----------------------------------------------------------------- palette --

## One cycle of the beam palette. t is in cycles, and wraps.
static func palette(t: float) -> Color:
	var f: float = fposmod(t,1.0)*4.0
	var i: int = clampi(int(f),0,3)
	var k: float = f-floor(f)
	k = k*k*(3.0-2.0*k)
	return HUES[i].lerp(HUES[(i+1)%4],k)

## The hue the beam is showing `along` metres from the muzzle, right now. Use it
## to colour anything that has to agree with the beam (impact effects, lights).
static func beam_tint(along: float, at_time: float = -1.0) -> Color:
	var now: float = at_time if at_time>=0.0 else fmod(float(Time.get_ticks_msec())*0.001,3600.0)
	var s: float = (along-now*BEAM_FLOW)/BEAM_WAVELENGTH
	var mixed: Color = palette(s).lerp(palette(s*2.7+0.37),0.34)
	var level: float = maxf(sqrt(mixed.r*mixed.r+mixed.g*mixed.g+mixed.b*mixed.b),0.001)
	return Color(mixed.r/level,mixed.g/level,mixed.b/level,1.0)

# ---------------------------------------------------------------- tracers --

## One shared strip and one shared material serve every live round: a tracer is
## two nodes, no allocation. combat.gd stretches scale.z as the round clears the
## muzzle, and the shader turns the strip into an axis-aligned billboard so a
## round always reads as a line, never as a blob.
static func _tracer_strip(copies: int = 1) -> ArrayMesh:
	if _tracer_meshes.has(copies): return _tracer_meshes[copies]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 10
	# (object z, UV.y). UV.y is 0 at the round and 1 at the end of the streak; it
	# runs NEGATIVE over the ogive nose lofted ahead of the round.
	var rings: Array = []
	for j in range(3):
		var q: float = float(j)/2.0
		rings.append([lerpf(TRACER_HEAD-TRACER_NOSE,TRACER_HEAD,q),-TRACER_NOSE_UV*(1.0-q)])
	for i in range(1,steps+1):
		var t: float = float(i)/steps
		rings.append([lerpf(TRACER_HEAD,TRACER_TAIL,t*t*0.35+t*0.65),t])
	var index := 0
	for copy in range(maxi(copies,1)):
		# Ghost rounds LEAD the live one. Trailing ghosts would hang off the
		# scale.z stretch combat.gd applies over the round's first 9 m and briefly
		# paint tracers BEHIND the aircraft; leading ones only ever extend the
		# stream downrange, where nobody can tell them from real rounds.
		var offset: float = -GHOST_SPACING*copy
		for ring: Array in rings:
			for side in [0.0,1.0]:
				st.set_uv(Vector2(side,float(ring[1])))
				st.set_uv2(Vector2(offset,float(copy)*7.0))
				st.set_normal(Vector3.BACK)
				st.add_vertex(Vector3(0,0,float(ring[0])+offset))
		for i in range(rings.size()-1):
			var a: int = index+i*2
			st.add_index(a); st.add_index(a+1); st.add_index(a+2)
			st.add_index(a+1); st.add_index(a+3); st.add_index(a+2)
		index += rings.size()*2
	var mesh: ArrayMesh = st.commit()
	# The vertex stage builds the billboard, so the mesh AABB is a bare line.
	var front: float = TRACER_HEAD-TRACER_NOSE-GHOST_SPACING*float(maxi(copies,1)-1)-2.0
	mesh.custom_aabb = AABB(Vector3(-6,-6,front),Vector3(12,12,TRACER_TAIL-front+4.0))
	_tracer_meshes[copies] = mesh
	return mesh

static func _tracer_shader() -> ShaderMaterial:
	if _tracer_material!=null: return _tracer_material
	_tracer_material = ShaderMaterial.new()
	_tracer_material.shader = load(TRACER_SHADER)
	_tracer_material.set_shader_parameter("width",0.040)
	_tracer_material.set_shader_parameter("min_width",0.0013)
	_tracer_material.set_shader_parameter("head_z",TRACER_HEAD)
	_tracer_material.set_shader_parameter("head_radius",0.10)
	_tracer_material.set_shader_parameter("nose_uv",TRACER_NOSE_UV)
	# A round has to beat a lit sunset sky at 1 km, and an additive streak two
	# stops over the sky dissolves under AgX. Base level plus a range lift.
	_tracer_material.set_shader_parameter("intensity",4.2)
	_tracer_material.set_shader_parameter("range_gain",2.4)
	_tracer_material.set_shader_parameter("range_full",700.0)
	return _tracer_material

static func projectile(kind: String, _variant: String = "gatling") -> Node3D:
	if kind=="missile": return missile(true)
	if kind=="plasma": return plasma_bolt()
	var root := Node3D.new(); root.name = "CannonTracer"
	var streak := MeshInstance3D.new(); streak.name = "Streak"
	streak.mesh = _tracer_strip(1+GHOST_ROUNDS); streak.material_override = _tracer_shader()
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(streak)
	return root

## Pulsed plasma round: a boiling core, a gradient corona and a short streak.
static func plasma_bolt() -> Node3D:
	var root := Node3D.new(); root.name = "PlasmaBolt"
	if _bolt_materials.is_empty():
		var core := ShaderMaterial.new(); core.shader = load(THROAT_SHADER)
		core.set_shader_parameter("mode",2); core.set_shader_parameter("charge",1.0); core.set_shader_parameter("firing",1.0)
		var halo := ShaderMaterial.new(); halo.shader = load(BLOOM_SHADER)
		halo.set_shader_parameter("mode",2); halo.set_shader_parameter("loop",1.0); halo.set_shader_parameter("t",0.0)
		halo.set_shader_parameter("size",1.35); halo.set_shader_parameter("grow",1.0); halo.set_shader_parameter("intensity",1.5)
		halo.set_shader_parameter("core_colour",Color(1.0,0.97,0.92)); halo.set_shader_parameter("edge_colour",HUES[0])
		var tail := ShaderMaterial.new(); tail.shader = load(TRACER_SHADER)
		tail.set_shader_parameter("width",0.16); tail.set_shader_parameter("min_width",0.0026)
		tail.set_shader_parameter("head_z",TRACER_HEAD); tail.set_shader_parameter("head_radius",0.02)
		tail.set_shader_parameter("nose_uv",TRACER_NOSE_UV)
		tail.set_shader_parameter("head_colour",HUES[1]); tail.set_shader_parameter("mid_colour",HUES[0])
		tail.set_shader_parameter("tail_colour",HUES[2]); tail.set_shader_parameter("tail_power",2.6)
		tail.set_shader_parameter("intensity",2.0); tail.set_shader_parameter("range_gain",1.4)
		_bolt_materials = {"core":core,"halo":halo,"tail":tail}
	var streak := MeshInstance3D.new(); streak.name = "Streak"
	streak.mesh = _tracer_strip(1); streak.material_override = _bolt_materials.tail
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(streak)
	var core := MeshInstance3D.new(); core.name = "Core"
	var bulb := SphereMesh.new(); bulb.radius = 0.19; bulb.height = 0.38; bulb.radial_segments = 16; bulb.rings = 8
	core.mesh = bulb; core.material_override = _bolt_materials.core
	core.position.z = TRACER_HEAD; core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(core)
	var halo := MeshInstance3D.new(); halo.name = "Corona"
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	halo.mesh = quad; halo.material_override = _bolt_materials.halo
	halo.position.z = TRACER_HEAD; halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root.add_child(halo)
	return root

# ------------------------------------------------------------------- beam --

static var _ribbons: Dictionary = {}

## A flat strip along local +Y, -0.5..0.5, that the beam shaders billboard into
## a ribbon. combat_visuals.gd's align_beam() stretches it along Y.
static func _ribbon(segments: int) -> ArrayMesh:
	if _ribbons.has(segments): return _ribbons[segments]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments+1):
		var t: float = float(i)/segments
		for side in [0.0,1.0]:
			st.set_uv(Vector2(side,t)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3(0,t-0.5,0))
	for i in range(segments):
		var a: int = i*2
		st.add_index(a); st.add_index(a+1); st.add_index(a+2)
		st.add_index(a+1); st.add_index(a+3); st.add_index(a+2)
	var mesh: ArrayMesh = st.commit()
	# The vertex stage builds the ribbon, so the mesh AABB is a bare line; give
	# it room for the snake and the range-based widening or it culls itself.
	mesh.custom_aabb = AABB(Vector3(-26,-0.5,-26),Vector3(52,1,52))
	_ribbons[segments] = mesh
	return mesh

static func _column(parent: Node3D, radius: float, shader_path: String, layer: int, phase: float, rings: int, gain: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _ribbon(rings)
	var material := ShaderMaterial.new()
	material.shader = load(shader_path)
	material.set_shader_parameter("radius",radius)
	material.set_shader_parameter("phase",phase)
	material.set_shader_parameter("intensity",gain)
	material.set_shader_parameter("wavelength",BEAM_WAVELENGTH)
	material.set_shader_parameter("flow_speed",BEAM_FLOW)
	material.set_shader_parameter("wobble_amount",1.0)
	if shader_path==BEAM_SHADER:
		material.set_shader_parameter("layer",layer)
		# combat_visuals.gd ships ONE layer at 0.35 lateral scale, which at 0.0020
		# was a 3 px hairline with no room for the palette to show. A little wider
		# gives the coloured shoulders somewhere to live and still reads as a beam
		# rather than a bar at 1900 m (about 5 px).
		material.set_shader_parameter("min_width",[0.0034,0.0046,0.0082][clampi(layer,0,2)])
	else:
		material.set_shader_parameter("min_width",0.0044)
		material.set_shader_parameter("arc_count",4.0)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## The white-hot filament at the centre of the beam, with the discharge that
## crawls over it. Kept on the same node so one align_beam() moves both.
## `color` is kept in the signature for combat_visuals.gd, but the beam's colour
## is the locked four-stop palette now: tinting one stop from the caller put the
## shader out of step with HUES and beam_tint() then lied about the hue at the
## impact point.
static func beam(parent: Node3D, _color: Color, radius: float, alpha: float) -> MeshInstance3D:
	var node: MeshInstance3D = _column(parent,radius,BEAM_SHADER,0,0.0,200,clampf(alpha,0.15,1.0))
	node.name = "BeamCore"
	_column(node,maxf(radius*3.4,0.34),ARC_SHADER,3,0.0,170,0.9).name = "Arcs"
	return node

## Outer layers. Under 0.5 m radius this is the braided plasma sheath; wider, it
## is the soft halo that keeps the beam readable against a bright sky.
static func energy_sheath(parent: Node3D, radius: float, phase: float) -> MeshInstance3D:
	var braid: bool = radius<0.5
	var node: MeshInstance3D = _column(parent,radius,BEAM_SHADER,1 if braid else 2,phase,180 if braid else 120,0.72 if braid else 0.40)
	node.name = "Braid" if braid else "Halo"
	if braid: _column(node,radius*1.9,ARC_SHADER,3,phase+2.1,160,0.75).name = "Arcs"
	else: _column(node,radius*1.3,BEAM_SHADER,2,phase+0.9,90,0.14).name = "Bloom"
	return node

static func align_beam(node: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction: Vector3 = end-start
	node.position = (start+end)*0.5
	var aim: Vector3 = direction.normalized()
	if aim.length_squared()<0.5: aim = Vector3.UP
	node.basis = Basis(Quaternion(Vector3.UP,aim)) if aim.dot(Vector3.UP)>-0.9999 else Basis.from_euler(Vector3(PI,0,0))
	node.scale = Vector3(1,maxf(direction.length(),0.001),1)

# ---------------------------------------------------------------- blooms --

## A muzzle corona (muzzle=true) or an impact bloom for the far end of the beam.
## Park it with node.position/look and feed it drive_bloom() each frame.
static func beam_bloom(parent: Node3D, muzzle: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "BeamMuzzleCorona" if muzzle else "BeamImpactBloom"
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	node.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = load(BLOOM_SHADER)
	material.set_shader_parameter("mode",2)
	material.set_shader_parameter("loop",1.0)
	material.set_shader_parameter("t",0.0)
	material.set_shader_parameter("grow",1.0)
	material.set_shader_parameter("size",0.9 if muzzle else 2.4)
	material.set_shader_parameter("intensity",1.0)
	material.set_shader_parameter("core_colour",Color(1,0.98,0.95))
	material.set_shader_parameter("edge_colour",HUES[0])
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	parent.add_child(node)
	return node

## intensity 0 hides it. `along` is the distance from the muzzle, so the bloom
## takes the hue the beam is carrying at that point.
static func drive_bloom(node: MeshInstance3D, intensity: float, along: float, size: float = -1.0) -> void:
	if not is_instance_valid(node): return
	node.visible = intensity>0.01
	if not node.visible: return
	var material: ShaderMaterial = node.material_override
	var tint: Color = beam_tint(along)
	material.set_shader_parameter("intensity",intensity)
	material.set_shader_parameter("edge_colour",tint)
	material.set_shader_parameter("core_colour",tint.lerp(Color(1,1,1),0.45))
	if size>0.0: material.set_shader_parameter("size",size)
