extends RefCounted
class_name FighterModel
const Utils = preload("res://systems/model_utils.gd")
const Spectre = preload("res://systems/spectre_airframe.gd")

## The player's aircraft. USE_SPECTRE_AIRFRAME picks the procedural SPECTRE
## X-26 (systems/spectre_airframe.gd); set it to false to fall back to the
## dressed FlightGear F-35B without touching anything else.
const USE_SPECTRE_AIRFRAME := true

const SPECTRE_SCALE := Vector3.ONE
const F35_SCALE := Vector3(1.06, 1.0, 1.07)
const SCALE := SPECTRE_SCALE if USE_SPECTRE_AIRFRAME else F35_SCALE
## Exhaust exit plane and gun muzzle in aircraft space; the effects layer hangs
## the plume, nozzle glow and muzzle flash off these.
const NOZZLE := Vector3(0, -0.30, 7.28) if USE_SPECTRE_AIRFRAME else Vector3(0, -0.782, 7.32)
const MUZZLE := Vector3(-1.20, -0.21, -3.53) if USE_SPECTRE_AIRFRAME else Vector3(-1.04, 0.23, -3.94)
const GUN_MOUNT := Vector3(-1.20, -0.21, -3.02) if USE_SPECTRE_AIRFRAME else Vector3(-0.80, -0.30, -3.10)

static func _paint(livery: Texture2D) -> ShaderMaterial:
	var material := Spectre.paint_material()
	material.set_shader_parameter("livery", livery)
	material.set_shader_parameter("use_livery", true)
	return material

static func create() -> Node3D:
	var model: Node3D = Spectre.create() if USE_SPECTRE_AIRFRAME else _dressed_f35()
	model.name = "SpectreX26"
	model.scale = SCALE
	for geometry: Node in model.find_children("*", "GeometryInstance3D", true, false):
		geometry.layers = 2
	# CG26 rotary cannon on the port chine. The gimbal is aimed by the effects
	# layer and the muzzle marker is where rounds and the flash originate.
	var gun := Node3D.new()
	gun.name = "CG26"
	gun.position = GUN_MOUNT
	var gimbal := Node3D.new()
	gimbal.name = "GunGimbal"
	gun.add_child(gimbal)
	var rotor: Node3D = load("res://assets/sourced_flight/cannon.gltf").instantiate()
	rotor.name = "GatlingRotor"
	gimbal.add_child(rotor)
	var muzzle := Marker3D.new()
	muzzle.name = "GunMuzzle"
	muzzle.position.z = -0.51
	gimbal.add_child(muzzle)
	# The sourced cannon ships in pale plastic; on a near-black airframe it reads
	# as a bolted-on toy unless it is repainted in the same gunmetal.
	var gunmetal := StandardMaterial3D.new()
	gunmetal.albedo_color = Color(0.042, 0.045, 0.050)
	gunmetal.metallic = 0.88
	gunmetal.roughness = 0.31
	for geometry: Node in gun.find_children("*", "GeometryInstance3D", true, false):
		geometry.layers = 2
		if geometry is MeshInstance3D and geometry.mesh != null:
			for surface in range(geometry.mesh.get_surface_count()):
				geometry.set_surface_override_material(surface, gunmetal)
	model.add_child(gun)
	return model

static func _dressed_f35() -> Node3D:
	var model: Node3D = load("res://assets/aircraft/f35/f35.tscn").instantiate()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		node.layers = 2
		if str(node.name).to_lower() in ["antennas", "reheatl"]:
			node.visible = false
			continue
		var part: String = str(node.name).to_lower()
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.mesh.surface_get_material(surface)
			if not source is StandardMaterial3D: continue
			if "canopy" in part or "glass" in part or part == "eots":
				# The F-35's canopy carries a thin gold-tinted conductive film.
				var canopy := StandardMaterial3D.new()
				canopy.albedo_color = Color(0.20, 0.145, 0.06); canopy.metallic = 0.92; canopy.roughness = 0.06
				canopy.clearcoat_enabled = true; canopy.clearcoat = 1.0; canopy.clearcoat_roughness = 0.03
				node.set_surface_override_material(surface, canopy)
			elif "nozzle" in part or part in ["engine", "reheatl", "fan"]:
				var metal: StandardMaterial3D = source.duplicate()
				metal.albedo_color = Color(0.34, 0.29, 0.27); metal.metallic = 0.95; metal.roughness = 0.36
				node.set_surface_override_material(surface, metal)
			elif part == "lights":
				var lamp := StandardMaterial3D.new()
				var tint: Color = source.albedo_color
				lamp.albedo_color = tint * 0.08; lamp.albedo_color.a = 1.0; lamp.roughness = 0.12
				lamp.emission_enabled = true; lamp.emission = tint; lamp.emission_energy_multiplier = 0.12
				node.set_surface_override_material(surface, lamp)
			elif part == "pylons":
				var pylon: StandardMaterial3D = source.duplicate()
				pylon.albedo_texture = null; pylon.albedo_color = Color(0.22, 0.24, 0.26); pylon.roughness = 0.5; pylon.metallic = 0.3
				node.set_surface_override_material(surface, pylon)
			elif source.albedo_texture != null:
				node.set_surface_override_material(surface, _paint(source.albedo_texture))
	return model
