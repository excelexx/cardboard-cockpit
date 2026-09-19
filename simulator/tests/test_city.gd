extends SceneTree
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func run() -> void:
	var app=load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","coast"); root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted=true
	app.on_action("guided")
	app.capture_file="city-review"
	var city: Node3D=app.world.metropolis
	check(app.world.village_home_count==60,"Five countryside settlements contain sixty assembled homes")
	if city.photo_tiles>0:
		check(city.photo_tiles==128,"Both photograph-derived districts are loaded completely")
		check(city.photo_tiles<=256,"Photogrammetry remains bounded")
		check(not city.obstacles.is_empty(),"Imported city has collision coverage")
		check(city.has_method("_build_photographic_district"),"Photographic district replaces generated grid")
	else:
		check(city.stats.buildings>250 and city.stats.buildings<500,"Bounded authored waterfront districts")
		check(city.stats.detailed_buildings>=15,"Imported apartment and factory architecture is placed")
		check(city.stats.trees>500,"Parks and avenues have tree cover")
		check(city.stats.roads_km>25,"Districts have a connected road network")
	check(city.get_child_count()<700,"Geometry uses bounded batches instead of one node per object")
	var ground_samples:=0
	var intersections:=0
	for tile in city.get_children():
		if not tile.get_meta("photogrammetry_base",false): continue
		for mesh in tile.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for i in range(0,vertices.size(),16):
					var point: Vector3=mesh.global_transform*vertices[i]
					ground_samples+=1
					if point.y<app.world.ground_height(point.x,point.z)-0.2:
						intersections+=1
						if intersections<=8: print("INTRUSION ",point," terrain=",app.world.ground_height(point.x,point.z))
	print("PHOTO GROUND SAMPLES ",ground_samples," intrusions=",intersections)
	check(intersections==0,"Underlying terrain does not cut through photographic city surfaces")
	if city.photo_tiles>0:
		check(city.photo_detail_tiles==256,"All high-detail district tiles are present")
		for group in city.photo_lod_groups.values():
			check(group.high.size()==4,"Each coarse tile has its complete four-tile refinement")
	var bounds: AABB=city.obstacles.values()[0][0]
	check(city.collides(bounds.get_center(),2),"Building contact is registered")
	check(not city.collides(Vector3(0,1000,-5600),2),"Cruise altitude is clear")
	for z in range(-1600,1700,200):
		check(not city.collides(Vector3(0,3,z),10),"Departure runway clear")
		check(not city.collides(Vector3(0,3,z-15000),10),"Arrival runway clear")
	if "--visual" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		var destination: String=ProjectSettings.globalize_path("res://../docs/screenshots/city")
		DirAccess.make_dir_recursive_absolute(destination)
		app.world.set_conditions("golden")
		var shots: Array[Dictionary]=[
			{"name":"kominka-detail","eye":Vector3(1715,31,-2500),"target":Vector3(1750,17,-2580)},
			{"name":"coastal-village","eye":Vector3(1600,75,-2350),"target":Vector3(1750,17,-2650)},
			{"name":"country-panorama","eye":Vector3(800,300,-7700),"target":Vector3(2050,15,-8600)},
			{"name":"airport-grounding","eye":Vector3(-230,145,1000),"target":Vector3(410,5,100)},
			{"name":"metropolitan-overview","eye":Vector3(-1300,1200,-2200),"target":Vector3(1300,0,-5200)},
			{"name":"downtown-waterfront","eye":Vector3(200,450,-3800),"target":Vector3(1550,60,-5100)},
			{"name":"neighbourhoods","eye":Vector3(2700,520,-1700),"target":Vector3(2200,0,-3300)},
			{"name":"city-cockpit","eye":Vector3(-1300,360,-5450),"target":Vector3(500,200,-6500)}
		]
		for shot in shots:
			if "--countryside" in OS.get_cmdline_user_args() and shot.name not in ["kominka-detail","coastal-village","country-panorama"]: continue
			app.flight.position=shot.eye
			app.flight.airborne=true
			app.flight.speed=110
			app.flight.heading=atan2(shot.target.x-shot.eye.x,shot.eye.z-shot.target.z)
			app.flight.pitch=-0.04
			app.mission.route_index=4
			app.mission.phase="combat"
			app.cockpit = shot.name=="city-cockpit"
			app.apply_aircraft_pose(); app.camera_rig.reset()
			app._process(1.0/60.0)
			if shot.name!="city-cockpit":
				app.aircraft.visible=false
				app.hud.visible=false
				app.camera.position=shot.eye
				app.camera.look_at(shot.target)
				app.camera.fov=65
			else: app.hud.visible=true
			if shot.name=="city-cockpit":
				for lever: Node3D in app.cockpit_frame.throttles:
					var grip: Vector3=lever.to_global(Vector3(0,0.159,0))
					var projected: Vector2=app.camera.unproject_position(grip)
					check(not app.camera.is_position_behind(grip),"Throttle is in front of the pilot")
					check(Rect2(Vector2(40,40),Vector2(root.size)-Vector2(80,80)).has_point(projected),"Throttle grip fits inside default cockpit view")
			for i in range(12):
				RenderingServer.force_draw()
				await process_frame
			var started: int=Time.get_ticks_msec()
			for i in range(30):
				RenderingServer.force_draw()
				await process_frame
			var seconds: float=(Time.get_ticks_msec()-started)/1000.0
			print("CITY RENDER ",shot.name," fps=",30/maxf(seconds,0.001)," objects=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)," draw_calls=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(destination+"/"+shot.name+".png")
	for failure in failures: printerr("CITY FAIL: ",failure)
	print("CITY RESULT: ",checks-failures.size(),"/",checks)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
