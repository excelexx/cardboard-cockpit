extends SceneTree
# HUD-free engine frames for UI design work, written to build/backdrops/. Native GPU only.
var app: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native GPU required");quit(2);return
	var folder:=ProjectSettings.globalize_path("res://../build/backdrops")
	DirAccess.make_dir_recursive_absolute(folder)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for i in 30:await process_frame
	app.audio.muted=true;app.set_quality(true)
	app.capture_file="review"   # a capture window is never focused; this keeps the game from auto-pausing
	var views:={
		"fight":{"at":Vector3(12000,300,-19300),"heading":1.45,"geese":[Vector3(0,22,260),Vector3(-46,8,330),Vector3(52,2,350),Vector3(-98,-6,410)]},
		"cruise":{"at":Vector3(2300,280,-13400),"heading":0.9,"geese":[]},
		"marin":{"at":Vector3(16600,520,-21500),"heading":0.25,"geese":[]},
		"pit":{"at":Vector3(12000,300,-19300),"heading":1.45,"geese":[],"cockpit":true},
		"pitfight":{"at":Vector3(2300,300,-13400),"heading":0.9,"geese":[Vector3(10,40,300),Vector3(-50,26,380),Vector3(64,20,400)],"cockpit":true},
		"final":{"approach":true},
		"beauty":{"at":Vector3(12000,300,-19300),"heading":1.45,"geese":[],"beauty":true},
	}
	for view: String in views:
		var spec: Dictionary=views[view];print("BEGIN ",view)
		app.set_process(false);app.set_physics_process(false)
		if spec.get("approach",false):
			app.start_flight("approach")
		else:
			print("  starting");app.start_flight("combat");print("  started");app.flight.spawn_airborne(spec.at,330);app.flight.gear=false;app.flight.throttle=.65
			app.flight.heading=spec.heading
		app.copilot=false;app.cockpit=spec.get("cockpit",false);app.hud.visible=false
		app.apply_aircraft_pose();app.combat.spawn_clock=999
		var right: Vector3=app.flight.forward().cross(Vector3.UP)
		for offset: Vector3 in spec.get("geese",[]):
			app.combat.spawn_contact("normal")
			var enemy: Dictionary=app.combat.enemies.back()
			enemy.position=app.flight.position+app.flight.forward()*offset.z+right*offset.x+Vector3.UP*offset.y
			enemy.node.position=enemy.position;enemy.fade=1;enemy.age=5;enemy.health=100000;enemy.max_health=100000
			enemy.right=Vector3.ZERO;enemy.course=app.flight.forward()*300
		app.camera_rig.reset();print("  ready ",view)
		var began:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-began<(7000 if view=="fight" else 3500):
			var dt: float=minf(app.get_process_delta_time(),.05)
			app.combat.tick(dt);app.flight.step(dt,Vector3.ZERO,false,0,false);app.apply_aircraft_pose();app._process(dt)
			await process_frame
		if spec.get("beauty",false):
			var offset: Vector3=app.flight.forward()*13.0+right*-7.5+Vector3.UP*-1.6
			app.camera.global_position=app.flight.position+offset;app.camera.look_at(app.flight.position,Vector3.UP);app.camera.fov=38
			for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+view+".png")
		print("BACKDROP ",view)
	for chunk in app.world.chunks:
		if chunk.requested and not is_instance_valid(chunk.node):ResourceLoader.load_threaded_get(chunk.path)
	app.queue_free();await process_frame;await process_frame;quit(0)
