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
	# The big skein has to fly like birds, not on rails: each bird's velocity
	# must keep moving relative to its own leader heading (cross_swing), and the
	# four birds of one chevron must share that heading so the V stays a V
	# (chevron_fan). Both were broken when the act pinned enemy.age, which froze
	# the director's weave into a constant per-bird cross-drift.
	var cross_swing: Dictionary={}
	var chevron_fan:=0.0
	var flock_frames:=0
	var held_frames:=0
	for frame in range(90000):
		var previous: Vector3 = app.flight.position
		app._physics_process(1.0/60.0)
		peak = maxf(peak,app.flight.position.y)
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
		if app.mission.phase=="skein":
			flock_frames+=1
			var lead_dirs: Array[Vector3]=[]
			for enemy: Dictionary in app.combat.enemies:
				var id: int=int(enemy.id)
				# Skip birds the director has pushed aside this frame: the
				# scatter it applies to a retiring contact is not flock motion.
				if enemy.health<=0 or bool(enemy.retiring) or not app.mission.skein_ids.has(id): continue
				var base: Vector3=Vector3(app.mission.flock_heading.get(id,Vector3.ZERO)); base.y=0
				if base.length()<1.0: continue
				var flat: Vector3=Vector3(enemy.velocity.x,0,enemy.velocity.z)
				if int(app.mission.flock_chevron.get(id,0))==0 and flat.length()>1.0: lead_dirs.append(flat.normalized())
				# Only once the act has pinned the bird's age: that is the regime
				# where the director's own age-driven weave stops moving, so it
				# is the regime the mission-side wander has to cover.
				if float(enemy.age)<app.mission.FLOCK_FROZEN_AGE-0.1: continue
				held_frames+=1
				var wing: Vector3=Vector3(base.z,0,-base.x).normalized()
				var cross: float=(Vector3(enemy.velocity)-base).dot(wing)
				var seen: Vector2=cross_swing.get(id,Vector2(cross,cross))
				cross_swing[id]=Vector2(minf(seen.x,cross),maxf(seen.y,cross))
			for a: Vector3 in lead_dirs:
				for b: Vector3 in lead_dirs: chevron_fan=maxf(chevron_fan,rad_to_deg(a.angle_to(b)))
		if app.mode=="results": break
		if frame%600==0: await process_frame
	if not app.mission_success: failures.append("Demo failed to reach a winning outcome")
	if not app.mission.skein_success or app.mission.skein_down<app.mission.skein_total(): failures.append("Demo failed to clear the big flock: "+str(app.mission.skein_down)+"/"+str(app.mission.skein_total()))
	if app.mission.skein_total()<12: failures.append("The last wave is not a flock of twelve: "+str(app.mission.skein_total()))
	if app.mission.clock>150: failures.append("Demo exceeded 150 second limit")
	if app.mission.visited_route.size()<2: failures.append("Demo did not reach the coast waypoints")
	if peak<350: failures.append("Did not reach the Bay Area touring altitude")
	if floor_corrections>0: failures.append("Route relied on terrain safety correction: "+str(floor_corrections))
	if app.profile().name!="SPECTRE X-26": failures.append("Current fighter was replaced")
	# Infinite gun and missile stores are a playability rule, not an oversight.
	if app.combat.hostile_launches!=0 or app.combat.ammo!=-1 or app.combat.missiles!=-1: failures.append("Current arcade rules were replaced")
	if coast_frames<1800: failures.append("Route did not spend at least thirty simulated seconds along the Pacific coast and Golden Gate")
	if app.combat.kills<1 or app.combat.rounds_fired<1 or app.combat.missiles_fired<1: failures.append("Demo did not demonstrate both weapons and an actual hit")
	var live:=0.0
	for id: int in cross_swing:
		var seen: Vector2=cross_swing[id]
		live=maxf(live,seen.y-seen.x)
	print("FLOCK MOTION: frames=",flock_frames," held samples=",held_frames," birds=",cross_swing.size()," cross swing=",snappedf(live,.01)," m/s  chevron fan=",snappedf(chevron_fan,.01)," deg")
	if flock_frames<300 or held_frames<600: failures.append("The flock act was too short to judge: "+str(flock_frames)+" frames / "+str(held_frames)+" held samples")
	if live<4.0: failures.append("The big skein flies on rails - cross-track swing only "+str(snappedf(live,.01))+" m/s")
	if chevron_fan>12.0: failures.append("The lead chevron is fanned open instead of flying one V: "+str(snappedf(chevron_fan,.01))+" deg")
	print("SF COMBAT: kills=",app.combat.kills," rounds=",app.combat.rounds_fired," missiles=",app.combat.missiles_fired)
	print("COAST SECONDS: ",coast_frames/60.0)
	print("SF ROUTE RESULT: ","PASS" if failures.is_empty() else "FAIL"," seconds=",app.flight.elapsed," peak=",peak," landmarks=",app.mission.visited_route.size()," corrections=",floor_corrections)
	for failure in failures: printerr(failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
