class_name CoastalBaseWorld
extends Node3D
## A deterministic alpine corridor. Flight collision samples exactly the same
## height function used to construct the visible terrain.

const DESTINATION_Z: float = -15000.0
const destination_z: float = -15000.0
const TERRAIN_X_MIN: float = -16500.0
const TERRAIN_X_MAX: float = 16500.0
const TERRAIN_Z_MIN: float = -25500.0
const TERRAIN_Z_MAX: float = 9500.0
const TERRAIN_STEP: float = 110.0
const RIVER_Y: float = -8.5
const CONDITIONS: Dictionary = {
	"golden": {"id": "golden", "name": "Golden hour", "time_of_day": "17:40", "cloud_cover": 0.30, "visibility_km": 30.0, "description": "Warm evening light · scattered high cloud", "visual_only": true},
	"clear": {"id": "clear", "name": "Clear midday", "time_of_day": "12:15", "cloud_cover": 0.17, "visibility_km": 45.0, "description": "Bright midday · excellent valley visibility", "visual_only": true},
	"overcast": {"id": "overcast", "name": "High overcast", "time_of_day": "10:30", "cloud_cover": 0.92, "visibility_km": 18.0, "description": "High cloud ceiling · soft light and valley haze", "visual_only": true}
}

var _built: bool = false
var _noise: FastNoiseLite = FastNoiseLite.new()
var _detail_noise: FastNoiseLite = FastNoiseLite.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _height_grid: Dictionary = {}
var _environment: WorldEnvironment
var _sun: DirectionalLight3D
var _condition_id: String = "golden"
var _condition_skies: Dictionary = {}
var _airport_obstacles: Array[AABB] = []
var metropolis: Node3D


func _init() -> void:
	_noise.seed = 42177
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.00019
	_noise.fractal_octaves = 4
	_noise.fractal_gain = 0.45
	_detail_noise.seed = 91241
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.0024
	_detail_noise.fractal_octaves = 3
	_rng.seed = 9182026


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	name = "AlpineValley"
	_build_atmosphere()
	_build_terrain()
	_build_river()
	_build_airport(0.0, "NORTHSTAR", "36", "18")
	_build_airport(DESTINATION_Z, "NORTH FIELD", "36", "18")
	metropolis=load("res://scenes/metropolitan_world.gd").new()
	add_child(metropolis)
	metropolis.build(self)
	_build_forests()
	_build_valley_landmarks()
	_build_farmland()
	_build_lakeside_town()
	_build_clouds()
	_build_scenic_cloud_sea()


func _build_farmland() -> void:
	# Terrain-following agricultural plots give altitude and scale cues on approach.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors: Array[Color] = [Color(0.32,0.38,0.18), Color(0.48,0.43,0.25), Color(0.26,0.34,0.16), Color(0.40,0.35,0.24)]
	for row in range(9):
		for column in range(3):
			var origin := Vector2(-1320+column*210,-11000+row*270)
			var color: Color = colors[(row*3+column)%colors.size()]
			for u in range(8):
				for v in range(10):
					var base := origin+Vector2(u*24,v*25)
					for corner: Vector2 in [Vector2(0,0),Vector2(0,25),Vector2(24,0),Vector2(24,0),Vector2(0,25),Vector2(24,25)]:
						var point := base+corner
						surface.set_color(color.lightened(0.025 if u%2==0 else 0.0))
						surface.add_vertex(Vector3(point.x,ground_height(point.x,point.y)+0.22,point.y))
	surface.generate_normals()
	var material := _mat("farmland",Color.WHITE)
	material.vertex_color_use_as_albedo = true
	var fields := MeshInstance3D.new()
	fields.name = "ValleyAgriculturalFields"
	fields.mesh = surface.commit()
	fields.material_override = material
	add_child(fields)


func _smooth(a: float, b: float, value: float) -> float:
	var t: float = clampf((value - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _river_center(z: float) -> float:
	return 1560.0 + sin(z * 0.00034) * 270.0 + sin(z * 0.00091) * 90.0


func _terrain_height(x: float, z: float) -> float:
	var broad: float = _noise.get_noise_2d(x, z)
	var detail: float = _detail_noise.get_noise_2d(x, z)
	var end_weight: float = maxf(_smooth(19300.0, 25500.0, -z), _smooth(4800.0, 9500.0, z))
	# A broad, populated basin instead of two mountain walls beside a bare runway.
	var mountain_weight: float = maxf(_smooth(3600.0, 7900.0, absf(x)), end_weight)
	var ridge: float = 1.0 - absf(_noise.get_noise_2d(x + 2810.0, z - 5400.0))
	var floor_height: float = -2.0 + broad * 23.0 + detail * 5.0
	var elevation: float = floor_height + mountain_weight * (1050.0 + broad * 1450.0 + pow(ridge, 3.0) * 1480.0)
	# Paired rock shoulders frame an actual flyable pass, not a wall across the route.
	var pass_z: float = exp(-pow((z+8250.0)/1050.0,2.0))
	elevation += pass_z*(820.0*exp(-pow((x+1150.0)/470.0,2.0))+1050.0*exp(-pow((x-1750.0)/510.0,2.0)))
	# Both airports have a generous level safety area and smooth earth embankments.
	var nearest_airport: float = minf(absf(z), absf(z - DESTINATION_Z))
	var airport_weight: float = (1.0 - _smooth(1050.0, 1370.0, absf(x))) * (1.0 - _smooth(1900.0, 2600.0, nearest_airport))
	elevation = lerpf(elevation, -0.20, airport_weight)
	var river_distance: float = absf(x - _river_center(z))
	var river_weight: float = (1.0 - _smooth(75.0, 205.0, river_distance)) * (1.0 - end_weight)
	elevation = lerpf(elevation, -23.0, river_weight)
	# A broad glacial lake on the left side of the outbound flight corridor.
	var lake_radius: float = Vector2((x+2350.0)/950.0,(z+4800.0)/1700.0).length()
	var lake_weight: float = 1.0-_smooth(0.82,1.16,lake_radius)
	elevation = lerpf(elevation,-25.0,lake_weight)
	return elevation


func _mat(key: String, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	_materials[key] = material
	return material


func _box(parent: Node3D, title: String, position_value: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var object: MeshInstance3D = MeshInstance3D.new()
	object.name = title
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size_value
	object.mesh = mesh
	object.position = position_value
	object.material_override = material
	parent.add_child(object)
	if title in ["MaintenanceHangar", "HangarRoof", "TerminalGroundFloor", "TerminalRoof", "ControlTowerBase", "JetBridge", "GateCabin"]:
		# Airport parents only translate. Capture the authored bounds before batching.
		_airport_obstacles.append(AABB(parent.position + position_value - size_value * 0.5, size_value))
	return object


func _cylinder(parent: Node3D, title: String, position_value: Vector3, radius: float, height: float, material: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var object: MeshInstance3D = MeshInstance3D.new()
	object.name = title
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 12
	object.mesh = mesh
	object.position = position_value
	object.material_override = material
	parent.add_child(object)
	if title in ["ControlTowerShaft", "ControlTowerCab", "ControlTowerRoof"]:
		var collision_radius: float = maxf(radius, top_radius)
		var bounds: Vector3 = Vector3(collision_radius * 2.0, height, collision_radius * 2.0)
		_airport_obstacles.append(AABB(parent.position + position_value - bounds * 0.5, bounds))
	return object


func _build_atmosphere() -> void:
	var sky_material: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/environment/kloppenheim_06_puresky_2k.hdr") as Texture2D
	sky_material.energy_multiplier = 0.50
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	_condition_skies["golden"] = sky
	_condition_skies["clear"] = _make_weather_sky(false)
	_condition_skies["overcast"] = _make_weather_sky(true)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.85
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.73, 0.80)
	environment.fog_light_energy = 0.85
	environment.fog_density = 0.000026
	environment.fog_aerial_perspective = 0.78
	environment.fog_sky_affect = 0.12
	_environment = WorldEnvironment.new()
	_environment.name = "MountainAtmosphere"
	_environment.environment = environment
	add_child(_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "ValleySun"
	_sun.directional_shadow_max_distance = 2400.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)
	set_conditions(_condition_id)


func _make_weather_sky(overcast: bool) -> Sky:
	# Sky clouds add no scene geometry, transparency overdraw, or draw calls.
	# A static sky also avoids rebuilding the environment's reflection map every frame.
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://assets/environment/weather_sky.gdshader") as Shader
	material.set_shader_parameter("cloud_cover", 0.92 if overcast else 0.17)
	material.set_shader_parameter("overcast", 1.0 if overcast else 0.0)
	material.set_shader_parameter("sun_direction", Vector3(-0.41, 0.82, 0.40) if overcast else Vector3(-0.32, 0.92, 0.22))
	var sky: Sky = Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	return sky


func set_conditions(preset: String) -> void:
	## Changes lighting and atmospheric visibility only; flight dynamics are unaffected.
	## Safe before build(), after build(), and when called repeatedly from the hangar.
	_condition_id = preset if CONDITIONS.has(preset) else "golden"
	if _environment == null or _sun == null:
		return
	var environment: Environment = _environment.environment
	environment.sky = _condition_skies[_condition_id] as Sky
	_sun.shadow_enabled = _condition_id != "overcast"
	match _condition_id:
		"clear":
			_sun.rotation_degrees = Vector3(-67.0, -55.0, 0.0)
			_sun.light_color = Color(1.0, 0.98, 0.94)
			_sun.light_energy = 1.55
			environment.ambient_light_energy = 0.58
			environment.tonemap_exposure = 0.96
			environment.fog_light_color = Color(0.67, 0.79, 0.90)
			environment.fog_light_energy = 0.95
			environment.fog_density = 0.000014
			environment.fog_aerial_perspective = 0.62
			environment.fog_sky_affect = 0.08
		"overcast":
			_sun.rotation_degrees = Vector3(-54.0, -46.0, 0.0)
			_sun.light_color = Color(0.87, 0.92, 1.0)
			_sun.light_energy = 0.72
			environment.ambient_light_energy = 0.85
			environment.tonemap_exposure = 1.02
			environment.fog_light_color = Color(0.69, 0.74, 0.78)
			environment.fog_light_energy = 0.88
			environment.fog_density = 0.000052
			environment.fog_aerial_perspective = 0.86
			environment.fog_sky_affect = 0.22
		_:
			_sun.rotation_degrees = Vector3(-31.0, -38.0, 0.0)
			_sun.light_color = Color(1.0, 0.93, 0.81)
			_sun.light_energy = 1.25
			environment.ambient_light_energy = 0.32
			environment.tonemap_exposure = 0.85
			environment.fog_light_color = Color(0.62, 0.73, 0.80)
			environment.fog_light_energy = 0.85
			environment.fog_density = 0.000026
			environment.fog_aerial_perspective = 0.78
			environment.fog_sky_affect = 0.12


func get_condition_name() -> String:
	return str(CONDITIONS[_condition_id]["name"])


func get_conditions() -> Dictionary:
	# A copy keeps HUD formatting from modifying the canonical preset definitions.
	return (CONDITIONS[_condition_id] as Dictionary).duplicate(true)


func obstacle_collision(position_value: Vector3, radius: float = 2.0) -> bool:
	## Major airport buildings use their visible authored bounds, retained after batching.
	## Tiny furniture and trees remain forgiving; this is not aircraft-wing collision.
	var safe_radius: float = maxf(radius, 0.0)
	if metropolis!=null and metropolis.collides(position_value,safe_radius): return true
	for bounds in _airport_obstacles:
		var nearest: Vector3 = position_value.clamp(bounds.position, bounds.end)
		if nearest.distance_squared_to(position_value) <= safe_radius * safe_radius:
			return true
	return false


func _terrain_color(x: float, z: float, h: float, normal: Vector3) -> Color:
	var noise_value: float = (_detail_noise.get_noise_2d(x * 1.4, z * 1.4) + 1.0) * 0.5
	var grass: Color = Color(0.23, 0.30, 0.19).lerp(Color(0.36, 0.38, 0.23), noise_value)
	var rock: Color = Color(0.32, 0.34, 0.33).lerp(Color(0.45, 0.43, 0.38), noise_value)
	var slope: float = 1.0 - normal.y
	var rocky_weight: float = maxf(_smooth(850.0, 1700.0, h), _smooth(0.11, 0.46, slope))
	var color: Color = grass.lerp(rock, rocky_weight)
	var snowline: float = 2130.0 + _noise.get_noise_2d(x * 2.2, z * 2.2) * 310.0
	var snow_weight: float = _smooth(snowline, snowline + 290.0, h) * (1.0 - _smooth(0.32, 0.60, slope))
	color = color.lerp(Color(0.86, 0.89, 0.88), snow_weight)
	var bank: float = absf(x - _river_center(z))
	if bank < 220.0 and h < 4.0:
		color = color.lerp(Color(0.32, 0.34, 0.28), 1.0 - _smooth(125.0, 220.0, bank))
	return color


func _build_terrain() -> void:
	var columns: int = int(ceil((TERRAIN_X_MAX - TERRAIN_X_MIN) / TERRAIN_STEP)) + 1
	var rows: int = int(ceil((TERRAIN_Z_MAX - TERRAIN_Z_MIN) / TERRAIN_STEP)) + 1
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(columns * rows)
	normals.resize(columns * rows)
	colors.resize(columns * rows)
	for row in range(rows):
		var z: float = TERRAIN_Z_MIN + row * TERRAIN_STEP
		for column in range(columns):
			var x: float = TERRAIN_X_MIN + column * TERRAIN_STEP
			var h: float = _grid_height(x, z)
			var normal: Vector3 = Vector3(_grid_height(x - TERRAIN_STEP, z) - _grid_height(x + TERRAIN_STEP, z), TERRAIN_STEP * 2.0, _grid_height(x, z - TERRAIN_STEP) - _grid_height(x, z + TERRAIN_STEP)).normalized()
			var index: int = row * columns + column
			vertices[index] = Vector3(x, h, z)
			normals[index] = normal
			colors[index] = _terrain_color(x, z, h, normal)
	for row in range(rows - 1):
		for column in range(columns - 1):
			var a: int = row * columns + column
			var b: int = a + 1
			var c: int = a + columns
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh: ArrayMesh = ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://assets/environment/coastal/terrain.gdshader") as Shader
	material.set_shader_parameter("grass_texture", load("res://assets/environment/aerial_grass_rock_diff_1k.jpg"))
	material.set_shader_parameter("rock_texture", load("res://assets/environment/aerial_rocks_02_diff_1k.jpg"))
	var terrain: MeshInstance3D = MeshInstance3D.new()
	terrain.name = "AlpineTerrain"
	terrain.mesh = terrain_mesh
	terrain.material_override = material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)


func _build_river() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var count: int = 501
	for i in range(count):
		var z: float = -25500.0 + i * 70.0
		var center: float = _river_center(z)
		var width: float = 113.0 + sin(z * 0.002) * 8.0
		vertices.append(Vector3(center - width, RIVER_Y, z))
		vertices.append(Vector3(center + width, RIVER_Y, z))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if i < count - 1:
			var a: int = i * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var water: MeshInstance3D = MeshInstance3D.new()
	water.name = "GlacialRiver"
	water.mesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://assets/environment/coastal/water.gdshader") as Shader
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _runway_text(parent: Node3D, value: String, at: Vector3, reverse: bool = false) -> void:
	var text_mesh: TextMesh = TextMesh.new()
	text_mesh.text = value
	text_mesh.font_size = 160
	text_mesh.pixel_size = 0.16
	text_mesh.depth = 0.0
	var label: MeshInstance3D = MeshInstance3D.new()
	label.name = "RunwayDesignation_" + value
	label.mesh = text_mesh
	label.material_override = _mat("markings", Color(0.89, 0.90, 0.85))
	label.position = at
	label.rotation_degrees = Vector3(-90.0, 180.0 if reverse else 0.0, 0.0)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)


func _build_airport(z_center: float, airport_name: String, north_number: String, south_number: String) -> void:
	var airport: Node3D = Node3D.new()
	airport.name = airport_name.replace(" ", "_")
	airport.position.z = z_center
	add_child(airport)
	var asphalt: ShaderMaterial = ShaderMaterial.new()
	asphalt.shader = load("res://assets/environment/coastal/asphalt.gdshader") as Shader
	asphalt.set_shader_parameter("aggregate",load("res://assets/environment/aerial_asphalt_01_diff_2k.jpg"))
	asphalt.set_shader_parameter("airport_z",z_center)
	var concrete:=ShaderMaterial.new()
	concrete.shader=load("res://assets/environment/coastal/concrete.gdshader")
	concrete.set_shader_parameter("aggregate",load("res://assets/environment/aerial_asphalt_01_diff_2k.jpg"))
	var pale_concrete: StandardMaterial3D = _mat("pale_concrete", Color(0.57, 0.58, 0.54))
	var yellow: StandardMaterial3D = _mat("yellow", Color(0.83, 0.64, 0.18))
	var markings: StandardMaterial3D = _mat("markings", Color(0.89, 0.90, 0.85))
	var metal: StandardMaterial3D = _mat("airport_metal", Color(0.31, 0.36, 0.37), 0.63, 0.15)
	var glass: StandardMaterial3D = _mat("airport_glass", Color(0.11, 0.25, 0.29), 0.16, 0.38)
	_box(airport, "Runway", Vector3(0.0, -0.13, 0.0), Vector3(100.0, 0.26, 3200.0), asphalt)
	_box(airport, "RunwayShoulderWest", Vector3(-56.0, -0.13, 0.0), Vector3(12.0, 0.20, 3220.0), concrete)
	_box(airport, "RunwayShoulderEast", Vector3(56.0, -0.13, 0.0), Vector3(12.0, 0.20, 3220.0), concrete)
	_box(airport, "Taxiway", Vector3(245.0, -0.09, 0.0), Vector3(44.0, 0.18, 3060.0), asphalt)
	_box(airport, "TaxiwayGuide", Vector3(245.0, 0.045, 0.0), Vector3(0.60, 0.016, 2980.0), yellow)
	_box(airport, "TerminalApron", Vector3(438.0, -0.085, 470.0), Vector3(370.0, 0.17, 950.0), concrete)
	for side in [-1.0, 1.0]:
		_box(airport, "EdgeStripe", Vector3(side * 45.0, 0.025, 0.0), Vector3(1.6, 0.015, 3150.0), markings)
		# The continuous terrain supplies the verge, avoiding long rectangular overlays.
	for stripe in range(-14, 15):
		_box(airport, "Centerline", Vector3(0.0, 0.030, stripe * 92.0), Vector3(1.8, 0.018, 40.0), markings)
	for threshold in [-1.0, 1.0]:
		for stripe in range(12):
			var x: float = -38.5 + stripe * 7.0
			_box(airport, "ThresholdStripe", Vector3(x, 0.030, threshold * 1535.0), Vector3(3.5, 0.018, 56.0), markings)
		for side in [-1.0, 1.0]:
			_box(airport, "AimingPoint", Vector3(side * 24.0, 0.035, threshold * 1170.0), Vector3(10.0, 0.018, 55.0), markings)
			for touch in range(3):
				_box(airport, "TouchdownZone", Vector3(side * 24.0, 0.03, threshold * (965.0 - touch * 160.0)), Vector3(5.0, 0.018, 35.0), markings)
		_box(airport, "RunwayConnector", Vector3(149.0, -0.08, threshold * 1450.0), Vector3(193.0, 0.16, 44.0), asphalt)
		_box(airport, "ConnectorGuide", Vector3(149.0, 0.040, threshold * 1450.0), Vector3(193.0, 0.012, 0.6), yellow)
	_runway_text(airport, north_number, Vector3(0.0, 0.052, 1400.0))
	_runway_text(airport, south_number, Vector3(0.0, 0.052, -1400.0), true)
	_add_runway_lights(airport)
	# Expansion joints, stand boundaries, and stop bars give the apron a human scale.
	for joint in range(20):
		_box(airport, "ApronExpansionJoint", Vector3(438.0, 0.017, 20.0 + joint * 46.0), Vector3(368.0, 0.009, 0.16), metal)
	for stand in range(6):
		var stand_z: float = 80.0 + stand * 145.0
		_box(airport, "StandCenterline", Vector3(420.0, 0.032, stand_z), Vector3(220.0, 0.015, 0.55), yellow)
		_box(airport, "StandStopBar", Vector3(520.0, 0.033, stand_z), Vector3(0.55, 0.015, 20.0), yellow)
		_box(airport, "StandFootprint", Vector3(432.0, 0.03, stand_z + 63.0), Vector3(238.0, 0.012, 0.3), markings)
	_build_terminal(airport, airport_name, concrete, metal, glass)
	_airport_service_detail(airport,metal,glass)
	for hangar in range(4):
		_build_hangar(airport, Vector3(470.0, 0.0, -330.0 - hangar * 215.0), 145.0, 130.0)
	for light_index in range(6):
		var light_z: float = 5.0 + light_index * 172.0
		_cylinder(airport, "ApronFloodlightMast", Vector3(617.0, 18.0, light_z), 0.42, 36.0, metal)
		_box(airport, "ApronFloodlightCrossbar", Vector3(617.0, 36.0, light_z), Vector3(0.8, 1.1, 9.0), metal)
		for fixture in [-3.0, 0.0, 3.0]:
			_box(airport, "ApronFloodlight", Vector3(616.3, 36.0, light_z + fixture), Vector3(1.0, 1.5, 2.0), pale_concrete)
	_build_windsock(airport, Vector3(-94.0, 0.0, 1200.0))
	_build_windsock(airport, Vector3(116.0, 0.0, -1100.0))
	# Navigation signs beside the taxiway.
	for sign_z in [-1250.0, -600.0, 300.0, 1280.0]:
		_box(airport, "TaxiwaySign", Vector3(204.0, 1.7, sign_z), Vector3(7.5, 2.2, 0.55), yellow)
		for support_x in [201.5, 206.5]:
			_box(airport, "SignSupport", Vector3(support_x, 0.6, sign_z), Vector3(0.25, 1.2, 0.25), metal)

	_batch_static_geometry(airport)


func _airport_service_detail(airport: Node3D, metal: Material, glass: Material) -> void:
	var white:=_mat("service_ivory",Color(0.69,0.72,0.69),0.65,0.12)
	var tire:=_mat("service_tire",Color(0.025,0.03,0.033))
	var roof:=_mat("roof_equipment",Color(0.22,0.27,0.28),0.5,0.4)
	for stand in range(6):
		var at:=Vector3(535,0,115+stand*145)
		_box(airport,"ServiceTruckBody",at+Vector3(0,1.8,0),Vector3(3.5,2.5,6.8),white)
		_box(airport,"ServiceTruckCab",at+Vector3(0,1.8,-4.2),Vector3(3.4,2.6,2.3),white)
		_box(airport,"TruckWindshield",at+Vector3(0,2.3,-5.37),Vector3(2.9,1.1,0.07),glass)
		for side in [-1.0,1.0]:
			for axle in [-3.8,2.3]:
				var wheel:=_cylinder(airport,"ServiceWheel",at+Vector3(side*1.7,0.65,axle),0.65,0.32,tire)
				wheel.rotation.z=PI/2
		for cart in range(3):
			_box(airport,"BaggageCart",at+Vector3(10,0.8,cart*4),Vector3(2.3,1.1,3.1),metal)
			_box(airport,"TowLink",at+Vector3(10,0.45,cart*4+1.9),Vector3(0.12,0.15,1),metal)
		# Roof plant has a visible raised curb, vents and louvered faces.
		var plant:=Vector3(682,18.3,310+stand*88)
		_box(airport,"HVACCurb",plant,Vector3(10,0.6,15),metal)
		_box(airport,"HVACUnit",plant+Vector3(0,1.7,0),Vector3(8,3,12),roof)
		for vent in range(7):
			_box(airport,"HVACLouver",plant+Vector3(-4.03,1.1+vent*0.3,0),Vector3(0.08,0.10,10),metal)
	# A service-side perimeter follows the airport edge, clear of flight paths.
	for index in range(110):
		var z: float=-1400+index*24
		_box(airport,"PerimeterPost",Vector3(1000,1.6,z),Vector3(0.13,3.2,0.13),metal)
		for rail in [0.65,1.6,2.6]:
			_box(airport,"PerimeterRail",Vector3(1000,rail,z+12),Vector3(0.07,0.07,24),metal)

func _add_runway_lights(airport: Node3D) -> void:
	var lights_material: StandardMaterial3D = _mat("runway_lights", Color(0.96, 0.94, 0.79))
	lights_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lights_material.emission_enabled = true
	lights_material.emission = Color(1.0, 0.94, 0.75)
	lights_material.emission_energy_multiplier = 2.0
	var blue_material: StandardMaterial3D = _mat("taxiway_lights", Color(0.1, 0.35, 0.95))
	blue_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var green_material: StandardMaterial3D = _mat("threshold_lights", Color(0.15, 0.92, 0.52))
	green_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var red_material: StandardMaterial3D = _mat("papi_red", Color(1.0, 0.13, 0.055))
	red_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var metal: StandardMaterial3D = _mat("airport_metal", Color(0.31, 0.36, 0.37))
	for index in range(54):
		var z: float = -1590.0 + index * 60.0
		for side in [-1.0, 1.0]:
			_box(airport, "RunwayEdgeLight", Vector3(side * 52.0, 0.55, z), Vector3(0.6, 0.6, 0.6), lights_material)
			_box(airport, "TaxiwayEdgeLight", Vector3(245.0 + side * 23.0, 0.45, z * 0.95), Vector3(0.4, 0.5, 0.4), blue_material)
	for threshold_z in [-1597.0, 1597.0]:
		for index in range(12):
			_box(airport, "ThresholdLight", Vector3(-44.0 + index * 8.0, 0.25, threshold_z), Vector3(0.85, 0.3, 0.85), green_material)
		for index in range(8):
			var approach_z: float = threshold_z + signf(threshold_z) * (45.0 + index * 35.0)
			_box(airport, "ApproachLightBar", Vector3(0.0, 1.0, approach_z), Vector3(9.0, 0.18, 0.3), metal)
			for light_x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
				_box(airport, "ApproachLight", Vector3(light_x, 1.2, approach_z), Vector3(0.45, 0.4, 0.45), lights_material)
	for side_z in [-1230.0, 1230.0]:
		for index in range(4):
			_box(airport, "PAPIHousing", Vector3(-76.0 - index * 8.0, 0.7, side_z), Vector3(2.5, 1.3, 1.3), metal)
			_box(airport, "PAPILamp", Vector3(-76.0 - index * 8.0, 0.7, side_z + signf(side_z) * 0.7), Vector3(2.0, 0.8, 0.1), red_material if index < 2 else lights_material)


func _build_terminal(airport: Node3D, airport_name: String, concrete: Material, metal: Material, glass: Material) -> void:
	_box(airport, "TerminalGroundFloor", Vector3(685.0, 8.0, 540.0), Vector3(92.0, 16.0, 510.0), concrete)
	_box(airport, "TerminalRoof", Vector3(685.0, 17.0, 540.0), Vector3(106.0, 2.0, 526.0), metal)
	_box(airport, "TerminalGlassFacade", Vector3(638.5, 9.5, 540.0), Vector3(0.6, 9.0, 470.0), glass)
	for mullion in range(40):
		_box(airport, "FacadeMullion", Vector3(637.8, 9.5, 309.0 + mullion * 12.0), Vector3(1.2, 10.0, 0.35), metal)
	for gate in range(4):
		var gate_z: float = 355.0 + gate * 123.0
		_box(airport, "JetBridge", Vector3(606.0, 6.4, gate_z), Vector3(58.0, 4.8, 5.5), concrete)
		_box(airport, "JetBridgeGlass", Vector3(606.0, 7.0, gate_z + 2.8), Vector3(52.0, 1.8, 0.18), glass)
		_box(airport, "GateCabin", Vector3(577.0, 6.2, gate_z), Vector3(8.0, 5.5, 8.0), metal)
		_cylinder(airport, "JetBridgeLeg", Vector3(581.0, 2.0, gate_z), 0.45, 4.0, metal)
	_box(airport, "ControlTowerBase", Vector3(730.0, 6.0, 175.0), Vector3(48.0, 12.0, 40.0), concrete)
	_cylinder(airport, "ControlTowerShaft", Vector3(730.0, 29.0, 175.0), 6.3, 58.0, concrete, 7.4)
	_cylinder(airport, "ControlTowerCab", Vector3(730.0, 61.0, 175.0), 14.0, 9.5, glass, 12.0)
	_cylinder(airport, "ControlTowerRoof", Vector3(730.0, 67.0, 175.0), 14.5, 2.0, metal)
	_cylinder(airport, "TowerAntenna", Vector3(730.0, 76.0, 175.0), 0.25, 16.0, metal)
	var text_mesh: TextMesh = TextMesh.new()
	text_mesh.text = airport_name
	text_mesh.font_size = 96
	text_mesh.pixel_size = 0.07
	text_mesh.depth = 0.03
	var sign_node: MeshInstance3D = MeshInstance3D.new()
	sign_node.name = "AirportIdentity"
	sign_node.mesh = text_mesh
	sign_node.position = Vector3(637.5, 18.9, 540.0)
	sign_node.rotation.y = -PI / 2.0
	sign_node.material_override = _mat("terminal_sign", Color(0.81, 0.84, 0.77))
	airport.add_child(sign_node)
	# Roads and a lined car park behind the terminal.
	_box(airport, "AccessRoad", Vector3(784.0, -0.06, 440.0), Vector3(22.0, 0.12, 1450.0), _mat("road", Color(0.17, 0.18, 0.17)))
	_box(airport, "CarPark", Vector3(880.0, -0.065, 565.0), Vector3(148.0, 0.13, 540.0), _mat("road", Color(0.17, 0.18, 0.17)))
	for row in range(3):
		for space in range(38):
			var car_x: float = 828.0 + row * 45.0
			var car_z: float = 310.0 + space * 13.0
			_box(airport, "ParkingStripe", Vector3(car_x, 0.01, car_z), Vector3(18.0, 0.012, 0.15), _mat("markings", Color(0.89, 0.90, 0.85)))
			if _rng.randf() > 0.35:
				var car_color: Color = Color(0.19, 0.23, 0.25).lerp(Color(0.65, 0.64, 0.60), _rng.randf())
				_box(airport, "ParkedCar", Vector3(car_x, 1.0, car_z + 5.0), Vector3(5.2, 2.0, 2.3), _mat("car_" + str(space % 7), car_color))


func _build_hangar(airport: Node3D, at: Vector3, width: float, depth: float) -> void:
	var wall:=ShaderMaterial.new()
	wall.shader=load("res://assets/environment/coastal/cladding.gdshader")
	var roof: StandardMaterial3D = _mat("hangar_roof", Color(0.28, 0.33, 0.32), 0.78, 0.18)
	var door: StandardMaterial3D = _mat("hangar_door", Color(0.32, 0.38, 0.39), 0.73, 0.12)
	_box(airport, "MaintenanceHangar", at + Vector3(0.0, 17.0, 0.0), Vector3(width, 34.0, depth), wall)
	# Low pitched roof, fascia, skylights and roof ventilation give the silhouette depth.
	for side in [-1.0,1.0]:
		var slope:=_box(airport,"HangarRoof",at+Vector3(0,37,side*depth*0.25),Vector3(width+5,1.2,depth*0.515+3),roof)
		slope.rotation.x=side*0.12
		_box(airport,"RoofGutter",at+Vector3(0,33.3,side*(depth*0.5+2)),Vector3(width+5,0.7,0.7),roof)
		for bay in range(6):
			var skylight:=_box(airport,"RoofSkylight",at+Vector3(-width*0.38+bay*width*0.15,38,side*depth*0.22),Vector3(12,0.5,18),_mat("hangar_skylight",Color(0.12,0.22,0.25),0.2,0.45))
			skylight.rotation.x=side*0.12
	for vent in range(4):
		_box(airport,"RoofVent",at+Vector3(-width*0.32+vent*width*0.21,42,0),Vector3(8,2,5),roof)
	for side in [-1.0,1.0]:
		_box(airport,"HangarPlinth",at+Vector3(0,1,side*depth*0.5),Vector3(width,2,0.6),_mat("hangar_plinth",Color(0.22,0.23,0.21)))
		for bay in range(9):
			_box(airport,"ClerestoryWindow",at+Vector3(-width*0.43+bay*width*0.105,27,side*(depth*0.5+0.1)),Vector3(width*0.085,4,0.2),_mat("hangar_skylight",Color(0.12,0.22,0.25),0.2,0.45))
	_box(airport, "HangarDoor", at + Vector3(-width * 0.5 - 0.1, 14.0, 0.0), Vector3(0.3, 27.0, depth * 0.86), door)
	for rib in range(19):
		_box(airport, "HangarCladdingRib", at + Vector3(0.0, 18.0, -depth * 0.5 - 0.2) + Vector3(-width * 0.46 + rib * width / 20.0, 0.0, 0.0), Vector3(0.6, 32.0, 0.55), roof)
	for panel in range(8):
		_box(airport, "HangarDoorPanel", at + Vector3(-width * 0.5 - 0.28, 14.0, -depth * 0.37 + panel * depth * 0.106), Vector3(0.35, 27.0, 0.45), roof)
	_box(airport, "HangarFrontApron", at + Vector3(-110.0, -0.07, 0.0), Vector3(85.0, 0.14, depth + 10.0), _mat("concrete", Color(0.43, 0.45, 0.43)))


func _build_windsock(airport: Node3D, at: Vector3) -> void:
	var pole: StandardMaterial3D = _mat("windsock_pole", Color(0.66, 0.68, 0.63))
	_cylinder(airport, "WindsockMast", at + Vector3(0.0, 7.5, 0.0), 0.13, 15.0, pole)
	var orange: StandardMaterial3D = _mat("windsock_orange", Color(0.85, 0.30, 0.10))
	var white: StandardMaterial3D = _mat("windsock_white", Color(0.83, 0.84, 0.76))
	for section in range(5):
		var sock: MeshInstance3D = _cylinder(airport, "Windsock", at + Vector3(0.75 + section * 1.2, 14.5 - section * 0.18, 0.0), 0.85 - section * 0.12, 1.3, orange if section % 2 == 0 else white, 0.72 - section * 0.12)
		sock.rotation_degrees.z = -82.0


func _make_tree_mesh() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Asymmetric layered conifers: shared geometry is instanced across the valley.
	var bark: Color = Color(0.22, 0.20, 0.16)
	var leaves: Array[Color] = [Color(0.14, 0.23, 0.16), Color(0.17, 0.27, 0.18), Color(0.20, 0.29, 0.20)]
	for segment in range(7):
		var angle_a: float = segment * TAU / 7.0
		var angle_b: float = (segment + 1) * TAU / 7.0
		var a: Vector3 = Vector3(cos(angle_a) * 0.35, 0.0, sin(angle_a) * 0.35)
		var b: Vector3 = Vector3(cos(angle_b) * 0.35, 0.0, sin(angle_b) * 0.35)
		var c: Vector3 = b + Vector3(0.0, 9.0, 0.0)
		var d: Vector3 = a + Vector3(0.0, 9.0, 0.0)
		for point in [a, b, c, a, c, d]:
			surface.set_color(bark)
			surface.add_vertex(point)
	for layer in range(4):
		var bottom: float = 3.0 + layer * 3.0
		var radius: float = 4.5 - layer * 0.84
		var tip: Vector3 = Vector3(0.16 * sin(layer * 2.1), bottom + 7.0 - layer * 0.6, 0.1)
		for segment in range(10):
			var angle_a: float = segment * TAU / 10.0
			var angle_b: float = (segment + 1) * TAU / 10.0
			var a: Vector3 = Vector3(cos(angle_a) * radius, bottom + sin(angle_a * 3.0) * 0.4, sin(angle_a) * radius)
			var b: Vector3 = Vector3(cos(angle_b) * radius, bottom + sin(angle_b * 3.0) * 0.4, sin(angle_b) * radius)
			for point in [a, tip, b]:
				surface.set_color(leaves[(segment + layer) % leaves.size()])
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _build_forests() -> void:
	var transforms: Array[Transform3D] = []
	var groves: Array[Vector2] = []
	for grove_index in range(100):
		var side: float = -1.0 if grove_index % 2 == 0 else 1.0
		groves.append(Vector2(side * _rng.randf_range(850.0, 4100.0), _rng.randf_range(-22000.0, 5700.0)))
	for attempt in range(39000):
		var x: float = _rng.randf_range(-9100.0, 9200.0)
		var z: float = _rng.randf_range(-23800.0, 7400.0)
		if attempt >= 9000:
			var grove: Vector2 = groves[int((attempt - 9000) / 300)]
			var radius: float = sqrt(_rng.randf()) * 245.0
			var angle: float = _rng.randf_range(0.0, TAU)
			x = grove.x + cos(angle) * radius
			z = grove.y + sin(angle) * radius
		var h: float = ground_height(x, z)
		var nearest_airport: float = minf(absf(z), absf(z - DESTINATION_Z))
		if absf(x) < 540.0 or (absf(x) < 1180.0 and nearest_airport < 2580.0):
			continue
		if absf(x)<3450 and z> -13600 and z< -2200:
			continue # Urban trees are placed along streets and inside parks instead.
		if x>580 and x<1240 and z>-6970 and z<-5500:
			continue # Streets and buildings have clear plots, not trees through roofs.
		if h < -3.0 or h > 1600.0 or absf(x - _river_center(z)) < 215.0:
			continue
		var forest_density: float = _noise.get_noise_2d(x * 3.0 + 1200.0, z * 3.0)
		if x>-1350 and x<-690 and z>-11050 and z<-8500:
			continue # Keep the agricultural plots clear of forest instances.
		if forest_density < -0.14:
			continue
		var size: float = _rng.randf_range(1.0, 2.5) * (1.0 - _smooth(950.0, 1750.0, h) * 0.5)
		var basis: Basis = Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(size, size * _rng.randf_range(0.9, 1.2), size))
		transforms.append(Transform3D(basis, Vector3(x, h - 0.5, z)))
	var material: StandardMaterial3D = _mat("trees", Color.WHITE)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: ArrayMesh = _make_tree_mesh()
	mesh.surface_set_material(0, material)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var forest: MultiMeshInstance3D = MultiMeshInstance3D.new()
	forest.name = "AlpineConiferForest"
	forest.multimesh = multimesh
	forest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(forest)


func _build_clouds() -> void:
	var cloud_shader: Shader = load("res://assets/environment/coastal/cloud.gdshader") as Shader
	for index in range(16):
		var cloud: MeshInstance3D = MeshInstance3D.new()
		cloud.name = "CloudBank_" + str(index)
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = Vector2(_rng.randf_range(2200.0, 4100.0), _rng.randf_range(500.0, 1100.0))
		cloud.mesh = mesh
		cloud.position = Vector3(_rng.randf_range(-12500.0, 12500.0), _rng.randf_range(3100.0, 4700.0), _rng.randf_range(-22000.0, 8000.0))
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = cloud_shader
		material.set_shader_parameter("seed", float(index) * 17.7)
		material.set_shader_parameter("cloud_color", Color(0.91, 0.93, 0.92, _rng.randf_range(0.45, 0.73)))
		cloud.material_override = material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.extra_cull_margin = 3000.0
		add_child(cloud)


func _build_scenic_cloud_sea() -> void:
	# Layered world-space patches form a low cloud sea, visible from both sides.
	# No volumetric renderer required: keeps the demo viable on integrated GPUs.
	var shader: Shader = load("res://assets/environment/coastal/cloud.gdshader")
	for i in range(30):
		var cloud := MeshInstance3D.new()
		cloud.name = "ScenicCloudSea_%02d" % i
		var mesh := QuadMesh.new()
		mesh.size = Vector2(1550,1100)
		cloud.mesh = mesh
		cloud.position = Vector3(-1800+(i%6)*700,720+(i%3)*45,-7850-(i/6)*450)
		cloud.rotation.x = -PI/2
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("billboard",false)
		material.set_shader_parameter("seed",float(i)*3.71)
		material.set_shader_parameter("cloud_color",Color(0.94,0.96,1.0,0.62))
		cloud.material_override = material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)
		# Billowed silhouettes break up the horizontal deck at pilot-eye level.
		var puff := MeshInstance3D.new()
		puff.name = "CloudCrown_%02d" % i
		var puff_mesh := QuadMesh.new()
		puff_mesh.size = Vector2(1000,400+(i%4)*70)
		puff.mesh = puff_mesh
		puff.position = cloud.position+Vector3(140,60,0)
		var puff_mat := ShaderMaterial.new()
		puff_mat.shader = shader
		puff_mat.set_shader_parameter("seed",float(i)*12.3)
		puff_mat.set_shader_parameter("cloud_color",Color(0.94,0.96,1.0,0.65))
		puff.material_override = puff_mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)

func cloud_immersion(at: Vector3) -> float:
	var footprint: float = (1.0-_smooth(1300,2300,absf(at.x)))*(1.0-_smooth(900,1550,absf(at.z+8750)))
	return footprint*_smooth(610,730,at.y)*(1.0-_smooth(810,960,at.y))

func update_cloud_passage(at: Vector3, enabled: bool) -> void:
	if _environment==null: return
	var density: float = cloud_immersion(at) if enabled else 0.0
	var base: float = 0.000014 if _condition_id=="clear" else 0.000052 if _condition_id=="overcast" else 0.000026
	_environment.environment.fog_density = lerpf(base,0.0035,density)

func _build_lakeside_town() -> void:
	var town := Node3D.new()
	town.name = "LakesideDistrict"
	add_child(town)
	var water := MeshInstance3D.new()
	water.name = "GlacialLake"
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(120):
		var a: float = TAU*i/120.0
		var b: float = TAU*(i+1)/120.0
		for p: Vector3 in [Vector3(-2350,-8.5,-4800),Vector3(-2350+cos(b)*980,-8.5,-4800+sin(b)*1750),Vector3(-2350+cos(a)*980,-8.5,-4800+sin(a)*1750)]:
			lake.set_normal(Vector3.UP)
			lake.add_vertex(p)
	water.mesh = lake.commit()
	var water_mat := ShaderMaterial.new()
	water_mat.shader = load("res://assets/environment/coastal/water.gdshader")
	water_mat.set_shader_parameter("glacial",true)
	water.material_override = water_mat
	add_child(water)
	var roofs := _mat("district_roofs",Color(0.28,0.16,0.12))
	var glass := _mat("district_windows",Color(0.17,0.29,0.32),0.22,0.3)
	var road := _mat("district_roads",Color(0.14,0.15,0.14))
	# A planned street grid, with pitched-roof houses and courtyards instead of scattered cubes.
	for block in range(7):
		var z: float = -6700+block*170
		for segment in range(12):
			var x: float = 620+segment*50
			_box(town,"TownStreet",Vector3(x,ground_height(x,z)+0.3,z),Vector3(52,0.6,10),road)
		for column in range(6):
			var x: float = 650+column*92
			var at := Vector3(x,ground_height(x,z+55),z+55)
			var height: float = 14.0+float((block+column)%3)*5.0
			var walls := _mat("district_wall_"+str(column%3),[Color(0.72,0.65,0.51),Color(0.55,0.59,0.57),Color(0.69,0.51,0.36)][column%3])
			_box(town,"TownHouse",at+Vector3(0,height/2,0),Vector3(37,height,44),walls)
			for side in [-1,1]:
				var roof := _box(town,"PitchedRoof",at+Vector3(side*10,height+5,0),Vector3(24,1.5,48),roofs)
				roof.rotation.z = -side*0.42
				for window in range(4):
					_box(town,"Window",at+Vector3(-12+window*8,height*0.65,side*22.1),Vector3(3.8,5,0.3),glass)
	# Tall recognisable landmark near the settlement.
	var church_at := Vector3(970,ground_height(970,-6900),-6900)
	_box(town,"ClockTower",church_at+Vector3(0,34,0),Vector3(23,68,23),_mat("stone",Color(0.57,0.55,0.48)))
	_cylinder(town,"ClockTowerSpire",church_at+Vector3(0,82,0),18,30,roofs,0)
	# Legible clock faces on all four sides, facing both approaches.
	var dial := _mat("clock_dial",Color(0.91,0.83,0.62))
	var hands := _mat("clock_hands",Color(0.09,0.12,0.13))
	for side in range(4):
		var face := Node3D.new()
		face.position = church_at+Vector3(0,56,0)
		face.rotation.y = side*PI/2
		town.add_child(face)
		_box(face,"ClockFace",Vector3(0,0,11.7),Vector3(13,13,0.4),dial)
		_box(face,"MinuteHand",Vector3(0,2,12),Vector3(0.7,5,0.5),hands)
		_box(face,"HourHand",Vector3(1.6,0,12),Vector3(3.8,0.7,0.5),hands)
	# A steel truss across the river: strong silhouette visible from the cockpit.
	var bridge_z: float = -10200
	var bridge_x: float = _river_center(bridge_z)
	var steel := _mat("truss_steel",Color(0.40,0.23,0.16),0.65,0.3)
	for side in [-1,1]:
		for i in range(11):
			var x: float = bridge_x-200+i*40
			_box(town,"TrussPost",Vector3(x,27,bridge_z+side*10),Vector3(2,30,2),steel)
			if i<10:
				_box(town,"TrussChord",Vector3(x+20,42,bridge_z+side*10),Vector3(41,2,2),steel)
				var brace := _box(town,"TrussDiagonal",Vector3(x+20,27,bridge_z+side*10),Vector3(50,1.6,1.6),steel)
				brace.rotation.z = 0.644 if i%2==0 else -0.644
	# Terminal service vehicles and baggage carts make the departure apron feel inhabited.
	for airport_z in [0.0,DESTINATION_Z]:
		for i in range(8):
			var at := Vector3(340+i%2*85,0,airport_z+80+i*105)
			_box(town,"ServiceVan",at+Vector3(0,2,0),Vector3(5,4,10),_mat("service_white",Color(0.81,0.81,0.73)))
			_box(town,"VanWindshield",at+Vector3(0,2.8,-5.1),Vector3(4,1.5,0.1),glass)
			for side in [-1,1]:
				for wheel_z in [-3,3]:
					var wheel := _cylinder(town,"VanWheel",at+Vector3(side*2.5,0.9,wheel_z),0.9,0.5,_mat("tires",Color(0.04,0.045,0.045)))
					wheel.rotation.z = PI/2
	_batch_static_geometry(town)


func _build_valley_landmarks() -> void:
	var village: Node3D = Node3D.new()
	village.name = "ValleyVillage"
	add_child(village)
	var roof: StandardMaterial3D = _mat("village_roof", Color(0.27, 0.25, 0.23))
	var walls: StandardMaterial3D = _mat("village_wall", Color(0.63, 0.61, 0.52))
	var road: StandardMaterial3D = _mat("road", Color(0.17, 0.18, 0.17))
	for index in range(55):
		var x: float = _rng.randf_range(-1450.0, -750.0)
		var z: float = _rng.randf_range(-8400.0, -6900.0)
		var ground: float = ground_height(x, z)
		var width: float = _rng.randf_range(12.0, 28.0)
		var depth: float = _rng.randf_range(14.0, 35.0)
		var height: float = _rng.randf_range(7.0, 16.0)
		_box(village, "AlpineHouse", Vector3(x, ground + height * 0.5, z), Vector3(width, height, depth), walls)
		_box(village, "HouseRoof", Vector3(x, ground + height + 0.6, z), Vector3(width + 1.4, 1.2, depth + 1.4), roof)
	# A narrow ribbon road traces the valley; bridge crosses the river south of the mission.
	for segment in range(130):
		var z: float = -19500.0 + segment * 180.0
		var x: float = -640.0 + sin(z * 0.00038) * 75.0
		var h: float = ground_height(x, z)
		var road_piece: MeshInstance3D = _box(village, "ValleyRoad", Vector3(x, h + 0.12, z), Vector3(13.0, 0.24, 184.0), road)
		road_piece.rotation.x = atan2(ground_height(x, z - 90.0) - ground_height(x, z + 90.0), 180.0)
	var bridge_z: float = -10200.0
	var river_x: float = _river_center(bridge_z)
	var bridge: StandardMaterial3D = _mat("bridge", Color(0.47, 0.48, 0.42))
	_box(village, "RiverBridgeDeck", Vector3(river_x, 12.0, bridge_z), Vector3(440.0, 2.0, 16.0), bridge)
	for side in [-1.0, 1.0]:
		_box(village, "BridgeGuardrail", Vector3(river_x, 14.0, bridge_z + side * 7.0), Vector3(440.0, 1.0, 0.45), bridge)
	for pier in [-150.0, -60.0, 60.0, 150.0]:
		_box(village, "BridgePier", Vector3(river_x + pier, -3.0, bridge_z), Vector3(5.0, 30.0, 11.0), bridge)

	_batch_static_geometry(village)


func _batch_static_geometry(parent: Node3D) -> void:
	# Merge airport furniture by material: thousands of authored details become
	# a few dozen draw calls, keeping the whole valley smooth on laptop GPUs.
	var groups: Dictionary = {}
	for child in parent.get_children():
		var instance: MeshInstance3D = child as MeshInstance3D
		if instance == null or instance.mesh == null or instance.mesh is TextMesh:
			continue
		var material: Material = instance.material_override
		if material == null:
			continue
		var key: String = str(material.get_instance_id()) + "_" + str(instance.cast_shadow)
		if not groups.has(key):
			groups[key] = []
		var instances: Array = groups[key]
		instances.append(instance)
	for key in groups:
		var instances: Array = groups[key]
		if instances.size() < 2:
			continue
		var first: MeshInstance3D = instances[0] as MeshInstance3D
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for value in instances:
			var instance: MeshInstance3D = value as MeshInstance3D
			for mesh_surface in range(instance.mesh.get_surface_count()):
				var arrays: Array=instance.mesh.surface_get_arrays(mesh_surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				var count: int=indices.size() if not indices.is_empty() else vertices.size()
				var normal_basis: Basis=instance.basis.inverse().transposed()
				for n in range(count):
					var index: int=indices[n] if not indices.is_empty() else n
					surface.set_normal((normal_basis*normals[index]).normalized())
					surface.set_uv(uv[index] if uv.size()>index else Vector2.ZERO)
					surface.add_vertex(instance.transform*vertices[index])
		var batch: MeshInstance3D = MeshInstance3D.new()
		batch.name = "StaticBatch_" + str(key)
		batch.mesh = surface.commit()
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		parent.add_child(batch)
		for value in instances:
			var instance: MeshInstance3D = value as MeshInstance3D
			parent.remove_child(instance)
			instance.queue_free()


func is_runway(x: float, z: float) -> bool:
	return absf(x) <= 50.0 and minf(absf(z), absf(z - DESTINATION_Z)) <= 1600.0

func _grid_height(x: float,z: float) -> float:
	# Reuse the actual rendered grid instead of recomputing noise/elevation for
	# every tree, vehicle and flight collision query. Terrain is immutable.
	var key:=Vector2i(roundi(x),roundi(z))
	if not _height_grid.has(key): _height_grid[key]=_terrain_height(x,z)
	return _height_grid[key]

func ground_height(x: float, z: float) -> float:
	# Runway deck is at zero; terrain immediately underneath remains recessed.
	if is_runway(x, z):
		return 0.0
	# Match the two triangles in the rendered heightfield, including on steep
	# mountain faces, instead of sampling a different continuous noise surface.
	var grid_x: float = (x - TERRAIN_X_MIN) / TERRAIN_STEP
	var grid_z: float = (z - TERRAIN_Z_MIN) / TERRAIN_STEP
	var x0: float = TERRAIN_X_MIN + floorf(grid_x) * TERRAIN_STEP
	var z0: float = TERRAIN_Z_MIN + floorf(grid_z) * TERRAIN_STEP
	var u: float = grid_x - floorf(grid_x)
	var v: float = grid_z - floorf(grid_z)
	var a: float = _grid_height(x0, z0)
	var b: float = _grid_height(x0 + TERRAIN_STEP, z0)
	var c: float = _grid_height(x0, z0 + TERRAIN_STEP)
	if u + v <= 1.0:
		return a + u * (b - a) + v * (c - a)
	var d: float = _grid_height(x0 + TERRAIN_STEP, z0 + TERRAIN_STEP)
	return d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)

# Shared presentation interface with the preserved alpine world.
func apply_quality(high: bool) -> void:
	if _environment==null: return
	var capable: bool = RenderingServer.get_current_rendering_method()=="forward_plus"
	_environment.environment.ssao_enabled = high and capable
	_environment.environment.glow_enabled = high and capable
	_environment.environment.ssr_enabled = false

func update_local_shadows(_at: Vector3,_dt: float) -> void:
	pass
