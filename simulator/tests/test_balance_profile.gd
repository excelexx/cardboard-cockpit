extends SceneTree
const Balance=preload("res://data/balance.gd")
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
	check(target.health==100 and Balance.BEAM_DPS==100,"Normal contact durability and per-beam damage are explicit")
	var plasma_ttk:=0.0
	for i in range(600):
		app.combat.fire_primary();app.combat.update_beam(1.0/120)
		plasma_ttk+=1.0/120
		if app.combat.kills>0:break
	check(app.combat.kills==1 and app.combat.rounds_fired==0,"Focused plasma clears the target without cannon rounds")
	check(absf(plasma_ttk-.5)<.02,"Two focused100DPS emitters clear100 health in half a second")
	target=target_at(600)
	app.combat.spawn_contact();var second: Dictionary=app.combat.enemies.back()
	second.position=app.flight.position+Vector3(30,0,-600);second.fade=1;second.health=100
	app.combat.fire_primary();app.combat.update_beam(.1)
	check(is_equal_approx(target.health,90) and is_equal_approx(second.health,90),"Split beams deal one emitter's damage to each separate target")
	app.combat.gun_firing_time=0;app.combat.update_beam(.2)
	check(is_equal_approx(target.health,90) and is_equal_approx(second.health,90),"Released plasma stops target damage")
	var speeds: Array[float] = []
	for hz in [60,120]:
		app.start_flight("combat"); app.flight.position.y = 800; app.flight.power_input = 1; app.flight.throttle = 1
		for i in range(hz*2): app.flight.step(1.0/hz,Vector3.ZERO,false,0,false)
		speeds.append(app.flight.speed)
	check(absf(speeds[0]-speeds[1])<1,"Speed response is consistent at 60 and 120 Hz")
	print("BALANCE PROFILE: ",checks," checks / ",failures.size()," failures / plasma TTK400m=",plasma_ttk," / speed at 2s=",speeds)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
