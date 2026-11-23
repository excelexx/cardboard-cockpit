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
	check(radio.cues.size()==15,"Fifteen licensed radio cues available")
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
	for id in ["cleared","checkpoint","approach","touchdown","landed"]: radio.say(id)
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
	# Goal 8 coverage. Everything above exercises RadioDirector's cue queue and
	# nothing else; these checks cover the new speed-of-sound queue, the
	# population-driven skein bed and the synthesised honk. They do NOT cover
	# the spatial mix, Doppler or the flock cadence, which need a native audio
	# device and a running flight - those stay a hand-verified item.
	var audio := EngineAudio.new()
	root.add_child(audio)
	audio.muted = true
	check(is_equal_approx(EngineAudio.propagation_delay(100.0),0.0),"Bangs inside 120 m are heard immediately")
	var far: float = EngineAudio.propagation_delay(700.0)
	check(far>1.2 and far<2.2,"A kill at 700 m is heard roughly two seconds later")
	check(EngineAudio.propagation_delay(1500.0)>far,"Propagation delay grows with range")
	check(EngineAudio.spatial_cutoff(50.0)>7000.0 and EngineAudio.spatial_cutoff(1500.0)<1500.0,"Distance rolls the high end off a report")
	check(EngineAudio.bed_db(0,false)<=-80.0,"An empty sky silences the skein bed")
	check(EngineAudio.bed_db(12,false)>EngineAudio.bed_db(1,false),"A bigger flock is a louder bed")
	check(EngineAudio.bed_db(12,true)<=-80.0,"Mute silences the skein bed")
	audio.spatial_queue.append({"effect":"explosion","at":Vector3.ZERO,"volume":-18.0,"pitch":1.0,"delay":1.0})
	audio.reset_flight()
	check(audio.spatial_queue.is_empty(),"Restart clears bangs still in flight")
	var honk: AudioStreamWAV = audio.make_honk(520.0,0.5)
	check(honk!=null and honk.data.size()>4000,"Goose honk is synthesised as a one-shot sample")
	check(honk.mix_rate==22050 and honk.loop_mode==AudioStreamWAV.LOOP_DISABLED,"Honk does not loop")
	check(audio.flock_players.size()==6 and audio.spatial_players.size()==8,"Flock voices get their own pool and do not starve the shared spatial players")
	audio.queue_free()
	await process_frame
	print("RADIO RESULT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	radio.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
