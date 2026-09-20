extends "res://tests/test_adaptive_plasma.gd"
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.set_meta("route_override","alpine");root.add_child(app)
	app.set_process(false);app.set_physics_process(false);app.audio.muted=true
	for sample: Array in [[.25,3.0,false],[.75,3.0,true],[1.0,12.0,false],[3.0,12.0,true],[6.0,30.0,true],[0.0,3.0,false]]:
		fresh()
		var angle: float=deg_to_rad(float(sample[1]))
		var enemy: Dictionary=bird(Vector3(sin(angle),0,-cos(angle))*2400)
		enemy.requires_aim_adjustment=true
		app.set_sensitivity("auto_aim",6);app.settings_visible=true;app.hud.settings_page="flight";app.hud.update_sensitivity_sliders()
		app.hud.sensitivity_sliders.auto_aim.value=sample[0]
		check(is_equal_approx(app.combat.aim_strength,float(sample[0])),"Slider immediately updates actual aim strength")
		app.combat.fire_primary();app.combat.update_beam(.1)
		check((enemy.health<100)==bool(sample[2]),"Slider %.2f controls real targeting at %.0f degrees"%[sample[0],sample[1]])
		check(app.hud.sensitivity_sliders.auto_aim.max_value==6,"Aim slider exposes its actual full range")
	app.queue_free();await process_frame
	print("AIM SLIDER: ",checks," checks / ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
