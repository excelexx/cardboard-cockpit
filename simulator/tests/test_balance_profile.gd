extends SceneTree
var app: Node3D
var failures: Array[String] = []
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures.append(label); push_error("BALANCE FAIL: "+label)
func target_at(distance: float):
	app.start_flight("combat"); app.flight.position.y = 500; app.apply_aircraft_pose()
	app.combat.spawn_clock = 999; app.combat.spawn_contact()
	var target: Dictionary = app.combat.enemies[0]
	target.position = app.flight.position+Vector3.FORWARD*distance
	target.course = Vector3(0,0,-1); target.right = Vector3.ZERO; target.fade = 1; target.age = 2
	return target
func run():
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	var target: Dictionary = target_at(400)
	check(target.health==100,"Reference-normalized target health is 100")
	var gun_ttk := 0.0
	for i in range(240):
		app.combat.tick(1.0/120); app.combat.fire_gun()
		gun_ttk += 1.0/120
		if app.combat.kills>0: break
	check(app.combat.kills==1 and app.combat.rounds_hit==20,"Five four-round Gatling packets clear a fresh target")
	check(gun_ttk>.35 and gun_ttk<.8,"At 400 metres gun travel plus tracking yields a short readable burst")
	target = target_at(600)
	for i in range(18): app.combat.tick(1.0/120)
	app.combat.fire_missile()
	var missile_ttk := 0.0
	for i in range(480):
		app.combat.tick(1.0/120); missile_ttk += 1.0/120
		if app.combat.kills>0: break
	check(app.combat.kills==1 and app.combat.missiles_fired==1,"One heavy guided missile clears a fresh target")
	check(missile_ttk>.7 and missile_ttk<2.5,"Missile launch, ignition, guidance and hit remain visible and responsive")
	app.start_flight("combat"); app.combat.spawn_clock = 999
	app.combat.spawn_shot(Vector3(0,500,-3500),Vector3(0,0,-185),"missile",-1,100)
	var shot: Dictionary = app.combat.shots[0]
	for i in range(84): app.combat.update_shots(1.0/120)
	check(absf(shot.velocity.length()-600)<1,"Missile reaches cruise speed half a second after ignition")
	var speeds: Array[float] = []
	for hz in [60,120]:
		app.start_flight("combat"); app.flight.position.y = 800; app.flight.power_input = 1; app.flight.throttle = 1
		for i in range(hz*2): app.flight.step(1.0/hz,Vector3.ZERO,false,0,false)
		speeds.append(app.flight.speed)
	check(absf(speeds[0]-speeds[1])<1,"Speed response is consistent at 60 and 120 Hz")
	print("BALANCE PROFILE: ",checks," checks / ",failures.size()," failures / gun TTK 400m=",gun_ttk," / missile TTK 600m=",missile_ttk," / speed at 2s=",speeds)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
