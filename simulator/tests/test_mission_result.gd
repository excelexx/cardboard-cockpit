extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.on_action("fly")
	app.flight.contact="landed";app.flight.speed=0;app.combat.boss_defeated=false
	app.finish_sortie(false,"SFO LANDING COMPLETE — INTERCEPT INCOMPLETE")
	var wrong:=false
	for cue in app.audio.radio.queue:
		if cue.id in ["landed","success"]:wrong=true
	print("Incomplete intercept must not announce mission completed: ",not wrong)
	var assess=load("res://systems/sortie_result.gd")
	var state: Dictionary={"cinematic":true,"boss":true,"contact":"landed","stopped":true}
	var result: Dictionary=assess.assess(state,true,"")
	wrong=wrong or not result.success or result.code!="mission_complete"
	state.boss=false;state.early_landing=true;result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="intercept_incomplete" or not result.advice.contains("before")
	state.boss=true;state.contact="";state.stopped=false;result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="recovery_incomplete"
	state.contact="crash";state.landing=true;result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="crash" or not result.advice.contains("flaps")
	state.contact="overrun";result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="runway_excursion"
	state.contact="";state.ejected=true;result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="ejected"
	state.ejected=false;state.cause="sector";result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="sector"
	state={"tutorial":true,"training_ready":true,"contact":"landed","stopped":true}
	result=assess.assess(state,true,"");wrong=wrong or not result.success or result.code!="training_complete"
	state.training_ready=false;result=assess.assess(state,true,"")
	wrong=wrong or result.success or result.code!="training_incomplete"
	print("MISSION OUTCOMES: ","FAIL" if wrong else "PASS")
	app.queue_free();await process_frame;quit(1 if wrong else 0)
