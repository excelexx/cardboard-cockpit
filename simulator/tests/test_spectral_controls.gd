extends SceneTree
var app: Node3D
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func key(code: int) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=true;app._input(e)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.start_flight("combat");app.flight.position.y=600;app.fire_guard=0;app.combat.spawn_clock=999
	key(KEY_SPACE);key(KEY_T)
	check(app.primary_latched and app.salvo_latched,"One switch action latches both weapon systems")
	for i in range(180):app._physics_process(1.0/60)
	check(app.combat.rounds_fired>160 and app.combat.missiles_fired>=8 and app.combat.beam_active,"Released switches sustain minigun, beam and repeated four-shot salvos")
	key(KEY_SPACE);key(KEY_T)
	var fired: int=app.combat.rounds_fired
	for i in range(60):app._physics_process(1.0/60)
	check(app.combat.rounds_fired==fired and not app.combat.beam_active,"Flipping off stops primary")
	app.start_flight("combat");app.combat.spawn_clock=999;app.combat.fire_missile()
	check(app.combat.launch_queue.size()==4,"Exactly four launch orders per salvo")
	var stores: Dictionary={}
	for launch in app.combat.launch_queue:stores[launch.store]=true
	check(stores.size()==4,"All four physical hardpoints are used once")
	app.combat.update_launches(.4)
	check(app.combat.missiles_fired==4,"All four staggered launches execute")
	for i in range(30):app.combat.update_shots(1.0/60)
	var directions: Array[Vector3]=[]
	for shot in app.combat.shots:directions.append(shot.velocity.normalized())
	check(directions[0].distance_to(directions[1])>.001,"Salvo paths diverge after safe separation and ignition")
	app.start_flight("combat");app.flight.position.y=600;app.fire_guard=0;app.combat.spawn_clock=999
	key(KEY_Q)
	check(app.flight.barrel_remaining>0,"Quick roll starts immediately")
	for i in range(90):app._physics_process(1.0/60)
	check(app.flight.barrel_remaining==0 and absf(app.flight.roll)<.15,"Roll recovers without sticky bank")
	app.primary_latched=true;app.salvo_latched=true;key(KEY_ESCAPE)
	var t: float=app.combat.elapsed;app._physics_process(1)
	check(app.mode=="paused" and app.combat.elapsed==t,"Pause freezes combat even with switches on")
	app.start_flight("combat")
	check(not app.primary_latched and not app.salvo_latched and app.combat.shots.is_empty(),"Replay clears weapon latch and projectiles")
	check(app.combat.visuals.projectile_pool.missile.size()==48 and app.combat.visuals.sprite_pool.size()==96,"Replay returns warmed resources to pools")
	app.fire_guard=0;app.copilot=false;app.vision.enabled=true;app.vision.tracking=true;app.vision.yoke=Vector2.ZERO;app.vision.throttle_confidence=1;app.vision.throttle=1
	app._physics_process(1.0/60)
	check(app.flight.power_input==1 and app.flight.afterburner,"Physical throttle retains boost independently of keyboard")
	app.vision.throttle=0;app._physics_process(1.0/60)
	check(app.flight.power_input==-1 and not app.flight.afterburner,"Physical throttle retains airbrake independently of keyboard")
	app.combat.intent.accuracy=.05;app.combat.intent.time_since_reward=20
	var help: float=app.combat.intent.help_amount
	for i in range(300):app.combat.intent.tick(app.combat,1.0/60)
	check(app.combat.intent.help_amount>help and app.combat.intent.help_amount<.93,"Assistance ramps smoothly after unsuccessful play")
	app.start_flight("combat");app.flight.position.y=650;app.combat.spawn_clock=999
	app.combat.spawn_contact();var tracked: Dictionary=app.combat.enemies[0]
	tracked.fade=1;tracked.position=app.flight.position+app.flight.forward()*700;app.combat.target_id=tracked.id
	app.combat.intent.selected_age=2;app.flight.barrel_remaining=.5
	tracked.position=app.flight.position+Vector3(sin(deg_to_rad(22)),0,-cos(deg_to_rad(22)))*700
	check(app.combat.intent.choose(app.combat,.016)==tracked.id,"Existing target survives off-axis roll motion")
	app.flight.barrel_remaining=0
	check(app.combat.intent.choose(app.combat,.016)==-1,"Wide roll margin closes after recovery")
	app.start_flight("combat");app.combat.spawn_contact("boss")
	var boss: Dictionary=app.combat.enemies[0];boss.age=5;app.mission.phase="boss"
	app.combat.hurt_enemy(boss,5000,"cannon",boss.position)
	check(boss.damage_stage>=1 and boss.health>0,"Primary damage breaks boss armor without instant kill")
	var kills: int=app.combat.kills
	app.combat.hurt_enemy(boss,100000,"missile",boss.position)
	app.combat.hurt_enemy(boss,100000,"missile",boss.position)
	check(app.combat.boss_defeated and app.combat.kills==kills+1,"Four-salvo follow-up impacts never double-count boss death")
	print("SPECTRAL CONTROLS: ",checks," checks / ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
