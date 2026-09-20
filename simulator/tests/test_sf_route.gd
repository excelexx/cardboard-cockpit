extends SceneTree
const ScenicRoute = preload("res://systems/san_francisco_route.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","sf"); root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted = true
	app.on_action("guided")
	var visual: bool = "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	# Offscreen captures must not auto-pause when Finder or the editor has focus.
	if visual: app.capture_file = "scenic-review"
	var previous_index := -1
	var peak := 0.0
	var floor_corrections := 0
	var coast_frames:=0
	var seen_waves: Dictionary={}
	var plasma_seen:=false
	var first_wave_down:=-1
	for frame in range(60*211):
		var previous: Vector3 = app.flight.position
		app._physics_process(1.0/60.0)
		peak = maxf(peak,app.flight.position.y)
		if app.mission.wave_number>0:seen_waves[app.mission.wave_number]=app.mission.wave_size
		plasma_seen=plasma_seen or app.combat.beam_active
		if app.mission.phase=="wave_break":first_wave_down=app.mission.wave_down()
		var at: Vector3=app.flight.position
		# Scenic showcase: Pacific cliffs, Ocean Beach, Lands End, Golden Gate, Marin Headlands.
		if at.x> -5500 and at.x<19000 and at.z< -9000 and at.z> -27000:
			coast_frames+=1
		if app.landing_transition<=0 and app.flight.position.distance_to(previous)>app.flight.velocity.length()/60.0+1.0:
			floor_corrections += 1
		if app.mission.route_index!=previous_index:
			previous_index = app.mission.route_index
			print("ROUTE ",previous_index," t=",app.flight.elapsed," pos=",app.flight.position)
			if visual:
				app.camera_rig.reset(); app.camera_rig.update(.2)
				app._process(1.0/60.0)
				await process_frame
				await RenderingServer.frame_post_draw
				var destination: String = ProjectSettings.globalize_path("res://../docs/screenshots/scenic")
				DirAccess.make_dir_recursive_absolute(destination)
				root.get_texture().get_image().save_png(destination+"/route-%02d.png" % previous_index)
		if app.mode=="results": break
		if frame%600==0: await process_frame
	if not app.mission_success or app.skein_down()<ceili(app.skein_total()*.75) or app.flight.contact!="landed" or app.flight.speed>.1: failures.append("Demo failed the current branch's flock-and-safe-landing outcome")
	if first_wave_down!=12 or app.skein_down()!=32 or not app.mission.skein_success:failures.append("Guided flight did not clear both complete waves: first=%d/12 total=%d/32" % [first_wave_down,app.skein_down()])
	if app.mission.clock>210: failures.append("Demo exceeded 210 second two-wave limit")
	if seen_waves.get(1)!=12 or seen_waves.get(2)!=20 or app.skein_total()!=32:failures.append("SF did not present the twelve and twenty bird waves with aggregate objective32")
	if app.mission.visited_route.size()<2: failures.append("Demo did not reach the coast waypoints")
	if peak<350: failures.append("Did not reach the Bay Area touring altitude")
	if floor_corrections>0: failures.append("Route relied on terrain safety correction: "+str(floor_corrections))
	if app.profile().name!="SPECTRE X-26": failures.append("Current fighter was replaced")
	if app.combat.hostile_launches!=0 or app.combat.ammo!=-1: failures.append("Current arcade rules were replaced")
	if coast_frames<1800: failures.append("Route did not spend at least thirty simulated seconds along the Pacific coast and Golden Gate")
	if app.combat.kills<1 or app.combat.rounds_fired<1 or not plasma_seen: failures.append("Demo did not demonstrate minigun, plasma and an actual hit")
	print("SF COMBAT: wave1=",first_wave_down,"/12 objective=",app.skein_down(),"/32 kills=",app.combat.kills," rounds=",app.combat.rounds_fired," missiles=",app.combat.missiles_fired)
	print("COAST SECONDS: ",coast_frames/60.0)
	print("SF ROUTE RESULT: ","PASS" if failures.is_empty() else "FAIL"," seconds=",app.flight.elapsed," peak=",peak," landmarks=",app.mission.visited_route.size()," corrections=",floor_corrections)
	for failure in failures: printerr(failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
