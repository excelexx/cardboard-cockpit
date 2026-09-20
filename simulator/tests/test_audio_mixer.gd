extends SceneTree
const Settings=preload("res://systems/audio_settings.gd")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var settings=Settings.new()
	check(settings.music==2 and settings.engine==.5 and settings.effects==.5 and settings.voice==.5,"Defaults double Free Bird and halve the other channels")
	settings.set_level("music",1.25);settings.set_level("engine",.2);settings.set_level("effects",0)
	var config:=ConfigFile.new();settings.save_config(config)
	var restored=Settings.new();restored.load_config(config)
	check(restored.music==1.25 and restored.engine==.2 and restored.effects==0,"Independent volumes persist exactly")
	restored.set_level("music",99);restored.set_level("voice",NAN)
	check(restored.music==4 and restored.voice==.5,"Invalid or excessive volumes are bounded")
	var app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.vision.enabled=false
	var music_bus:=AudioServer.get_bus_index("Cockpit Music");var engine_bus:=AudioServer.get_bus_index("Cockpit Engine")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)),2),"Music receives the actual 2x mixer gain")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(engine_bus)),.5),"Aircraft audio receives the actual half-volume gain")
	check(app.audio.music.bus=="Cockpit Music" and app.audio.player.bus=="Cockpit Engine" and app.audio.wind.bus=="Cockpit Engine","Music and aircraft loops are separated")
	check(app.audio.beam_loop.bus=="Cockpit Effects" and app.audio.spatial_players[0].bus=="Cockpit Effects" and app.audio.flock_players[0].bus=="Cockpit Effects","Weapons and spatial effects use the effects channel")
	check(app.audio.radio.player.bus=="Cockpit Voice" and app.audio.voice_gain==.5,"Radio and instructor volume follow the voice setting")
	app.on_action("settings");app.on_action("settings_audio");app.hud.update_audio_sliders();app.hud.update_sensitivity_sliders()
	for slider: HSlider in app.hud.audio_sliders.values():check(slider.visible,"Audio tab exposes its real slider")
	for slider: HSlider in app.hud.sensitivity_sliders.values():check(not slider.visible,"Flight sliders cannot overlap the audio tab")
	app.hud.audio_sliders.music.value=1.1
	check(is_equal_approx(app.audio_settings.music,1.1) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)),1.1),"Dragging music changes the mixer immediately")
	app.hud.audio_sliders.effects.value=0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Cockpit Effects")) and not AudioServer.is_bus_mute(music_bus),"Effects can be silenced without silencing Free Bird")
	app.on_action("audio_reset");check(app.audio_settings.music==2 and app.audio_settings.effects==.5,"Reset Audio restores the requested balance")
	for axis: String in app.hud.sensitivity_sliders:
		app.hud.sensitivity_sliders[axis].value=6
		check(is_equal_approx(app.hud.setting_value(axis),6),"Raised control ceiling applies: "+axis)
	app.flight.pitch_agility=6;app.flight.bank_agility=6;app.flight.yaw_agility=6;app.combat.aim_strength=6
	check(app.flight.pitch_agility==6 and app.flight.bank_agility==6 and app.flight.yaw_agility==6 and app.combat.aim_strength==6,"Runtime accepts raised agility and aim limits")
	app.audio.music.stream=app.audio.make_sound(3,false);app.audio.player.stream=app.audio.music.stream;app.audio.player.play();app.start_flight("demo");app._process(.016)
	app.settings_visible=true;app.hud.settings_page="audio";app._process(.016)
	check(app.audio.music.playing and not app.audio.music.stream_paused and app.audio.player.stream_paused,"Audio tab previews music while flight effects remain paused")
	app.audio.muted=false;app.audio.instructor_speaking=false;app.audio.update(.5,120,true,.1)
	var music_before: float=app.audio.music.volume_db
	app.audio.instructor_speaking=true;app.audio.update(.5,120,true,.1)
	check(is_equal_approx(app.audio.music.volume_db,music_before),"Instructor speech leaves music volume unchanged")
	app.queue_free();await process_frame
	print("AUDIO MIXER: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
