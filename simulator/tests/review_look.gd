extends SceneTree
# Renders the hero views to build/look/ for design review. Native GPU only.
# Usage: Godot --path simulator --windowed --resolution 1600x1000 --script tests/review_look.gd [-- view ...]
var app: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native GPU required");quit(2);return
	var wanted:=OS.get_cmdline_user_args()
	var folder:=ProjectSettings.globalize_path("res://../build/look")
	DirAccess.make_dir_recursive_absolute(folder)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for i in 30:await process_frame  # let the app finish booting before driving it
	app.audio.muted=true;app.set_quality(true)
	if wanted.is_empty() or "title" in wanted:
		for i in 40:await process_frame
		await shot(folder,"title")
	for view in ["chase","cockpit","boss","bay","cliffs","beach","gate","marin"]:
		if not wanted.is_empty() and view not in wanted:continue
		app.set_process(false);app.set_physics_process(false)
		app.start_flight("combat");app.copilot=false;app.cockpit=view=="cockpit";app.text_hud=true
		var scenic:={"cliffs":[Vector3(-4200,360,-8300),0.7],"beach":[Vector3(2300,280,-13400),0.9],"gate":[Vector3(12000,300,-19300),1.45],"marin":[Vector3(16600,520,-21500),0.25]}
		var start:=Vector3(15400,430,-10500) if view!="bay" else Vector3(9000,260,-6000)
		if scenic.has(view):start=scenic[view][0]
		app.flight.spawn_airborne(start,330);app.flight.gear=false;app.flight.throttle=.65
		app.flight.heading=scenic[view][1] if scenic.has(view) else -.35 if view!="bay" else 1.2;app.apply_aircraft_pose();app.combat.spawn_clock=999
		if view!="bay" and not scenic.has(view):
			app.combat.spawn_contact("boss" if view=="boss" else "normal")
			var enemy: Dictionary=app.combat.enemies[0]
			enemy.position=app.flight.position+app.flight.forward()*(420 if view=="boss" else 260)+Vector3.UP*30
			enemy.node.position=enemy.position;enemy.fade=1;enemy.age=5;enemy.health=100000;enemy.max_health=100000
			enemy.right=Vector3.ZERO;enemy.course=app.flight.forward()*300
			app.combat.target_id=enemy.id;app.combat.lock_progress=1;app.combat.intent.confidence=1
		app.camera_rig.reset()
		var began:=Time.get_ticks_msec();var frames:=0;var worst:=0
		while Time.get_ticks_msec()-began<9000:
			var frame_began:=Time.get_ticks_msec()
			var dt: float=minf(app.get_process_delta_time(),.05)
			app.combat.tick(dt);app.flight.step(dt,Vector3.ZERO,false,0,false);app.apply_aircraft_pose()
			app._process(dt)
			await process_frame
			# Steady-state numbers only: the first seconds include streaming and pipeline compiles.
			if Time.get_ticks_msec()-began>6000:frames+=1;worst=maxi(worst,Time.get_ticks_msec()-frame_began)
		var mounted:={};var pending:=0;var statuses:={}
		for chunk in app.world.chunks:
			if is_instance_valid(chunk.node):mounted[chunk.kind]=int(mounted.get(chunk.kind,0))+1
			elif chunk.requested:pending+=1;statuses[ResourceLoader.load_threaded_get_status(chunk.path)]=int(statuses.get(ResourceLoader.load_threaded_get_status(chunk.path),0))+1
		print("LOOK ",view," fps=",frames/3.0," worst_ms=",worst," mounted=",mounted," pending=",pending," statuses=",statuses," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," size=",root.size)
		await shot(folder,view)
		if "profile" in wanted:
			for kind in ["shadows","ssao","glow","fog","city","road","trees"]:
				for chunk in app.world.chunks:
					if is_instance_valid(chunk.node) and chunk.kind==kind:chunk.node.visible=false
				if kind=="trees":
					for chunk: Dictionary in app.world.tree_chunks:
						if chunk.has("node"):chunk.node.visible=false
				if kind=="shadows":app.world.sun.shadow_enabled=false
				if kind=="ssao":app.world.environment.environment.ssao_enabled=false
				if kind=="glow":app.world.environment.environment.glow_enabled=false
				if kind=="fog":app.world.environment.environment.fog_enabled=false
				var t0:=Time.get_ticks_msec();var n:=0
				while Time.get_ticks_msec()-t0<1500:
					app._process(.016);await process_frame;n+=1
				print("PROFILE after hiding ",kind,": fps=",n/1.5," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000)
	for chunk in app.world.chunks:
		if chunk.requested and not is_instance_valid(chunk.node):ResourceLoader.load_threaded_get(chunk.path)
	app.queue_free();await process_frame;await process_frame;quit(0)
func shot(folder: String,name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
