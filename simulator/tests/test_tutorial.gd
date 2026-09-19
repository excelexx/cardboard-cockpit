extends SceneTree
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);push_error(label)
func key(app: Node,code: int) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.keycode=code;app._input(event)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	app.on_action("tutorial")
	check(app.tutorial.active and not app.demo_auto_fire and app.combat.managed_mission,"Training is separate from timed automatic demo")
	check(not app.audio.radio.enabled and not app.tutorial.spoken_text.is_empty(),"Instructor script suppresses conflicting radio chatter")
	var start: Vector3=app.flight.position
	app._physics_process(2)
	check(app.flight.position==start,"Aircraft waits during introductory instructions")
	app.begin_landing();check(not app.landing_started,"Cannot skip weapon learning by landing immediately")
	for i in range(3):app.tutorial.advance()
	check(app.tutorial.index==3 and not app.tutorial.ready(),"Primary exercise waits for real weapon input")
	app.tutorial.advance();check(app.tutorial.index==3,"Continue cannot bypass an incomplete exercise")
	for i in range(60):app._physics_process(1.0/60)
	key(app,KEY_SPACE);check(app.tutorial.ready(),"Primary switch satisfies the first exercise")
	app.tutorial.advance();key(app,KEY_T)
	check(app.tutorial.ready() and app.combat.salvo_count>0,"Salvo exercise observes a real launch")
	app.tutorial.advance()
	for i in range(60*30):
		app._physics_process(1.0/60)
		if app.combat.kills>0:break
		if i%120==0:await process_frame
	check(app.tutorial.ready() and app.combat.kills>0,"Target exercise requires an actual kill")
	app.tutorial.advance();app.tutorial.advance()
	check(app.tutorial.index==7 and not app.primary_latched and not app.salvo_latched,"Landing briefing safes the weapons")
	app.begin_landing();check(app.tutorial.index==8,"Landing enters the final training step")
	for i in range(60*40):
		app._physics_process(1.0/60)
		if app.mode=="results":break
	check(app.result_code=="training_complete" and app.mission_success,"Completed training reports training success without a boss kill")
	check(app.flight.contact=="landed" and app.flight.speed==0,"Training requires touchdown and full stop")
	check(not app.tutorial.active and app.audio.radio.enabled,"Results release instructor and restore game radio")
	app.on_action("tutorial");app.on_action("title")
	check(not app.tutorial.active and app.audio.radio.enabled,"Exit cancels tutorial cleanly")
	print("TUTORIAL: ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
