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
class FakeTutorial extends RefCounted:
	var active:=false
class FakeApp extends Node:
	var mission := FakeMission.new()
	var combat: CombatDirector
	var flight_kind := "demo"
	var flight: FlightDynamics
	var landing_started:=false
	var mode:="flight"
	var tutorial:=FakeTutorial.new()
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

func flight(airspeed: float,height: float) -> FlightDynamics:
	var f: FlightDynamics = Dynamics.new()
	f.reset(Catalog.PROFILE)
	f.spawn_airborne(Vector3(0,height,0),airspeed)
	return f

func _initialize() -> void: call_deferred("run")

func run() -> void:
	objective()
	copy()
	airspeed()
	marker()
	indexer()
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
	# Until the combat package publishes its skein fields the bar still reads,
	# from the kill count against the designed skein size.
	var plain: CombatDirector = CombatDirector.new()
	plain.kills = 3
	check(HUD.skein_tally(plain)==Vector2(3,float(Tune.SKEIN_SIZE)),"Without skein fields the tally falls back to kills")
	check(HUD.skein_ids(plain).is_empty(),"Skein ids are empty, not an error, before the combat package lands them")
	var fields: FieldOnlyDirector = FieldOnlyDirector.new()
	check(HUD.skein_tally(fields)==Vector2(5,12),"A plain skein_down field reads too")
	fields.free()
	plain.free()
	c.free()

## GOAL 1: no boss copy survives anywhere in this package.
func copy() -> void:
	var hud: CockpitHUD = HUD.new()
	var app := FakeApp.new()
	app.combat = CombatDirector.new()
	app.flight=flight(180,400)
	hud.app = app
	root.add_child(app)
	app.mission.phase = "gather"
	check(hud.mission_line().contains("Endless"),"The mission describes the continuous judge demo")
	app.mission.phase = "skein"
	check(hud.mission_line().contains("land whenever"),"The flight prompt makes landing a player choice")
	for phase: String in ["opening","combat","gather","skein","aftermath","approach","rollout","anticipation","boss","takeoff","return",""]:
		app.mission.phase = phase
		var line: String = hud.mission_line().to_lower()
		check(not line.contains("boss") and not line.contains("mother goose"),"Phase '%s' never names a boss" % phase)
		app.mission.cinematic = false
		check(not hud.mission_line().to_lower().contains("boss"),"Free-flight phase '%s' never names a boss" % phase)
		app.mission.cinematic = true
	app.mission.phase = "skein"
	app.mission.clock = 30.0
	check(hud.clock_text()=="0:30","The mission clock shows elapsed time instead of a deadline")
	app.mission.active = false;app.flight.elapsed=95
	check(hud.clock_text()=="1:35","Free flight shows elapsed flight time")
	app.flight.gear=true;app.flight.flaps=1
	check(hud.context_coach().title.contains("RETRACT"),"Airborne gear-down coaching calls for retraction")
	app.landing_started=true
	check(hud.context_coach().body.contains("Keep them down") and hud.mission_line().contains("Your approach"),"Configured landing coaches manual control without asking for a wrong toggle")
	app.flight.gear=false;app.flight.flaps=0
	check(hud.context_coach().body.contains("BADGE A / G"),"Landing with gear up prompts the correct configuration control")
	app.mode="rollout"
	check(hud.context_coach().title.contains("LANDED"),"Rollout coaching follows live flight state")
	check(hud.thousands(23400)=="23,400" and hud.thousands(-940)=="-940","Altitudes group in thousands")
	check(hud.has_method("draw_objective") and not hud.has_method("draw_boss"),"The objective bar replaced the boss bar")
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

## GOAL 3: the on-speed indexer closes as the wing works harder.
func indexer() -> void:
	var f: FlightDynamics = flight(180.0,600.0)
	var previous := 1e9
	for step in range(11):
		f.aoa = Dynamics.ALPHA_MAX*float(step)/10.0
		var gap: float = HUD.aoa_bracket_gap(f)
		check(gap<previous and gap>=HUD.INDEXER_SHUT,"The indexer gap closes at %.1f of the alpha limit" % (float(step)/10.0))
		previous = gap
	f.aoa = Dynamics.ALPHA_MAX*3.0
	check(HUD.aoa_bracket_gap(f)==previous,"Past the limit the indexer stays shut instead of inverting")
	f.aoa = -Dynamics.ALPHA_MAX
	check(HUD.aoa_bracket_gap(f)==HUD.INDEXER_OPEN,"A push opens the indexer to its widest, never negative")

## The grep the audit asks for, kept as a test so it cannot rot.
func sources() -> void:
	for path: String in ["res://ui/hud.gd","res://ui/cockpit_instruments.gd"]:
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		check(not text.contains("boss"),"%s mentions no boss anywhere" % path)
		check(not text.contains("mother goose"),"%s names no individual goose" % path)
	check(not FileAccess.get_file_as_string("res://ui/hud.gd").contains("max_health"),"No per-goose health bar is left in the HUD")
