extends SceneTree

const Settings = preload("res://systems/gameplay_settings.gd")
const Flight = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func aircraft(agility: float):
	var f = Flight.new(); f.reset(Catalog.PROFILE); f.spawn_airborne(Vector3(0,1000,0),160)
	f.pitch_agility = agility; f.bank_agility = agility; f.yaw_agility = agility
	return f

func run() -> void:
	for axis in range(3):
		for direction in [-1,1]:
			var base = aircraft(1); var agile = aircraft(1.3)
			var input := Vector3.ZERO; input[axis] = .45*direction
			base.integrate(1.0/120,input,false,0); agile.integrate(1.0/120,input,false,0)
			var old: float = [base.roll_velocity,base.pitch_velocity,base.yaw_velocity][axis]
			var fast: float = [agile.roll_velocity,agile.pitch_velocity,agile.yaw_velocity][axis]
			check(is_equal_approx(fast,old*1.3),"Identical input produces 1.3× angular rate on axis %d, direction %d" % [axis,direction])
			check(is_equal_approx(base.speed,agile.speed),"Agility does not change thrust or forward speed")
	var base = aircraft(1); var agile = aircraft(1.3)
	base.roll = .35; agile.roll = .35
	base.integrate(.02,Vector3.ZERO,false,0); agile.integrate(.02,Vector3.ZERO,false,0)
	check(is_equal_approx(agile.yaw_velocity,base.yaw_velocity*1.3),"Banked turns are faster at the same bank angle")
	var settings = Settings.new()
	check(settings.pitch_agility==1.3 and settings.bank_agility==1.3 and settings.yaw_agility==1.3 and settings.auto_aim==1.4,"New defaults are 1.3× agility and 1.4× auto-aim")
	settings.pitch_agility = 1.8; settings.bank_agility = .75; settings.yaw_agility = 2.5; settings.auto_aim = 2.1
	var config := ConfigFile.new(); settings.save_config(config)
	var restored = Settings.new(); restored.load_config(config)
	check(restored.pitch_agility==1.8 and restored.bank_agility==.75 and restored.yaw_agility==2.5 and restored.auto_aim==2.1,"All gameplay values round-trip independently")
	config.set_value("gameplay","pitch_agility",-5); config.set_value("gameplay","auto_aim","bad")
	restored.load_config(config)
	check(restored.pitch_agility==.5 and restored.auto_aim==1.4,"Invalid preferences are bounded or replaced by defaults")
	var legacy := ConfigFile.new(); legacy.set_value("gameplay","agility",1.4)
	restored.load_config(legacy)
	check(restored.pitch_agility==1.4 and restored.bank_agility==1.4 and restored.yaw_agility==1.4,"Existing shared agility migrates to all axes")
	for axis: String in ["pitch","bank","yaw"]:
		var normal = aircraft(1); var changed = aircraft(1)
		changed.set(axis+"_agility",2.0)
		var input := Vector3(.3,.3,.3)
		normal.integrate(.01,input,false,0); changed.integrate(.01,input,false,0)
		var rates := ["roll_velocity","pitch_velocity","yaw_velocity"]
		var index: int = ["bank","pitch","yaw"].find(axis)
		check(float(changed.get(rates[index]))>float(normal.get(rates[index]))*1.9,"Only selected axis becomes faster: "+axis)
		# Bank induces a coordinated yaw turn by design; pitch and rudder gains must not change bank.
		for other: int in range(2):
			if other!=index: check(is_equal_approx(changed.get(rates[other]),normal.get(rates[other])),axis+" agility leaves unrelated angular rates unchanged")
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.on_action("settings"); app.hud.update_sensitivity_sliders()
	var pitch: float = app.vision.pitch_sensitivity
	app.hud.sensitivity_sliders.pitch_agility.value = 1.85
	app.hud.sensitivity_sliders.bank_agility.value = .85
	app.hud.sensitivity_sliders.yaw_agility.value = 2.15
	app.hud.sensitivity_sliders.auto_aim.value = 1.65
	check(app.flight.pitch_agility==1.85 and app.flight.bank_agility==.85 and app.flight.yaw_agility==2.15 and app.combat.aim_strength==1.65 and app.vision.pitch_sensitivity==pitch,"Independent sliders update real gameplay without changing yoke sensitivity")
	app.on_action("sensitivity_reset")
	check(app.flight.pitch_agility==1.3 and app.flight.bank_agility==1.3 and app.flight.yaw_agility==1.3 and app.combat.aim_strength==1.4,"Reset applies requested defaults to the live aircraft and aiming")
	for kind: String in ["combat","paper","demo","runway"]:
		app.start_flight(kind)
		check(not app.flight.airborne and app.flight.speed==0 and app.flight.throttle==0 and app.flight.gear and app.is_on_runway(app.flight.position),"Normal %s start is stationary on the runway" % kind)
		check(is_equal_approx(app.flight.position.y,app.world.ground_height(app.flight.position.x,app.flight.position.z)+float(app.profile().clearance)),"Aircraft rests on the actual runway surface")
		for i in range(90): app.combat.tick(1.0/30)
		check(app.combat.elapsed==0 and app.combat.enemies.is_empty(),"Preparation does not consume combat time or spawn contacts")
	app.start_flight("approach")
	check(app.flight.airborne,"Explicit landing practice still begins on final approach")
	app.start_flight("combat",true); app.flight.position.y = 500
	app.combat.spawn_clock = 999; app.combat.spawn_contact()
	var enemy: Dictionary = app.combat.enemies[0]
	enemy.position = app.flight.position+Vector3(sin(deg_to_rad(7.5)),0,-cos(deg_to_rad(7.5)))*600
	enemy.course = Vector3.ZERO; enemy.right = Vector3.ZERO; enemy.velocity = Vector3.ZERO; enemy.fade = 1; enemy.age = 2
	app.combat.aim_strength = 1
	app.combat.tick(0)
	check(app.combat.target_id==-1,"A target 7.5 degrees off-centre is outside the original six-degree acquisition")
	app.combat.aim_strength = 1.4; app.combat.tick(0)
	check(app.combat.target_id==enemy.id and is_equal_approx(app.combat.acquire_angle(),8.4) and is_equal_approx(app.combat.release_angle(),10.5),"1.4× auto-aim acquires the same target with a wider retention margin")
	app.combat.lock_progress = 0
	for i in range(6): app.combat.tick(1.0/60)
	check(app.combat.lock_progress==1,"Stronger auto-aim completes lock within a tenth of a second")
	enemy.position = app.flight.position+Vector3(sin(deg_to_rad(5)),0,-cos(deg_to_rad(5)))*600
	enemy.velocity = app.flight.velocity
	app.combat.aim_strength = 1; app.combat.aim_direction = app.flight.forward(); app.combat.update_aim(.005)
	var old_angle: float = app.flight.forward().angle_to(app.combat.aim_direction)
	app.combat.aim_strength = 1.4; app.combat.aim_direction = app.flight.forward(); app.combat.update_aim(.005)
	check(app.flight.forward().angle_to(app.combat.aim_direction)>old_angle*1.3,"Stronger auto-aim follows a target faster, not just with a bigger cone")
	app.combat.aim_strength = 0
	check(app.combat.assisted_direction().is_equal_approx(app.flight.forward()),"Auto-aim at zero immediately shoots straight ahead")
	app.combat.tick(.02)
	check(app.combat.target_id==-1,"Zero auto-aim releases the target")
	app.queue_free(); await process_frame
	print("GAMEPLAY SETTINGS: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
