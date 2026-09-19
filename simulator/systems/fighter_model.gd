extends RefCounted
class_name FighterModel
const Utils = preload("res://systems/model_utils.gd")
static func create() -> Node3D:
	var model: Node3D = load("res://assets/aircraft/f35/f35.tscn").instantiate()
	model.name = "SpectreX26"
	model.scale = Vector3(1.14,1.0,1.015)
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.mesh.surface_get_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				if material.albedo_texture!=null and "Default" in material.albedo_texture.resource_path:
					material.albedo_texture = load("res://assets/fighter/spectre-livery.png")
					material.albedo_color = Color(0.80,0.86,0.90)
				material.roughness = 0.38
				material.metallic = 0.42
				material.clearcoat_enabled = true
				material.clearcoat = 0.45
				material.clearcoat_roughness = 0.22
				if "canopy" in str(node.name).to_lower() or "glass" in str(node.name).to_lower():
					material.albedo_color = Color(0.08,0.17,0.22)
					material.metallic = 0.75
					material.roughness = 0.055
					material.clearcoat = 0.95
				node.set_surface_override_material(surface,material)
	var kit := Node3D.new()
	kit.name = "SpectreChines"
	model.add_child(kit)
	var titanium := Utils.material(Color(0.19,0.23,0.27),0.65,0.32)
	var silver := Utils.material(Color(0.46,0.53,0.57),0.65,0.25)
	for side in [-1.0,1.0]:
		# Faceted, swept fore-chines add a distinct silhouette without replacing
		# the detailed licensed airframe, control surfaces, or landing gear.
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(side*1.0,0.15,-4.5)
		var b := Vector3(side*3.35,0.12,-1.8)
		var c := Vector3(side*1.05,0.24,-0.8)
		var d := Vector3(side*1.05,-0.10,-1.8)
		for point in [a,b,c,a,d,b,a,c,d,b,d,c]: surface.add_vertex(point)
		surface.generate_normals()
		var chine := MeshInstance3D.new()
		chine.mesh = surface.commit()
		chine.material_override = titanium
		kit.add_child(chine)
		Utils.box(kit,Vector3(0.04,0.03,2.5),Vector3(side*1.38,0.60,-2.4),silver)
		var strip := Utils.material(Color(0.15,0.76,0.83),0.4,0.25)
		strip.emission_enabled = true
		strip.emission = Color(0.08,0.48,0.58)
		strip.emission_energy_multiplier = 0.45
		Utils.box(kit,Vector3(0.06,0.035,1.3),Vector3(side*1.4,0.63,-1.4),strip)
	var badge := Label3D.new()
	badge.text = "X–26"
	badge.font_size = 64
	badge.pixel_size = 0.006
	badge.modulate = Color(0.7,0.75,0.76)
	badge.position = Vector3(0,1.85,1.5)
	badge.rotation_degrees.x = -90
	kit.add_child(badge)
	return model
