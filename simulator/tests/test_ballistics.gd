extends SceneTree
var app: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if not value: failures.append(label); push_error("BALLISTICS FAIL: "+label)
func run():
	app = load("res://scenes/main.tscn").instantiate(); app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.start_flight("combat", true)
	app.cockpit = false # This assertion tests exterior muzzle effects, hidden in cockpit view.
	check(is_instance_valid(app.fighter_fx.gun_rotor) and is_instance_valid(app.fighter_fx.gun_muzzle),"Imported rotary gun retains animated rotor and physical muzzle")
	app.combat.fire_gun(); app.fighter_fx.update_gun(.05)
	check(app.fighter_fx.rotor_speed>0 and app.fighter_fx.gun_flash.visible,"Gun fires immediately with rotating barrels and attached muzzle flash")
	var live_muzzle: Vector3 = app.fighter_fx.gun_muzzle_position(Vector3.ZERO)
	check(live_muzzle.distance_to(app.flight.position)>2 and live_muzzle.distance_to(app.flight.position)<9,"Projectile origin uses actual barrel tip")
	app.combat.gun_firing_time = 0
	for i in range(60): app.fighter_fx.update_gun(1.0/60)
	check(app.fighter_fx.rotor_speed==0 and not app.fighter_fx.gun_flash.visible,"Releasing fire stops flash and lets rotor coast to a stop")
	app.start_flight("combat", true)
	var start := Vector3(0,500,-3500)
	app.combat.spawn_shot(start,Vector3(0,0,-1250),"cannon",-1,28)
	var shot: Dictionary = app.combat.shots.back()
	for i in range(60): app.combat.update_shots(1.0/60)
	check(shot.position.y<start.y-4 and shot.position.y>start.y-6,"Cannon trajectory includes one second of gravitational drop")
	check(shot.velocity.length()<1200 and shot.velocity.length()>1100,"Air drag slows the projectile")
	app.start_flight("combat", true); app.combat.spawn_contact()
	var enemy: Dictionary = app.combat.enemies[0]
	enemy.position = start+Vector3(0,0,-20); enemy.health = 28
	app.combat.spawn_shot(start,Vector3(0,0,-5000),"cannon",-1,28)
	app.combat.update_shots(1.0/60)
	check(app.combat.kills==1,"Swept collision detects a target crossed between frames")
	app.start_flight("combat", true)
	app.combat.spawn_shot(Vector3(0,5,-3500),Vector3(0,-600,-100),"cannon",-1,28)
	app.combat.update_shots(.03)
	check(app.combat.shots.is_empty() and not app.combat.bursts.is_empty(),"Projectiles hit terrain and produce an impact")
	app.start_flight("combat", true); app.combat.spawn_contact()
	enemy = app.combat.enemies[0]; enemy.position = app.flight.position+app.flight.forward()*430
	enemy.health = 100000; enemy.cooldown = 999; app.combat.spawn_clock = 999
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
		Input.parse_input_event(event); Input.flush_buffered_events()
	for i in range(1500):
		app._physics_process(1.0/60)
		if i%90==0: await process_frame
	for code in [KEY_SPACE]:
		var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = false
		Input.parse_input_event(event); Input.flush_buffered_events()
	print("GUN FIRE rounds=",app.combat.rounds_fired," mode=",app.mode)
	check(app.combat.rounds_fired>1200,"Holding fire sustains the gun beyond former ammunition limits")
	check(app.combat.ammo==-1,"Unlimited ammunition never depletes")
	app.start_flight("combat", true); app.combat.spawn_contact(); enemy = app.combat.enemies[0]
	enemy.position = app.flight.position+Vector3(35,0,-500); app.combat.target_id = enemy.id
	var initial: Vector3 = app.combat.assisted_direction()
	app.combat.update_aim(1.0/60)
	check(initial.angle_to(app.combat.assisted_direction())<deg_to_rad(6),"Magnetic aim moves smoothly instead of snapping instantly")
	for i in range(24): app.combat.update_aim(1.0/120)
	check(app.combat.assisted_direction().angle_to((enemy.position-app.flight.position).normalized())<deg_to_rad(3),"Magnetic aim settles quickly onto a visible target")
	var samples: Array[Vector2] = [Vector2(2400,-4800),Vector2(-4400,-8100),Vector2(960,-6500),Vector2(130,-13800)]
	for at in samples:
		var cached: float = app.world.ground_height(at.x,at.y)
		var columns: int = app.world._height_columns; app.world._height_columns = 0
		var direct: float = app.world.ground_height(at.x,at.y); app.world._height_columns = columns
		check(absf(cached-direct)<.001,"Cached collision terrain matches the rendered heightfield")
	for path in ["res://assets/environment/alpine-fir.png","res://assets/environment/alpine-fir-b.png","res://assets/environment/alpine-granite.png","res://assets/fighter/spectre-satin.png"]:
		var texture: Texture2D = load(path)
		check(texture.get_image().has_mipmaps(),"Runtime 3D texture includes filtered distance levels: "+path)
	print("BALLISTICS: ",checks," checks / ",failures.size()," failures")
	app.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
