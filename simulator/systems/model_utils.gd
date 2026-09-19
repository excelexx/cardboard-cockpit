extends RefCounted
class_name ModelUtils
static func bounds(node: Node3D, accumulated: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform: Transform3D = accumulated*node.transform
	var result := AABB()
	if node is MeshInstance3D: result = transform*node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = bounds(child,transform)
			if child_bounds.size.length()>0:
				result = child_bounds if result.size.length()==0 else result.merge(child_bounds)
	return result
static func material(color: Color, metallic: float = 0.4, roughness: float = 0.4) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result
static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	parent.add_child(node)
	return node
