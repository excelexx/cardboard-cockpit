extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native speech test requires desktop display");quit(2);return
	await process_frame
	var chosen:="";var name:=""
	for voice: Dictionary in DisplayServer.tts_get_voices():
		if str(voice.language).begins_with("en") and (chosen.is_empty() or str(voice.name).contains("Daniel")):
			chosen=str(voice.id);name=str(voice.name)
	if chosen.is_empty():printerr("No English system voice; captions remain available");quit(2);return
	DisplayServer.tts_speak("Flight training ready. Follow the instructor, and take each step at your own pace.",chosen,65,1,.96,101,true)
	await create_timer(.6).timeout
	var started:=DisplayServer.tts_is_speaking()
	DisplayServer.tts_pause();await create_timer(.2).timeout
	var paused:=DisplayServer.tts_is_paused()
	DisplayServer.tts_resume();await create_timer(.3).timeout
	var resumed:=DisplayServer.tts_is_speaking() and not DisplayServer.tts_is_paused()
	DisplayServer.tts_stop();await create_timer(.1).timeout
	print("NATIVE INSTRUCTOR voice=",name," started=",started," paused=",paused," resumed=",resumed," stopped=",not DisplayServer.tts_is_speaking())
	quit(0 if started and paused and resumed and not DisplayServer.tts_is_speaking() else 1)
