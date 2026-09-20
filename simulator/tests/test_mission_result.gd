extends SceneTree
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true;app.on_action("keyboard_play")
	app.flight.contact="landed";app.flight.speed=0;app.combat.kills=0
	app.finish_sortie(false,"No targets cleared")
	check(app.mission_success and app.result_code=="demo_complete","A stopped judge-demo landing succeeds with zero kills even if a legacy caller requests failure")
	var success_cue:=false
	for cue in app.audio.radio.queue:
		if cue.id=="success":success_cue=true
	check(success_cue,"The debrief radio agrees with zero-quota landing success")
	var assess=load("res://systems/sortie_result.gd")
	var state: Dictionary={"judge_demo":true,"cinematic":true,"cleared":false,"down":0,"total":64,"kills":0,"contact":"landed","stopped":true}
	var result: Dictionary=assess.assess(state,false,"")
	check(result.success and result.code=="demo_complete" and result.summary.contains("0 geese"),"Judge results report actual kills without a quota")
	state.kills=7;state.down=7;result=assess.assess(state,false,"")
	check(result.success and result.summary.contains("7 geese"),"Partial-wave landing preserves truthful score text")
	state.stopped=false;result=assess.assess(state,false,"")
	check(not result.success and result.code!="demo_complete","Moving aircraft cannot receive a completed judge-demo landing")
	state.contact="";state.cleared=true;state.down=64;result=assess.assess(state,false,"")
	check(not result.success,"Clearing targets alone does not claim a stopped landing")
	state.contact="crash";state.landing=true;result=assess.assess(state,false,"")
	check(not result.success and result.code=="crash","Unsettled crash state does not fabricate a completed landing")
	state.contact="overrun";result=assess.assess(state,false,"")
	check(not result.success and result.code=="runway_excursion","Unsettled excursion retains its explicit outcome")
	state.contact="";state.ejected=true;result=assess.assess(state,false,"")
	check(not result.success and result.code=="ejected","Ejection remains distinguishable from a landed demo")
	state.ejected=false;state.cause="sector";result=assess.assess(state,false,"")
	check(not result.success and result.code=="sector","Leaving the sector keeps its own outcome")
	print("JUDGE MISSION OUTCOMES: ",failures.size()," failures")
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
