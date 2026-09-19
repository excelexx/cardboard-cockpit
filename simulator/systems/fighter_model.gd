extends RefCounted
class_name FighterModel
const Utils = preload("res://systems/model_utils.gd")
const SCALE := Vector3(1.06,1.0,1.07)
const NOZZLE := Vector3(0,-0.782,7.32)
const MUZZLE := Vector3(-1.04,0.23,-3.94)
static func create() -> Node3D:
	var model: Node3D = load("res://assets/aircraft/f35/f35.tscn").instantiate()
	model.name = "SpectreX26"
	model.scale = SCALE
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		node.layers = 2
		if str(node.name).to_lower() in ["antennas","reheatl"]:
			node.visible = false
			continue
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.mesh.surface_get_material(surface)
			if not source is StandardMaterial3D: continue
			var material: StandardMaterial3D = source.duplicate()
			var part: String = str(node.name).to_lower()
			material.roughness = 0.60
			material.metallic = 0.12
			material.clearcoat_enabled = true
			material.clearcoat = 0.08
			material.clearcoat_roughness = 0.38
			if "canopy" in part or "glass" in part:
				material.albedo_texture = null
				material.albedo_color = Color(0.085,0.12,0.14)
				material.metallic = 0.72
				material.roughness = 0.075
				material.clearcoat = 0.9
			elif "nozzle" in part or part=="engine":
				material.albedo_color = Color(0.28,0.24,0.21)
				material.metallic = 0.86
				material.roughness = 0.34
			elif part=="pylons":
				material.albedo_texture = null
				material.albedo_color = Color(0.24,0.27,0.29)
				material.roughness = 0.52
			node.set_surface_override_material(surface,material)
	var gun := Node3D.new(); gun.name = "CG26"
	gun.position = Vector3(-1.5,.27,-3.10)
	var gimbal := Node3D.new(); gimbal.name = "GunGimbal"; gun.add_child(gimbal)
	var rotor: Node3D = load("res://assets/sourced_flight/cannon.gltf").instantiate()
	rotor.name = "GatlingRotor"; gimbal.add_child(rotor)
	var muzzle := Marker3D.new(); muzzle.name = "GunMuzzle"; muzzle.position.z = -.51; gimbal.add_child(muzzle)
	for geometry: Node in gun.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
	model.add_child(gun)
	return model
