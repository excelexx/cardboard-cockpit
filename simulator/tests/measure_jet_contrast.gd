extends SceneTree
# Measures how well the jet reads from the chase camera over different grounds.
# Each case is rendered twice (jet shown, jet hidden); the pixels that differ are the jet.
# Reports the jet's mean luminance, its spread (form: a flat cut-out has almost none) and
# the contrast against the ground right around it. PNGs land in build/contrast/.
# Usage: Godot --path simulator --windowed --resolution 1600x1000 --script tests/measure_jet_contrast.gd
var app: Node3D
func _initialize() -> void:call_deferred("run")
func luminance(c: Color) -> float:return 0.2126*c.r+0.7152*c.g+0.0722*c.b
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name()=="headless":printerr("Native GPU required");quit(2);return
	var folder:=ProjectSettings.globalize_path("res://../build/contrast")
	DirAccess.make_dir_recursive_absolute(folder)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	for i in 30:await process_frame
	app.audio.muted=true;app.set_quality(true);app.capture_file="review"
	# name, position, heading, speed, gear down
	var cases:=[["runway",Vector3(0,0,0),0.0,0.0,true],["coast",Vector3(-3600,420,-9600),0.35,300.0,false],["water",Vector3(-9000,300,-9000),-1.2,300.0,false],["hills",Vector3(-4200,420,-8300),0.7,300.0,false],["city",Vector3(15400,430,-10500),-0.35,300.0,false]]
	for entry in cases:
		app.set_process(false);app.set_physics_process(false)
		app.start_flight("demo" if entry[0]=="runway" else "combat");app.copilot=false;app.cockpit=false;app.text_hud=true
		if entry[0]!="runway":
			app.flight.spawn_airborne(entry[1],entry[3]);app.flight.gear=false;app.flight.throttle=.6
			app.flight.heading=entry[2]
		app.apply_aircraft_pose();app.combat.spawn_clock=999
		app.camera_rig.reset()
		var began:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-began<(7000 if entry[0]!="runway" else 4000):
			var dt: float=minf(app.get_process_delta_time(),.05)
			if entry[0]!="runway":app.flight.step(dt,Vector3.ZERO,false,0,false);app.apply_aircraft_pose()
			app._process(dt)
			await process_frame
		app.hud.visible=false
		for i in 3:await process_frame
		var shown: Image=await grab()
		app.aircraft.visible=false;app.fighter_fx.visible=false
		for i in 3:await process_frame
		var hidden: Image=await grab()
		# The mask: the airframe alone, painted flat magenta, so animated water cannot pollute it.
		app.aircraft.visible=true
		var paint:=StandardMaterial3D.new();paint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;paint.albedo_color=Color(1,0,1)
		var parts: Array=app.aircraft.find_children("*","GeometryInstance3D",true,false)
		var before:=[]
		for part: GeometryInstance3D in parts:before.append(part.material_override);part.material_override=paint
		for i in 3:await process_frame
		var keyed: Image=await grab()
		for i in parts.size():parts[i].material_override=before[i]
		app.fighter_fx.visible=true;app.hud.visible=true
		shown.save_png(folder+"/"+entry[0]+".png")
		var w:=shown.get_width();var h:=shown.get_height()
		var step:=2
		var jet_sum:=0.0;var jet_sq:=0.0;var jet_n:=0;var minx:=w;var maxx:=0;var miny:=h;var maxy:=0
		var mask:={}
		for y in range(0,h,step):
			for x in range(0,w,step):
				var k:=keyed.get_pixel(x,y)
				if k.r-k.g>0.22 and k.b-k.g>0.18:
					var l:=luminance(shown.get_pixel(x,y));jet_sum+=l;jet_sq+=l*l;jet_n+=1;mask[Vector2i(x,y)]=true
					minx=mini(minx,x);maxx=maxi(maxx,x);miny=mini(miny,y);maxy=maxi(maxy,y)
		if jet_n<50:print("CONTRAST ",entry[0]," jet not found");continue
		var pad:=int((maxx-minx)*0.18)
		var ground_sum:=0.0;var ground_n:=0
		for y in range(maxi(0,miny-pad),mini(h,maxy+pad),step):
			for x in range(maxi(0,minx-pad),mini(w,maxx+pad),step):
				if mask.has(Vector2i(x,y)):continue
				ground_sum+=luminance(hidden.get_pixel(x,y));ground_n+=1
		var jet_mean:=jet_sum/jet_n;var spread:=sqrt(maxf(0.0,jet_sq/jet_n-jet_mean*jet_mean));var ground:=ground_sum/maxf(ground_n,1)
		var ratio:=(maxf(jet_mean,ground)+0.05)/(minf(jet_mean,ground)+0.05)
		shown.get_region(Rect2i(maxi(0,minx-pad),maxi(0,miny-pad),mini(w,maxx+pad)-maxi(0,minx-pad),mini(h,maxy+pad)-maxi(0,miny-pad))).save_png(folder+"/"+entry[0]+"_crop.png")
		print("CONTRAST ",entry[0]," jet=",snappedf(jet_mean,0.001)," spread=",snappedf(spread,0.001)," ground=",snappedf(ground,0.001)," ratio=",snappedf(ratio,0.01)," jet_px=",jet_n*step*step)
	quit()
