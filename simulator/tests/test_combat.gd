extends SceneTree
var app: Node3D
var failures: Array[String] = []
var checks := 0
var settings: PackedByteArray
var had_settings := false
func _initialize() -> void:
	had_settings = FileAccess.file_exists("user://settings.cfg")
	if had_settings: settings = FileAccess.get_file_as_bytes("user://settings.cfg")
	call_deferred("run_tests")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("COMBAT FAIL: "+label)
func run_tests() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	app.set_process(false)
	app.audio.muted = true
	app.select_plane(5)
	check(app.profile().id=="an225" and app.profile().engines==6, "An-225 is selectable with six engines")
	check(app.preview.scale.x<1.02 and app.preview.scale.x>1, "An-225 mesh normalized to its published wingspan")
	var heavy_scale: float = app.profile().span
	app.select_plane(1)
	check(heavy_scale/app.profile().span>8, "An-225 wingspan exceeds eight F-35 spans")
	check(app.preview.scale.x<1.1, "Fighter is not enlarged for hangar display")
	app.flight_kind = "combat"
	app.start_flight()
	var c: CombatDirector = app.combat
	check(c.active and app.flight.airborne and not app.flight.gear, "Combat begins airborne in an F-35")
	check(not c.fire_missile() and c.missiles==8, "Missile cannot fire without a lock")
	c.spawn_wave()
	for i in range(100): c.tick(1.0/60.0)
	check(c.target_id>=0 and c.lock_progress>=1, "Forward drone acquires a stable lock")
	check(c.fire_missile() and c.missiles==7, "Locked missile consumes one round")
	check(not c.fire_missile(), "Missile cooldown prevents repeated launches")
	for i in range(300): c.tick(1.0/60.0)
	check(c.kills>0, "Guided projectile intercepts and destroys a drone")
	c.spawn_shot(app.flight.position+Vector3(0,0,-100),Vector3(0,0,50),"hostile",-1,14)
	check(c.deploy_flares() and c.flares==5, "Flares consume one countermeasure charge")
	var live_hostile := false
	for shot: Dictionary in c.shots:
		if shot.kind=="hostile" and shot.life>0: live_hostile = true
	check(not live_hostile, "Flares defeat nearby hostile projectiles")
	var hull_before: float = c.hull
	c.spawn_shot(app.flight.position+Vector3(0,0,-20),Vector3(0,0,200),"hostile",-1,14)
	c.update_shots(0.1)
	check(c.hull<hull_before, "Enemy hits reduce aircraft hull")
	check(app.flight.start_barrel_roll(), "Airborne F-35 can begin a barrel roll")
	var rolled_past_inverted := false
	for i in range(120):
		app.flight.step(1.0/60.0,Vector3.ZERO,false,-1000,false)
		rolled_past_inverted = rolled_past_inverted or absf(app.flight.roll)>PI
	check(rolled_past_inverted and app.flight.barrel_remaining==0, "Barrel roll completes a full rotation and recovers")
	app.select_plane(5)
	app.flight_kind = "free"
	app.start_flight()
	app.flight.airborne = true
	app.flight.position.y = 650
	check(not app.flight.start_barrel_roll(), "Heavy transport cannot perform fighter roll maneuver")
	app.select_plane(1)
	app.flight_kind = "combat"
	app.start_flight()
	c = app.combat
	# Exercise complete waves through the real lock, ammunition, projectile and
	# damage systems. This fixture holds position and aims; it is not an AI pilot.
	for i in range(18000):
		if app.mode!="flight": break
		if not c.enemies.is_empty():
			var delta: Vector3 = c.enemies[0].position-app.flight.position
			app.flight.heading = atan2(delta.x,-delta.z)
			app.flight.pitch = atan2(delta.y,Vector2(delta.x,delta.z).length())
		c.tick(1.0/60.0)
		c.fire_gun()
		if c.lock_progress>=1: c.fire_missile()
	check(app.mission_success and c.wave==3 and c.kills==12, "All three waves can be won using actual projectiles")
	app.start_flight()
	c = app.combat
	check(c.eject() and app.mode=="ejected" and not c.active, "Ejection transfers to parachute camera state")
	for i in range(370): c.tick_ejection(1.0/60.0)
	check(app.mode=="results" and "parachute" in app.result_reason, "Ejection ends with pilot recovery debrief")
	if had_settings:
		FileAccess.open("user://settings.cfg",FileAccess.WRITE).store_buffer(settings)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("COMBAT RESULT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
