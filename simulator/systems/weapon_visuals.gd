extends RefCounted
class_name WeaponVisuals
const Shapes = preload("res://systems/model_utils.gd")
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
		var model: Node3D = load("res://assets/weapons/seeker.glb").instantiate()
		model.rotation = Vector3(-PI/2,0,0)
		var bounds: AABB = Shapes.bounds(model)
		var size: float = 4.8
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
	else:

		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.65,0.43,0.16)
		shell.metallic = 0.85
		shell.roughness = 0.25
		cylinder(root,0.09,0.65,shell)
		var tip := Color(1,0.85,0.43)
		cylinder(root,0.025,3.2,emissive(tip,3),Vector3(0,0,1.5))
	return root
