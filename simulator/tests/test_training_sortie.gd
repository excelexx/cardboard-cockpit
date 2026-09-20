extends SceneTree
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","sf");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.vision.enabled=false
	app.on_action("keyboard_training");app.copilot=true;app.demo_auto_fire=true
	check(app.flight_kind=="demo" and app.mission.cinematic and not app.mission is TrainingMission,"Legacy Tutorial launches the common SF judge demo")
	check(app.combat.training_target_limit==-1,"Legacy entry cannot reinstate a finite training quota")
	var departed:=false;var requested:=false;var manual:=false;var first_clear:=0
	var phases: Array[String]=[]
	for frame in range(60*240):
		if app.mission.phase not in phases:phases.append(app.mission.phase)
		departed=departed or app.flight.airborne
		if app.mission.phase=="wave_break" and not requested:
			first_clear=app.mission.wave_down()
			var key:=InputEventKey.new();key.keycode=KEY_B;key.physical_keycode=KEY_B;key.pressed=true;app._input(key)
			requested=app.landing_started;manual=not app.copilot
			if not app.flight.gear:app.toggle_gear()
		app._physics_process(1.0/60)
		if app.mode=="results":break
		if frame%120==0:await process_frame
	check(departed and first_clear==6,"Common demo takes off and clears its real first wave")
	check(requested and manual,"D switches the ongoing demo to a pilot-controlled landing")
	check(app.mode=="results" and app.mission_success and app.flight.contact=="landed" and app.flight.speed<=.1,"Legacy entry can land and stop without completing a fixed course")
	check("opening" in phases and "skein" in phases and "approach" in phases,"Shared flight follows the SF encounter and the chosen landing")
	print("SHARED JUDGE SORTIE: ",failures.size()," failures / ",app.mission.clock," seconds / first wave ",first_clear)
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
