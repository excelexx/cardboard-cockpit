extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label); push_error("DEMO FAIL: "+label)
func test_route() -> String: return "sf" if "--sf" in OS.get_cmdline_user_args() else "alpine"
func run():
	var app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override",test_route()); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.gameplay_settings.reset(); app.apply_gameplay_settings()
	app.on_action("guided")
	check(app.mission.rings.size()==3 and app.mission.rings[0].visible,"Departure has visible in-world guidance rings")
	check(app.mission.active and app.mission.phase=="takeoff" and not app.flight.airborne and app.flight.speed==0,"Full demo starts stationary on the departure runway")
	var jump := 0.0
	var max_speed := 0.0
	var rotations := 0
	var cruise_altitude := 0.0
	var landing_heading_change := 0.0
	var had_wheels := true
	for i in range(36000):
		if app.mode=="results": break
		var before: Vector3 = app.flight.position
		app._physics_process(1.0/60)
		app.aircraft_visuals.update_visuals(1.0/60,app.flight,app.control)
		jump = maxf(jump,app.flight.position.distance_to(before))
		max_speed = maxf(max_speed,app.flight.speed)
		if app.mission.phase=="combat": cruise_altitude = maxf(cruise_altitude,app.flight.position.y)
		if app.mission.phase in ["return","approach"] and is_instance_valid(app.mission.airfield):
			landing_heading_change = maxf(landing_heading_change,absf(wrapf(app.flight.heading-app.mission.airfield.heading,-PI,PI)))
		if had_wheels and app.flight.airborne: rotations += 1
		had_wheels = not app.flight.airborne
		if i%60==0: await process_frame
	check(app.mission_success and app.mode=="results","Complete demo reaches a successful debrief")
	var phases: Array[String] = []
	for entry: Dictionary in app.mission.history: phases.append(entry.phase)
	check(phases==["takeoff","combat","return","approach","rollout","secured"],"Departure, engagement, recovery, approach and rollout happen in order")
	check(cruise_altitude>850,"Geese are engaged while cruising high above departure")
	check(rotations==1,"Aircraft takes off once; no airborne respawn")
	check(jump<max_speed/60+1,"No position discontinuity through mission transitions")
	check(landing_heading_change<deg_to_rad(30),"Landing route needs only a gentle bend, never a circuit or U-turn")
	check(app.mission.airfield.contains_runway(app.flight.position.x,app.flight.position.z),"Aircraft lands at the new destination ahead, not the departure runway")
	check(app.flight.contact=="landed" and app.flight.speed==0 and app.is_on_runway(app.flight.position),"Flight finishes stopped on the destination runway")
	check(app.mission.clock>270 and app.mission.clock<(360 if test_route()=="sf" else 600),"Guided flight lasts about five minutes, roughly twice the previous demo")
	check(app.combat.kills==16 and app.combat.next_id==16 and app.combat.rounds_fired>0,"Exactly sixteen targets are cleared by real cannon fire, with no replacement wave")
	check(app.aircraft_visuals.gear_progress>.99,"Visible landing gear finishes fully deployed")
	check(app.combat.hull==100 and app.combat.shots.all(func(shot): return shot.kind == "cannon"),"Relaxed demo has no enemy attacks or incoming damage")
	check(app.combat.score>=app.combat.kills*100,"Every route target earns its clear reward")
	print("FULL DEMO: ",checks," checks / ",failures.size()," failures / ",snappedf(app.mission.clock,.01)," seconds / ",app.combat.kills ," intercepts "," / flares used ",app.combat.flares_fired," / max frame displacement ",jump)
	app.start_flight("demo")
	app.flight.spawn_airborne(Vector3(0,180,-1500),115)
	app.mission.transition("combat")
	check(app.combat.enemies.size()==16,"Sixteen targets are distributed along the cruising route")
	check(app.mission.airfield.position.distance_to(app.flight.position)>26900,"Destination is farther away, about twenty-seven kilometres ahead")
	var separation := INF
	for a in range(app.combat.enemies.size()):
		for b in range(a+1,app.combat.enemies.size()):
			separation = minf(separation,app.combat.enemies[a].position.distance_to(app.combat.enemies[b].position))
	var width := 0.0
	for enemy: Dictionary in app.combat.enemies: width = maxf(width,absf(enemy.position.x))
	check(width>400,"Targets vary substantially left and right along the route")
	check(separation>=499,"Geese occupy separate positions at least five hundred metres apart along the route")
	check(absf(app.combat.enemies[0].position.z-app.combat.enemies[15].position.z)>7490,"Targets span seven and a half kilometres, not a single plane or cluster")
	var initial_goose: Vector3 = app.combat.enemies[0].position
	for enemy: Dictionary in app.combat.enemies:
		check(app.flight.forward().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(20),"Every demo target starts inside the forward view")
		enemy.age = 120
	app.flight.position += Vector3(50,0,-100)
	app.combat.spawn_contact(); app.combat.tick(.1)
	check(app.combat.enemies[0].position.distance_to(initial_goose)<3,"Goose movement stays tied to the route instead of following every aircraft movement")
	check(app.combat.next_id==16 and app.combat.enemies.size()==16 and app.combat.enemies.all(func(e): return not e.retiring),"Unshot targets persist and extra spawn calls cannot exceed sixteen")
	app.mission.phase_clock = 300; app.combat.kills = 15; app.mission.tick(.1)
	check(app.mission.phase=="combat","Time and fifteen kills cannot bypass the sixteenth target")
	app.mission.route_index = app.mission.landing_index-1
	app.flight.position = app.mission.route_target(); app.mission.previous_position = app.flight.position
	app.mission.tick(.1)
	check(app.mission.phase=="combat" and app.mission.route_index==0 and app.mission.airfield.position.distance_to(app.flight.position)>26900,"Slow shooting extends the cruise ahead instead of sending the pilot past the airport")
	app.flight.throttle = .8; app.flight.gear = false; app.flight.flaps = 0
	check(not "Reduce throttle" in app.mission.instruction(),"Shooting at cruise altitude does not prompt landing configuration")
	app.combat.kills = 16; app.mission.tick(.1)
	check(app.mission.phase=="combat","Clearing geese early keeps the aircraft cruising until the descent gates")
	app.mission.route_index = app.mission.landing_index; app.mission.tick(.1)
	var ahead: Vector3 = app.mission.airfield.position-app.flight.position; ahead.y = 0
	check(app.flight.forward().angle_to(ahead.normalized())<deg_to_rad(10),"Landing airport remains almost straight ahead")
	check(app.mission.phase=="return" and not app.combat.engagement_enabled and app.mission.rings.size()==15,"Cleared geese and completed cruise gates activate landing preparation")
	app.flight.throttle = .8; app.flight.speed = 120; app.flight.gear = false; app.flight.flaps = 0
	check("Reduce throttle" in app.mission.instruction(),"Landing first prompts reduced thrust")
	app.flight.throttle = .1
	check("landing gear" in app.mission.instruction(),"Then prompts gear down")
	app.flight.gear = true
	check("landing flaps" in app.mission.instruction(),"Then prompts landing flaps")
	app.flight.flaps = 2
	check("gold rings" in app.mission.instruction(),"Configured aircraft gets route guidance")
	var display = load("res://ui/cockpit_instruments.gd").new()
	display.set_navigation("sf",3,app.mission.points)
	check(display.navigation_target()==app.mission.points[3],"Cockpit navigation uses the same forward route as the rings")
	display.free()
	app.copilot = false; app.vision.enabled = true; app.vision.tracking = true
	app.vision.throttle_confidence = 1; app.vision.throttle = 0
	app.flight.throttle = 0; app.flight.speed = 160
	app.flight.gear = false; app.flight.flaps = 0
	app._physics_process(1.0/60)
	check(app.flight.power_input<0 and app.flight.airbrake>0,"Pulling the physical throttle to idle sheds speed for landing")
	check(not app.flight.gear and app.flight.flaps==0,"Manual flight prompts do not override the separate gear/flap controls")
	# Real camera-control descent with skipped rings must reach the physical runway.
	app.mission.phase = "return"; app.mission.route_index = 0
	var field = app.mission.airfield
	app.flight.spawn_airborne(field.to_global(Vector3(0,25,1200)),75)
	app.flight.heading = field.heading; app.flight.pitch = -.05241; app.flight.airborne_time = 20
	app.flight.gear = true; app.flight.flaps = 2; app.flight.engine = .12; app.flight.throttle = .12
	app.vision.throttle = .12; app.vision.yoke = Vector2.ZERO; app.vision.yoke_yaw = 0
	app.control = Vector3.ZERO; app.mission.previous_position = app.flight.position
	check(app.mission.in_landing_corridor(),"Final approach is recognized from position, independently of missed rings")
	app.flight.gear = false
	var manual = preload("res://systems/arcade_controls.gd")
	var command: Vector3 = manual.command(app.flight,Vector3(0,-.3,0),20,false,not app.mission.in_landing_corridor())
	check(command.y<0,"A pending gear prompt cannot create an invisible height floor above the runway")
	var protected: Vector3 = manual.command(app.flight,Vector3(0,-.3,0),20,false,true)
	check(protected.y>0,"Terrain protection remains active away from the landing corridor")
	app.flight.gear = true
	for i in range(5400):
		app._physics_process(1.0/60)
		if i%120==0: await process_frame
		if app.mode=="results": break
	check(app.mission_success and app.flight.contact=="landed" and app.flight.speed==0,"Neutral camera yoke can descend, touch down and stop despite missed approach rings")
	check(not app.copilot and app.is_on_runway(app.flight.position),"Manual camera landing stays under player control on the real destination surface")
	app.vision.enabled = false
	app.start_flight("demo"); app.flight.contact = "landed"; app.finish_sortie(true,"Test early landing")
	check(not app.mission_success and app.mission.phase!="secured","Landing before clearing sixteen cannot win the demo")
	app.on_action("keyboard_play")
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
		Input.parse_input_event(event); Input.flush_buffered_events()
	for i in range(3600):
		app._physics_process(1.0/60)
		if i%90==0: await process_frame
		if app.mission.phase=="combat" and app.combat.rounds_fired>0: break
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = false
		Input.parse_input_event(event); Input.flush_buffered_events()
	check(app.flight.airborne and app.mission.phase=="combat","Holding fire through departure does not apply takeoff brakes")
	check(app.combat.rounds_fired>0,"Play mode fires the held gun while flight assistance continues")
	# Preserve the badge button integration when merging the new mission into main.
	var badge_packet := {"version":1,"connected":true,"phase_supported":true,"session":"demo-badge-test","sequence":1,"mask":0}
	app.badge.accept_input(JSON.stringify(badge_packet).to_utf8_buffer(),Time.get_ticks_msec())
	var initial_gear: bool = app.flight.gear
	badge_packet.sequence = 2; badge_packet.mask = 1
	app.badge.accept_input(JSON.stringify(badge_packet).to_utf8_buffer(),Time.get_ticks_msec())
	app.process_badge_controls(); app.badge.pressed = 0
	app._physics_process(1.0/60)
	check(app.flight.gear!=initial_gear,"Badge gear selection survives the guided flight update")
	badge_packet.sequence = 3; badge_packet.mask = 0
	app.badge.accept_input(JSON.stringify(badge_packet).to_utf8_buffer(),Time.get_ticks_msec())
	var initial_flaps: int = app.flight.flaps
	badge_packet.sequence = 4; badge_packet.mask = 2
	app.badge.accept_input(JSON.stringify(badge_packet).to_utf8_buffer(),Time.get_ticks_msec())
	app.process_badge_controls(); app.badge.pressed = 0
	app._physics_process(1.0/60)
	check(app.flight.flaps==(initial_flaps+1)%3,"Badge flap selection survives the guided flight update")
	print("PLAY INPUT: 2 additional checks / total ",checks," / failures ",failures.size())
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
