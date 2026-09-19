extends RefCounted
class_name DemoMission
const Tune = preload("res://data/balance.gd")
## A continuous departure, valley engagement, recovery and landing.
const CoastalRoute = preload("res://systems/scenic_route.gd")
const SFRoute = preload("res://systems/san_francisco_route.gd")
func route_points() -> Array[Vector3]: return SHOWCASE_POINTS if cinematic else SFRoute.POINTS if app.route_id=="sf" else CoastalRoute.POINTS
func route_names() -> Array[String]: return SHOWCASE_NAMES if cinematic else SFRoute.NAMES if app.route_id=="sf" else CoastalRoute.NAMES
const SHOWCASE_POINTS: Array[Vector3]=[Vector3(4000,350,-3500),Vector3(10000,470,-6500),Vector3(15500,430,-10500),Vector3(18000,380,-13500),Vector3(15700,420,-17800),Vector3(15000,480,-15800)]
const SHOWCASE_NAMES: Array[String]=["BAY DEPARTURE","CITY RUSH","DOWNTOWN","ALCATRAZ CHANNEL","GOLDEN GATE","OPEN SKY"]
var cinematic := false
var act := 0
var boss_dead_at := -1.0
var roll_demo_done := false
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
	cinematic=enabled and app.route_id=="sf";act=0;boss_dead_at=-1;roll_demo_done=false
	if cinematic:
		phase="opening";app.flight.speed=45;app.flight.engine=1;app.flight.throttle=1;app.flight.flaps=1
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
	if cinematic:
		_tick_showcase(dt);return
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
	if cinematic:return {"opening":"01 / SKYWARD","combat":"02 / CITY RUSH","anticipation":"03 / ANOMALOUS CONTACT","boss":"04 / THE FINAL HONK","aftermath":"SIGNAL CLEAR"}.get(phase,"SF / FREE FLIGHT")
	return {"takeoff":"01 / DEPARTURE","combat":"02 / INTERCEPT","return":"03 / RECOVERY","approach":"03 / FINAL APPROACH","rollout":"03 / ROLLOUT"}.get(phase,"")
func instruction() -> String:
	if cinematic:
		if phase=="boss":return ""
		if phase=="anticipation":return "LARGE SIGNATURE" if phase_clock<2 else ""
		return ""
	if app.route_id in ["coast","sf"] and phase in ["combat","return"]: return route_names()[mini(route_index,route_names().size()-1)]+"  •  FOLLOW THE BLUE DIAMOND"
	if phase=="takeoff": return "W  FULL POWER  •  ↑ ROTATE AT 105 KT" if not app.flight.airborne else "POSITIVE CLIMB  •  G GEAR UP"
	if phase=="combat": return "W ACCELERATE  /  S AIRBRAKE  •  ALIGN THE ACQUISITION RING"
	if phase=="return": return "NORTH FIELD / RWY 36  •  REDUCE POWER"
	if phase=="approach": return "GEAR DOWN  •  FLAPS 2  •  HOLD THE GLIDEPATH"
	return "HOLD SPACE TO BRAKE  •  A / D CENTRELINE"
func controls() -> Vector3:
	if cinematic:return _showcase_controls()
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

func _tick_showcase(dt: float) -> void:
	var c: CombatDirector=app.combat
	if phase=="opening" and clock>=22:act=1;transition("combat")
	elif phase=="combat" and clock>=60:act=2;transition("anticipation");app.audio.radio.say("warning",2);c.event("boss_signature",app.flight.position+app.flight.forward()*1700,4)
	elif phase=="anticipation" and clock>=76:
		act=3;transition("boss")
		for enemy: Dictionary in c.enemies:
			if enemy.kind!="boss":enemy.retiring=true
		if c.boss_id<0:c.spawn_contact("boss")
	if phase=="anticipation" and clock>=66 and c.boss_id<0:c.spawn_contact("boss")
	if phase=="boss" and c.boss_defeated:
		boss_dead_at=clock;transition("aftermath");act=4
	if phase=="boss" and clock>=139:
		boss_dead_at=clock;transition("aftermath");act=4
		for enemy: Dictionary in c.enemies:enemy.retiring=true
	if phase=="aftermath" and (clock-boss_dead_at>=7 or clock>=Tune.DEMO_LIMIT):
		app.finish_sortie(c.boss_defeated,"THE SKY IS YOURS" if c.boss_defeated else "INTERCEPT WINDOW CLOSED — TAKE ANOTHER RUN")
		return
	if clock>=Tune.DEMO_LIMIT:
		app.finish_sortie(c.boss_defeated,"THE SKY IS YOURS" if c.boss_defeated else "RUN COMPLETE — TAKE ANOTHER RUN");return
	c.engagement_enabled=phase in ["opening","combat","boss"]
	if phase=="anticipation":
		for enemy: Dictionary in c.enemies:
			if enemy.health>0 and enemy.kind!="boss":enemy.retiring=true
	var delta: Vector3=route_target()-app.flight.position
	if Vector2(delta.x,delta.z).length()<550 and route_index<SHOWCASE_POINTS.size()-1:
		visited_route.append(route_index);route_index+=1
	if app.demo_auto_fire and app.copilot and clock>14 and not roll_demo_done:
		roll_demo_done=app.flight.start_barrel_roll(1)
		if roll_demo_done:c.event("roll",app.flight.position,1)
	if app.world.has_method("update_showcase"):app.world.update_showcase(app.flight.position,act,c.intent.intensity,dt)

func _showcase_controls() -> Vector3:
	var f: FlightDynamics=app.flight
	if not f.airborne:
		f.throttle=1;f.gear=true;f.flaps=1
		return Vector3(0,.85 if f.speed>f.effective_rotation_speed() else 0,clampf(-f.position.x*.03-f.heading*3,-1,1))
	f.gear=false;f.flaps=0
	var desired: Vector3=route_target()
	var wanted_speed: float=380 if clock<65 else 265
	if phase in ["boss","aftermath"]:desired=f.position+f.forward()*1400;desired.y=clampf(f.position.y,300,650)
	if app.demo_auto_fire:
		var tracked: Dictionary=app.combat.target()
		if not tracked.is_empty():
			var lead: Vector3=app.combat.lead_point(tracked)
			# Keep the fast SF route in view; only chase contacts already along it.
			var route_direction: Vector3=(desired-f.position).normalized()
			if phase=="boss" or route_direction.angle_to((lead-f.position).normalized())<deg_to_rad(14):desired=lead
	var ground: float=app.world.ground_height(f.position.x,f.position.z)
	for distance in [250.0,600.0,1000.0]:
		var p: Vector3=f.position+f.forward()*distance;ground=maxf(ground,app.world.ground_height(p.x,p.z))
	desired.y=maxf(desired.y,ground+130)
	var delta: Vector3=desired-f.position
	var error: float=wrapf(atan2(delta.x,-delta.z)-f.heading,-PI,PI)
	var bank: float=clampf(error*1.8,-.85,.85)
	var pitch: float=clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),300)),-.20,.32)
	f.throttle=clampf(.35+(wanted_speed-f.speed)*.055,0,1)
	f.afterburner=clock<12 or (clock>28 and clock<33)
	f.power_input=1 if f.afterburner else -.55 if clock>33 and clock<34 else 0
	return Vector3(clampf((bank-f.roll)*4-f.roll_velocity*.25,-1,1),clampf((pitch-f.pitch)*4.5-f.pitch_velocity*.25,-1,1),clampf(error*1.4,-1,1))
