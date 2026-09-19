extends SceneTree
const Radio = preload("res://systems/radio_director.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("RADIO FAIL: "+label)
func run_tests() -> void:
	var radio = Radio.new()
	root.add_child(radio)
	check(radio.cues.size()==20,"Twenty licensed radio cues available")
	check(radio.say("target_down"),"First cue accepted")
	check(not radio.say("target_down"),"Duplicate queued callout rejected")
	radio.tick(.01,false,false)
	check(radio.active_id=="target_down" and radio.duck_db()<0,"Voice starts and requests music ducking")
	var remaining: float = radio.remaining
	radio.tick(2,true,false)
	check(radio.remaining==remaining,"Pause freezes voice and subtitle timing")
	check(radio.say("warning"),"Urgent warning accepted")
	radio.tick(.1,false,false)
	check(radio.active_id=="warning","Urgent warning replaces low-priority chatter")
	for id in ["stage_2","stage_3","stage_4","stage_5","stage_6"]: radio.say(id)
	check(radio.queue.size()<=3,"Radio queue remains bounded")
	radio.tick(.1,false,true)
	check(radio.caption.is_empty() and radio.queue.is_empty() and radio.duck_db()==0,"Mute clears voice, subtitles and ducking")
	radio.tick(.01,false,false)
	radio.say("intro")
	radio.tick(.01,false,false)
	check(radio.active_id=="intro","Radio can play again after unmuting")
	radio.reset()
	check(radio.active_id.is_empty() and radio.queue.is_empty(),"Restart cancels stale callouts")
	for id in radio.cues:
		var cue: Dictionary = radio.cues[id]
		check(FileAccess.file_exists("res://assets/audio/radio/"+str(cue.file)),"Voice audio exists: "+id)
		check(float(cue.duration)>0 and float(cue.duration)<7,"Voice cue length is bounded: "+id)
	print("RADIO RESULT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	radio.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
