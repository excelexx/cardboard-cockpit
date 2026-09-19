extends SceneTree
## Run: Godot --headless --path simulator --script res://tests/test_weather.gd
## Weather must change visibility without changing terrain or adding scene geometry.
const World = preload("res://scenes/world.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func geometry_count(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D else 0
	for child in node.get_children():
		count += geometry_count(child)
	return count

func run() -> void:
	var world = World.new()
	world.set_conditions("clear")
	expect(world.get_condition_name() == "Clear midday", "Preset can be selected before build")
	root.add_child(world)
	var environment: Environment = world.get_node("MountainAtmosphere").environment
	var sun: DirectionalLight3D = world.get_node("ValleySun")
	expect(environment.sky.sky_material is ShaderMaterial, "Preselected clear sky is applied during build")
	var initial_geometry: int = geometry_count(world)
	var probes: Array[Vector2] = [Vector2(0, 0), Vector2(0, -15000), Vector2(5300, -4500), Vector2(-9800, 8500), Vector2(1700, -10200)]
	var elevations: Array[float] = []
	for probe in probes:
		elevations.append(world.ground_height(probe.x, probe.y))
	var fog: Dictionary = {}
	var exposure: Dictionary = {}
	var sun_angles: Dictionary = {}
	for preset in ["golden", "clear", "overcast", "golden"]:
		world.set_conditions(preset)
		expect(world.get_conditions().id == preset, preset + " identity")
		expect(geometry_count(world) == initial_geometry, preset + " adds no cloud geometry")
		for index in range(probes.size()):
			expect(world.ground_height(probes[index].x, probes[index].y) == elevations[index], preset + " preserves terrain")
		var detached: Dictionary = world.get_conditions()
		detached["name"] = "mutation"
		expect(world.get_condition_name() != "mutation", "Metadata cannot mutate canonical presets")
		fog[preset] = environment.fog_density
		exposure[preset] = environment.tonemap_exposure
		sun_angles[preset] = sun.rotation
		if preset == "overcast":
			expect(not sun.shadow_enabled, "Overcast removes hard directional shadows")
	expect(fog.clear < fog.golden and fog.golden < fog.overcast, "Visibility changes from clear to golden to overcast")
	expect(exposure.clear != exposure.golden and exposure.clear != exposure.overcast, "Presets change exposure")
	expect(sun_angles.clear != sun_angles.golden and sun_angles.clear != sun_angles.overcast, "Time presets change sun direction")
	expect(sun.shadow_enabled, "Returning to golden hour restores directional shadows")
	expect(environment.sky.sky_material is PanoramaSkyMaterial, "Returning to golden hour restores the photographic sky")
	world.set_conditions("invalid")
	expect(world.get_conditions().id == "golden", "Unknown preset falls back to golden hour")
	test_terrain_mesh(world)
	test_building_contacts(world)
	for failure in failures:
		printerr("FAIL: ", failure)
	print("Weather and scenery: ", checks - failures.size(), "/", checks, " checks passed.")
	quit(1 if not failures.is_empty() else 0)

func test_terrain_mesh(world) -> void:
	expect(world.ground_height(0, 0) == 0.0 and world.ground_height(0, -15000) == 0.0, "Both runway decks remain at zero")
	var terrain: MeshInstance3D = world.get_node("AlpineTerrain")
	var arrays: Array = terrain.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles: int = indices.size() / 3
	# Independent rendered-triangle samples cover the valley and steep mountains.
	for sample_index in range(32):
		var triangle: int = (sample_index * 5939 + 317) % triangles
		var center: Vector3 = (points[indices[triangle * 3]] + points[indices[triangle * 3 + 1]] + points[indices[triangle * 3 + 2]]) / 3.0
		if absf(center.x) <= 50.0 and minf(absf(center.z), absf(center.z + 15000.0)) <= 1600.0:
			continue # The separately rendered runway deck intentionally covers this terrain.
		expect(absf(world.ground_height(center.x, center.z) - center.y) < 0.01, "Terrain contact matches rendered triangle " + str(triangle))

func test_building_contacts(world) -> void:
	for offset in [0.0, -15000.0]:
		expect(world.obstacle_collision(Vector3(470, 15, -330 + offset)), "Hangar is solid")
		expect(world.obstacle_collision(Vector3(470, 37, -330 + offset)), "Hangar roof is solid within aircraft radius")
		expect(world.obstacle_collision(Vector3(685, 8, 540 + offset)), "Terminal is solid")
		expect(world.obstacle_collision(Vector3(730, 61, 175 + offset)), "Tower cab is solid")
		expect(world.obstacle_collision(Vector3(606, 7, 355 + offset)), "Jet bridge is solid")
		expect(not world.obstacle_collision(Vector3(0, 3, offset)), "Runway is unobstructed")
		expect(not world.obstacle_collision(Vector3(245, 3, offset)), "Taxiway is unobstructed")
		expect(not world.obstacle_collision(Vector3(470, 80, -330 + offset)), "Air above hangar is clear")
		expect(not world.obstacle_collision(Vector3(470, 15, -262 + offset), 2.0), "Outside building radius is clear")
		expect(world.obstacle_collision(Vector3(470, 15, -263.5 + offset), 2.0), "Radius contacts building edge")
