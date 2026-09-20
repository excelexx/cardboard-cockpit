extends SceneTree
var app: Node
var folder: String
func _initialize() -> void:call_deferred("run")
func snapshot(name: String) -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
	print("TEAM UI CAPTURE ",name)
func test_frame(color: Color,label: String) -> ImageTexture:
	var frame:=Image.create(640,360,false,Image.FORMAT_RGB8);frame.fill(color)
	for y in range(20,340):
		for x in range(20,620):
			if (x/32+y/32)%2==0:frame.set_pixel(x,y,color.lightened(.14))
	return ImageTexture.create_from_image(frame)
func run() -> void:
	if OS.get_environment("COCKPIT_DISABLE_BADGE")!="1":printerr("Preview requires COCKPIT_DISABLE_BADGE=1");quit(2);return
	folder=ProjectSettings.globalize_path("res://../build/team-ui");DirAccess.make_dir_recursive_absolute(folder)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.test_mode=true;app.audio.muted=true
	app.set_process(false);app.set_physics_process(false);app.get_window().title="Integration review — simulated cameras, badge disabled"
	app.start_flight("combat");app.camera_rig.update(1);app.vision.enabled=true;app.vision.connected=true;app.vision.tracking=true;app.vision.throttle_confidence=.95
	app.yoke_preview.texture=test_frame(Color(.14,.24,.30),"LAPTOP");app.throttle_preview.texture=test_frame(Color(.23,.22,.13),"PHONE")
	app.mode="flight";await snapshot("flight-cameras")
	app.mode="paused";app.resume_mode="flight";await snapshot("pause")
	app.on_action("settings");await snapshot("settings")
	app.on_action("camera");await snapshot("camera-setup")
	app.controls_lesson.calibrating=false;app.controls_lesson.index=1;app.vision.throttle=.75;await snapshot("setup-throttle")
	app.controls_lesson.index=3;await snapshot("setup-yoke")
	app.controls_lesson.index=5;app.vision.gun_trigger=false;await snapshot("setup-gun")
	app.controls_lesson.index=7;await snapshot("setup-ready")
	app.cancel_control_setup();app.start_flight("training");app.flight.spawn_airborne(Vector3(0,350,-800),110);app.camera_rig.update(1);await snapshot("tutorial")
	app.on_action("title");await snapshot("title")
	app.queue_free();await process_frame;quit()
