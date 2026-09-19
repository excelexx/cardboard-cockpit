extends SceneTree
var app: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("SCENE FAIL: "+label)
func tap(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		Input.parse_input_event(event); Input.flush_buffered_events()
func run_tests() -> void:
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	await process_frame
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	check(app.mode=="title","Application starts on the flight deck")
	check(not app.has_method("select_plane") and not app.has_method("apply_campaign_aircraft"),"No plane selection or upgrade system remains")
	tap(KEY_ENTER)
	check(app.mode=="flight" and app.profile().name=="SPECTRE X-26","Enter launches the single fighter")
	check(app.combat.ammo==-1 and app.combat.missiles==-1,"Permanent cannon-and-missile loadout")
	var children: int = app.aircraft.get_child_count()
	app.start_flight("combat")
	check(app.aircraft.get_child_count()==children,"Restart never duplicates the fighter or weapon stores")
	app.vision.enabled = true; app.copilot = true
	tap(KEY_W)
	check(not app.vision.enabled and not app.copilot,"A key tap immediately takes control")
	var position: Vector3 = app.flight.position
	tap(KEY_ESCAPE); app._physics_process(.1)
	check(app.mode=="paused" and app.flight.position==position,"Pause freezes flight")
	tap(KEY_ESCAPE)
	check(app.mode=="flight","Escape resumes the same flight")
	check(app.combat.fire_missile(),"Missiles can fire without holding a steady lock")
	app.combat.reset(true)
	app.combat.spawn_contact()
	var enemy: Dictionary = app.combat.enemies[0]
	enemy.position = app.flight.position+app.flight.forward()*1000
	app.combat.target_id = enemy.id; app.combat.lock_progress = 1
	check(app.combat.fire_missile() and app.combat.launch_queue.size()==1,"Missile begins a controlled bay-launch sequence")
	check(app.aircraft_visuals.bay_doors.size()==4,"Four authored weapon-bay doors are animated")
	app.combat.tick(.25)
	check(is_instance_valid(app.combat.last_missile) and app.combat.missiles==-1 and app.combat.missiles_fired==1,"Missile leaves the bay after its opening interval")
	var hold := InputEventKey.new(); hold.physical_keycode = KEY_X; hold.keycode = KEY_X; hold.pressed = true
	Input.parse_input_event(hold); Input.flush_buffered_events(); app.camera_rig.update(.016)
	check(app.camera_rig.missile_link and app.camera_rig.pip_camera.transform.is_finite(),"Held missile view preserves a valid separate camera")
	hold = InputEventKey.new(); hold.physical_keycode = KEY_X; hold.keycode = KEY_X; hold.pressed = false
	Input.parse_input_event(hold); Input.flush_buffered_events(); app.camera_rig.update(.016)
	tap(KEY_X); app.camera_rig.update(.016)
	check(not app.camera_rig.missile_link,"Toggling X off stops missile viewport rendering")
	var angle := deg_to_rad(4)
	enemy.position = app.flight.position+Vector3(sin(angle),0,-cos(angle))*1000
	app.combat.target_id = enemy.id
	for i in range(24): app.combat.update_aim(1.0/120)
	check(app.combat.assisted_direction().angle_to(app.flight.forward())>deg_to_rad(3),"Narrow assistance corrects a near-centre shot")
	check(app.combat.assisted_direction().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(2),"Assisted shots converge on the visible goose")
	check(app.combat.fire_gun() and app.combat.rounds_fired==4 and app.combat.ammo==-1,"Cannon records shots without depleting ammunition")
	app.combat.spawn_shot(app.flight.position+Vector3(0,0,-600),Vector3(0,0,280),"hostile_missile",-1,24)
	check(app.combat.deploy_flares() and app.combat.flares==-1 and app.combat.flares_fired==1,"Countermeasures record a burst without running out")
	check(app.combat.shots.back().has("decoy"),"Incoming missile is redirected toward a decoy")
	for pose: Vector3 in [Vector3.ZERO,Vector3(.8,1.4,.9),Vector3(-.8,-2.9,-2.8)]:
		app.flight.pitch = pose.x; app.flight.heading = pose.y; app.flight.roll = pose.z
		for cockpit in [false,true]:
			app.cockpit = cockpit; app.camera_rig.reset(); app.camera_rig.update(.016)
			check(app.camera.transform.is_finite(),"Camera remains finite through extreme attitudes")
	app.start_flight("combat")
	app.combat.elapsed = 20
	for i in range(4):
		app.combat.spawn_contact(); app.combat.enemies.back().cooldown = 0
	app.combat.tick(.016)
	var incoming := 0
	for shot: Dictionary in app.combat.shots:
		if shot.kind=="hostile_missile": incoming += 1
	check(incoming==0,"Geese never attack the player")
	app.start_flight("approach"); app.copilot = true
	for i in range(12000):
		if app.mode=="results": break
		app._physics_process(1.0/60.0)
	check(app.mission_success and app.flight.contact=="landed" and app.flight.speed<=.1,"Approach, touchdown and braking complete smoothly")
	print("SPECTRE SCENE: ",checks," checks / ",failures.size()," failures")
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
