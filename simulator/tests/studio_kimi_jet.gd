extends SceneTree
## Standalone look harness for the KimiAirframe proposal. Same sky, sun and
## grading as the San Francisco world, no terrain load - just the jet over a
## dark-water plane, shot from the six judgement angles.
##
##   Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_kimi_jet.gd
##   ... -- gear        # gear-down variant
##
## PNGs land in build/kimi_jet/.
const Airframe = preload("res://systems/kimi_airframe.gd")

const SKY_YAW_DEGREES := -79.8

# name: [camera position, look target, fov]
const VIEWS := {
	"chase": [Vector3(0, 4.0, 12.5), Vector3(0, 0.2, -8.0), 52.0],
	"rear34": [Vector3(9.5, 4.8, 12.5), Vector3(0, -0.3, 0.5), 44.0],
	"front34low": [Vector3(-8.5, -3.6, -13.5), Vector3(0, 0.5, -1.0), 42.0],
	"side": [Vector3(20.5, 0.4, 0.0), Vector3(0, -0.3, 0.0), 32.0],
	"top": [Vector3(0.0, 25.0, 0.3), Vector3(0, 0, 0.15), 33.0],
	"headon": [Vector3(0, 0.5, -19.5), Vector3(0, -0.2, 0.0), 30.0],
}
const ORDER := ["chase", "rear34", "front34low", "side", "top", "headon"]

var camera: Camera3D
var model: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("studio_kimi_jet needs a GPU; run windowed")
		quit(2)
		return
	var folder := ProjectSettings.globalize_path("res://../build/kimi_jet")
	DirAccess.make_dir_recursive_absolute(folder)
	_stage()
	model = Airframe.create()
	root.add_child(model)
	var gear_down := "gear" in OS.get_cmdline_user_args()
	var gear := model.get_node_or_null("gear")
	if gear != null:
		gear.visible = gear_down
	var triangles := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			triangles += node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3
	print("KIMI JET triangles=", triangles)
	for i in 20:
		await process_frame
	for view: String in ORDER:
		var spec: Array = VIEWS[view]
		camera.fov = float(spec[2])
		camera.global_position = spec[0]
		camera.look_at(Vector3(spec[1]), Vector3(0, 0, -1) if view == "top" else Vector3.UP)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var label: String = view + ("_gear" if gear_down else "")
		root.get_texture().get_image().save_png(folder + "/" + label + ".png")
		print("KIMI SHOT ", label)
	quit(0)

func _stage() -> void:
	# Sky, sun and grading copied from scenes/san_francisco_world.gd so studio
	# shots predict the real game light.
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://assets/look/sunset_sky.gdshader")
	sky_material.set_shader_parameter("panorama", load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(SKY_YAW_DEGREES), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.glow_enabled = true
	env.glow_intensity = 0.40
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.30
	var holder := WorldEnvironment.new()
	holder.environment = env
	root.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, -110, 0)
	sun.light_color = Color(1.0, 0.66, 0.38)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	root.add_child(sun)
	# The game's effects layer rides the airframe with a culled fill light;
	# mirror it so studio shots match what the chase camera actually sees.
	var fill := OmniLight3D.new()
	fill.light_cull_mask = 2
	fill.light_color = Color(1.0, 0.93, 0.84)
	fill.light_energy = 1.8
	fill.omni_range = 26
	fill.omni_attenuation = 0.6
	fill.shadow_enabled = false
	fill.position = Vector3(0, 7, 6)
	root.add_child(fill)
	# Dark water 300 m below: the worst-case backdrop the owner complained about.
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000, 9000)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position = Vector3(0, -300, 0)
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.019, 0.030, 0.044)
	water_material.metallic = 0.85
	water_material.roughness = 0.10
	water.material_override = water_material
	root.add_child(water)
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 12000
	camera.current = true
	root.add_child(camera)
