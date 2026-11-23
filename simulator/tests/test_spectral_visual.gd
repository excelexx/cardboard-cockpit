extends SceneTree
var app: Node3D
var samples: Array[Dictionary]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native GPU required");quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.capture_file="native-qa";app.set_quality(true);app.developer_mode=true
	var folder:=ProjectSettings.globalize_path("res://../docs/screenshots/spectral")
	DirAccess.make_dir_recursive_absolute(folder)
	var scenarios: Array=["blue-sky","cloud","dark-ground","city","sun","far-target","close-target","crossing","roll","boost","skein-stress","blue-sky-warm"]
	# `-- feathers` runs only the bird-strike probe: one burst, four frames
	# across its life, so the feather cloud can be judged on its own.
	if OS.get_cmdline_user_args().has("feathers"):scenarios=["feather-probe"]
	for scenario in scenarios:
		app.start_flight("combat");app.copilot=false;app.cockpit=false;app.text_hud=scenario!="city"
		app.flight.spawn_airborne(Vector3(15400,430,-10500),330);app.flight.gear=false;app.flight.throttle=.65
		app.flight.heading=-.35;app.apply_aircraft_pose();app.combat.spawn_clock=999
		# No boss any more: the heavy case is a full skein arriving at once.
		if scenario=="skein-stress":
			if app.combat.has_method("spawn_skein"):app.combat.spawn_skein()
			else:
				for i in range(7):app.combat.spawn_contact("normal")
		else:
			app.combat.spawn_contact("normal")
		if app.combat.enemies.is_empty():app.combat.spawn_contact("normal")
		var enemy: Dictionary=app.combat.enemies[0]
		# Framed for CONTACT_MODEL_SCALE 3.0, not the 8.5 these numbers were
		# written against.
		var distance: float=800 if scenario=="far-target" else 60 if scenario=="close-target" else 110 if scenario=="feather-probe" else 300
		enemy.position=app.flight.position+app.flight.forward()*distance;enemy.node.position=enemy.position
		enemy.fade=1;enemy.age=5;enemy.health=100000;enemy.max_health=100000;enemy.right=Vector3.ZERO
		enemy.course=app.flight.forward()*300+(Vector3.RIGHT*150 if scenario=="crossing" else Vector3.ZERO)
		app.combat.target_id=enemy.id;app.combat.lock_progress=1;app.combat.intent.confidence=1
		var env: Environment=app.world.environment.environment
		env.tonemap_exposure=.35 if scenario=="dark-ground" else .83
		env.volumetric_fog_density=.004 if scenario=="cloud" else .00002
		if scenario=="sun":app.flight.heading=1.5
		if scenario=="blue-sky":app.flight.pitch=.18;enemy.position.y+=120
		if scenario=="dark-ground":app.flight.pitch=-.12
		if scenario=="roll":app.flight.start_barrel_roll(1)
		if scenario=="boost":app.flight.afterburner=true;app.flight.power_input=1
		app.camera_rig.reset()
		var began:=Time.get_ticks_msec();var frames:=0;var max_shots:=0;var saved_roll:=false
		var feather_clock:=0.0;var flare_clock:=0.6
		var probe_marks: Array=[0.10,0.40,0.80,1.60];var probe_index:=0;var probe_fired:=false
		while Time.get_ticks_msec()-began<4500:
			var dt: float=minf(app.get_process_delta_time(),.05)
			app.combat.fire_gun();app.combat.fire_missile();app.combat.tick(dt)
			# The kill effect never fires on its own here (the contacts are
			# given 100k health so they stay framed), so drive the bird-strike
			# path directly: this is the shot the lead judges feather
			# legibility and the no-fireball rule from.
			if scenario=="feather-probe":
				var probe_t: float=(Time.get_ticks_msec()-began)/1000.0
				if not probe_fired and probe_t>0.6:
					probe_fired=true;began=Time.get_ticks_msec()
					app.combat.visuals.event("kill",enemy.position,enemy.size_factor)
					app.combat.deploy_flares()
				elif probe_fired and probe_index<probe_marks.size() and probe_t>float(probe_marks[probe_index]):
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(folder+"/feather-%d.png" % probe_index)
					print("FEATHER PROBE frame ",probe_index," t=",probe_t," flares=",app.combat.visuals.flare_items.size())
					probe_index+=1
			if scenario in ["close-target","far-target","skein-stress"]:
				feather_clock-=dt
				if feather_clock<=0:
					feather_clock=1.1
					app.combat.visuals.event("kill",enemy.position,enemy.size_factor)
			if scenario=="skein-stress":
				flare_clock-=dt
				if flare_clock<=0:flare_clock=2.0;app.combat.deploy_flares()
			app.flight.step(dt,Vector3.ZERO,false,0,false);app.apply_aircraft_pose()
			app._process(dt);frames+=1;max_shots=maxi(max_shots,app.combat.shots.size())
			await process_frame
			if scenario=="roll" and not saved_roll and app.flight.barrel_remaining<.5:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/roll-mid.png");saved_roll=true
		var elapsed_ms:=Time.get_ticks_msec()-began
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		samples.append({"scenario":scenario,"fps":frames*1000.0/elapsed_ms,"shots":max_shots,"nodes":get_node_count(),"sprites":app.combat.visuals.sprites.size(),"lights":app.combat.visuals.lights.size()})
		print("NATIVE QA ",samples.back())
		if max_shots>220 or app.combat.visuals.sprites.size()>96 or app.combat.visuals.lights.size()>8:quit(1);return
	var file:=FileAccess.open(folder+"/metrics.json",FileAccess.WRITE);file.store_string(JSON.stringify(samples,"\t"));file.close()
	# Finish in-flight mesh resource requests before destroying the test app.
	for chunk in app.world.chunks:
		if chunk.requested and not is_instance_valid(chunk.node):ResourceLoader.load_threaded_get(chunk.path)
	app.queue_free();await process_frame;await process_frame;quit(0)
