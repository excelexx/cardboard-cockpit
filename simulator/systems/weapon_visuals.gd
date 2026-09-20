extends RefCounted
class_name WeaponVisuals
const Shapes = preload("res://systems/model_utils.gd")
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
static func projectile(_variant: String = "gatling") -> Node3D:
	var root := Node3D.new(); root.name = "CannonTracer"
	# The visible streak represents exposure time, not an oversized physical shell.
	cylinder(root,.055,8.5,emissive(Color(1,.66,.25),2.0,.42),Vector3(0,0,2.6))
	cylinder(root,.032,2.0,emissive(Color(1,.95,.73),2.5,.9),Vector3.ZERO)
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


static func energy_sheath(parent: Node3D, radius: float, phase: float) -> MeshInstance3D:
	var node: MeshInstance3D = beam(parent,Color(0.15,0.75,1),radius,0.25)
	var shader := ShaderMaterial.new()
	shader.shader = load("res://assets/vfx/plasma_flow.gdshader")
	shader.set_shader_parameter("phase",phase)
	node.material_override = shader
	return node
