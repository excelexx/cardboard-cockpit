extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var audio=load("res://systems/engine_audio.gd").new();root.add_child(audio)
	audio.music.stream=audio.make_sound(1.0,false);audio.geese.stream=audio.make_sound(1.0,false)
	audio.tone.stream=audio.make_sound(.22,true);audio.tone.play()
	audio.set_context("flight",false,"",true);audio.update(0,0,false,.016);audio.set_music_active(true)
	check(not audio.tone.playing,"Tracking hold stops the acquisition chime")
	check(not audio.music.playing and not audio.geese.playing,"Tracking hold cannot start or restart looping sounds")
	audio.ping();check(not audio.tone.playing,"Tracking hold rejects new chimes")
	audio.set_context("flight",false,"",false);audio.update(0,0,true,.016);audio.set_music_active(true)
	check(audio.music.playing and not audio.music.stream_paused,"Normal audio resumes after tracking returns")
	audio.queue_free();await process_frame
	print("TRACKING AUDIO: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
