extends RefCounted
class_name FighterModel
const Utils = preload("res://systems/model_utils.gd")
const SCALE := Vector3(1.06,1.0,1.07)
const NOZZLE := Vector3(0,-0.782,7.32)
const MUZZLE := Vector3(-1.04,0.23,-3.94)
static var _grain: NoiseTexture2D
static func _paint(livery: Texture2D) -> ShaderMaterial:
	if _grain==null:
		var noise := FastNoiseLite.new(); noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.frequency = 0.03; noise.fractal_octaves = 5
		_grain = NoiseTexture2D.new(); _grain.width = 512; _grain.height = 512; _grain.seamless = true; _grain.generate_mipmaps = true; _grain.noise = noise
	var material := ShaderMaterial.new(); material.shader = preload("res://assets/look/jet_paint.gdshader")
	material.set_shader_parameter("livery",livery); material.set_shader_parameter("grain",_grain)
	return material
static func create() -> Node3D:
	var model: Node3D = load("res://assets/aircraft/f35/f35.tscn").instantiate()
	model.name = "SpectreX26"
	model.scale = SCALE
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		node.layers = 2
		if str(node.name).to_lower() in ["antennas","reheatl"]:
			node.visible = false
			continue
		var part: String = str(node.name).to_lower()
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.mesh.surface_get_material(surface)
			if not source is StandardMaterial3D: continue
			if "canopy" in part or "glass" in part or part=="eots":
				# The F-35's canopy carries a thin gold-tinted conductive film.
				var canopy := StandardMaterial3D.new()
				canopy.albedo_color = Color(0.20,0.145,0.06); canopy.metallic = 0.92; canopy.roughness = 0.06
				canopy.clearcoat_enabled = true; canopy.clearcoat = 1.0; canopy.clearcoat_roughness = 0.03
				node.set_surface_override_material(surface,canopy)
			elif "nozzle" in part or part in ["engine","reheatl","fan"]:
				# Heat-tinted titanium: dark, metallic, straw-to-blue toward the petals.
				var metal: StandardMaterial3D = source.duplicate()
				metal.albedo_color = Color(0.34,0.29,0.27); metal.metallic = 0.95; metal.roughness = 0.36
				node.set_surface_override_material(surface,metal)
			elif part=="lights":
				var lamp := StandardMaterial3D.new()
				var tint: Color = source.albedo_color
				lamp.albedo_color = tint*0.08; lamp.albedo_color.a = 1.0; lamp.roughness = 0.12
				lamp.emission_enabled = true; lamp.emission = tint; lamp.emission_energy_multiplier = 0.12
				node.set_surface_override_material(surface,lamp)
			elif part=="pylons":
				var pylon: StandardMaterial3D = source.duplicate()
				pylon.albedo_texture = null; pylon.albedo_color = Color(0.22,0.24,0.26); pylon.roughness = 0.5; pylon.metallic = 0.3
				node.set_surface_override_material(surface,pylon)
			elif source.albedo_texture!=null:
				node.set_surface_override_material(surface,_paint(source.albedo_texture))
	var gun := Node3D.new(); gun.name = "CG26"
	gun.position = Vector3(-.80,-.30,-3.10) # Intersects the source fuselage at x=-.869 m.
	var gimbal := Node3D.new(); gimbal.name = "GunGimbal"; gun.add_child(gimbal)
	var rotor: Node3D = load("res://assets/sourced_flight/cannon.gltf").instantiate()
	rotor.name = "GatlingRotor"; gimbal.add_child(rotor)
	var muzzle := Marker3D.new(); muzzle.name = "GunMuzzle"; muzzle.position.z = -.51; gimbal.add_child(muzzle)
	for geometry: Node in gun.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
	model.add_child(gun)
	return model
