extends SceneTree
## Deterministic behavioral tests for the assisted flight model.
## Run: Godot --headless --path simulator --script res://tests/test_flight.gd
## The UI pauses by not calling step(); the model owns reset and terminal-contact freezing.
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	for aircraft in Catalog.PLANES:
		test_departure_threshold(aircraft)
		test_progressive_thrust(aircraft)
		test_banked_turn(aircraft)
		test_reset(aircraft)
		test_bounded_attitude(aircraft)
	test_touchdown_outcomes()
	test_braking()
	test_pause_contract()
	test_landing_score()
	if failures.is_empty():
		print("PASS: ", checks, " flight behavior checks across ", Catalog.PLANES.size(), " aircraft.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr(failures.size(), " failures across ", checks, " checks.")
		quit(1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fresh(aircraft: Dictionary):
	var model = Dynamics.new()
	model.reset(aircraft.duplicate(true))
	return model

func simulate(model, seconds: float, input: Vector3, brakes: bool = false, runway: bool = true) -> void:
	var remaining := seconds
	while remaining > 0.00001:
		var dt := minf(1.0 / 60.0, remaining)
		model.step(dt, input, brakes, 0.0, runway)
		remaining -= dt

func airborne_model(aircraft: Dictionary):
	var model = fresh(aircraft)
	model.position = Vector3(0, 1200, 0)
	model.speed = 90.0
	model.throttle = 0.6
	model.engine = 0.6
	model.airborne = true
	model.ever_airborne = true
	model.airborne_time = 20.0
	return model

func test_departure_threshold(aircraft: Dictionary) -> void:
	var model = fresh(aircraft)
	var label: String = aircraft.id
	# Pulling fully aft cannot lift a stationary aircraft or one below rotation speed.
	simulate(model, 1.0, Vector3(0, 1, 0))
	expect(not model.airborne and is_equal_approx(model.position.y, aircraft.clearance), label + ": stationary aft control stays on ground")
	model.speed = aircraft.rotation_speed - 0.25
	model.step(1.0 / 60.0, Vector3(0, 1, 0), false, 0.0, true)
	expect(not model.airborne, label + ": below-rotation speed cannot take off")
	# Speed alone must not initiate a takeoff; rotation is an explicit pilot action.
	model.speed = aircraft.rotation_speed + 2.0
	model.step(1.0 / 60.0, Vector3.ZERO, false, 0.0, true)
	expect(not model.airborne, label + ": reaching rotation speed without aft control stays on ground")
	model.step(1.0 / 60.0, Vector3(0, 0.7, 0), false, 0.0, true)
	expect(model.airborne and model.ever_airborne, label + ": sufficient speed plus rotation lifts off")
	expect(model.position.y > aircraft.clearance and model.vertical_speed > 0.0, label + ": departure has positive clearance and climb")

func test_progressive_thrust(aircraft: Dictionary) -> void:
	var model = fresh(aircraft)
	var label: String = aircraft.id
	model.throttle = 1.0
	model.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(model.engine > 0.0 and model.engine < 0.5, label + ": engine spools progressively after throttle command")
	expect(model.speed < 1.0, label + ": full throttle does not instantly jump to flight speed")
	var early_engine: float = model.engine
	simulate(model, 2.0, Vector3.ZERO)
	expect(model.engine > early_engine and model.engine <= 1.0, label + ": sustained throttle increases bounded engine output")
	expect(model.speed > 0.0 and model.speed < aircraft.rotation_speed, label + ": early ground roll accelerates below rotation speed")
	var accelerated_speed: float = model.speed
	simulate(model, 2.0, Vector3.ZERO)
	expect(model.speed > accelerated_speed, label + ": sustained engine thrust increases ground speed")

func test_banked_turn(aircraft: Dictionary) -> void:
	var right = airborne_model(aircraft)
	var left = airborne_model(aircraft)
	simulate(right, 1.0, Vector3(0.45, 0, 0))
	simulate(left, 1.0, Vector3(-0.45, 0, 0))
	expect(right.roll > 0.0 and right.heading > 0.0 and right.position.x > 0.0, aircraft.id + ": right bank turns and travels right")
	expect(left.roll < 0.0 and left.heading < 0.0 and left.position.x < 0.0, aircraft.id + ": left bank turns and travels left")
	expect(absf(right.heading + left.heading) < 0.00001, aircraft.id + ": mirrored bank inputs produce symmetric turns")
	expect(left.get_heading_degrees() >= 0.0 and left.get_heading_degrees() < 360.0, aircraft.id + ": negative headings are normalized for display")

func test_reset(aircraft: Dictionary) -> void:
	var model = airborne_model(aircraft)
	simulate(model, 2.0, Vector3(0.8, 0.5, 0.5))
	model.contact = "crash"
	model.gear = false
	model.touchdown_speed = 130.0
	model.touchdown_sink = -20.0
	model.touchdown_bank = 0.8
	model.stall_time = 10.0
	model.reset(aircraft.duplicate(true))
	expect(model.position.is_equal_approx(Vector3(0, aircraft.clearance, 1100)), aircraft.id + ": reset restores departure position")
	expect(model.speed == 0.0 and model.vertical_speed == 0.0 and model.throttle == 0.0 and model.engine == 0.0, aircraft.id + ": reset clears motion and power")
	expect(model.pitch == 0.0 and model.roll == 0.0 and model.heading == 0.0, aircraft.id + ": reset clears aircraft attitude")
	expect(not model.airborne and not model.ever_airborne and model.gear and model.contact == "", aircraft.id + ": reset clears terminal status and restores gear")
	expect(model.elapsed == 0.0 and model.airborne_time == 0.0 and model.distance == 0.0 and model.roughness == 0.0 and model.stall_time == 0.0, aircraft.id + ": reset clears accumulated flight statistics")
	expect(model.touchdown_speed == 0.0 and model.touchdown_sink == 0.0 and model.touchdown_bank == 0.0, aircraft.id + ": reset clears touchdown metrics")
	model.throttle = 1.0
	simulate(model, 1.0, Vector3.ZERO)
	expect(model.elapsed > 0.0 and model.engine > 0.0, aircraft.id + ": reset permits a fresh simulation after a crash")

func test_bounded_attitude(aircraft: Dictionary) -> void:
	var model = airborne_model(aircraft)
	model.position.y = 10000.0
	# Includes a 1-second hitch; controls remain inside the documented normalized range.
	for dt in [1.0 / 60.0, 0.1, 0.25, 1.0]:
		for direction in [-1.0, 1.0]:
			for iteration in range(20):
				model.step(dt, Vector3(direction, direction, direction), false, -100000.0, true)
			expect(is_finite(model.pitch) and is_finite(model.roll) and is_finite(model.speed) and model.position.is_finite(), aircraft.id + ": large frame steps remain finite")
			expect(absf(model.pitch) < PI / 2.0 and absf(model.roll) < PI / 2.0, aircraft.id + ": sustained full controls keep attitude within assisted-flight limits")
			expect(model.speed >= 0.0 and model.speed <= aircraft.max_speed * 1.2, aircraft.id + ": airspeed remains bounded under full controls")

func touchdown_fixture():
	var model = airborne_model(Catalog.PLANES[3])
	model.position = Vector3(0, float(model.profile.clearance) + 0.05, 0)
	model.speed = 65.0
	model.engine = 0.0
	model.throttle = 0.0
	model.pitch = -0.035
	model.vertical_speed = -2.0
	return model

func test_touchdown_outcomes() -> void:
	var landing = touchdown_fixture()
	landing.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(landing.contact == "landed" and not landing.airborne, "controlled runway touchdown with gear down succeeds")
	expect(is_equal_approx(landing.position.y, landing.profile.clearance) and landing.vertical_speed == 0.0, "successful touchdown settles aircraft on runway")
	expect(landing.touchdown_speed > 0.0 and landing.touchdown_sink < 0.0, "landing records pre-contact speed and sink for results")
	var touchdown_position: Vector3 = landing.position
	var touchdown_time: float = landing.elapsed
	landing.step(1.0, Vector3.ONE, false, 0.0, true)
	expect(landing.position == touchdown_position and landing.elapsed == touchdown_time and landing.contact == "landed", "terminal landing freezes model until reset")
	var gear_up = touchdown_fixture()
	gear_up.gear = false
	gear_up.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(gear_up.contact == "crash", "gear-up runway touchdown is rejected")
	var off_runway = touchdown_fixture()
	off_runway.step(0.1, Vector3.ZERO, false, 0.0, false)
	expect(off_runway.contact == "crash", "airborne touchdown away from runway is rejected")
	var hard = touchdown_fixture()
	hard.vertical_speed = -18.0
	hard.pitch = -0.32
	hard.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(hard.contact == "crash", "hard runway touchdown is rejected")
	var banked = touchdown_fixture()
	banked.roll = 0.6
	banked.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(banked.contact == "crash", "excessive bank at touchdown is rejected")
	var fast = touchdown_fixture()
	fast.speed = 130.0
	fast.step(0.1, Vector3.ZERO, false, 0.0, true)
	expect(fast.contact == "crash", "excessive touchdown speed is rejected")
	var crash_position: Vector3 = hard.position
	var crash_time: float = hard.elapsed
	hard.step(1.0, Vector3.ONE, false, 0.0, true)
	expect(hard.position == crash_position and hard.elapsed == crash_time and hard.contact == "crash", "terminal crash freezes model until reset")
	var excursion = fresh(Catalog.PLANES[3])
	excursion.speed = 65.0
	excursion.step(0.1, Vector3.ZERO, false, 0.0, false)
	expect(excursion.contact == "excursion", "high-speed ground departure from runway is an excursion")

func test_braking() -> void:
	var braking = fresh(Catalog.PLANES[3])
	var coasting = fresh(Catalog.PLANES[3])
	braking.speed = 30.0
	coasting.speed = 30.0
	simulate(braking, 1.0, Vector3.ZERO, true)
	simulate(coasting, 1.0, Vector3.ZERO, false)
	expect(braking.speed < coasting.speed - 10.0, "wheel brakes materially reduce ground speed")
	simulate(braking, 3.0, Vector3.ZERO, true)
	expect(braking.speed == 0.0, "continued braking stops without reversing")

func test_pause_contract() -> void:
	var model = airborne_model(Catalog.PLANES[3])
	simulate(model, 1.0, Vector3.ZERO)
	var paused_position: Vector3 = model.position
	var paused_time: float = model.elapsed
	# Match caller pause semantics: read instruments but intentionally do not call step.
	for frame in range(120):
		model.get_heading_degrees()
		model.get_smoothness()
	expect(model.position == paused_position and model.elapsed == paused_time, "paused instrument reads do not advance flight")
	simulate(model, 0.1, Vector3.ZERO)
	expect(model.position != paused_position and model.elapsed > paused_time, "resuming step advances paused flight")

func test_landing_score() -> void:
	var gentle = touchdown_fixture()
	gentle.contact = "landed"
	gentle.touchdown_speed = 60.0
	gentle.touchdown_sink = -1.0
	var hard = touchdown_fixture()
	hard.contact = "landed"
	hard.touchdown_speed = 60.0
	hard.touchdown_sink = -8.0
	var fast = touchdown_fixture()
	fast.contact = "landed"
	fast.touchdown_speed = 100.0
	fast.touchdown_sink = -1.0
	expect(gentle.get_smoothness() > hard.get_smoothness(), "gentler touchdown earns a higher smoothness score")
	expect(gentle.get_smoothness() > fast.get_smoothness(), "slower safe touchdown earns a higher smoothness score")
