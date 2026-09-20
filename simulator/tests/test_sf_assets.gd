extends SceneTree
const SanFrancisco := preload("res://scenes/san_francisco_world.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	# Capture modes are a design review, not a regression run: they skip the
	# asset assertions so the window is not held for two minutes of texture loads.
	if DisplayServer.get_name()!="headless":
		if "--world" in OS.get_cmdline_user_args():
			await capture_world(); quit(0); return
		if "--visual" in OS.get_cmdline_user_args():
			await capture(); quit(0); return
	var source := "res://assets/san_francisco/"
	var vegetation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"trees.json"))
	var points := FileAccess.get_file_as_bytes(source+"tree_positions.f32").to_float32_array()
	if points.size()!=int(vegetation.count)*3: failures.append("Tree coordinate stream length does not match the index")
	for chunk: Dictionary in vegetation.chunks:
		if int(chunk.offset)+int(chunk.count)*3>points.size(): failures.append("Tree chunk exceeds the coordinate stream")
	var photos: Array = JSON.parse_string(FileAccess.get_file_as_string(source+"aerial/manifest.json"))
	for photo: Dictionary in photos:
		var path := source+"aerial/"+str(photo.tile)+".jpg"
		var image: Texture2D = load(path)
		if image==null or image.get_width()!=4000 or image.get_height()!=2000: failures.append("Missing or invalid original aerial image: "+path)
		var scene: Node3D = load(source+"terrain_"+str(photo.tile)+".scn").instantiate()
		var photographed := false
		for geometry in scene.find_children("*","MeshInstance3D",true,false):
			for i in range(geometry.mesh.get_surface_count()):
				var material = geometry.mesh.surface_get_material(i)
				if material is StandardMaterial3D and material.albedo_texture!=null and material.albedo_texture.resource_path==path: photographed=true
		if not photographed: failures.append("Photo is not bound to its terrain: "+str(photo.tile))
		scene.free()
	var downtown: Node3D = load(source+"city_w130n30_w123n37_942066b000.scn").instantiate()
	var mesh: Mesh = downtown.find_children("*","MeshInstance3D",true,false)[0].mesh
	var imported := ImporterMesh.from_mesh(mesh)
	if imported.get_surface_lod_count(0)<1: failures.append("Downtown is missing distance detail levels")
	if mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()<1000000: failures.append("Full-detail downtown source geometry was removed")
	downtown.free()

	# --- The Golden Gate wears International Orange, not salmon ----------------
	var bridge: Node3D = load(source+"landmark_ggb-fb.scn").instantiate()
	var painted := 0
	var dominant := 0
	var dominant_colour := Color.BLACK
	for geometry in bridge.find_children("*","MeshInstance3D",true,false):
		for i in range(geometry.mesh.get_surface_count()):
			var material = geometry.mesh.surface_get_material(i)
			if not (material is StandardMaterial3D): continue
			if not SanFrancisco.wears_international_orange(material): continue
			painted += 1
			var triangles: int = geometry.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()/3
			if triangles>dominant:
				dominant = triangles
				var value: float = clampf(material.albedo_color.v/0.9234,0.55,1.0)
				dominant_colour = Color(SanFrancisco.INTERNATIONAL_ORANGE.r*value,SanFrancisco.INTERNATIONAL_ORANGE.g*value,SanFrancisco.INTERNATIONAL_ORANGE.b*value)
	bridge.free()
	if painted!=2: failures.append("Golden Gate repaint selector picked "+str(painted)+" surfaces, expected the 2 structural ones")
	var target: Color = SanFrancisco.INTERNATIONAL_ORANGE
	if absf(dominant_colour.r-target.r)>0.1 or absf(dominant_colour.g-target.g)>0.1 or absf(dominant_colour.b-target.b)>0.1:
		failures.append("Golden Gate dominant surface is not International Orange: "+str(dominant_colour))

	# --- The relief shader is gated on each surface's own UV extent ------------
	var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"region.json"))
	var eligible := 0
	var clamped := 0
	var ksfo_eligible := 0
	var ksfo_clamped := 0
	for item: Dictionary in region.chunks:
		if item.kind!="terrain": continue
		var node: Node3D = load(source+str(item.file)).instantiate()
		for geometry in node.find_children("*","MeshInstance3D",true,false):
			for i in range(geometry.mesh.get_surface_count()):
				var material = geometry.mesh.surface_get_material(i)
				if not (material is StandardMaterial3D) or material.roughness<0.4 or material.albedo_texture==null: continue
				var ok: bool = SanFrancisco.relief_eligible(geometry.mesh,i)
				if ok: eligible += 1
				else: clamped += 1
				if str(item.file)=="terrain_KSFO.scn":
					if ok: ksfo_eligible += 1
					else: ksfo_clamped += 1
		node.free()
	if eligible!=450: failures.append("Aerial photo surfaces receiving the relief shader changed: "+str(eligible)+" (expected 450)")
	if clamped!=315: failures.append("Tiled surfaces left on their original material changed: "+str(clamped)+" (expected 315)")
	if ksfo_eligible!=20: failures.append("KSFO correctly-UV'd surfaces changed: "+str(ksfo_eligible)+" (expected surf0-19)")
	if ksfo_clamped!=13: failures.append("KSFO tiled surfaces surf20-32 must keep their StandardMaterial3D: "+str(ksfo_clamped))

	# --- 28R carries approach, runway and PAPI lighting -----------------------
	var world: Node3D = SanFrancisco.new()
	root.add_child(world)
	await process_frame
	var lights = world.runway_lights
	if lights==null:
		failures.append("Runway lighting was not built")
	else:
		if lights.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: failures.append("Runway lights must not cast shadows")
		if not is_finite(lights.visibility_range_end) or lights.visibility_range_end<=0.0: failures.append("Runway lights need a finite visibility range")
		if lights.multimesh==null or lights.multimesh.instance_count<600: failures.append("Runway lighting is too sparse: "+str(0 if lights.multimesh==null else lights.multimesh.instance_count))
		if lights.papi_first<0: failures.append("PAPI boxes are missing")
		else:
			# Headless cannot read MultiMesh colours back, so assert the decision
			# the renderer is handed: low is four red, high is four white, and the
			# three-degree path itself is the canonical two white over two red.
			var on_path := Vector3(0,lights.papi_height+1300.0*tan(deg_to_rad(3.0)),lights.PAPI_Z+1300.0)
			var reading := [lights.papi_white(0,on_path),lights.papi_white(1,on_path),lights.papi_white(2,on_path),lights.papi_white(3,on_path)]
			if reading!=[true,true,false,false]: failures.append("PAPI is not two white over two red on the 3.00 degree path: "+str(reading))
			if lights.papi_white(0,Vector3(0,20,2600)): failures.append("PAPI shows white to an aircraft below the path")
			if not lights.papi_white(3,Vector3(0,320,2600)): failures.append("PAPI shows red to an aircraft high above the path")
	world.queue_free()
	await process_frame

	print("SF ASSETS: ",photos.size()," geographic photos / full-detail mesh plus LODs / relief ",eligible,"+",clamped," gated / ",failures.size()," failures")
	for failure in failures:printerr(failure)
	quit(0 if failures.is_empty() else 1)

## Design review for the things the headless suite cannot see: the 28R approach
## lighting on final, the jet's own shadow on the ground, and the marine layer.
## Usage: Godot --path simulator --windowed --script tests/test_sf_assets.gd -- --visual
func capture() -> void:
	var folder := ProjectSettings.globalize_path("res://../build/look")
	DirAccess.make_dir_recursive_absolute(folder)
	var app: Node3D = load("res://scenes/main.tscn").instantiate()
	app.set_meta("route_override","sf")
	root.add_child(app)
	for i in 30: await process_frame
	app.audio.muted=true; app.set_quality(true)
	app.capture_file="review"
	var shots: Array = [
		{"name":"p8_final_long","at":Vector3(0,3.0+4700.0*0.05241,6000),"heading":0.0,"gear":true,"speed":78.0},
		{"name":"p8_final_short","at":Vector3(0,3.0+1800.0*0.05241,3100),"heading":0.0,"gear":true,"speed":72.0},
		{"name":"p8_final_flare","at":Vector3(0,3.0+800.0*0.05241,2100),"heading":0.0,"gear":true,"speed":68.0},
		{"name":"p8_shadow","at":Vector3(16400,240,-21400),"heading":0.30,"gear":false,"speed":240.0},
		{"name":"p8_marine","at":Vector3(6200,230,-16200),"heading":1.10,"gear":false,"speed":260.0},
		{"name":"p8_gate_low","at":Vector3(11800,180,-19000),"heading":1.45,"gear":false,"speed":260.0}
	]
	var wanted := OS.get_cmdline_user_args()
	for shot: Dictionary in shots:
		if wanted.size()>1 and str(shot.name) not in wanted: continue
		app.set_process(false); app.set_physics_process(false)
		app.start_flight("combat"); app.copilot=false; app.cockpit=false; app.text_hud=true
		app.combat.spawn_clock=999
		app.flight.spawn_airborne(shot.at,shot.speed)
		app.flight.gear=shot.gear; app.flight.flaps=2 if shot.gear else 0
		app.flight.heading=shot.heading; app.flight.throttle=.4
		app.apply_aircraft_pose(); app.camera_rig.reset()
		var began := Time.get_ticks_msec(); var frames := 0
		while Time.get_ticks_msec()-began<5000:
			var dt: float = minf(app.get_process_delta_time(),.05)
			app.flight.position=shot.at; app.flight.velocity=Vector3.ZERO
			app.apply_aircraft_pose()
			app._process(dt)
			await process_frame
			frames += 1
		app.hud.visible=false
		for i in 6: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+str(shot.name)+".png")
		app.hud.visible=true
		var env: Environment = app.world.environment.environment
		print("P8 SHOT ",shot.name," fps=",frames/5.0," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var casting := 0
		for chunk in app.world.chunks:
			if chunk.kind=="terrain" and bool(chunk.get("casting",false)): casting += 1
		print("   shadow: casters=",casting," mode=",app.world.sun.directional_shadow_mode," max=",app.world.sun.directional_shadow_max_distance," on=",app.world.sun.shadow_enabled)
		if str(shot.name)=="p8_shadow":
			app.hud.visible=false
			app.world.sun.shadow_enabled=false
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/p8_shadow_off.png")
			app.world.sun.shadow_enabled=true
			app.hud.visible=true
		print("   marine deck=",app.world.marine_deck.size()," vol=",env.volumetric_fog_enabled," at=",shot.at)
	app.queue_free()
	await process_frame


## World-only design review: the terrain, water, sky, marine layer and airfield
## lighting with no aircraft, HUD or cockpit in the way - and no dependency on
## scenes/main.tscn, which other packages are editing at the same time.
## Usage: Godot --path simulator --windowed --script tests/test_sf_assets.gd -- --world [name ...]
func capture_world() -> void:
	var folder := ProjectSettings.globalize_path("res://../build/look")
	DirAccess.make_dir_recursive_absolute(folder)
	var world: Node3D = SanFrancisco.new()
	root.add_child(world)
	world.apply_quality(true)
	var camera := Camera3D.new()
	camera.far = 90000.0
	camera.fov = 62.0
	root.add_child(camera)
	camera.current = true
	var views: Array = [
		{"name":"w_runway_long","eye":Vector3(0,250,6200),"look":Vector3(0,5,1300)},
		{"name":"w_runway_short","eye":Vector3(0,62,2650),"look":Vector3(0,3,300)},
		{"name":"w_hills","eye":Vector3(16600,320,-21000),"look":Vector3(15600,60,-22800)},
		{"name":"w_gate","eye":Vector3(11600,300,-19000),"look":Vector3(15200,90,-18600)},
		{"name":"w_beach","eye":Vector3(4200,320,-15200),"look":Vector3(9000,30,-18400)},
		{"name":"w_lake","eye":Vector3(3700,210,-13900),"look":Vector3(5100,6,-15300)},
		{"name":"w_sunwater","eye":Vector3(12000,300,-19300),"look":Vector3(12000,240,-19300)+world.sun.transform.basis.z*1000.0}
	]
	var wanted := OS.get_cmdline_user_args()
	for view: Dictionary in views:
		if wanted.size()>1 and str(view.name) not in wanted: continue
		camera.global_position = view.eye
		camera.look_at(view.look,Vector3.UP)
		var began := Time.get_ticks_msec(); var frames := 0
		while Time.get_ticks_msec()-began<6000:
			world.update_local_shadows(view.eye,minf(1.0/60.0,0.05))
			await process_frame
			frames += 1
		var casting := 0
		for chunk in world.chunks:
			if chunk.kind=="terrain" and bool(chunk.get("casting",false)): casting += 1
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+str(view.name)+".png")
		var env: Environment = world.environment.environment
		print("P8 WORLD ",view.name," fps=",frames/6.0," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," prims=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," terrain_casters=",casting," deck=",world.marine_deck.size(),"/",env.volumetric_fog_enabled," lights=",(0 if world.runway_lights==null else world.runway_lights.multimesh.instance_count))
		if str(view.name)=="w_gate":
			for sheet in world.marine_deck: sheet.visible=false
			for i in 6: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/w_gate_nofog.png")
			for sheet in world.marine_deck: sheet.visible=true
		if str(view.name)=="w_hills":
			world.sun.shadow_enabled=false
			for i in 6: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/w_hills_noshadow.png")
			world.sun.shadow_enabled=true
	world.queue_free(); camera.queue_free()
	await process_frame
