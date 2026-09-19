class_name FlightWorld
extends Node3D
## A deterministic alpine corridor. Flight collision samples exactly the same
## height function used to construct the visible terrain.

const DESTINATION_Z: float = -15000.0
const destination_z: float = -15000.0
const TERRAIN_X_MIN: float = -16500.0
const TERRAIN_X_MAX: float = 16500.0
const TERRAIN_Z_MIN: float = -25500.0
const TERRAIN_Z_MAX: float = 9500.0
const TERRAIN_STEP: float = 55.0
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
var _environment: WorldEnvironment
var _sun: DirectionalLight3D
var _condition_id: String = "golden"
var _condition_skies: Dictionary = {}
var _airport_obstacles: Array[AABB] = []
var _forest_transforms: Array[Transform3D] = []
var _forest_shadow: MultiMeshInstance3D
var _shadow_refresh := 0.0
var _quality_high := true
var _height_cache := PackedFloat32Array()
var _height_columns := 0
var _height_rows := 0
var _forest_cells: Dictionary = {}


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
	_build_forests()
	_build_shore_details()
	_build_valley_landmarks()


func _smooth(a: float, b: float, value: float) -> float:
	var t: float = clampf((value - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _river_center(z: float) -> float:
	return 1030.0 + sin(z * 0.00034) * 170.0 + sin(z * 0.00091) * 60.0

func _river_width(z: float) -> float:
	return 113.0+470.0*exp(-pow((z+7000)/2550.0,2))+200.0*exp(-pow((z+19000)/2300.0,2))


func _terrain_height(x: float, z: float) -> float:
	var broad: float = _noise.get_noise_2d(x, z)
	var detail: float = _detail_noise.get_noise_2d(x, z)
	var end_weight: float = maxf(_smooth(19300.0, 25500.0, -z), _smooth(4800.0, 9500.0, z))
	var mountain_weight: float = maxf(_smooth(1350.0, 5100.0, absf(x)), end_weight)
	var ridge: float = 1.0 - absf(_noise.get_noise_2d(x + 2810.0, z - 5400.0))
	var floor_height: float = -2.0 + broad * 23.0 + detail * 5.0
	var sharp_detail: float = 260.0*_detail_noise.get_noise_2d(x*.65,z*.65)
	var elevation: float = floor_height + mountain_weight * (1180.0 + broad * 1450.0 + pow(ridge, 3.0) * 1480.0+sharp_detail)
	# Both airports have a generous level safety area and smooth earth embankments.
	var nearest_airport: float = minf(absf(z), absf(z - DESTINATION_Z))
	var airport_weight: float = (1.0 - _smooth(1050.0, 1370.0, absf(x))) * (1.0 - _smooth(1900.0, 2600.0, nearest_airport))
	elevation = lerpf(elevation, -0.20, airport_weight)
	var river_distance: float = absf(x - _river_center(z))
	var river_weight: float = (1.0 - _smooth(_river_width(z)-35, _river_width(z)+75, river_distance)) * (1.0 - end_weight)
	elevation = lerpf(elevation, -23.0, river_weight)
	for island_z in [-5200.0,-6500.0,-7550.0,-8300.0,-17600.0]:
		if absf(z-island_z)>260: continue
		var island_x: float = _river_center(island_z)+sin(island_z)*180
		var island: float = Vector2((x-island_x)/120,(z-island_z)/230).length()
		elevation += (1-_smooth(.35,1,island))*35
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
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/environment/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama",load("res://assets/environment/alpine-sunset.png"))
	sky_material.set_shader_parameter("front_clouds",load("res://assets/environment/alpine-cloud-front.png"))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	_condition_skies["golden"] = sky
	_condition_skies["clear"] = _make_weather_sky(false)
	_condition_skies["overcast"] = _make_weather_sky(true)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.48,.56,.67)
	environment.ambient_light_energy = 0.90
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.98
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.62, 0.73, 0.80)
	environment.fog_light_energy = 0.85
	environment.fog_density = 0.000041
	environment.fog_aerial_perspective = 0.92
	environment.fog_sky_affect = 0.12
	_environment = WorldEnvironment.new()
	_environment.name = "MountainAtmosphere"
	_environment.environment = environment
	add_child(_environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "ValleySun"
	_sun.directional_shadow_max_distance = 5000.0
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
			_sun.rotation_degrees = Vector3(-12.0, 152.0, 0.0)
			_sun.light_color = Color(1.0, 0.85, 0.66)
			_sun.light_energy = 1.1
			environment.ambient_light_energy = 0.90
			environment.tonemap_exposure = 0.98
			environment.fog_light_color = Color(0.62, 0.73, 0.80)
			environment.fog_light_energy = 0.85
			environment.fog_density = 0.000041
			environment.fog_aerial_perspective = 0.92
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
	_height_columns = columns; _height_rows = rows
	_height_cache.resize(columns*rows)
	for row in range(rows):
		for column in range(columns): _height_cache[row*columns+column] = _terrain_height(TERRAIN_X_MIN+column*TERRAIN_STEP,TERRAIN_Z_MIN+row*TERRAIN_STEP)
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
			var h: float = _height_at_grid(column,row)
			var normal: Vector3 = Vector3(_height_at_grid(column-1,row)-_height_at_grid(column+1,row),TERRAIN_STEP*2,_height_at_grid(column,row-1)-_height_at_grid(column,row+1)).normalized()
			var index: int = row * columns + column
			vertices[index] = Vector3(x, h, z)
			normals[index] = normal
			colors[index] = Color.WHITE
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
	material.shader = load("res://assets/environment/terrain.gdshader") as Shader
	material.set_shader_parameter("grass_texture", load("res://assets/environment/aerial_grass_rock_diff_1k.jpg"))
	material.set_shader_parameter("rock_texture", load("res://assets/environment/alpine-granite.png"))
	var terrain: MeshInstance3D = MeshInstance3D.new()
	terrain.name = "AlpineTerrain"
	terrain.mesh = terrain_mesh
	terrain.material_override = material
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(terrain)


func _build_river() -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var count: int = 501
	for i in range(count):
		var z: float = -25500.0 + i * 70.0
		var center: float = _river_center(z)
		var width: float = _river_width(z)+110+sin(z*.002)*7
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
	material.shader = load("res://assets/environment/water.gdshader") as Shader
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
	asphalt.shader = load("res://assets/environment/asphalt.gdshader") as Shader
	var concrete: StandardMaterial3D = _mat("concrete", Color(0.43, 0.45, 0.43))
	var pale_concrete: StandardMaterial3D = _mat("pale_concrete", Color(0.57, 0.58, 0.54))
	var yellow: StandardMaterial3D = _mat("yellow", Color(0.83, 0.64, 0.18))
	var markings: StandardMaterial3D = _mat("markings", Color(0.89, 0.90, 0.85))
	var metal: StandardMaterial3D = _mat("airport_metal", Color(0.31, 0.36, 0.37), 0.63, 0.15)
	var glass: StandardMaterial3D = _mat("airport_glass", Color(0.11, 0.25, 0.29), 0.16, 0.38)
	var field_green: StandardMaterial3D = _mat("mown_grass", Color(0.28, 0.34, 0.20))
	_box(airport, "Runway", Vector3(0.0, -0.13, 0.0), Vector3(100.0, 0.26, 3200.0), asphalt)
	_box(airport, "RunwayShoulderWest", Vector3(-56.0, -0.13, 0.0), Vector3(12.0, 0.20, 3220.0), concrete)
	_box(airport, "RunwayShoulderEast", Vector3(56.0, -0.13, 0.0), Vector3(12.0, 0.20, 3220.0), concrete)
	_box(airport, "Taxiway", Vector3(245.0, -0.09, 0.0), Vector3(44.0, 0.18, 3060.0), asphalt)
	_box(airport, "TaxiwayGuide", Vector3(245.0, 0.045, 0.0), Vector3(0.60, 0.016, 2980.0), yellow)
	_box(airport, "TerminalApron", Vector3(438.0, -0.085, 470.0), Vector3(370.0, 0.17, 950.0), concrete)
	for side in [-1.0, 1.0]:
		_box(airport, "EdgeStripe", Vector3(side * 45.0, 0.025, 0.0), Vector3(1.6, 0.015, 3150.0), markings)
		_box(airport, "MownVerge", Vector3(side * 95.0, -0.115, 0.0), Vector3(50.0, 0.06, 3350.0), field_green)
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
	var wall: StandardMaterial3D = _mat("hangar_wall", Color(0.42, 0.46, 0.44), 0.69, 0.12)
	var roof: StandardMaterial3D = _mat("hangar_roof", Color(0.28, 0.33, 0.32), 0.78, 0.18)
	var door: StandardMaterial3D = _mat("hangar_door", Color(0.32, 0.38, 0.39), 0.73, 0.12)
	_box(airport, "MaintenanceHangar", at + Vector3(0.0, 17.0, 0.0), Vector3(width, 34.0, depth), wall)
	_box(airport, "HangarRoof", at + Vector3(0.0, 35.0, 0.0), Vector3(width + 5.0, 2.0, depth + 5.0), roof)
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
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(3):
		var basis := Basis(Vector3.UP,index*PI/3)
		for item: Array in [[Vector3(-8,0,0),Vector2(0,1)],[Vector3(-8,24,0),Vector2(0,0)],[Vector3(8,24,0),Vector2(1,0)],[Vector3(-8,0,0),Vector2(0,1)],[Vector3(8,24,0),Vector2(1,0)],[Vector3(8,0,0),Vector2(1,1)]]:
			surface.set_uv(item[1]); surface.set_normal(basis*Vector3(0,.25,1).normalized()); surface.add_vertex(basis*item[0])
	return surface.commit()

func _tree_variation(at: Vector3) -> float:
	var value: int = (roundi(at.x*8)*73856093) ^ (roundi(at.z*8)*19349663)
	return float(absi(value%1000))/1000.0

func _build_forests() -> void:
	var cells: Dictionary = {}
	for grid_z in range(-21000,3400,22):
		for grid_x in range(-3300,3300,22):
			var x: float = grid_x+_rng.randf_range(-7,7)
			var z: float = grid_z+_rng.randf_range(-7,7)
			var h: float = ground_height(x,z)
			var airport: float = minf(absf(z),absf(z-DESTINATION_Z))
			if (absf(x)<760 and airport<1920) or (absf(x)<120 and (z<-10000 or z>-2400)): continue
			if x>-1500 and x<-700 and z>-8500 and z<-6800: continue
			if absf(x-(-640+sin(z*.00038)*75))<14: continue
			if h < -7.0 or h>1850: continue
			if _noise.get_noise_2d(x*2+1200,z*2)<-.35: continue
			var size: float = _rng.randf_range(1.8,2.7)*(1-_smooth(1250,2000,h)*.45)
			var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(size,size*_rng.randf_range(.9,1.2),size))
			var transform := Transform3D(basis,Vector3(x,h-.5,z))
			_forest_transforms.append(transform)
			var key := Vector2i(floori(x/1400),floori(z/1400))
			if not cells.has(key): cells[key] = []
			cells[key].append(transform)
	_forest_cells = cells
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/environment/foliage.gdshader")
	material.set_shader_parameter("foliage",load("res://assets/environment/alpine-fir.png"))
	material.set_shader_parameter("foliage_b",load("res://assets/environment/alpine-fir-b.png"))
	var mesh := _make_tree_mesh(); mesh.surface_set_material(0,material)
	for key: Vector2i in cells:
		var transforms: Array = cells[key]
		var forest := MultiMeshInstance3D.new(); forest.name = "Conifers_%s_%s" % [key.x,key.y]
		var multimesh := MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh; multimesh.use_custom_data = true; multimesh.instance_count = transforms.size()
		var origin := Vector3(key.x*1400,0,key.y*1400)
		for i in range(transforms.size()):
			var transform: Transform3D = transforms[i]; transform.origin -= origin
			multimesh.set_instance_transform(i,transform)
			multimesh.set_instance_custom_data(i,Color(_tree_variation(transforms[i].origin),0,0,0))
		forest.multimesh = multimesh; forest.position = origin
		forest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		forest.visibility_range_end = 9500
		add_child(forest)
	_forest_shadow = MultiMeshInstance3D.new()
	var shadow_mesh := MultiMesh.new(); shadow_mesh.transform_format = MultiMesh.TRANSFORM_3D
	shadow_mesh.mesh = mesh; shadow_mesh.use_custom_data = true; shadow_mesh.instance_count = 700; shadow_mesh.visible_instance_count = 0
	_forest_shadow.multimesh = shadow_mesh; _forest_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(_forest_shadow)


func _build_clouds() -> void:
	var cloud_shader: Shader = load("res://assets/environment/cloud.gdshader") as Shader
	for index in range(34):
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
				surface.append_from(instance.mesh, mesh_surface, instance.transform)
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

func _height_at_grid(x: int, z: int) -> float:
	if x>=0 and z>=0 and x<_height_columns and z<_height_rows and not _height_cache.is_empty(): return _height_cache[z*_height_columns+x]
	return _terrain_height(TERRAIN_X_MIN+x*TERRAIN_STEP,TERRAIN_Z_MIN+z*TERRAIN_STEP)

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
	var a: float = _height_at_grid(floori(grid_x),floori(grid_z))
	var b: float = _height_at_grid(floori(grid_x)+1,floori(grid_z))
	var c: float = _height_at_grid(floori(grid_x),floori(grid_z)+1)
	if u + v <= 1.0:
		return a + u * (b - a) + v * (c - a)
	var d: float = _height_at_grid(floori(grid_x)+1,floori(grid_z)+1)
	return d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)

var _fog_volumes: Array[FogVolume] = []
func apply_quality(high: bool) -> void:
	_quality_high = high
	if _environment == null: return
	var environment: Environment = _environment.environment
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.03
	environment.adjustment_saturation = 1.0
	var capable: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.glow_enabled = high and capable
	environment.glow_intensity = 0.38
	environment.glow_bloom = 0.06
	environment.ssao_enabled = high and capable
	environment.ssao_radius = 2.4
	environment.ssao_intensity = 1.1
	environment.ssr_enabled = high and capable
	environment.volumetric_fog_enabled = high and capable
	environment.volumetric_fog_density = 0.000025
	environment.volumetric_fog_anisotropy = 0.28
	environment.volumetric_fog_length = 4500
	environment.volumetric_fog_albedo = Color(0.78,0.84,0.91)
	environment.volumetric_fog_emission = Color(0.12,0.16,0.22)
	if high and capable and _fog_volumes.is_empty() and DisplayServer.get_name()!="headless":
		var noise := FastNoiseLite.new(); noise.seed = 26026; noise.frequency = 0.04
		var texture := NoiseTexture3D.new(); texture.width = 64; texture.height = 32; texture.depth = 64; texture.noise = noise
		for index in range(8):
			var cloud := FogVolume.new()
			cloud.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
			cloud.size = Vector3(1800,400,2200)
			cloud.position = Vector3((-1 if index%2 else 1)*(2200+index*170),950+index*105,-2000-index*2100)
			var material := FogMaterial.new(); material.density = 0.0015; material.albedo = Color(0.68,0.74,0.82); material.density_texture = texture
			cloud.material = material
			add_child(cloud); _fog_volumes.append(cloud)
		for index in range(5):
			var mist := FogVolume.new(); mist.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID; mist.size = Vector3(1450,100,2200)
			mist.position = Vector3(_river_center(-4500-index*2000),30,-4500-index*2000)
			var material := FogMaterial.new(); material.density = 0.0005; material.density_texture = texture; material.albedo = Color(0.68,0.78,0.86)
			mist.material = material; add_child(mist); _fog_volumes.append(mist)
	for volume: FogVolume in _fog_volumes: volume.visible = high and capable

func update_local_shadows(at: Vector3, dt: float) -> void:
	if not is_instance_valid(_forest_shadow): return
	_forest_shadow.visible = _quality_high
	if not _quality_high: return
	_shadow_refresh -= dt
	if _shadow_refresh>0: return
	_shadow_refresh = 1.0
	var candidates: Array[Dictionary] = []
	var cell := Vector2i(floori(at.x/1400),floori(at.z/1400))
	for dx in range(-1,2):
		for dz in range(-1,2):
			for transform: Transform3D in _forest_cells.get(cell+Vector2i(dx,dz),[]):
				var distance: float = Vector2(transform.origin.x-at.x,transform.origin.z-at.z).length_squared()
				if distance<490000: candidates.append({"distance":distance,"transform":transform})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return a.distance<b.distance)
	var count: int = mini(700,candidates.size())
	for i in range(count):
		_forest_shadow.multimesh.set_instance_transform(i,candidates[i].transform)
		_forest_shadow.multimesh.set_instance_custom_data(i,Color(_tree_variation(candidates[i].transform.origin),0,0,0))
	_forest_shadow.multimesh.visible_instance_count = count

func _build_shore_details() -> void:
	var shape := SphereMesh.new(); shape.radius = 1; shape.height = 2; shape.radial_segments = 12; shape.rings = 6
	var arrays: Array = shape.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		vertices[i] *= 1+.19*sin(v.x*7+v.z*5)+.11*cos(v.y*9-v.x*4)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new(); material.shader = load("res://assets/environment/shore_rock.gdshader")
	material.set_shader_parameter("granite",load("res://assets/environment/alpine-granite.png")); mesh.surface_set_material(0,material)
	var transforms: Array[Transform3D] = []
	for z in range(-19000,-2600,45):
		for side in [-1,1]:
			for i in range(3):
				var at_z: float = z+_rng.randf_range(-24,24)
				var x: float = _river_center(at_z)+side*(_river_width(at_z)+_rng.randf_range(15,85))
				var h: float = ground_height(x,at_z)
				if h < -14 or h>12: continue
				var size: float = _rng.randf_range(2.5,8.0)
				var basis := Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(size,size*_rng.randf_range(.4,.8),size*_rng.randf_range(.7,1.5)))
				transforms.append(Transform3D(basis,Vector3(x,h+size*.1,at_z)))
	var stones := MultiMeshInstance3D.new(); stones.name = "GraniteShoreline"
	var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.mesh = mesh; multi.instance_count = transforms.size()
	for i in range(transforms.size()): multi.set_instance_transform(i,transforms[i])
	stones.multimesh = multi; add_child(stones)
