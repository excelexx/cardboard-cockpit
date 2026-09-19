extends RefCounted
class_name DemoMission
const Tune = preload("res://data/balance.gd")
## A continuous departure, valley engagement, recovery and landing.
const CoastalRoute = preload("res://systems/scenic_route.gd")
const SFRoute = preload("res://systems/san_francisco_route.gd")
func route_points() -> Array[Vector3]: return SFRoute.POINTS if app.route_id=="sf" else CoastalRoute.POINTS
func route_names() -> Array[String]: return SFRoute.NAMES if app.route_id=="sf" else CoastalRoute.NAMES
var route_index := 0
var visited_route: Array[int] = []
var app: Node
var active := false
var phase := "takeoff"
var clock := 0.0
var phase_clock := 0.0
var history: Array[Dictionary] = []
var nearest_runway_distance := INF
func reset(enabled: bool) -> void:
	active = enabled; phase = "takeoff"; clock = 0; phase_clock = 0
	history.clear(); nearest_runway_distance = INF; route_index = 0; visited_route.clear()
	if enabled: history.append({"phase":phase,"time":0.0,"position":app.flight.position})
func transition(next: String) -> void:
	if phase==next: return
	phase = next; phase_clock = 0
	history.append({"phase":phase,"time":clock,"position":app.flight.position})
	if phase=="combat":
		app.combat.spawn_clock = Tune.FIRST_ARRIVAL
	elif phase=="return": app.audio.radio.say("checkpoint")
	print("DEMO PHASE: ",phase," time=",snappedf(clock,.01)," position=",app.flight.position)
func tick(dt: float) -> void:
	if not active: return
	clock += dt; phase_clock += dt
	var f: FlightDynamics = app.flight
	if phase=="takeoff" and f.airborne and f.position.y-app.world.ground_height(f.position.x,f.position.z)>45:
		transition("combat")
	elif app.route_id not in ["coast","sf"] and phase=="combat" and (f.position.z<-9000 or phase_clock>Tune.ALPINE_COMBAT_LIMIT):
		transition("return")
	elif app.route_id not in ["coast","sf"] and phase=="return" and f.position.z<-10300 and f.position.z>-13200 and absf(f.position.x)<350 and absf(f.heading)<.45:
		transition("approach")
	if app.route_id in ["coast","sf"] and phase in ["combat","return"]:
		var delta: Vector3 = route_target()-f.position
		if Vector2(delta.x,delta.z).length()<Tune.WAYPOINT_RADIUS and absf(delta.y)<Tune.WAYPOINT_HEIGHT_TOLERANCE:
			visited_route.append(route_index); route_index += 1
			if route_index>=route_points().size(): transition("approach")
			elif route_index>=8 and phase=="combat": transition("return")
	if f.contact=="landed": transition("rollout")
	app.combat.engagement_enabled = phase=="combat"
func label() -> String:
	return {"takeoff":"01 / DEPARTURE","combat":"02 / INTERCEPT","return":"03 / RECOVERY","approach":"03 / FINAL APPROACH","rollout":"03 / ROLLOUT"}.get(phase,"")
func instruction() -> String:
	if app.route_id in ["coast","sf"] and phase in ["combat","return"]: return route_names()[mini(route_index,route_names().size()-1)]+"  •  FOLLOW THE BLUE DIAMOND"
	if phase=="takeoff": return "W  FULL POWER  •  ↑ ROTATE AT 105 KT" if not app.flight.airborne else "POSITIVE CLIMB  •  G GEAR UP"
	if phase=="combat": return "W ACCELERATE  /  S AIRBRAKE  •  ALIGN THE ACQUISITION RING"
	if phase=="return": return "NORTH FIELD / RWY 36  •  REDUCE POWER"
	if phase=="approach": return "GEAR DOWN  •  FLAPS 2  •  HOLD THE GLIDEPATH"
	return "HOLD SPACE TO BRAKE  •  A / D CENTRELINE"
func controls() -> Vector3:
	var f: FlightDynamics = app.flight
	if phase=="takeoff":
		f.throttle = 1 if clock>2.4 else 0; f.gear = true; f.flaps = 1; f.afterburner = false
		var pitch: float = .15 if f.airborne else .7 if f.speed>f.effective_rotation_speed() else 0
		return Vector3(clampf(-f.roll*2,-1,1),clampf((pitch-f.pitch)*2.8,-1,1) if f.airborne else pitch,clampf(-f.position.x*.03-f.heading*3,-1,1))
	if phase=="approach":
		f.afterburner = false
		return app.approach_controls()
	if app.route_id in ["coast","sf"]: return coastal_controls()
	var desired := Vector3(0,240,-11000)
	var speed := Tune.ALPINE_RETURN_SPEED
	if phase=="combat":
		f.gear = false; f.flaps = 0
		speed = Tune.ALPINE_COMBAT_SPEED
		desired = Vector3(sin(-f.position.z*.00085)*150,210+sin(clock*.07)*25,f.position.z-1300)
		var nearest := INF
		for enemy: Dictionary in app.combat.enemies:
			var delta: Vector3 = enemy.position-f.position
			if delta.z < -150 and absf(enemy.position.x)<550 and enemy.position.y<420 and delta.length()<nearest:
				nearest = delta.length(); desired = app.combat.lead_point(enemy)
	else:
		f.gear = false; f.flaps = 1
	var terrain: float = app.world.ground_height(f.position.x,f.position.z)
	for distance in [300.0,650.0,1100.0]:
		var probe: Vector3 = f.position+f.forward()*distance
		terrain = maxf(terrain,app.world.ground_height(probe.x,probe.z))
	desired.y = maxf(desired.y,terrain+110)
	var delta: Vector3 = desired-f.position
	var error: float = wrapf(atan2(delta.x,-delta.z)-f.heading,-PI,PI)
	var bank: float = clampf(error*2.2,-.65,.65)
	var pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),500)),-.18,.24)
	f.throttle = clampf(.2+(speed-f.speed)*.045,0,1)
	f.afterburner = phase=="combat" and phase_clock<1.8
	if f.afterburner: f.throttle = 1
	if app.combat.incoming_distance<650:
		for shot: Dictionary in app.combat.shots:
			if shot.kind=="hostile_missile" and not shot.has("decoy") and shot.position.distance_to(f.position)<650:
				app.combat.deploy_flares(); break
	return Vector3(clampf((bank-f.roll)*1.6-f.roll_velocity*.3,-1,1),clampf((pitch-f.pitch)*3.0-f.pitch_velocity*.25,-1,1),clampf(error*.8,-1,1))

func route_target() -> Vector3:
	return route_points()[mini(route_index,route_points().size()-1)]

func coastal_controls() -> Vector3:
	var f: FlightDynamics = app.flight
	var delta: Vector3 = route_target()-f.position
	var error: float = wrapf(atan2(delta.x,-delta.z)-f.heading,-PI,PI)
	var desired_roll: float = clampf(error*1.6,-.66,.66)
	var desired_pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),250)),-.36,.40)
	var desired_speed: float = Tune.COAST_EARLY_SPEED if route_index<4 else Tune.COAST_CRUISE_SPEED
	if route_index>=8: desired_speed = Tune.COAST_RETURN_SPEED
	if app.route_id=="sf": desired_speed = 200 if route_index<11 else 135 if route_index<13 else 100
	f.gear = false; f.flaps = 0; f.afterburner = false
	f.throttle = clampf(.24+(desired_speed-f.speed)*.065,0,1)
	return Vector3(clampf((desired_roll-f.roll)*5,-1,1),clampf((desired_pitch-f.pitch)*6,-1,1),clampf(error*1.4,-1,1))
