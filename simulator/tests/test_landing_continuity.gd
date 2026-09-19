extends SceneTree
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
var app: Node3D
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CONTINUITY FAIL: "+message)
func run_tests() -> void:
	var flight = Dynamics.new()
	var tune: Dictionary = Catalog.PLANES[3].duplicate()
	tune.clearance = 3.0
	flight.reset(tune)
	flight.position = Vector3(0,3.01,-14200)
	flight.speed = 65
	flight.airborne = true
	flight.ever_airborne = true
	flight.airborne_time = 30
	flight.pitch = -0.06
	flight.roll = 0.08
	flight.vertical_speed = -2
	var before: Vector3 = flight.position
	flight.step(1.0/60.0,Vector3.ZERO,false,0,true)
	check(flight.contact=="landed", "Stable runway approach contacts ground")
	check(absf(flight.pitch+0.06)<0.01 and absf(flight.roll-0.08)<0.01, "Touchdown preserves attitude instead of snapping level")
	check(flight.position.distance_to(before)<1.2, "Touchdown motion stays within one physics step")
	var touchdown_pitch: float = flight.pitch
	flight.rollout_step(1.0/60.0,true,0,true)
	check(absf(flight.pitch-touchdown_pitch)<0.01 and absf(flight.pitch)>0.02, "First rollout frame lowers the nose gradually")
	for i in range(120): flight.rollout_step(1.0/60.0,true,0,true)
	check(absf(flight.pitch)<0.005 and absf(flight.roll)<0.005, "Rollout settles onto level gear")
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	app.set_process(false)
	app.audio.muted = true
	app.on_action("demo")
	app.copilot = false
	app.flight.position = Vector3(0,3.01,-14200)
	app.flight.speed = 65
	app.flight.gear = true
	app.flight.pitch = -0.035
	app.flight.vertical_speed = -2
	var position_before: Vector3 = app.flight.position
	app._physics_process(1.0/60.0)
	check(app.flight.position.distance_to(position_before)<2, "Showcase landing does not teleport to the 100-meter safety floor")
	check(app.mode=="rollout", "Gear-down showcase landing enters rollout")
	app.on_action("demo")
	app.flight.position = Vector3(130,580,-6250)
	app.flight.heading = 0.45
	app.flight.pitch = 0.04
	app.flight.roll = -0.15
	app.flight.speed = 117
	app.flight.vertical_speed = 2.2
	app.flight.throttle = 0.37
	var original: Vector3 = app.flight.position
	app.combat.spawn_wave()
	check(app.flight.position.is_equal_approx(original), "Aircraft upgrade preserves world position")
	check(is_equal_approx(app.flight.speed,117) and is_equal_approx(app.flight.heading,0.45), "Aircraft upgrade preserves speed and heading")
	check(is_equal_approx(app.flight.pitch,0.04) and is_equal_approx(app.flight.roll,-0.15), "Aircraft upgrade preserves attitude")
	check(is_equal_approx(app.flight.throttle,0.37), "Aircraft upgrade preserves pilot throttle")
	print("LANDING CONTINUITY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL",checks])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
