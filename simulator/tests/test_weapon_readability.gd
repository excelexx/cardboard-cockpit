extends SceneTree
const Tune=preload("res://data/balance.gd")
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
	app.combat.fire_primary();app.combat.update_beam(.016);app.combat.visuals.draw_plasma()
	check(app.combat.beam_active and app.combat.visuals.beams.size()==6,"Two plasma emitters each have a core, braid and halo")
	check(app.combat.shots.is_empty() and app.combat.rounds_fired==0,"Primary creates no minigun bullets or trailing cannon ribbon")
	check(app.fighter_fx.plasma_models.size()==2 and app.fighter_fx.plasma_muzzles.size()==2,"Two visible plasma assemblies have separate muzzle anchors")
	var first_muzzle: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,0)
	var second_muzzle: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,1)
	check(first_muzzle.distance_to(second_muzzle)>1,"Emitter separation remains visibly distinct")
	for index in range(2):
		var muzzle: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,index)
		var beam=app.combat.visuals.beams[index*3]
		check(beam.visible and beam.position.distance_to((muzzle+app.combat.beam_ends[index])*.5)<.001,"Each beam stays anchored to its own mounted machinery")
		check(float(beam.material_override.get_shader_parameter("radius"))>=.2,"Each plasma core is visibly thick")
		check((app.combat.beam_ends[index]-muzzle).dot(app.flight.forward())>Tune.BEAM_RANGE*.95,"Unassigned plasma projects ahead of the aircraft")
	app.flight.position+=Vector3(25,3,-150);app.flight.roll=.4;app.apply_aircraft_pose()
	app.combat.fire_primary();app.combat.update_beam(.016);app.combat.visuals.draw_plasma()
	for index in range(2):
		var muzzle: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,index)
		check(app.combat.visuals.beams[index*3].position.distance_to((muzzle+app.combat.beam_ends[index])*.5)<.001,"Moving and banking updates both emitter anchors without stale trails")
	app.cockpit=true;app.camera_rig.reset();app.camera_rig.update(.016);app.combat.visuals.draw_plasma()
	for index in range(2):
		var muzzle: Vector3=app.fighter_fx.plasma_muzzle_position(Vector3.ZERO,index)
		check((muzzle-app.camera.global_position).dot(-app.camera.global_basis.z)>1.0,"Both plasma emitters are physically ahead of the cockpit camera")
	for material in app.combat.visuals.plasma_materials:check(is_equal_approx(float(material.get_shader_parameter("width_scale")),.32),"Every cockpit plasma layer is thinner")
	app.cockpit=false;app.combat.visuals.draw_plasma()
	check(is_equal_approx(float(app.combat.visuals.plasma_materials[0].get_shader_parameter("width_scale")),1.0),"Chase view keeps its original beam width")
	app.combat.gun_firing_time=0;app.combat.update_beam(.1);app.combat.visuals.draw_plasma()
	for beam in app.combat.visuals.beams:check(not beam.visible,"Release hides every plasma layer")
	check(not app.combat.beam_active,"Release clears plasma activity")
	for bloom in app.combat.visuals.plasma_muzzle_blooms+app.combat.visuals.plasma_impact_blooms:check(not bloom.visible,"Releasing primary removes its muzzle and target blooms")
	for i in range(8):
		app.combat.spawn_contact();var enemy: Dictionary=app.combat.enemies.back()
		enemy.position=app.flight.position+Vector3((i-3)*35,0,-800-i*50);enemy.fade=1;enemy.retiring=false
	app.combat.update_swarm_missiles()
	check(app.combat.swarm_active and app.combat.launch_queue.size()==2,"An eligible large flock schedules an automatic two-missile burst without a manual trigger")
	var stores: Dictionary={}
	var targets: Dictionary={}
	for request: Dictionary in app.combat.launch_queue:stores[request.store]=true;targets[request.target]=true
	check(stores.size()==2 and targets.size()==2,"The burst uses opposite hardpoints and two distinct targets")
	app.combat.update_launches(.1)
	check(app.combat.missiles_fired==2 and app.combat.shots.size()==2,"Both automatic missiles leave their stores")
	for shot: Dictionary in app.combat.shots:check(shot.kind=="missile" and shot.node.scale.x>=3,"Automatic missiles use enlarged, readable models")
	var shot: Dictionary=app.combat.shots[0]
	for effect_name in ["EngineFlare","MotorLight","LaunchPulse"]:check(not shot.node.get_node(effect_name).visible,"A missile leaves the rail with its motor effects off")
	shot.age=Tune.MISSILE_IGNITION_DELAY+.05;app.combat.visuals.update_projectile(shot,.05)
	check(shot.node.get_node("EngineFlare").visible and shot.node.get_node("LaunchPulse").visible,"Motor ignition has a brief visible flare and launch pulse")
	shot.age=Tune.MISSILE_MOTOR_TIME+.01;app.combat.visuals.update_projectile(shot,.01)
	check(not shot.node.get_node("MotorLight").visible and not shot.node.get_node("EngineFlare").visible and not shot.node.get_node("LaunchPulse").visible,"Visual motor and launch flash end with the actual motor burn")
	app.combat.visuals.release_projectile(shot.node,"missile")
	var reused=app.combat.visuals.take_projectile("missile")
	check(not reused.get_node("EngineFlare").visible and not reused.get_node("LaunchPulse").visible,"Reused missile cannot inherit an old ignition flash")
	check(not app.combat.has_method("fire_gun") and not app.combat.has_method("fire_missile"),"Only the plasma weapon has a manual firing API")
	app.queue_free();await process_frame
	print("WEAPON READABILITY: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
