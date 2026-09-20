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
	check(target.health==100 and Balance.GUN_ROUNDS_PER_PACKET==4 and Balance.GUN_DAMAGE_PER_ROUND==5 and is_equal_approx(Balance.GUN_INTERVAL,.10),"Four-round cannon packets retain damage with the new slower cadence")
	var gun_ttk := 0.0
	for i in range(600):
		app.combat.tick(1.0/120); app.combat.fire_gun()
		gun_ttk += 1.0/120
		if app.combat.kills>0: break
	check(app.combat.kills==1 and app.combat.rounds_hit>0 and app.combat.beam_active,"Combined minigun and plasma clear the target with recorded cannon hits")
	check(gun_ttk>.1 and gun_ttk<1,"At 400 metres the current branch keeps gun travel visible and the kill responsive")
	target = target_at(600)
	app.combat.hurt_enemy(target,Balance.GUN_ROUNDS_PER_PACKET*Balance.GUN_DAMAGE_PER_ROUND,"cannon",target.position)
	check(target.health==80 and app.combat.kills==0,"One four-round packet damages but does not kill a fresh goose")
	for i in range(4):app.combat.hurt_enemy(target,20,"cannon",target.position)
	check(app.combat.kills==1 and app.combat.missiles_fired==0,"Five cannon packets clear a target without secondary ordnance")
	var speeds: Array[float] = []
	for hz in [60,120]:
		app.start_flight("combat"); app.flight.position.y = 800; app.flight.power_input = 1; app.flight.throttle = 1
		for i in range(hz*2): app.flight.step(1.0/hz,Vector3.ZERO,false,0,false)
		speeds.append(app.flight.speed)
	check(absf(speeds[0]-speeds[1])<1,"Speed response is consistent at 60 and 120 Hz")
	print("BALANCE PROFILE: ",checks," checks / ",failures.size()," failures / gun TTK 400m=",gun_ttk," / speed at 2s=",speeds)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
