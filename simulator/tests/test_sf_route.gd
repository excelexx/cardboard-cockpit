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
	var cleared_waves: Dictionary={}
	var requested_landing:=false
	var manual_landing:=false
	for frame in range(60*420):
		if app.mission.phase=="wave_break":
			cleared_waves[app.mission.wave_number]=app.mission.wave_down()
			if app.mission.wave_number>=3 and not requested_landing:
				var land:=InputEventKey.new();land.keycode=KEY_B;land.physical_keycode=KEY_B;land.pressed=true;app._input(land)
				requested_landing=app.landing_started;manual_landing=not app.copilot
				if not app.flight.gear:app.toggle_gear()
		var previous: Vector3 = app.flight.position
		app._physics_process(1.0/60.0)
		peak = maxf(peak,app.flight.position.y)
		if app.mission.wave_number>0:seen_waves[app.mission.wave_number]=app.mission.wave_size
		plasma_seen=plasma_seen or app.combat.beam_active
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
	if not requested_landing or not manual_landing or not app.mission_success or app.flight.contact!="landed" or app.flight.speed>.1:failures.append("Explicit B did not complete a pilot-controlled stopped landing")
	if cleared_waves.get(1)!=6 or cleared_waves.get(2)!=8 or cleared_waves.get(3)!=10 or app.skein_down()!=24:failures.append("Three live waves were not actually cleared: "+str(cleared_waves)+" total="+str(app.skein_down()))
	if seen_waves.get(1)!=6 or seen_waves.get(2)!=8 or seen_waves.get(3)!=10 or app.skein_total()!=24:failures.append("Endless progression did not present 6,8,10 targets")
	var route_names: Array[String]=app.mission.route_names()
	if not route_names.has("OCEAN BEACH") or not route_names.has("GOLDEN GATE") or not route_names.has("MARIN HEADLANDS") or app.mission.route_points().size()!=route_names.size():failures.append("The SF coastal route and landmark waypoints are unavailable")
	for point: Vector3 in app.mission.route_points():
		if not point.is_finite():failures.append("The SF route contains an invalid waypoint")
	if peak<350: failures.append("Did not reach the Bay Area touring altitude")
	if floor_corrections>0: failures.append("Route relied on terrain safety correction: "+str(floor_corrections))
	if app.profile().name!="SPECTRE X-26": failures.append("Current fighter was replaced")
	if app.combat.hostile_launches!=0 or app.combat.ammo!=-1: failures.append("Current arcade rules were replaced")
	var world_assets: Array[String]=[]
	for chunk: Dictionary in app.world.region.chunks:world_assets.append(str(chunk.file))
	for landmark: String in ["landmark_ggb-fb.scn","landmark_transamerica-fb.scn","landmark_KSFO_InternationalTerminal.scn"]:
		if not world_assets.has(landmark) or not ResourceLoader.exists("res://assets/san_francisco/"+landmark):failures.append("Original SF landmark unavailable: "+landmark)
	if app.combat.kills<1 or app.combat.rounds_fired!=0 or app.combat.missiles_fired<4 or not plasma_seen: failures.append("Demo did not demonstrate dual plasma, automatic two-missile support and actual hits")
	print("SF COMBAT: waves=",cleared_waves," objective=",app.skein_down(),"/64 kills=",app.combat.kills," rounds=",app.combat.rounds_fired," missiles=",app.combat.missiles_fired)
	print("COAST SECONDS: ",coast_frames/60.0)
	print("SF ROUTE RESULT: ","PASS" if failures.is_empty() else "FAIL"," seconds=",app.flight.elapsed," peak=",peak," landmarks=",app.mission.visited_route.size()," corrections=",floor_corrections)
	for failure in failures: printerr(failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
