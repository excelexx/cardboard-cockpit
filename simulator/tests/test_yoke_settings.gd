extends SceneTree

const Vision = preload("res://systems/vision_client.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var v = Vision.new()
	check(v.pitch_sensitivity==1.2 and v.bank_sensitivity==1 and v.yaw_sensitivity==1,"Defaults preserve 1.2× pitch and 1× bank/yaw")
	v.yoke = Vector2(.3,-.4); v.yoke_yaw = .2
	v.pitch_sensitivity = 2; v.bank_sensitivity = .5; v.yaw_sensitivity = 1.5
	check(v.steering().is_equal_approx(Vector3(.15,-.8,.3)),"Three gains independently scale the correct axes")
	v.yoke = Vector2(-1,1); v.yoke_yaw = -1
	v.pitch_sensitivity = 3; v.bank_sensitivity = 3; v.yaw_sensitivity = 3
	check(v.steering()==Vector3(-1,1,-1),"All axes remain bounded with the original signs")
	var config := ConfigFile.new()
	v.pitch_sensitivity = .85; v.bank_sensitivity = 1.35; v.yaw_sensitivity = 1.75
	v.save_sensitivity(config)
	var path := "user://yoke-settings-test.cfg"
	check(config.save(path)==OK,"Settings serialize to disk")
	var loaded := ConfigFile.new(); loaded.load(path)
	var restored = Vision.new(); restored.load_sensitivity(loaded)
	check(restored.pitch_sensitivity==.85 and restored.bank_sensitivity==1.35 and restored.yaw_sensitivity==1.75,"All three values survive a new client and file reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	config.set_value("controls","yoke_pitch_sensitivity","bad")
	config.set_value("controls","yoke_bank_sensitivity",-10)
	config.set_value("controls","yoke_yaw_sensitivity",100)
	restored.load_sensitivity(config)
	check(restored.pitch_sensitivity==1.2 and restored.bank_sensitivity==.25 and restored.yaw_sensitivity==3,"Invalid saved settings fall back or clamp to usable ranges")
	var packet := {"version":1,"sequence":1,"timestamp":1000,"tracking":true,"yoke":{"roll":.1,"pitch":.2,"yaw":-.6,"confidence":1},"throttle":{"value":.7,"confidence":1}}
	check(v._accept_packet(JSON.stringify(packet).to_utf8_buffer(),1000) and is_equal_approx(v.yoke_yaw,-.6),"Yaw arrives on the real control packet parser")
	packet.sequence = 2
	for invalid: Variant in [true,".5",null,2,-2]:
		packet.yoke.yaw = invalid
		check(not v._accept_packet(JSON.stringify(packet).to_utf8_buffer(),2000) and v.sequence==1 and v.last_received==1000,"Malformed yaw cannot mutate controls or refresh freshness")
	packet.yoke.erase("yaw")
	check(v._accept_packet(JSON.stringify(packet).to_utf8_buffer(),2000) and v.yoke_yaw==0,"Older trackers without yaw remain compatible with neutral rudder")
	packet.sequence = 3
	packet.yoke = {"roll":.2,"pitch":.4,"yaw":-.6,"confidence":1}
	packet.raw_yoke = {"roll":.1,"pitch":.2,"yaw":-.3}
	packet.sensitivity = {"bank":2,"pitch":2,"yaw":2}
	v.bank_sensitivity = 2; v.pitch_sensitivity = 2; v.yaw_sensitivity = 2
	check(v._accept_packet(JSON.stringify(packet).to_utf8_buffer(),3000) and v.steering().is_equal_approx(Vector3(.2,.4,-.6)),"Adjusted Python packets do not double-apply sensitivity")
	for invalid: Variant in [true,".2",null,1.5]:
		var bad: Dictionary = packet.duplicate(true); bad.sequence = 4; bad.raw_yoke.pitch = invalid
		check(not v._accept_packet(JSON.stringify(bad).to_utf8_buffer(),4000) and v.sequence==3 and v.last_received==3000,"Malformed physical input cannot bypass packet validation")
	for invalid: Variant in [true,"2",null,.1,4]:
		var bad: Dictionary = packet.duplicate(true); bad.sequence = 4; bad.sensitivity.pitch = invalid
		check(not v._accept_packet(JSON.stringify(bad).to_utf8_buffer(),4000) and v.sequence==3,"Malformed gain metadata cannot mutate the input")
	var app = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","alpine"); root.add_child(app)
	app.set_process(false); app.set_physics_process(false); app.audio.muted = true
	app.on_action("settings"); app.hud.update_sensitivity_sliders()
	check(app.mode=="title" and app.settings_visible and app.overlay_visible(),"Settings opens from the main menu")
	for axis: String in ["pitch","bank","yaw"]:
		var slider: HSlider = app.hud.sensitivity_sliders[axis]
		check(slider.visible and slider.min_value==.25 and slider.max_value==3,"Each sensitivity control is a visible draggable slider")
		slider.value = 1.65
		check(is_equal_approx(app.vision.get(axis+"_sensitivity"),1.65),"Slider changes reach the game settings immediately")
	app.on_action("sensitivity_reset"); app.hud.update_sensitivity_sliders()
	check(app.vision.pitch_sensitivity==1.2 and app.vision.bank_sensitivity==1 and app.vision.yaw_sensitivity==1,"Reset restores all defaults")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	app._input(escape)
	check(not app.settings_visible and app.mode=="title","Esc closes settings back to the main menu")
	app.start_flight("combat", true); app.combat.active = false; app.mission.active = false
	app._input(escape); app.on_action("settings")
	check(app.mode=="paused" and app.settings_visible,"Esc pause menu can open settings")
	var clock: float = app.flight.elapsed
	app._physics_process(.1)
	check(app.flight.elapsed==clock,"Opening settings keeps the flight paused")
	app._input(escape)
	check(app.mode=="paused" and not app.settings_visible,"Closing settings preserves the pause")
	app.on_action("resume"); app.test_mode = true
	app.vision.enabled = true; app.vision.tracking = true
	app.vision.yoke = Vector2.ZERO; app.vision.yoke_yaw = .4
	app.vision.pitch_sensitivity = 2; app.vision.bank_sensitivity = 1.5; app.vision.yaw_sensitivity = .5
	app.control = Vector3.ZERO
	app._physics_process(1.0/60)
	var expected: float = .2*app.Tune.RUDDER_SCALE*(1-exp(-app.Tune.INPUT_RESPONSE/60.0))
	check(is_equal_approx(app.control.z,expected) and app.flight.yaw_velocity>0 and app.control.x==0,"Yaw slider drives the actual rudder and turns the nose without banking")
	app.queue_free(); await process_frame
	print("YOKE SETTINGS: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
