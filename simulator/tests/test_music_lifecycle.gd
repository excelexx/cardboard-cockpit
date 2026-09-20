extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var track=load("res://assets/audio/runway_music.mp3")
	check(track is AudioStreamMP3 and absf(track.get_length()-900)<.1,"Bundled song is a playable fifteen-minute MP3")
	track.loop=true;check(track.loop,"Long flights can keep the trimmed song playing")
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.vision.enabled=false
	app.audio.music.stream=app.audio.make_sound(30,false)
	app._process(.016);check(not app.audio.music.playing,"Main menu stays silent")
	app.start_flight("demo");app._process(.016)
	check(app.audio.music.playing,"Runway entry immediately starts the song")
	app.audio.music.play(12)
	for mode: String in ["flight","rollout","results"]:
		app.mode=mode;app._process(.016)
		check(app.audio.music.playing and app.audio.music.get_playback_position()>11.9,"The same playback continues through "+mode)
	app.on_action("title");app._process(.016);check(not app.audio.music.playing,"Returning to the main menu stops the song")
	app.start_flight("demo");app._process(.016)
	check(app.audio.music.playing and app.audio.music.get_playback_position()<.2,"The next runway start cues the beginning again")
	app.queue_free();await process_frame
	print("MUSIC LIFECYCLE: ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
