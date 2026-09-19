extends RefCounted
class_name WeaponVisuals
const Shapes = preload("res://systems/fantasy_aircraft.gd")
static func emissive(color: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color,alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha<1:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat
static func cylinder(parent: Node3D, radius: float, length: float, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation.x = PI/2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
static func projectile(kind: String, variant: String = "gatling") -> Node3D:
	var root := Node3D.new()
	if kind=="missile":
		var heavy: bool = variant=="battery"
		var model: Node3D = load("res://assets/weapons/%s.glb" % ("battery" if heavy else "seeker")).instantiate()
		model.rotation = Vector3(0,PI/2,0) if heavy else Vector3(-PI/2,0,0)
		var bounds: AABB = Shapes.bounds(model)
		var size: float = 6.2 if heavy else 4.8
		var scale_factor: float = size/maxf(bounds.size.z,0.01)
		model.scale = Vector3.ONE*scale_factor
		model.position = -bounds.get_center()*scale_factor
		root.add_child(model)
		var exhaust := Sprite3D.new()
		exhaust.texture = load("res://assets/vfx/flash.png")
		exhaust.pixel_size = 0.0025
		exhaust.position.z = size*0.5+0.18
		exhaust.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		exhaust.modulate = Color(1,0.63,0.24,0.85)
		exhaust.shaded = false
		root.add_child(exhaust)
		cylinder(root,0.10,1.8,emissive(Color(1,0.64,0.2),3),Vector3(0,0,size*0.5+0.8))
	elif kind=="plasma":
		cylinder(root,0.15,2.6,emissive(Color(0.85,0.99,1),4))
		cylinder(root,0.35,3.3,emissive(Color(0.15,0.65,1),2,0.36))
		cylinder(root,0.55,3.6,emissive(Color(0.1,0.3,0.85),1,0.10))
	else:
		var heavy: bool = variant=="heavy"
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.65,0.43,0.16) if not heavy else Color(0.30,0.33,0.36)
		shell.metallic = 0.85
		shell.roughness = 0.25
		cylinder(root,0.09 if not heavy else 0.16,0.65 if not heavy else 1.1,shell)
		var tip := Color(1,0.25,0.04) if kind=="hostile" else Color(1,0.65,0.17) if heavy else Color(1,0.85,0.43)
		cylinder(root,0.025 if not heavy else 0.045,3.2 if not heavy else 5.2,emissive(tip,3),Vector3(0,0,1.5))
	return root
static func beam(parent: Node3D, color: Color, radius: float, alpha: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = 1.0
	shape.radial_segments = 16
	node.mesh = shape
	node.material_override = emissive(color,3,alpha)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
static func align_beam(node: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction: Vector3 = end-start
	node.position = (start+end)*0.5
	node.basis = Basis(Quaternion(Vector3.UP,direction.normalized()))
	node.scale = Vector3(1,maxf(direction.length(),0.001),1)

static func plasma_emitter() -> Node3D:
	var root := Node3D.new()
	root.name = "PlasmaEmitter"
	var chassis: Node3D = load("res://assets/weapons/blaster-p.glb").instantiate()
	var bounds: AABB = Shapes.bounds(chassis)
	var factor: float = 6.4/maxf(bounds.size.z,0.01)
	chassis.scale = Vector3.ONE*factor
	chassis.position = -bounds.get_center()*factor+Vector3(0,0.75,0)
	var housing := ShaderMaterial.new()
	housing.shader = load("res://assets/vfx/plasma_housing.gdshader")
	housing.set_shader_parameter("palette",load("res://assets/weapons/Textures/colormap.png"))
	for node: Node in chassis.find_children("*","MeshInstance3D",true,false): node.material_override = housing
	if chassis is MeshInstance3D: chassis.material_override = housing
	root.add_child(chassis)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.06,0.1,0.14)
	steel.metallic = 0.75
	steel.roughness = 0.25
	cylinder(root,0.45,5.5,steel,Vector3(0,0.9,-0.4))
	var rings: Array[StandardMaterial3D] = []
	for i in range(3):
		var coil := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.43
		torus.outer_radius = 0.66
		torus.rings = 28
		torus.ring_segments = 8
		coil.mesh = torus
		coil.rotation.x = PI/2
		coil.position = Vector3(0,0.9,-0.8-i*0.75)
		var glow: StandardMaterial3D = emissive(Color(0.04,0.82,1),2.5)
		coil.material_override = glow
		rings.append(glow)
		root.add_child(coil)
	var mouth := MeshInstance3D.new()
	var iris := TorusMesh.new()
	iris.inner_radius = 0.40
	iris.outer_radius = 0.79
	iris.rings = 6
	iris.ring_segments = 6
	mouth.mesh = iris
	mouth.material_override = steel
	mouth.rotation.x = PI/2
	mouth.position = Vector3(0,0.9,-3.5)
	root.add_child(mouth)
	var corona := Sprite3D.new()
	corona.name = "Corona"
	corona.texture = load("res://assets/vfx/flash.png")
	corona.pixel_size = 0.007
	corona.position = Vector3(0,0.9,-3.7)
	corona.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	corona.modulate = Color(0.1,0.8,1,0.3)
	root.add_child(corona)
	var light := OmniLight3D.new()
	light.name = "PlasmaLight"
	light.light_color = Color(0.1,0.75,1)
	light.light_energy = 0.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	light.position = Vector3(0,1.1,-3.3)
	root.add_child(light)
	root.set_meta("rings",rings)
	return root

static func energy_sheath(parent: Node3D, radius: float, phase: float) -> MeshInstance3D:
	var node: MeshInstance3D = beam(parent,Color(0.15,0.75,1),radius,0.25)
	var shader := ShaderMaterial.new()
	shader.shader = load("res://assets/vfx/plasma_flow.gdshader")
	shader.set_shader_parameter("phase",phase)
	node.material_override = shader
	return node
