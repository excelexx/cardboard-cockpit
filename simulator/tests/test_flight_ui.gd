extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","sf")
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var hud=load("res://ui/hud.gd").new()
	hud.app=app
	var instruments=load("res://ui/cockpit_instruments.gd").new()
	instruments.navigation_kind="sf"
	var failures:=0
	for degrees in [0.0,61.0,62.0,63.0,180.0,359.0]:
		app.flight.heading=deg_to_rad(degrees)
		instruments.heading=app.flight.get_heading_degrees()
		var heading: float=hud.flight_heading()
		if heading<0 or heading>=360 or not is_equal_approx(heading,instruments.display_heading()):
			failures+=1
	app.route_id="alpine"
	instruments.navigation_kind="valley"
	if not is_equal_approx(hud.flight_heading(),instruments.display_heading()):failures+=1
	var points: Array[Vector3]=[Vector3(100,200,-300),Vector3(400,300,-600)]
	instruments.set_navigation("sf",1,points)
	if instruments.route_points().size()!=2 or instruments.navigation_target()!=points[1]:failures+=1
	instruments.set_navigation("sf",2,points)
	if instruments.navigation_target()!=points[1] or instruments.navigation_target_label()!="LANDING STRIP":failures+=1
	print("FLIGHT UI HEADING: ",failures," failures")
	hud.free()
	instruments.free()
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
