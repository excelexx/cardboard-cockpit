extends SceneTree
# Clay renders of the sourced cockpit mesh to see what geometry it contains. Native GPU only.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var folder:=ProjectSettings.globalize_path("res://../build/cockpit")
	DirAccess.make_dir_recursive_absolute(folder)
	var world:=Node3D.new();root.add_child(world)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.55,.62,.70)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.75,.8,.9);env.ambient_light_energy=.55
	env.ssao_enabled=true;env.ssao_radius=.25;env.ssao_intensity=3.0;env.tonemap_mode=Environment.TONE_MAPPER_AGX
	var we:=WorldEnvironment.new();we.environment=env;world.add_child(we)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-150,0);sun.light_energy=1.6;sun.shadow_enabled=true;sun.directional_shadow_max_distance=8;world.add_child(sun)
	var model: Node3D=load("res://assets/sourced_flight/cockpit.gltf").instantiate();world.add_child(model)
	var clay:=StandardMaterial3D.new();clay.albedo_color=Color(.55,.56,.58);clay.roughness=.7
	for m in model.find_children("*","MeshInstance3D",true,false):
		for s in m.mesh.get_surface_count():
			if s==0:m.set_surface_override_material(s,clay)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var shots:={"eye":[Vector3(0,.07,.10),Vector3(0,-.35,-1.0),95.0],"eye_down":[Vector3(0,.07,.10),Vector3(0,-1.0,-.9),95.0],"left":[Vector3(0,.07,.10),Vector3(-1.0,-.7,-.5),95.0],"right":[Vector3(0,.07,.10),Vector3(1.0,-.7,-.5),95.0],"outside":[Vector3(1.6,1.3,1.8),Vector3(-1.6,-1.5,-2.2),50.0],"top":[Vector3(0,2.6,0.05),Vector3(0,-1,-.02),50.0],"front":[Vector3(0,.6,-2.4),Vector3(0,-.5,1),50.0]}
	for name: String in shots:
		camera.position=shots[name][0];camera.look_at(camera.position+shots[name][1],Vector3.UP);camera.fov=shots[name][2]
		for i in 6:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/clay_"+name+".png")
	quit(0)
