extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(512,512)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var document:=GLTFDocument.new()
	var state:=GLTFState.new()
	var source: String=ProjectSettings.globalize_path("res://../.downloads/nature/tree_small_02/tree_small_02.gltf")
	assert(document.append_from_file(source,state)==OK)
	var tree: Node3D=document.generate_scene(state)
	viewport.add_child(tree)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(0.8,0.9,1)
	environment.environment.ambient_light_energy=0.6
	viewport.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-45,0)
	light.light_energy=1.0
	viewport.add_child(light)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=6.0
	viewport.add_child(camera)
	camera.position=Vector3(7,2.4,8)
	camera.look_at(Vector3(0,2.2,0.5))
	camera.current=true
	for i in range(8):
		RenderingServer.force_draw()
		await process_frame
	var path: String=ProjectSettings.globalize_path("res://assets/nature/tree_impostor.png")
	var error: int=viewport.get_texture().get_image().save_png(path)
	print("TREE IMPOSTOR ",error," ",path)
	quit(error)
