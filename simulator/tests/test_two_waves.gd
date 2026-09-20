extends SceneTree
var app: Node3D
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error("TWO WAVES: "+message)
func _initialize() -> void:call_deferred("run")
func start_first_wave() -> void:
	app.vision.enabled=false;app.start_flight("demo")
	app.flight.spawn_airborne(Vector3(0,500,-6000),265)
	app.mission.clock=63.99;app.mission.transition("gather")
	for i in range(8):app.mission.tick(.02)
func clear_wave() -> void:
	for enemy: Dictionary in app.combat.enemies:
		if app.mission.wave_ids.has(int(enemy.id)) and enemy.health>0:
			app.combat.hurt_enemy(enemy,100000,"cannon",enemy.position)
	app.mission.tick(.02)
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	if not is_instance_valid(app.fighter_fx) or not is_instance_valid(app.hud):
		push_error("TWO WAVES: application dependencies failed to initialize");quit(1);return
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	start_first_wave()
	check(app.mission.wave_number==1 and app.mission.wave_size==12 and app.mission.wave_ids.size()==12,"First wave contains exactly twelve distinct birds")
	check(app.mission.skein_total()==32 and app.mission.skein_down==0 and not app.mission.skein_success,"The full thirty-two target objective is truthful before any kills")
	clear_wave()
	check(app.mission.phase=="wave_break" and app.mission.skein_down==12 and app.mission.wave_down()==12,"Clearing twelve produces the reward beat and accurate first-wave tally")
	check(not app.mission.skein_final and not app.mission.skein_success,"The first clear never finishes the full objective")
	app.mission.tick(3.9)
	check(app.mission.phase=="wave_break" and app.mission.wave_number==1,"Second wave waits for the brief clear beat")
	app.mission.tick(.11)
	for i in range(12):app.mission.tick(.02)
	check(app.mission.wave_number==2 and app.mission.wave_size==20 and app.mission.wave_ids.size()==20,"Second wave contains exactly twenty fresh birds")
	check(app.mission.skein_ids.size()==32 and app.mission.wave_down()==0 and app.mission.skein_down==12,"Wave-local counters reset while aggregate kills remain")
	clear_wave()
	check(app.mission.skein_success and app.mission.skein_final and app.mission.skein_down==32 and app.mission.skein_remaining()==0,"All thirty-two actual kills finish both waves")
	check(app.mission.phase=="aftermath","Both waves hand off to the existing landing phase")
	start_first_wave()
	var missing: Dictionary=app.combat.enemies[0]
	app.combat.enemies.erase(missing);missing.node.queue_free()
	app.mission.tick(.02)
	check(app.mission.wave_down()==0 and app.mission.wave_remaining()==12 and app.mission.skein_down==0,"A disappeared or retired bird never becomes a kill")
	app.mission.clock=106.99;app.mission.tick(.02)
	check(app.mission.phase=="wave_break" and not app.mission.skein_success,"First deadline advances without falsely clearing survivors")
	var late_hit: Dictionary=app.combat.enemies[0]
	app.combat.hurt_enemy(late_hit,100000,"cannon",late_hit.position)
	app.mission.tick(2.0)
	check(app.mission.skein_down==1,"A real impact during the wave transition still counts once")
	app.mission.tick(2.01)
	for i in range(12):app.mission.tick(.02)
	check(app.mission.wave_number==2 and app.mission.wave_ids.size()==20,"Deadline fallback still presents the complete second wave")
	app.mission.clock=164.99;app.mission.tick(.02)
	check(app.mission.skein_final and not app.mission.skein_success and app.mission.skein_down==1 and app.mission.skein_total()==32 and app.mission.skein_remaining()==31,"Final deadline preserves actual kills and missed birds without granting kills")
	app.start_flight("training");app.mission.transition("combat")
	check(not app.mission.cinematic and app.mission.TARGET_COUNT==16 and app.combat.enemies.size()==16,"The independent sixteen-target Tutorial is unchanged")
	check(app.mission.wave_number==0 and app.mission.skein_total()==0,"Tutorial never inherits the showcase wave objective")
	print("TWO WAVES: ",checks," checks / ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
