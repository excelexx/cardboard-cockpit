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
## violet, magenta, gold and cyan on the beam at the same time and scrolls them
## toward the target.
const Shapes = preload("res://systems/model_utils.gd")
const TRACER_SHADER := "res://assets/vfx/tracer.gdshader"
const BEAM_SHADER := "res://assets/vfx/plasma_beam.gdshader"
const ARC_SHADER := "res://assets/vfx/plasma_flow.gdshader"
const BLOOM_SHADER := "res://assets/vfx/impact_bloom.gdshader"
const THROAT_SHADER := "res://assets/vfx/plasma_housing.gdshader"

# The beam palette, kept in step with plasma_beam.gdshader / plasma_flow.gdshader.
const HUES: Array[Color] = [Color(0.46, 0.10, 1.00), Color(1.00, 0.12, 0.66), Color(1.00, 0.70, 0.14), Color(0.08, 0.92, 1.00)]
const BEAM_WAVELENGTH := 210.0
const BEAM_FLOW := 330.0
const TRACER_HEAD := -0.40
const TRACER_TAIL := 8.00

static var _tracer_mesh: ArrayMesh
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
	root.scale = Vector3.ONE*(3.2 if in_flight else 2.0)
	if in_flight:
		# Narrow tapered motor plume leaves the seeker, body and fins readable.
		for layer in range(2):
			var plume := MeshInstance3D.new(); var cone := CylinderMesh.new()
			cone.top_radius = .16 if layer==0 else .065; cone.bottom_radius = .004
			cone.height = 3.2 if layer==0 else 1.75; cone.radial_segments = 20
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
static func _tracer_strip() -> ArrayMesh:
	if _tracer_mesh!=null: return _tracer_mesh
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 10
	for i in range(steps+1):
		var t: float = float(i)/steps
		var z: float = lerpf(TRACER_HEAD,TRACER_TAIL,t*t*0.35+t*0.65)
		for side in [0.0,1.0]:
			st.set_uv(Vector2(side,t)); st.set_normal(Vector3.BACK); st.add_vertex(Vector3(0,0,z))
	for i in range(steps):
		var a: int = i*2
		st.add_index(a); st.add_index(a+1); st.add_index(a+2)
		st.add_index(a+1); st.add_index(a+3); st.add_index(a+2)
	_tracer_mesh = st.commit()
	# The vertex stage builds the billboard, so the mesh AABB is a bare line.
	_tracer_mesh.custom_aabb = AABB(Vector3(-2,-2,TRACER_HEAD-1),Vector3(4,4,TRACER_TAIL-TRACER_HEAD+2))
	return _tracer_mesh

static func _tracer_shader() -> ShaderMaterial:
	if _tracer_material!=null: return _tracer_material
	_tracer_material = ShaderMaterial.new()
	_tracer_material.shader = load(TRACER_SHADER)
	_tracer_material.set_shader_parameter("width",0.055)
	_tracer_material.set_shader_parameter("min_width",0.0012)
	_tracer_material.set_shader_parameter("head_z",TRACER_HEAD)
	_tracer_material.set_shader_parameter("head_radius",0.22)
	_tracer_material.set_shader_parameter("intensity",2.2)
	return _tracer_material

static func projectile(kind: String, _variant: String = "gatling") -> Node3D:
	if kind=="missile": return missile(true)
	if kind=="plasma": return plasma_bolt()
	var root := Node3D.new(); root.name = "CannonTracer"
	var streak := MeshInstance3D.new(); streak.name = "Streak"
	streak.mesh = _tracer_strip(); streak.material_override = _tracer_shader()
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
		halo.set_shader_parameter("core_colour",Color(0.92,0.96,1.0)); halo.set_shader_parameter("edge_colour",Color(0.55,0.18,1.0))
		var tail := ShaderMaterial.new(); tail.shader = load(TRACER_SHADER)
		tail.set_shader_parameter("width",0.16); tail.set_shader_parameter("min_width",0.0026)
		tail.set_shader_parameter("head_z",TRACER_HEAD); tail.set_shader_parameter("head_radius",0.02)
		tail.set_shader_parameter("head_colour",Color(0.90,0.95,1.0)); tail.set_shader_parameter("mid_colour",Color(0.70,0.25,1.0))
		tail.set_shader_parameter("tail_colour",Color(0.22,0.60,1.0)); tail.set_shader_parameter("tail_power",2.6)
		tail.set_shader_parameter("intensity",0.8)
		_bolt_materials = {"core":core,"halo":halo,"tail":tail}
	var streak := MeshInstance3D.new(); streak.name = "Streak"
	streak.mesh = _tracer_strip(); streak.material_override = _bolt_materials.tail
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
	mesh.custom_aabb = AABB(Vector3(-9,-0.5,-9),Vector3(18,1,18))
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
		material.set_shader_parameter("min_width",[0.0020,0.0038,0.0075][clampi(layer,0,2)])
	else:
		material.set_shader_parameter("min_width",0.0044)
		material.set_shader_parameter("arc_count",4.0)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## The white-hot filament at the centre of the beam, with the discharge that
## crawls over it. Kept on the same node so one align_beam() moves both.
static func beam(parent: Node3D, color: Color, radius: float, alpha: float) -> MeshInstance3D:
	var node: MeshInstance3D = _column(parent,radius,BEAM_SHADER,0,0.0,200,clampf(alpha,0.15,1.0))
	node.name = "BeamCore"
	var material: ShaderMaterial = node.material_override
	material.set_shader_parameter("hue_gold",Color(color.r,color.g,color.b).lerp(HUES[2],0.75))
	_column(node,maxf(radius*3.4,0.34),ARC_SHADER,3,0.0,170,0.9).name = "Arcs"
	return node

## Outer layers. Under 0.5 m radius this is the braided plasma sheath; wider, it
## is the soft halo that keeps the beam readable against a bright sky.
static func energy_sheath(parent: Node3D, radius: float, phase: float) -> MeshInstance3D:
	var braid: bool = radius<0.5
	var node: MeshInstance3D = _column(parent,radius,BEAM_SHADER,1 if braid else 2,phase,180 if braid else 120,1.05 if braid else 0.90)
	node.name = "Braid" if braid else "Halo"
	if braid: _column(node,radius*1.9,ARC_SHADER,3,phase+2.1,160,0.75).name = "Arcs"
	else: _column(node,radius*1.6,BEAM_SHADER,2,phase+0.9,90,0.30).name = "Bloom"
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
