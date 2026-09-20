extends SceneTree
const Tune=preload("res://data/balance.gd")
const Art=preload("res://systems/weapon_visuals.gd")
var app: Node
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false)
	check(not app.audio.muted,"Sound starts enabled")
	app.audio.muted=true;app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.apply_aircraft_pose();app.combat.spawn_clock=999
	for i in range(60):app.combat.tick(1.0/60);app.combat.fire_gun()
	var packets: float=float(app.combat.rounds_fired)/Tune.GUN_ROUNDS_PER_PACKET
	check(packets>=9 and packets<=11,"Primary draws about ten separate bullet packets per second")
	check(Art.TRACER_TAIL-Art.TRACER_HEAD<Tune.GUN_MUZZLE_SPEED*Tune.GUN_INTERVAL*.1,"Bullet streaks are compact, not long beam segments")
	for shot: Dictionary in app.combat.shots:
		check(shot.trail_node==null,"Cannon cannot leave a ribbon connected to an old muzzle position")
	check(app.combat.beam_active,"Continuous plasma accompanies held primary fire")
	check(app.combat.visuals.beams.size()==3,"Plasma has a core, braid and halo")
	check(float(app.combat.visuals.beams[0].material_override.get_shader_parameter("radius"))>=.2,"Plasma core is visibly thicker")
	app.combat.gun_firing_time=0;app.combat.update_beam(.1);app.combat.visuals.draw_plasma()
	check(not app.combat.beam_active and not app.combat.visuals.beams[0].visible,"Releasing primary stops the plasma projector")
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.apply_aircraft_pose();app.combat.spawn_clock=999
	check(app.combat.fire_missile() and app.combat.launch_queue.size()==1,"One missile per trigger interval")
	check(not app.combat.fire_missile(),"Missiles cannot bypass their long cooldown")
	app.combat.update_launches(.1)
	check(app.combat.missiles_fired==1 and app.combat.shots.size()==1,"One scheduled missile actually launches")
	check(app.combat.shots[0].node.scale.x>=3.0,"Launched missile uses the enlarged model")
	for i in range(120):app.combat.tick(1.0/60)
	check(not app.combat.fire_missile(),"A two-second hold cannot fire a second missile")
	for i in range(61):app.combat.tick(1.0/60)
	check(app.combat.fire_missile(),"Missile becomes available after three seconds")
	app.start_flight("combat");app.flight.spawn_airborne(Vector3(0,3000,0),180);app.apply_aircraft_pose();app.combat.spawn_clock=999
	var muzzle: Vector3=app.fighter_fx.gun_muzzle_position(Vector3.ZERO)
	app.combat.fire_gun()
	check(app.combat.shots[0].position.is_equal_approx(muzzle),"Gun shots originate at the mounted barrel tip")
	for i in range(15):
		app.flight.position+=app.flight.velocity/60;app.apply_aircraft_pose();app.combat.update_shots(1.0/60)
		for shot: Dictionary in app.combat.shots:
			var tail: Vector3=shot.node.to_global(Vector3(0,0,Art.TRACER_TAIL))
			check((tail-app.flight.position).dot(app.flight.forward())>0,"Straight-flight tracer tail remains ahead of the aircraft")
	app.combat.gun_firing_time=.1;app.combat.update_beam(.016)
	var emitter: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO)
	check(emitter.distance_to(app.fighter_fx.gun_muzzle_position(Vector3.ZERO))>1,"Gun and plasma have distinct mounted emitters")
	app.combat.visuals.draw_plasma()
	var beam=app.combat.visuals.beams[0]
	check(beam.position.distance_to((emitter+app.combat.beam_end)*.5)<.001,"Plasma beam is anchored to its actual machinery")
	app.queue_free();await process_frame
	print("WEAPON READABILITY: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
