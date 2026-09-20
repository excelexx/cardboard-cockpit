extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label); push_error("DEMO FAIL: "+label)
func run():
	var app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.on_action("guided")
	check(app.mission.active and app.mission.phase=="takeoff" and not app.flight.airborne and app.flight.speed==0,"Full demo starts stationary on the departure runway")
	var jump := 0.0
	var max_speed := 0.0
	var rotations := 0
	var had_wheels := true
	var plasma_seen:=false
	for i in range(18000):
		if app.mode=="results": break
		var before: Vector3 = app.flight.position
		app._physics_process(1.0/60)
		plasma_seen=plasma_seen or app.combat.beam_active
		app.aircraft_visuals.update_visuals(1.0/60,app.flight,app.control)
		jump = maxf(jump,app.flight.position.distance_to(before))
		max_speed = maxf(max_speed,app.flight.speed)
		if had_wheels and app.flight.airborne: rotations += 1
		had_wheels = not app.flight.airborne
		if i%60==0: await process_frame
	check(app.mission_success and app.mode=="results","Complete demo reaches a successful debrief")
	var phases: Array[String] = []
	for entry: Dictionary in app.mission.history: phases.append(entry.phase)
	check(phases==["takeoff","combat","return","approach","rollout","secured"],"Departure, engagement, recovery, approach and rollout happen in order")
	check(rotations==1,"Aircraft takes off once; no airborne respawn")
	check(jump<max_speed/60+1,"No position discontinuity through mission transitions")
	check(app.flight.contact=="landed" and app.flight.speed==0 and app.is_on_runway(app.flight.position),"Flight finishes stopped on the destination runway")
	check(app.mission.clock>100 and app.mission.clock<180,"Complete guided demo fits inside three minutes")
	check(app.combat.kills>=3 and app.combat.primary_used and app.combat.rounds_fired==0 and plasma_seen,"Combat uses adaptive dual plasma against multiple contacts")
	check(app.aircraft_visuals.gear_progress>.99,"Visible landing gear finishes fully deployed")
	check(app.combat.hull==100 and app.combat.hostile_launches==0,"Relaxed demo has no enemy attacks or incoming damage")
	check(app.combat.best_combo>=3 and app.combat.score>app.combat.kills*100,"Rapid clears earn visible streak rewards")
	print("FULL DEMO: ",checks," checks / ",failures.size()," failures / ",snappedf(app.mission.clock,.01)," seconds / ",app.combat.kills," intercepts / enemy missiles ",app.combat.hostile_launches," / flares used ",app.combat.flares_fired," / max frame displacement ",jump)
	app.on_action("keyboard_play")
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
		Input.parse_input_event(event); Input.flush_buffered_events()
	for i in range(1050):
		app._physics_process(1.0/60)
		if i%90==0: await process_frame
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = false
		Input.parse_input_event(event); Input.flush_buffered_events()
	check(app.flight.airborne and app.mission.phase=="combat","Holding fire through departure does not apply takeoff brakes")
	check(app.combat.primary_used and app.combat.rounds_fired==0 and app.combat.missiles_fired==0,"Play mode fires the held primary without automatic secondary launches")
	print("PLAY INPUT: 2 additional checks / total ",checks," / failures ",failures.size())
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
