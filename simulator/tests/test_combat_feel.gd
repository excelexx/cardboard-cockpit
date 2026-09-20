extends SceneTree
var app: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if not value: failures.append(label); push_error("COMBAT FEEL FAIL: "+label)
func run():
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true;app.on_action("sensitivity_reset")
	app.start_flight("combat"); app.flight.position.y = 500
	check(app.combat.enemies.is_empty(),"Combat starts without a flock appearing at once")
	var arrivals: Array[float] = []; var last_id := 0; var max_contacts := 0
	for i in range(2400):
		app.flight.position += app.flight.forward()*165/60
		app.combat.tick(1.0/60)
		max_contacts = maxi(max_contacts,app.combat.enemies.size())
		if app.combat.next_id!=last_id:
			arrivals.append(float(i)/60); last_id = app.combat.next_id
		if i%120==0: await process_frame
	var smallest_gap := INF
	for i in range(1,arrivals.size()): smallest_gap = minf(smallest_gap,arrivals[i]-arrivals[i-1])
	check(max_contacts<=4 and arrivals.size()>=3,"Paced arrivals keep at most four contacts and continue after old contacts leave")
	check(smallest_gap>=7.99 and arrivals[0]>=7.9,"Each arrival is separated, including the first contact")
	check(app.combat.hostile_launches==0 and app.combat.hull==100,"Pacing retains harmless geese")
	app.start_flight("combat"); app.combat.spawn_clock = 999; app.combat.spawn_contact()
	var enemy: Dictionary = app.combat.enemies[0]
	enemy.position = app.flight.position+Vector3(sin(deg_to_rad(4)),0,-cos(deg_to_rad(4)))*600
	enemy.fade = 1; enemy.age = 2; enemy.course = Vector3(0,0,-1); enemy.right = Vector3.ZERO
	for i in range(12): app.combat.tick(1.0/60)
	check(app.combat.target_id==enemy.id and app.combat.lock_progress>=1,"A comfortable four-degree near-centre target locks within 0.2 seconds")
	check(app.combat.reticle_point().distance_to(enemy.position)<4,"Visible crosshair tracks onto the target instead of staying at screen centre")
	check(app.combat.assisted_direction().angle_to((app.combat.lead_point(enemy)-app.flight.position).normalized())<deg_to_rad(.4),"Narrow assistance still provides reliable gun alignment")
	enemy.position = app.flight.position+Vector3(sin(deg_to_rad((app.combat.acquire_angle()+app.combat.release_angle())*.5)),0,-cos(deg_to_rad((app.combat.acquire_angle()+app.combat.release_angle())*.5)))*600
	app.combat.tick(1.0/60)
	check(app.combat.target_id==enemy.id,"Small drift outside acquisition radius preserves a comfortable lock margin")
	enemy.position = app.flight.position+Vector3(sin(deg_to_rad(app.combat.release_angle()+.5)),0,-cos(deg_to_rad(app.combat.release_angle()+.5)))*600
	app.combat.tick(1.0/60)
	check(app.combat.target_id==-1 and app.combat.lock_progress<1,"A target outside the XLX release cone releases immediately")
	for i in range(24): app.combat.update_aim(1.0/120)
	check(app.combat.assisted_direction().angle_to(app.flight.forward())<deg_to_rad(.5),"Gun sight returns to the nose after losing the target")
	app.combat.assist=false;app.combat.aim_strength=0;app.combat.fire_primary();app.combat.update_beam(.1)
	check(app.combat.beam_active and app.combat.shots.is_empty(),"An unlocked pilot can fire plasma without hidden bullet projectiles")
	check(app.combat.beam_target_ids==[-1,-1],"Disabled assistance cannot steer plasma onto an off-axis target")
	var start: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,0)
	check((app.combat.beam_ends[0]-start).normalized().is_equal_approx(app.flight.forward()),"Unassisted plasma points straight ahead")
	app.start_flight("combat"); app.flight.position.y = 600; app.flight.power_input = 1; app.flight.throttle = 1
	var speed: float = app.flight.speed
	for i in range(240): app.flight.step(1.0/120,Vector3.ZERO,false,0,false)
	check(app.flight.speed>speed+130,"Full acceleration creates a strong speed change within two seconds")
	speed = app.flight.speed; app.flight.power_input = -1; app.flight.throttle = 0
	for i in range(240): app.flight.step(1.0/120,Vector3.ZERO,false,0,false)
	check(app.flight.speed<speed-140 and app.flight.speed>78,"Airbraking sheds speed quickly without stopping the jet in midair")
	for i in range(1800): app.flight.step(1.0/120,Vector3.ZERO,false,0,false)
	check(app.flight.speed>=80 and app.flight.contact=="","Holding the airbrake remains forgiving at low speed")
	app.start_flight("combat");app.combat.spawn_contact()
	var victim: Dictionary=app.combat.enemies[0]
	victim.health=10;victim.max_health=10
	app.camera_rig.trauma=0
	app.combat.hurt_enemy(victim,1,"plasma",victim.position)
	check(app.camera_rig.trauma==0,"A nonlethal hit does not shake the camera")
	app.combat.hurt_enemy(victim,20,"plasma",victim.position)
	check(app.camera_rig.trauma>=.65,"A goose kill creates a visible shake pulse")
	var kill_trauma: float=app.camera_rig.trauma
	app.combat.hurt_enemy(victim,20,"plasma",victim.position)
	check(app.camera_rig.trauma==kill_trauma,"A dead goose cannot retrigger the kill shake")
	print("COMBAT FEEL: ",checks," checks / ",failures.size()," failures / peak contacts ",max_contacts," / arrival gap ",smallest_gap)
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
