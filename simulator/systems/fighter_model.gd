extends RefCounted
class_name FighterModel
const Utils = preload("res://systems/model_utils.gd")
const Spectre = preload("res://systems/spectre_airframe.gd")
const Weapons = preload("res://systems/weapon_models.gd")

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
# Forward chine pods: the barrel cluster and accelerator sit outside the hull,
# while the tapered rear fairings blend into the shoulder behind them.
const GUN_SCALE := 1.45
const PLASMA_SCALE := 1.65
const GUN_MOUNT := Vector3(-1.70, 0.30, -4.00) if USE_SPECTRE_AIRFRAME else Vector3(-1.25, 0.30, -3.70)
const PLASMA_MOUNT := Vector3(1.72, 0.30, -3.65) if USE_SPECTRE_AIRFRAME else Vector3(1.25, 0.30, -3.70)
const MUZZLE := GUN_MOUNT + Vector3(0, 0, Weapons.MUZZLE_Z * GUN_SCALE)
const PLASMA_MUZZLE := PLASMA_MOUNT + Vector3(0, 0, -0.52 * PLASMA_SCALE)

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
	# Keep the authored graphite, machined edges, gold trim and heat shaders.
	# The gimbal translates for recoil; only GatlingRotor rotates.
	_hardpoint(model, GUN_MOUNT, -1.0, 3.30)
	var gun_mount := Node3D.new()
	gun_mount.name = "GunMount"
	gun_mount.position = GUN_MOUNT
	model.add_child(gun_mount)
	var gimbal := Node3D.new()
	gimbal.name = "GunGimbal"
	gun_mount.add_child(gimbal)
	var gun := Weapons.rotary_cannon()
	gun.scale = Vector3.ONE * GUN_SCALE
	gimbal.add_child(gun)

	_hardpoint(model, PLASMA_MOUNT, 1.0, 1.85)
	var plasma := Weapons.plasma_cannon()
	plasma.position = PLASMA_MOUNT
	plasma.scale = Vector3.ONE * PLASMA_SCALE
	model.add_child(plasma)
	return model

## A low swept mounting shoe carries each pod back into the chine. The socket
## stays fixed to the airframe while the rotary cannon recoils above it.
static func _hardpoint(model: Node3D, origin: Vector3, side: float, length: float) -> void:
	var mount := Node3D.new()
	mount.name = "PortWeaponHardpoint" if side < 0 else "StarboardWeaponHardpoint"
	mount.position = origin + Vector3(-side * 0.19, -0.17, 0.25)
	model.add_child(mount)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	Weapons.loft(surface, 0, [
		[0.0, Weapons.section(8, 0.15, 0.045, 0.0), Vector2.ZERO],
		[0.24, Weapons.section(8, 0.30, 0.085, 0.0), Vector2.ZERO],
		[length * 0.70, Weapons.section(8, 0.28, 0.065, 0.0), Vector2(-side * 0.07, -0.025)],
		[length, Weapons.section(8, 0.055, 0.018, 0.0), Vector2(-side * 0.18, -0.07)]])
	surface.generate_normals()
	surface.generate_tangents()
	var shoe := MeshInstance3D.new()
	shoe.name = "ChineSocket"
	shoe.mesh = surface.commit()
	shoe.material_override = Weapons.metal({"base_tint": Color(0.052, 0.058, 0.068), "rough_lo": 0.30, "rough_hi": 0.52})
	shoe.layers = 2
	mount.add_child(shoe)

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
