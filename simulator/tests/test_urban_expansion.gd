extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","coast")
	root.add_child(app)
	await process_frame
	app.set_process(false); app.set_physics_process(false)
	app.audio.muted=true
	app.on_action("guided")
	app.capture_file="urban-review"
	var city=app.world.urban_expansion
	check(city.stats.buildings>10000,"Expanded city has more than ten thousand buildings")
	check(city.footprint_km2>130,"Urban coverage exceeds 130 square kilometres after fitting blocks around protected areas")
	check(city.get_child_count()<1000 and city.stats.buildings/city.get_child_count()>30,"City geometry uses bounded batches rather than individual building nodes")
	check(city.connected_blocks>1000,"Residential buildings form joined street-front blocks")
	check(city.park_blocks>50 and city.industrial_blocks>50 and city.office_blocks>50,"Districts have different land uses")
	var widths: Dictionary={}
	var angles: Dictionary={}
	for size: Vector2 in city.block_sizes: widths[roundi(size.x/10)]=true
	for angle: float in city.block_angles: angles[roundi(rad_to_deg(angle))]=true
	check(widths.size()>10 and angles.size()>8,"Street blocks vary in width and orientation")
	check(city.traffic.size()>200 and city.traffic.size()<=650,"Moving traffic is bounded")
	var departure_traffic:=0
	var arrival_traffic:=0
	for car: Dictionary in city.traffic:
		if car.a.y> -2500: departure_traffic+=1
		if car.a.y< -14000: arrival_traffic+=1
	check(departure_traffic>10 and arrival_traffic>10,"Traffic reaches both airports instead of filling only the first generated districts")
	check(city.skyscraper_count>50 and city.height_max>350,"Downtown includes a genuinely tall skyline")
	check(city.height_min<10,"Low-rise neighbourhoods contrast with skyscrapers")
	check(is_instance_valid(city.train),"Urban transit is present")
	for bounds: AABB in city.lot_bounds:
		check(bounds.position.y>=app.world.ground_height(bounds.position.x,bounds.position.z)-0.3,"Building foundation clears terrain")
	for z in range(-17400,2500,100):
		if minf(absf(z),absf(z+15000))<4200:
			check(not city.collides(Vector3(0,25,z),25),"Actual approach corridor remains clear")
	check(not city.reserved(Vector2(0,-6000)),"Runway reservation does not cut through the entire city")
	check(city.stats.detailed_buildings>0 and city.stats.detailed_buildings<=48,"Departure streets include bounded imported facade detail")
	check(city.detailed_tree_count>0 and city.detailed_tree_count<=160,"Departure vegetation uses bounded scanned models")
	for throttle in app.cockpit_frame.throttles:
		check(throttle.position.z> -1.0,"Throttle pivot sits behind the dashboard")
		for power in [0.0,0.5,1.0]:
			app.flight.throttle=power
			app.cockpit_frame.update_instruments(app.flight,Vector3.ONE,1.0)
			var grip: Vector3=throttle.transform*Vector3(0,0.148,0)
			check(grip.z> -1.05 and grip.y> -0.64,"Throttle grip clears panel and console through full travel")
	if "--visual" in OS.get_cmdline_user_args():
		var folder: String=ProjectSettings.globalize_path("res://../docs/screenshots/urban")
		DirAccess.make_dir_recursive_absolute(folder)
		for shot in [
			{"name":"departure-neighborhood","eye":Vector3(2200,310,-1800),"target":Vector3(1300,10,450)},
			{"name":"cockpit","eye":Vector3(0,3,1000),"target":Vector3(0,3,-2000)},
			{"name":"airport-city","eye":Vector3(-900,450,1800),"target":Vector3(300,30,-1900)},
			{"name":"urban-skyline","eye":Vector3(-2400,420,-3800),"target":Vector3(-1000,80,-1500)},
			{"name":"city-scale","eye":Vector3(-3000,1500,2300),"target":Vector3(1800,30,-6500)}]:
			app.flight.position=shot.eye
			app.flight.heading=0; app.flight.pitch=0; app.flight.roll=0
			app.flight.speed=0; app.flight.throttle=0.6
			app.cockpit=shot.name=="cockpit"
			app.apply_aircraft_pose(); app.camera_rig.reset(); app._process(0.1)
			app.hud.visible=app.cockpit
			if not app.cockpit:
				app.aircraft.visible=false
				app.camera.position=shot.eye; app.camera.look_at(shot.target)
			for i in range(20): await process_frame
			var frame_times: Array[float]=[]
			for i in range(90):
				var start: int=Time.get_ticks_usec()
				await process_frame
				frame_times.append((Time.get_ticks_usec()-start)/1000.0)
			frame_times.sort()
			print("URBAN FRAME MS ",shot.name," median=",frame_times[45]," p95=",frame_times[85]," max=",frame_times[-1])
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+shot.name+".png")
	print("URBAN RESULT: ","PASS" if failures.is_empty() else "FAIL", " buildings=",city.stats.buildings," area=",city.footprint_km2," batches=",city.get_child_count())
	print("NEIGHBORHOODS: residential=",city.connected_blocks," office=",city.office_blocks," industrial=",city.industrial_blocks," park=",city.park_blocks," traffic departure/arrival=",departure_traffic,"/",arrival_traffic)
	for failure in failures.slice(0,10): printerr(failure)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
