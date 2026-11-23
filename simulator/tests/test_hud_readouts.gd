extends SceneTree
## Headless gate for the HUD package. hud._draw() never runs under --headless,
## so every readout that can be wrong in a way a player would notice is written
## as a pure function in ui/hud.gd and driven from here.
##   Godot --headless --path simulator --script tests/test_hud_readouts.gd
const HUD = preload("res://ui/hud.gd")
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
const Tune = preload("res://data/balance.gd")

var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("HUD READOUT FAIL: "+label)

class FakeMission extends RefCounted:
	var active := true
	var cinematic := true
	var phase := "combat"
	var clock := 0.0
class FakeApp extends Node:
	var mission: Variant = FakeMission.new()
	var combat: CombatDirector
	var flight_kind := "combat"
## Stands in for the skein bookkeeping the combat package publishes.
class SkeinDirector extends CombatDirector:
	var skein_total := 12
	var skein_down := 0
	var skein_ids: Array = []
	func skein_remaining() -> int: return maxi(0,skein_total-skein_down)
## The same bookkeeping without the method scenes/main.gd prefers.
class FieldOnlyDirector extends CombatDirector:
	var skein_total := 12
	var skein_down := 5
## How systems/demo_mission.gd keeps the flock: a method for the size, a field
## for the count down, and nothing at all before the skein opens.
class FlockMission extends RefCounted:
	var active := true
	var cinematic := true
	var phase := "skein"
	var clock := 0.0
	var size := 0
	var skein_down := 0
	func skein_total() -> int: return size
	func skein_remaining() -> int: return maxi(0,size-skein_down)
	func skein_has(id: int) -> bool: return id==3

func flight(airspeed: float,height: float) -> FlightDynamics:
	var f: FlightDynamics = Dynamics.new()
	f.reset(Catalog.PROFILE)
	f.spawn_airborne(Vector3(0,height,0),airspeed)
	return f

func _initialize() -> void:
	# Opt-in look pass for the panoramic cockpit display, which no headless run can
	# draw and which the review harness cannot feed a skein to until the combat
	# package publishes one. Native GPU only:
	#   Godot --path simulator --windowed --resolution 1638x650 \
	#     --script tests/test_hud_readouts.gd -- capture
	if "capture" in OS.get_cmdline_user_args():
		call_deferred("capture_run")
		return
	if "hudshot" in OS.get_cmdline_user_args():
		call_deferred("hud_shot_run")
		return
	call_deferred("run")

## Look pass for the flight HUD over the real world, so the aim point can be
## judged on what it actually draws. Native GPU only:
##   Godot --path simulator --windowed --resolution 1600x1000 \
##     --script tests/test_hud_readouts.gd -- hudshot
## Saves the frame and a 2.5x blow-up of the aim point, which is where every
## finding in this pass lives and which no full-frame thumbnail can settle.
func save_shot(folder: String,name: String,app: Node3D) -> void:
	var shot: Image = root.get_texture().get_image()
	shot.save_png(folder+"/"+name+".png")
	var window: Vector2i = shot.get_size()
	# Centre the blow-up on the gunsight, not on the window, and take it tall
	# enough to hold the flight-path marker when alpha carries it below.
	var aim := Vector2(float(window.x)/2.0,float(window.y)/2.0)
	var nose := aim
	var at: Vector2 = HUD.OFFSCREEN
	if app!=null and app.camera.is_inside_tree():
		var point: Vector3 = app.flight.position+app.combat.forward()*2000.0
		if not app.camera.is_position_behind(point): nose = app.camera.unproject_position(point)
		aim = app.camera.unproject_position(app.combat.reticle_point())
		at = HUD.fpm_screen_point(app.flight,app.camera)
	var seen: float = HUD.fpm_opacity(at,aim,nose,60.0)
	print("   sight=",aim," marker=",at," visible=",seen)
	# Frame the gunsight AND the marker, so the two silhouettes are judged together.
	var focus: Vector2 = aim if seen<=0.0 else (aim+at)*0.5
	var reach: float = 0.0 if seen<=0.0 else aim.distance_to(at)*0.5
	var half: float = maxf(150.0,reach+110.0)
	var box := Rect2i(int(focus.x-half*1.2),int(focus.y-half),int(half*2.4),int(half*2.0))
	var zoom: Image = shot.get_region(box.intersection(Rect2i(Vector2i.ZERO,window)))
	if zoom.get_width()<2 or zoom.get_height()<2: return
	var scale: int = clampi(900/maxi(zoom.get_width(),1),1,4)
	if scale>1: zoom.resize(zoom.get_width()*scale,zoom.get_height()*scale,Image.INTERPOLATE_NEAREST)
	zoom.save_png(folder+"/"+name+"_zoom.png")

func hud_shot_run() -> void:
	if DisplayServer.get_name()=="headless": printerr("Native GPU required"); quit(2); return
	var folder: String = ProjectSettings.globalize_path("res://../build/p5_hud")
	DirAccess.make_dir_recursive_absolute(folder)
	var app: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	for i in 30: await process_frame
	app.audio.muted = true
	app.capture_file = "review"   # an unfocused capture window must not auto-pause
	app.set_quality(true)
	app.on_action("guided")
	var began: int = Time.get_ticks_msec()
	for mark: Array in [[15.0,"fix_chase_level",false,false],[31.0,"fix_chase_turn",false,false],[46.0,"fix_cockpit_turn",true,false],[54.0,"fix_chase_slow",false,true]]:
		while (Time.get_ticks_msec()-began)/1000.0<float(mark[0]):
			if app.mode=="paused": app.mode = app.resume_mode
			await process_frame
		if bool(mark[2])!=bool(app.cockpit):
			app.cockpit = bool(mark[2]); app.camera_rig.reset()
			for i in 14: await process_frame
		if bool(mark[3]): app.flight.stall_time = 1.2
		await process_frame
		await RenderingServer.frame_post_draw
		save_shot(folder,str(mark[1]),app)
		print("HUD SHOT ",mark[1]," phase=",app.mission.phase," aoa=",app.flight.aoa," share=",app.flight.aoa/Dynamics.ALPHA_MAX," fps=",Engine.get_frames_per_second())
	# A hard pull: the one flight state where the path really does leave the
	# boresight, so the marker has to be there and has to read as its own symbol.
	var wait: int = Time.get_ticks_msec()
	while absf(app.flight.g_load)<3.2 and (Time.get_ticks_msec()-wait)/1000.0<40.0:
		if app.mode=="paused": app.mode = app.resume_mode
		await process_frame
	await RenderingServer.frame_post_draw
	save_shot(folder,"fix_chase_pull",app)
	print("HUD SHOT fix_chase_pull g=",app.flight.g_load," aoa=",app.flight.aoa)
	# Landing: gear and flaps hold real alpha, so the marker is up where the
	# player is told to sit it on the runway numbers.
	app.start_flight("approach")
	app.copilot = true; app.used_copilot = true
	began = Time.get_ticks_msec()
	while (Time.get_ticks_msec()-began)/1000.0<26.0:
		if app.mode=="paused": app.mode = app.resume_mode
		await process_frame
	await RenderingServer.frame_post_draw
	save_shot(folder,"fix_approach_marker",app)
	print("HUD SHOT fix_approach_marker aoa=",app.flight.aoa," gear=",app.flight.gear," alt=",app.flight.position.y)
	# Free-flight combat: nobody keeps a skein here, so the objective bar must
	# not draw at all. Before this pass it advertised a skein that never spawns.
	app.cockpit = false
	app.start_flight("combat")
	began = Time.get_ticks_msec()
	while (Time.get_ticks_msec()-began)/1000.0<7.0:
		if app.mode=="paused": app.mode = app.resume_mode
		await process_frame
	await RenderingServer.frame_post_draw
	save_shot(folder,"fix_freeflight_no_objective",app)
	print("HUD SHOT freeflight mission.active=",app.mission.active," tally=",HUD.skein_tally(app.hud.objective_source()))
	quit(0)

func capture_run() -> void:
	if DisplayServer.get_name()=="headless": printerr("Native GPU required"); quit(2); return
	var folder: String = ProjectSettings.globalize_path("res://../build/p5_hud")
	DirAccess.make_dir_recursive_absolute(folder)
	var panel: CockpitInstruments = load("res://ui/cockpit_instruments.gd").new()
	panel.display_mode = "panorama"
	panel.size = Vector2(1638,650)
	root.add_child(panel)
	var f: FlightDynamics = flight(220.0,400.0)
	f.throttle = 0.8; f.engine = 0.8; f.gear = false
	for frame: Array in [["panorama_cruise",1.1,0.62,false],["panorama_fight",5.4,0.94,true]]:
		f.g_load = frame[1]; f.mach = frame[2]; f.stall_time = 1.0 if frame[3] else 0.0
		panel.update_flight(f,1.0)
		panel.stall = bool(frame[3])
		panel.tactical = {"gun":true,"missiles":bool(frame[3]),"tracking":true,"lock":1.0 if frame[3] else 0.55,
			"contacts":[Vector3(420,-780,1),Vector3(-1100,520,0),Vector3(260,900,0)],"skein":Vector2(7,12),
			"waypoint":Vector2(1400,-900),"damaged":false,"objective":"Clear the skein","clock":"1:12"}
		panel.queue_redraw()
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+str(frame[0])+".png")
		print("CAPTURED ",frame[0])
	quit(0)

func run() -> void:
	objective()
	copy()
	airspeed()
	marker()
	aim_point()
	stall_copy()
	sources()
	print("HUD READOUTS: ",checks," checks / failures ",failures.size())
	for line: String in failures: print("  FAIL: ",line)
	quit(0 if failures.is_empty() else 1)

## GOAL 1: the objective is how much of the skein is down, never a health bar.
func objective() -> void:
	var c: SkeinDirector = SkeinDirector.new()
	check(HUD.objective_fraction(c)==0.0,"Objective reads empty with no birds down")
	c.skein_down = 6
	check(is_equal_approx(HUD.objective_fraction(c),0.5),"Half a skein down is half the bar")
	c.skein_down = 12
	check(HUD.objective_fraction(c)==1.0,"A cleared skein fills the bar")
	c.skein_down = 40
	check(HUD.objective_fraction(c)==1.0,"Overkill cannot drive the bar past full")
	check(HUD.skein_tally(c)==Vector2(12,12),"The tally clamps to the size of the skein")
	c.skein_total = 0
	check(HUD.objective_fraction(c)==0.0 and HUD.skein_tally(c)==Vector2.ZERO,"No skein means no bar and no divide by zero")
	check(HUD.objective_fraction(null)==0.0,"A missing combat director reads zero, not an error")
	# Nobody keeping a flock means NO objective bar. The tally must never invent
	# a skein out of the kill count against the designed size: free-flight combat
	# never spawns one, and "GEESE 3 / 12" for birds that will not arrive is a
	# false objective on the most-read line of the HUD.
	var plain: CombatDirector = CombatDirector.new()
	plain.kills = 3
	check(HUD.skein_tally(plain)==Vector2.ZERO,"With no skein size at all there is no bar, whatever the kill count")
	check(HUD.objective_fraction(plain)==0.0,"A kill count alone never fills the objective bar")
	plain.kills = int(Tune.SKEIN_SIZE)+4
	check(HUD.skein_tally(plain)==Vector2.ZERO,"Even a full sortie of kills invents no skein")
	check(HUD.skein_ids(plain).is_empty(),"Skein ids are empty, not an error, before the combat package lands them")
	var fields: FieldOnlyDirector = FieldOnlyDirector.new()
	check(HUD.skein_tally(fields)==Vector2(5,12),"A plain skein_down field reads too")
	fields.free()
	var flock := FlockMission.new()
	check(HUD.skein_tally(flock)==Vector2.ZERO,"Before the flock opens there is no objective bar")
	flock.size = 12
	check(HUD.skein_tally(flock)==Vector2(0,12),"The bar opens empty at the size of the flock")
	flock.skein_down = 7
	check(HUD.skein_tally(flock)==Vector2(7,12) and is_equal_approx(HUD.objective_fraction(flock),7.0/12.0),"Seven birds down is seven pips")
	plain.free()
	c.free()

## GOAL 1: no boss copy survives anywhere in this package.
func copy() -> void:
	var hud: CockpitHUD = HUD.new()
	var app := FakeApp.new()
	app.combat = CombatDirector.new()
	hud.app = app
	root.add_child(app)
	app.mission.phase = "gather"
	check(hud.mission_line()=="A skein is inbound","The gather phase tells the player a skein is inbound")
	app.mission.phase = "skein"
	check(hud.mission_line()=="Clear the skein","The skein phase tells the player to clear it")
	for phase: String in ["opening","combat","gather","skein","aftermath","approach","rollout","anticipation","boss","takeoff","return",""]:
		app.mission.phase = phase
		var line: String = hud.mission_line().to_lower()
		check(not line.contains("boss") and not line.contains("mother goose"),"Phase '%s' never names a boss" % phase)
		app.mission.cinematic = false
		check(not hud.mission_line().to_lower().contains("boss"),"Free-flight phase '%s' never names a boss" % phase)
		app.mission.cinematic = true
	app.mission.phase = "skein"
	app.mission.clock = 30.0
	check(hud.clock_text()=="%d:%02d" % [int(Tune.DEMO_LIMIT-30)/60,int(Tune.DEMO_LIMIT-30)%60],"The mission clock counts the showcase down")
	app.mission.active = false
	check(hud.clock_text()!="","A free-flight sortie still shows time left")
	check(hud.thousands(23400)=="23,400" and hud.thousands(-940)=="-940","Altitudes group in thousands")
	check(hud.has_method("draw_objective") and not hud.has_method("draw_boss"),"The objective bar replaced the boss bar")
	# Whoever is keeping the flock feeds the bar, and the scope marks its birds.
	check(hud.objective_source()==app.combat,"With no flock mission the objective follows the combat director")
	check(not hud.marked(7),"A contact nobody claims is not part of the skein")
	var flock := FlockMission.new()
	flock.size = 12; flock.skein_down = 4
	app.mission = flock
	check(hud.objective_source()==flock,"A running flock mission owns the objective")
	check(HUD.skein_tally(hud.objective_source())==Vector2(4,12),"The bar reads the mission's own count")
	check(hud.marked(3) and not hud.marked(9),"The scope marks the mission's skein and nothing else")
	flock.active = false
	check(hud.objective_source()==app.combat,"A finished mission hands the objective back")
	app.combat.free()
	root.remove_child(app)
	app.free()
	hud.free()

## GOAL 4: the number captioned KNOTS is an airspeed, not a ground speed.
func airspeed() -> void:
	var sea: FlightDynamics = flight(180.0,0.0)
	check(absf(HUD.cas_knots(sea)-sea.speed*1.94384)<0.5,"At sea level calibrated airspeed matches the true speed")
	var high: FlightDynamics = flight(180.0,6000.0)
	check(HUD.cas_knots(high)<high.speed*1.94384-10.0,"At 6000 m the indicator reads well below the ground speed")
	var showcase: FlightDynamics = flight(180.0,400.0)
	check(HUD.cas_knots(showcase)<showcase.speed*1.94384,"At showcase height the indicator is honest about the air")
	check(HUD.cas_knots(high)<HUD.cas_knots(showcase),"Calibrated airspeed falls as the air thins")
	check(HUD.cas_knots(null)==0.0,"A missing flight model reads zero, not an error")

## GOAL 3: the flight-path marker never flies across the screen.
func marker() -> void:
	var f: FlightDynamics = flight(180.0,600.0)
	check(HUD.fpm_screen_point(f,null)==HUD.OFFSCREEN,"No camera is a sentinel, not garbage")
	var camera := Camera3D.new()
	check(HUD.fpm_screen_point(f,camera)==HUD.OFFSCREEN,"A camera outside the tree is a sentinel, not garbage")
	root.add_child(camera)
	camera.global_position = f.position
	camera.look_at(f.position+f.velocity.normalized(),Vector3.UP)
	var ahead: Vector2 = HUD.fpm_screen_point(f,camera)
	check(ahead!=HUD.OFFSCREEN,"Looking along the flight path puts the marker on the screen")
	check(is_finite(ahead.x) and is_finite(ahead.y),"The marker point is a real screen position")
	camera.look_at(f.position-f.velocity.normalized(),Vector3.UP)
	check(HUD.fpm_screen_point(f,camera)==HUD.OFFSCREEN,"With the flight path behind the camera the marker is dropped")
	var parked: FlightDynamics = Dynamics.new()
	parked.reset(Catalog.PROFILE)
	check(HUD.fpm_screen_point(parked,camera)==HUD.OFFSCREEN,"A stationary jet has no flight path to mark")
	camera.free()

## GOAL 3: the marker never sits on the aim point and is never pinned to an edge.
func aim_point() -> void:
	var aim := Vector2(800,450)
	var radius := 60.0
	check(HUD.fpm_opacity(aim,aim,aim,radius)==0.0,"On the gunsight the marker is gone, not a second ring")
	check(HUD.fpm_opacity(aim+Vector2(HUD.SIGHT_REACH,0),aim,aim,radius)==0.0,"Touching the gunsight cross the marker is still gone")
	var clear: Vector2 = aim+Vector2(HUD.SIGHT_REACH+HUD.FPM_SPAN+HUD.FPM_FADE+1.0,0)
	check(HUD.fpm_opacity(clear,aim,aim,radius)==1.0,"Well clear of the gunsight the marker is fully drawn")
	var previous := -1.0
	for step in range(13):
		var at: Vector2 = aim+Vector2(float(step)*10.0,0)
		var seen: float = HUD.fpm_opacity(at,aim,aim,radius)
		check(seen>=previous,"The marker only ever fades UP as it leaves the aim point (%d px)" % (step*10))
		previous = seen
	# The nose ring counts as the aim point too, and the wider ring pushes the
	# marker further out before it is allowed to show.
	check(HUD.fpm_opacity(clear,Vector2(200,850),aim,radius)==1.0,"Clear of the nose ring the marker shows")
	check(HUD.fpm_opacity(clear,Vector2(200,850),aim,200.0)==0.0,"A wide nose ring keeps the marker suppressed further out")
	# Off-boresight it is DROPPED, never pinned to the border.
	for outside: Vector2 in [Vector2(60,450),Vector2(1560,450),Vector2(800,60),Vector2(800,960),HUD.OFFSCREEN]:
		check(HUD.fpm_opacity(outside,aim,aim,radius)==0.0,"Outside the HUD box the marker is dropped, not clamped to %s" % str(outside))
	check(HUD.FPM_BOX.has_point(Vector2(141,171)) and HUD.FPM_BOX.has_point(Vector2(1459,689)),"The marker box is the old clamp rectangle")
	# No on-speed indexer survives: it was inert across the band the jet flies.
	var hud: CockpitHUD = HUD.new()
	check(not hud.has_method("aoa_bracket_gap"),"The inert on-speed indexer is gone, not just shrunk")
	hud.free()

## PLAYABILITY GUARD: stall is a pure airspeed test in the flight model, so the
## banner names the speed and gives the recovery that works.
func stall_copy() -> void:
	var f: FlightDynamics = flight(180.0,600.0)
	var alpha: float = Dynamics.ALPHA_REF
	check(alpha/Dynamics.ALPHA_MAX<0.1,"Cruise alpha really is a tiny share of the drawn limit")
	check(f.get("aoa")!=null and f.get("pitch")!=null,"The flight model publishes aoa and pitch")
	var model: String = FileAccess.get_file_as_string("res://systems/flight_dynamics.gd")
	check(model.contains("stall_time = stall_time+dt if lift<0.85 else 0"),"stall_time still comes from lift, i.e. from airspeed alone")
	for path: String in ["res://ui/hud.gd","res://ui/cockpit_instruments.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		check(text.contains("TOO SLOW"),"%s says TOO SLOW" % path)
		check(not text.to_upper().contains("NOSE TOO HIGH") and not text.to_upper().contains("NOSE HIGH"),"%s never blames the nose for an airspeed cue" % path)
		check(not text.contains("Ease off"),"%s never says the ambiguous 'Ease off'" % path)
	check(FileAccess.get_file_as_string("res://ui/hud.gd").contains("Nose down, add power"),"The HUD gives the recovery that works")

## The grep the audit asks for, kept as a test so it cannot rot.
func sources() -> void:
	for path: String in ["res://ui/hud.gd","res://ui/cockpit_instruments.gd"]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		check(not text.contains("boss"),"%s mentions no boss anywhere" % path)
		check(not text.contains("mother goose"),"%s names no individual goose" % path)
	check(not FileAccess.get_file_as_string("res://ui/hud.gd").contains("max_health"),"No per-goose health bar is left in the HUD")
