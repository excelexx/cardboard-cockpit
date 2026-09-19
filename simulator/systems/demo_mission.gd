extends RefCounted
class_name DemoMission
## A continuous departure, valley engagement, recovery and landing.
const Route=preload("res://systems/scenic_route.gd")
var route_index:=0
var visited_route: Array[int]=[]
var app: Node
var active := false
var phase := "takeoff"
var clock := 0.0
var phase_clock := 0.0
var history: Array[Dictionary] = []
var nearest_runway_distance := INF
func reset(enabled: bool) -> void:
	active = enabled; phase = "takeoff"; clock = 0; phase_clock = 0
	history.clear(); nearest_runway_distance = INF
	route_index=0; visited_route.clear()
	if enabled: history.append({"phase":phase,"time":0.0,"position":app.flight.position})
func transition(next: String) -> void:
	if phase==next: return
	phase = next; phase_clock = 0
	history.append({"phase":phase,"time":clock,"position":app.flight.position})
	if phase=="combat":
		for i in range(7): app.combat.spawn_contact()
	elif phase=="return": app.audio.radio.say("checkpoint")
	print("DEMO PHASE: ",phase," time=",snappedf(clock,.01)," position=",app.flight.position)
func tick(dt: float) -> void:
	if not active: return
	clock += dt; phase_clock += dt
	var f: FlightDynamics = app.flight
	if phase=="takeoff" and f.airborne and f.position.y-app.world.ground_height(f.position.x,f.position.z)>45:
		transition("combat")
	elif phase=="combat" and route_index>=8:
		transition("return")
	elif phase=="return" and route_index>=Route.POINTS.size() and f.position.z>-13200 and absf(f.position.x)<350 and absf(f.heading)<.45:
		transition("approach")
	if phase in ["combat","return"] and route_index<Route.POINTS.size():
		if f.position.distance_to(Route.POINTS[route_index])<330:
			visited_route.append(route_index)
			route_index+=1
	if f.contact=="landed": transition("rollout")
	app.combat.engagement_enabled = phase=="combat"
func label() -> String:
	return {"takeoff":"01 / DEPARTURE","combat":"02 / INTERCEPT","return":"03 / RECOVERY","approach":"03 / FINAL APPROACH","rollout":"03 / ROLLOUT"}.get(phase,"")
func instruction() -> String:
	if phase=="takeoff": return "W  FULL POWER  •  ↑ ROTATE AT 105 KT" if not app.flight.airborne else "POSITIVE CLIMB  •  G GEAR UP"
	if phase=="combat": return "HOLD SPACE + T TO FIRE BOTH  /  OR HOLD BOTH MOUSE BUTTONS"
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
	var desired: Vector3=Route.POINTS[mini(route_index,Route.POINTS.size()-1)]
	var speed: float=145.0 if phase=="combat" else 110.0
	f.gear=false
	f.flaps=0 if phase=="combat" else 1
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
