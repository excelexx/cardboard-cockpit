extends SceneTree
## Offline bake only. The 478 MB source never loads in the game.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(512,1024)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var document:=GLTFDocument.new()
	var state:=GLTFState.new()
	assert(document.append_from_file(ProjectSettings.globalize_path("res://../.downloads/nature/fir_tree_01/fir_tree_01.gltf"),state)==OK)
	var tree: Node3D=document.generate_scene(state)
	viewport.add_child(tree)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(0.72,0.82,1)
	environment.environment.ambient_light_energy=0.5
	viewport.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,-45,0)
	light.light_energy=1.3
	viewport.add_child(light)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=10.0
	viewport.add_child(camera)
	camera.position=Vector3(0,10,30)
	camera.look_at(Vector3(0,10,0))
	camera.current=true
	var parts: Array[Node]=tree.find_children("*","MeshInstance3D",true,false)
	for index in range(parts.size()):
		for part in parts: part.visible=false
		parts[index].visible=true
		parts[index].position=Vector3.ZERO
		for i in range(12):
			RenderingServer.force_draw()
			await process_frame
		var path: String=ProjectSettings.globalize_path("res://assets/nature/fir_%d.png"%index)
		assert(viewport.get_texture().get_image().save_png(path)==OK)
		print("BAKED ",path)
	quit()
