extends SceneTree
## v0.2 regression for rollout, flap lift/drag, landing score, and shared guidance.
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
const Approach = preload("res://systems/approach_guidance.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for profile in Catalog.PLANES:
		test_rollout(profile)
		test_flaps(profile)
		test_score(profile)
		test_landing_reset(profile)
	test_guidance()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("PASS: " if failures.is_empty() else "FAIL: ", checks, " landing and approach checks across all five aircraft.")
	quit(0 if failures.is_empty() else 1)

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func fresh(profile: Dictionary):
	var flight = Dynamics.new()
	var tune := profile.duplicate()
	tune.clearance = 3.0
	flight.reset(tune)
	return flight

func touchdown(profile: Dictionary):
	var flight = fresh(profile)
	flight.position = Vector3(0, 3.05, -14100)
	flight.speed = profile.rotation_speed * 1.15
	flight.airborne = true
	flight.ever_airborne = true
	flight.airborne_time = 30.0
	flight.pitch = -0.035
	flight.vertical_speed = -2.0
	flight.step(0.1, Vector3.ZERO, false, 0.0, true)
	return flight

func rollout(flight, seconds: float, brakes: bool, steering: float = 0.0) -> void:
	for index in int(seconds * 60.0):
		flight.rollout_step(1.0 / 60.0, brakes, steering, true)

func test_rollout(profile: Dictionary) -> void:
	var flight = touchdown(profile)
	var label: String = profile.id
	expect(flight.contact == "landed" and not flight.airborne, label + ": controlled approach settles onto landing gear")
	var start: Vector3 = flight.position
	var sink: float = flight.touchdown_sink
	var touchdown_speed: float = flight.touchdown_speed
	var time: float = flight.elapsed
	flight.throttle = 1.0
	flight.engine = 1.0
	flight.step(0.1, Vector3.ONE, false, 0.0, true)
	expect(flight.position == start and flight.elapsed == time, label + ": regular airborne integration stops at contact")
	rollout(flight, 1.0, true)
	expect(flight.position.z < start.z and flight.position.y == start.y, label + ": landed aircraft continues along the runway at constant ground height")
	expect(flight.elapsed > time and flight.rollout_elapsed > 0.99, label + ": rollout advances flight and rollout clocks")
	expect(flight.throttle == 0.0 and flight.engine < 1.0, label + ": rollout sets idle and winds engine down")
	var braking = touchdown(profile)
	var coasting = touchdown(profile)
	rollout(braking, 5.0, true)
	rollout(coasting, 5.0, false)
	expect(braking.speed + 20.0 < coasting.speed, label + ": wheel brakes materially improve deceleration over coasting")
	expect(braking.distance < coasting.distance, label + ": brakes reduce ground distance needed to stop")
	rollout(flight, 20.0, true)
	expect(flight.speed == 0.0 and flight.contact == "landed", label + ": sustained braking safely stops without reversing")
	expect(flight.touchdown_speed == touchdown_speed and flight.touchdown_sink == sink, label + ": rollout preserves original touchdown metrics")
	var stopped: Vector3 = flight.position
	rollout(flight, 1.0, true, 1.0)
	expect(flight.position == stopped, label + ": stopped aircraft does not creep or steer sideways")
	var right = touchdown(profile)
	var left = touchdown(profile)
	rollout(right, 1.0, true, 0.4)
	rollout(left, 1.0, true, -0.4)
	expect(right.position.x > 0.0 and left.position.x < 0.0 and is_equal_approx(right.position.x, -left.position.x), label + ": runway steering responds symmetrically")
	var overrun = touchdown(profile)
	overrun.rollout_step(0.1, false, 0.0, false)
	expect(overrun.contact == "overrun", label + ": leaving runway at speed records overrun")
	var overrun_position: Vector3 = overrun.position
	overrun.rollout_step(1.0, true, 1.0, true)
	expect(overrun.position == overrun_position, label + ": overrun is terminal until reset")
	var slow_exit = touchdown(profile)
	slow_exit.speed = 4.0
	slow_exit.rollout_step(0.1, true, 0.0, false)
	expect(slow_exit.contact == "overrun", label + ": a slow runway exit is not accepted as a safe stop")
	var stopped_outside = touchdown(profile)
	stopped_outside.speed = 0.05
	stopped_outside.rollout_step(0.1, true, 0.0, false)
	expect(stopped_outside.contact == "overrun", label + ": braking to zero outside the runway still fails landing")
	var departure = fresh(profile)
	departure.speed = 25.0
	var departure_position: Vector3 = departure.position
	departure.rollout_step(1.0, true, 1.0, true)
	expect(departure.position == departure_position and departure.speed == 25.0, label + ": rollout integration cannot run before touchdown")

func test_flaps(profile: Dictionary) -> void:
	var clean = fresh(profile)
	var takeoff = fresh(profile)
	var approach = fresh(profile)
	takeoff.flaps = 1
	approach.flaps = 2
	expect(clean.effective_rotation_speed() > takeoff.effective_rotation_speed() and takeoff.effective_rotation_speed() > approach.effective_rotation_speed(), profile.id + ": each flap detent lowers assisted rotation speed")
	var between: float = (clean.effective_rotation_speed() + approach.effective_rotation_speed()) / 2.0
	clean.speed = between
	approach.speed = between
	clean.step(0.05, Vector3(0, 0.8, 0), false, 0.0, true)
	approach.step(0.05, Vector3(0, 0.8, 0), false, 0.0, true)
	expect(not clean.airborne and approach.airborne, profile.id + ": flap lift changes actual takeoff behavior at the same airspeed")
	clean = fresh(profile)
	approach = fresh(profile)
	approach.flaps = 2
	for flight in [clean, approach]:
		flight.airborne = true
		flight.ever_airborne = true
		flight.airborne_time = 30.0
		flight.position.y = 1000.0
		flight.speed = 100.0
	for index in 60:
		clean.step(1.0 / 60.0, Vector3.ZERO, false, 0.0, true)
		approach.step(1.0 / 60.0, Vector3.ZERO, false, 0.0, true)
	expect(approach.speed < clean.speed - 1.0, profile.id + ": extended flaps produce additional drag in flight")

func test_score(profile: Dictionary) -> void:
	var flight = fresh(profile)
	flight.touchdown_speed = profile.rotation_speed
	flight.touchdown_sink = -0.3
	var gentle: int = flight.landing_score()
	flight.touchdown_sink = -5.0
	var hard: int = flight.landing_score()
	expect(gentle > 95 and hard < gentle - 25, profile.id + ": landing score rewards a gentle touchdown")
	flight.touchdown_bank = deg_to_rad(12.0)
	flight.touchdown_center = 30.0
	expect(flight.landing_score() < hard - 20, profile.id + ": bank and centerline deviation reduce landing score")
	flight.touchdown_sink = -0.3
	flight.touchdown_bank = 0.0
	flight.touchdown_center = 0.0
	flight.touchdown_speed = profile.rotation_speed * 1.15 + 25.0
	expect(flight.landing_score() < gentle - 15, profile.id + ": excess approach speed reduces landing score")
	flight.touchdown_sink = -100.0
	flight.touchdown_center = 1000.0
	expect(flight.landing_score() == 0, profile.id + ": very poor touchdown score remains bounded at zero")

func test_landing_reset(profile: Dictionary) -> void:
	var flight = touchdown(profile)
	flight.flaps = 2
	rollout(flight, 2.0, true)
	flight.reset(profile)
	expect(flight.flaps == 0 and flight.rollout_elapsed == 0.0 and flight.touchdown_center == 0.0 and flight.contact == "", profile.id + ": restart clears approach and rollout state")

func test_guidance() -> void:
	var path: Dictionary = Approach.solution(Vector3(0, 0, Approach.AIM_Z + 1000.0))
	var centered: Dictionary = Approach.solution(Vector3(0, path.ideal_height, Approach.AIM_Z + 1000.0))
	expect(centered.on_path and is_zero_approx(centered.localizer) and is_zero_approx(centered.glideslope), "shared approach solution centers both diamonds on the ideal glide path")
	var right_high: Dictionary = Approach.solution(Vector3(90, path.ideal_height + 40.0, Approach.AIM_Z + 1000.0))
	expect(right_high.localizer < 0.0 and right_high.glideslope < 0.0 and not right_high.on_path, "right/high approach deviation calls for left/down correction")
	var left_low: Dictionary = Approach.solution(Vector3(-90, path.ideal_height - 40.0, Approach.AIM_Z + 1000.0))
	expect(left_low.localizer > 0.0 and left_low.glideslope > 0.0, "left/low approach deviation calls for right/up correction")
	var farther: Dictionary = Approach.solution(Vector3(0, 0, Approach.AIM_Z + 2000.0))
	expect(is_equal_approx(farther.ideal_height - path.ideal_height, 1000.0 * Approach.GLIDESLOPE), "approach path height scales consistently with runway distance")
	var passed: Dictionary = Approach.solution(Vector3(10000, 10000, Approach.AIM_Z - 500.0))
	expect(passed.distance == 0.0 and passed.ideal_height == 3.0, "past touchdown aim point guidance stays on the runway plane")
	expect(absf(passed.localizer) <= 1.0 and absf(passed.glideslope) <= 1.0, "off-scale approach guidance clamps instrument deflection")
