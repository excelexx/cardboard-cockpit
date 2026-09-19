extends SceneTree
var app: Node3D
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("CAMPAIGN FAIL: "+label)
func tap(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
func run_tests() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_physics_process(false)
	app.audio.muted = true
	app.on_action("demo")
	var campaign: GooseCampaign = app.combat
	check(campaign.wave==1 and campaign.showcase, "One-click demo starts the trainer stage")
	check(app.profile().id=="trainer", "Starting aircraft is the small trainer")
	check(app.camera_view=="cockpit", "Demo starts in the pilot seat")
	check(campaign.phase=="takeoff" and not app.flight.airborne and app.flight.speed==0, "Demo begins stationary on the runway")
	check(not campaign.fire_weapon(), "Weapons are inhibited during departure")
	app.flight.airborne = true
	app.flight.ever_airborne = true
	app.flight.position = Vector3(0,200,-1800)
	app.flight.speed = 90
	campaign.tick(1.0/60.0)
	check(campaign.phase=="combat" and campaign.wave==1, "Climb unlocks the first combat stage")
	campaign.stage_clock = 100
	campaign.tick(1.0/60.0)
	check(campaign.wave==1 and campaign.route_index==0, "A timer cannot skip scenic landmarks")
	check(app.target_position()==campaign.route_target(), "Campaign navigation points at scenery, not enemies")
	check(app.world.ground_height(0,-4900)<-8.5, "Waterfront flight corridor is over the ocean")
	check(app.world.cloud_immersion(Vector3(0,1100,-8750))==0, "Coastal panorama remains visible")
	check(not campaign.skip_to(5), "Developer skipping is locked during ordinary play")
	tap(KEY_F9)
	check(campaign.developer, "F9 enables developer controls")
	var weapons: Array[String] = []
	var planes: Array[String] = []
	var last_count := 0
	for index in range(6):
		var prior_position: Vector3 = app.flight.position
		tap((KEY_1+index) as Key)
		check(app.flight.position==prior_position, "Aircraft upgrade preserves position")
		check(app.camera_view=="cockpit", "Upgrade preserves cockpit view")
		check(campaign.wave==index+1, "Developer stage key changes level %d" % (index+1))
		weapons.append(str(campaign.stage().weapon))
		planes.append(str(app.profile().id))
		check(campaign.enemies.size()>last_count, "Each stage increases flock size")
		last_count = campaign.enemies.size()
		var visible_models:=0
		for child in app.aircraft.get_children():
			if child is Node3D and child.visible: visible_models+=1
		check(app.campaign_models.size()==6 and app.aircraft.get_child_count()==6 and visible_models==1 and app.flight.airborne,"Upgrade activates exactly one of six bounded cached aircraft")
		check(app.campaign_models[str(app.profile().id)].root.visible,"Visible cached aircraft matches the selected stage")
	check(weapons.size()==6 and planes==["trainer","f35","b2","an225","vx9","falcon"], "Every stage has a distinct aircraft and weapon")
	check(weapons[-1]=="TWIN PLASMA CANNONS", "Final loadout is plasma, with no reality-warping systems")
	app.vision.enabled = true
	app.vision.tracking = true
	app.vision.yoke = Vector2(0.3,0)
	app.copilot = true
	app._physics_process(1.0/60.0)
	check(not app.copilot and app.vision.enabled, "Cardboard input takes control from the guided demo without disabling vision")
	app.vision.enabled = false
	tap(KEY_F9)
	check(not campaign.developer and not campaign.skip_to(0), "Developer controls can be disabled again")
	campaign.begin_approach()
	check(app.mode=="flight" and campaign.phase=="landing", "Final stage leads to approach, not premature results")
	check(campaign.enemies.is_empty() and not campaign.fire_weapon(), "Approach clears targets and safes weapons")
	check(app.flight.gear and app.flight.flaps==2 and app.ring_index==5, "Landing configuration and guidance enabled")
	print("CAMPAIGN RESULT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
