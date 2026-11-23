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
	check(target.health==20,"An ordinary goose starts with 20 HP, not a boss health bar")
	var gun_ttk := 0.0
	for i in range(600):
		app.combat.tick(1.0/120); app.combat.fire_gun()
		gun_ttk += 1.0/120
		if app.combat.kills>0: break
	# One 2-round packet carries 24 damage against 20 HP, and the plasma cannon
	# burns the same goose while the gun runs: either way one good burst downs it
	# well inside half a second. (The owner restored the beam as a weapon; it can
	# only make this faster.)
	check(app.combat.kills==1 and gun_ttk<=0.5,"One good burst downs a goose")
	check(gun_ttk>.05 and gun_ttk<.9,"At 400 metres the goose is down inside a second of held trigger")
	target = target_at(600)
	for i in range(18): app.combat.tick(1.0/120)
	app.combat.fire_missile()
	var missile_ttk := 0.0
	for i in range(480):
		app.combat.tick(1.0/120); app.combat.fire_missile(); missile_ttk += 1.0/120
		if app.combat.kills>0: break
	check(app.combat.kills==1 and app.combat.missiles_fired>=1 and app.combat.missiles_fired<=16,"A salvo clears a fresh goose")
	# Re-measured under proportional navigation and the G limit, which fly a
	# longer curved intercept than the old per-frame lead snap did.
	check(missile_ttk>1 and missile_ttk<4,"Missile launch, ignition, guidance and hit remain visible and responsive")
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
