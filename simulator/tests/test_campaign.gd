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
	check(not campaign.skip_to(5), "Developer skipping is locked during ordinary play")
	tap(KEY_F9)
	check(campaign.developer, "F9 enables developer controls")
	var weapons: Array[String] = []
	var planes: Array[String] = []
	var last_count := 0
	for index in range(6):
		tap((KEY_1+index) as Key)
		check(campaign.wave==index+1, "Developer stage key changes level %d" % (index+1))
		weapons.append(str(campaign.stage().weapon))
		planes.append(str(app.profile().id))
		check(campaign.enemies.size()>last_count, "Each stage increases flock size")
		last_count = campaign.enemies.size()
		check(app.aircraft.get_child_count()==(4 if index==5 else 2) and app.flight.airborne, "Upgrade replaces aircraft without leaving duplicate models")
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
	print("CAMPAIGN RESULT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
