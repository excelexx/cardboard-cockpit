extends RefCounted
class_name DemoMission
const Tune = preload("res://data/balance.gd")
## Endless scenic flock encounters until the pilot requests a landing.
const CoastalRoute = preload("res://systems/scenic_route.gd")
const SFRoute = preload("res://systems/san_francisco_route.gd")
const Outcome = preload("res://systems/sortie_result.gd")
const GOOSE_FLIGHT_PATH := "res://systems/goose_flight.gd"
## The flock crosses the showcase route at this angle at a real goose speed.
## Shallower than a right-angle merge on purpose: a 19 m/s target crossed by a
## 265 m/s jet at ninety degrees is the shortest firing window in the game.
const FLOCK_CROSS_DEGREES := 40.0
const FLOCK_SPEED := 19.0
const FLOCK_REGROUP_DISTANCE := 900.0
const FLOCK_SPREAD := 1000.0
const FLOCK_CLOSE_RATE := 20.0
const SECOND_WAVE_SIZE := 2
const WAVE_SECONDS := 18.0
const FIRST_WAVE_AIRBORNE_SECONDS := 10.0
const MAX_WAVE_SIZE := 3
const HISTORY_LIMIT := 32
const WAVE_BREAK_SECONDS := 3.0
func route_points() -> Array[Vector3]: return SHOWCASE_POINTS if cinematic else SFRoute.POINTS if app.route_id=="sf" else CoastalRoute.POINTS
func route_names() -> Array[String]: return SHOWCASE_NAMES if cinematic else SFRoute.NAMES if app.route_id=="sf" else CoastalRoute.NAMES
# Scenic showcase: over the coast range to the Pacific cliffs, up Ocean Beach with the
# city as a hazy backdrop, through the Golden Gate and into the Marin Headlands.
const SHOWCASE_POINTS: Array[Vector3]=[Vector3(2600,420,-3200),Vector3(-3400,680,-6800),Vector3(-3600,340,-9600),Vector3(0,300,-11700),Vector3(4500,270,-15100),Vector3(10300,300,-18700),Vector3(16000,390,-19200),Vector3(17600,720,-25500)]
const SHOWCASE_NAMES: Array[String]=["SFO DEPARTURE","COAST RANGE","PACIFIC CLIFFS","DALY CITY CLIFFS","OCEAN BEACH","LANDS END","GOLDEN GATE","MARIN HEADLANDS"]
var cinematic := false
var act := 0
var skein_cleared_at := -1.0
## Flock bookkeeping. The counters are kept here as well as in the combat
## director so the mission still knows the score when the director has no
## flock API yet, and so the debrief can be honest after stragglers retire.
var skein_ids: Array[int] = []
var skein_alive: Array[int] = []
var skein_pending := 0
var skein_down := 0
var skein_success := false
var skein_final := false
var skein_size := 0
var wave_number := 0
var wave_size := 0
var wave_ids: Array[int] = []
var airborne_clock := 0.0
var empty_view_clock := 0.0
const STREAM_MIN_DISTANCE := 600.0
const STREAM_MAX_DISTANCE := 1500.0
const SPAWN_INTERVAL := 10.0
var next_spawn_at := 0.0
var stream_gap := 1050.0
var stream_distance := 0.0
var stream_position := Vector3.ZERO
var wave_tail_clock := 0.0
const EMPTY_VIEW_SECONDS := 4.0
var observed_down := 0
var sortie_kill_base := 0
var wave_kill_base := 0
var last_wave_cleared := false
var skein_killed: Array[int] = []
var flock_course := Vector3.ZERO
var flock_altitude := 0.0
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
	cinematic=enabled and app.route_id=="sf";act=0;skein_cleared_at=-1;roll_demo_done=false
	skein_ids.clear();skein_alive.clear();skein_pending=0;skein_down=0;skein_success=false;skein_final=false;skein_size=0
	wave_number=0;wave_size=0;wave_ids.clear();skein_killed.clear()
	next_spawn_at=0;airborne_clock=0;empty_view_clock=0;observed_down=0;sortie_kill_base=app.combat.kills;wave_kill_base=sortie_kill_base;last_wave_cleared=false
	flock_course=Vector3.ZERO;flock_altitude=0.0;Outcome.cinematic_state={}
	if cinematic:
		app.combat.managed_mission=true;app.combat.spawn_clock=INF;app.combat.engagement_enabled=false
		phase="opening";app.flight.speed=0;app.flight.engine=0;app.flight.throttle=0;app.flight.flaps=1
	if enabled: history.append({"phase":phase,"time":0.0,"position":app.flight.position})
func transition(next: String) -> void:
	if phase==next: return
	phase = next; phase_clock = 0
	history.append({"phase":phase,"time":clock,"position":app.flight.position})
	if history.size()>HISTORY_LIMIT:history.pop_front()
	if cinematic and phase in ["approach","rollout"]:end_waves()
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
	if cinematic:return {"opening":"TAKE OFF","combat":"PACIFIC COAST","gather":"BIG FLOCK INCOMING","skein":wave_label(),"wave_break":"NEXT WAVE INCOMING","aftermath":"FREE FLIGHT","approach":"LANDING","rollout":"BRAKING"}.get(phase,"FREE FLIGHT")
	return {"takeoff":"TAKE OFF","combat":"GEESE","return":"HEAD HOME","approach":"LANDING","rollout":"BRAKING"}.get(phase,"")
## "TITLE|words|[KEY]|words": the HUD draws the title in colour and [KEY] as a keycap.
func instruction() -> String:
	if cinematic:
		if phase=="aftermath":return "LAND WHEN READY|Press badge|[B]"
		if phase=="approach":return "LANDING|Follow the runway and brake after touchdown"
		if phase=="rollout":return "LANDED|Braking"
		if phase=="gather":return "FIRST FLOCK INCOMING|Six geese ahead"
		if phase=="wave_break":return ("WAVE %d CLEAR|" % wave_number if last_wave_cleared else "NEXT WAVE|")+"%d fresh geese incoming" % size_for_wave(wave_number+1)
		if app.flight.airborne and app.flight.gear and not app.demo_auto_fire:return "GEAR UP|Press badge|[A]|or|[G]"
		if phase=="skein":return "%s|%d geese — aim and hold primary|Land any time with|[B]" % [wave_label(),wave_size] if phase_clock<4 else ""

		return ""
	if app.route_id in ["coast","sf"] and phase in ["combat","return"]: return "GO TO|"+route_names()[mini(route_index,route_names().size()-1)].capitalize()+"|Follow the diamond"
	if phase=="takeoff": return "TAKE OFF|Hold|[W]|Pull up at 105 knots" if not app.flight.airborne else "GEAR UP|Press|[G]"
	if phase=="combat": return "AIM|Put the ring on a goose"
	if phase=="return": return "HEAD HOME|Slow down for the runway"
	if phase=="approach": return "LANDING|Gear down, flaps 2, keep the diamond centered"
	return "LANDED|Hold|[SPACE]|to brake"
func controls() -> Vector3:
	if cinematic:return app.approach_controls() if phase=="approach" else _showcase_controls()
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
	if not skein_final:_tally_skein(c)
	if app.landing_started or phase in ["approach","rollout"]:
		end_waves();_publish_outcome();return
	if skein_final:return
	# Only this director owns arrivals. Prevent incidental ambient spawns and
	# the combat director's finite patrol timer from ending an endless flight.
	c.managed_mission=true;c.spawn_clock=INF
	airborne_clock = airborne_clock+dt if app.flight.airborne else 0.0
	if phase=="opening" and airborne_clock>=FIRST_WAVE_AIRBORNE_SECONDS-2.0:
		act=2;transition("gather");app.audio.radio.say("warning",2)
		var signature: Vector3=app.flight.position+app.flight.forward()*1700
		c.event("skein_signature",signature,4);c.event("scan",signature,1)
	elif phase=="gather" and app.flight.airborne and airborne_clock>=FIRST_WAVE_AIRBORNE_SECONDS and _spawn_visible(c):
		act=3;transition("skein");_open_skein(c,1)
	elif phase=="wave_break" and app.flight.airborne:
		stream_distance+=app.flight.position.distance_to(stream_position);stream_position=app.flight.position
		if clock>=next_spawn_at and _spawn_visible(c):transition("skein");_open_skein(c,wave_number+1)
	if phase=="skein":
		_drive_skein(c,dt)
		if skein_spawned() and wave_remaining()==0:_finish_wave(c,true)
		else:
			empty_view_clock=0.0 if _flock_ahead(c) else empty_view_clock+dt
			if skein_spawned():wave_tail_clock+=dt
			if wave_tail_clock>=WAVE_SECONDS or (skein_spawned() and (empty_view_clock>=EMPTY_VIEW_SECONDS or clock>=next_spawn_at)):_finish_wave(c,false)
	_publish_outcome()
	c.engagement_enabled=phase=="skein"
	var delta: Vector3=route_target()-app.flight.position
	if Vector2(delta.x,delta.z).length()<550 and route_index<SHOWCASE_POINTS.size()-1:
		visited_route.append(route_index);route_index+=1
	if app.demo_auto_fire and app.copilot and clock>14 and not roll_demo_done:
		roll_demo_done=app.flight.start_barrel_roll(1)
		if roll_demo_done:c.event("roll",app.flight.position,1)
	if app.world.has_method("update_showcase"):app.world.update_showcase(app.flight.position,act,c.intent.intensity,dt)

func _flock_ahead(c: CombatDirector) -> bool:
	var forward: Vector3=app.flight.forward()
	for enemy: Dictionary in c.enemies:
		if enemy.health<=0 or not wave_ids.has(int(enemy.id)):continue
		var delta: Vector3=enemy.position-app.flight.position
		if delta.length()<5000 and forward.dot(delta.normalized())>cos(deg_to_rad(55)):return true
	return false

## Endless waves retain only current-wave IDs. Scalar totals count actual
## arrivals and actual kills; expired or missing birds never become takedowns.
func _combat_flock() -> bool: return app.combat.has_method("spawn_skein")
func skein_has(id: int) -> bool: return skein_ids.has(id)
func skein_total() -> int: return skein_size if cinematic else 0
func skein_remaining() -> int: return maxi(0,skein_total()-skein_down)
func skein_spawned() -> bool: return wave_number>0 and skein_pending==0 and wave_ids.size()==wave_size
func wave_down() -> int:
	# Combat increments kills at the fatal hit; this also catches a real kill
	# whose corpse was removed before the next mission tick.
	return clampi(maxi(skein_killed.size(),app.combat.kills-wave_kill_base),0,wave_ids.size())
func wave_remaining() -> int: return maxi(0,wave_size-wave_down())
func wave_label() -> String: return "WAVE %d" % wave_number if wave_number>0 else "ENDLESS GEESE"
func size_for_wave(number: int) -> int:
	return 2 if number%2==1 else 3

func _open_skein(c: CombatDirector,number: int = 1) -> void:
	if skein_final or app.landing_started or phase in ["approach","rollout"]:return
	_tally_skein(c)
	# The break lets survivors fade. Any remaining contact is now removed as
	# a retired target, with no health mutation and no score/kill event.
	for enemy: Dictionary in c.enemies:
		if is_instance_valid(enemy.node):enemy.node.queue_free()
	c.enemies.clear();c.target_id=-1;c.lock_progress=0;c.spawn_clock=INF
	empty_view_clock=0;stream_gap=randf_range(STREAM_MIN_DISTANCE,STREAM_MAX_DISTANCE);stream_distance=stream_gap;stream_position=app.flight.position;wave_tail_clock=0
	wave_number=number;wave_size=size_for_wave(number);wave_kill_base=c.kills
	wave_ids.clear();skein_ids.clear();skein_alive.clear();skein_killed.clear();flock_altitude=0.0
	flock_course=_flock_course(app.flight.heading)
	skein_pending=wave_size
	c.announce("WAVE %d — %d GEESE" % [wave_number,wave_size])

func _finish_wave(c: CombatDirector,cleared: bool) -> void:
	last_wave_cleared=cleared
	transition("wave_break");c.engagement_enabled=false
	c.announce("WAVE %d CLEAR — %d MORE INCOMING" % [wave_number,size_for_wave(wave_number+1)] if cleared else "WAVE %d: %d DOWN — %d FRESH GEESE NEXT" % [wave_number,wave_down(),size_for_wave(wave_number+1)])
	if cleared:
		app.audio.radio.say("cleared",2);c.event("reward",app.flight.position+app.flight.forward()*500,1)
	for enemy: Dictionary in c.enemies:
		if enemy.health>0:enemy.retiring=true

func end_waves() -> void:
	if skein_final:return
	_tally_skein(app.combat)
	skein_final=true;skein_pending=0;skein_cleared_at=clock
	app.combat.engagement_enabled=false;app.combat.spawn_clock=INF
	for enemy: Dictionary in app.combat.enemies:
		if enemy.health>0:enemy.retiring=true
	_publish_outcome()

func request_landing() -> void:
	end_waves();transition("approach")

func _drive_skein(c: CombatDirector,dt: float) -> void:
	stream_distance+=app.flight.position.distance_to(stream_position)
	stream_position=app.flight.position
	if skein_pending>0 and clock>=next_spawn_at and _spawn_visible(c):
		_spawn_slice(c)
		next_spawn_at=clock+SPAWN_INTERVAL
	_tally_skein(c)
	if not _combat_flock():_hold_formation(c,dt)

## A goose does not fly the player's heading at the player's speed. The flock
## gets its own course from GooseFlight when that exists, clamped to a real
## 16-24 m/s either way.
func _flock_course(heading: float) -> Vector3:
	var track: float=heading+deg_to_rad(FLOCK_CROSS_DEGREES)
	var course:=Vector3(sin(track),0,-cos(track))*FLOCK_SPEED
	if ResourceLoader.exists(GOOSE_FLIGHT_PATH):
		var flight_script: Variant=load(GOOSE_FLIGHT_PATH)
		if flight_script!=null:
			for entry: Dictionary in flight_script.get_script_method_list():
				if entry.name=="skein_course" and entry.args.size()==1:
					var supplied: Variant=flight_script.skein_course(app.combat) if int(entry.args[0].get("type",TYPE_NIL))==TYPE_OBJECT else flight_script.skein_course(heading)
					if supplied is Vector3:
						var candidate: Vector3=supplied
						candidate.y=0
						if candidate.length()>0.5:course=candidate
					break
	return course.normalized()*clampf(course.length(),16.0,24.0)

func _wave_position(c: CombatDirector,index: int) -> Vector3:
	var next_number: int=wave_number+1 if phase in ["opening","gather","wave_break"] else wave_number
	var side: float=1.0 if next_number%2==0 else -1.0
	var lateral: float=[120.0,-90.0,90.0][index%3]*side
	var point: Vector3=c.spawn_sight_point(Tune.GOOSE_SPAWN_DISTANCE+index*Tune.GOOSE_DEPTH_SPACING)+c.spawn_sight_right()*lateral
	point.y=maxf(point.y,app.world.ground_height(point.x,point.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
	return point

func _spawn_visible(c: CombatDirector) -> bool:
	for i in range(MAX_WAVE_SIZE):
		if not c.spawn_point_clear(_wave_position(c,i)):return false
	return true

func _spawn_slice(c: CombatDirector) -> void:
	var count: int=skein_pending
	for i in range(count):
		if c.enemies.size()>=MAX_WAVE_SIZE:break
		var place: Vector3=_wave_position(c,i)
		var previous_count: int=c.enemies.size()
		c.spawn_contact("goose")
		if c.enemies.size()<=previous_count:break
		var bird: Dictionary=c.enemies.back()
		bird.position=place
		bird.node.position=bird.position
		bird.formation_altitude=bird.position.y
		bird.course=flock_course
		bird.velocity=flock_course
		bird.retiring=false
		bird.age=0.0
		skein_ids.append(int(bird.id));skein_alive.append(int(bird.id));wave_ids.append(int(bird.id))
		skein_pending-=1;skein_size+=1

func _tally_skein(c: CombatDirector) -> void:
	var health: Dictionary={}
	for enemy: Dictionary in c.enemies:health[enemy.id]=enemy.health
	for i in range(skein_alive.size()-1,-1,-1):
		var id: int=skein_alive[i]
		if not health.has(id):skein_alive.remove_at(i)
		elif float(health[id])<=0.0:
			if not skein_killed.has(id):skein_killed.append(id);observed_down+=1
			skein_alive.remove_at(i)

	skein_down=clampi(maxi(observed_down,c.kills-sortie_kill_base),0,skein_size)

## Hold the V together and let it wheel back toward the fight after the jet has
## blown through it. Geese bank and regroup, they do not evaporate - and a flock
## that turns back is easier to finish, never harder.
func _hold_formation(c: CombatDirector,dt: float) -> void:
	var f: FlightDynamics=app.flight
	var centre:=Vector3.ZERO;var count:=0
	for enemy: Dictionary in c.enemies:
		if enemy.health>0 and wave_ids.has(int(enemy.id)):centre+=enemy.position;count+=1
	if count==0:return
	centre/=float(count)
	if flock_altitude<=0.0:flock_altitude=centre.y
	var turn: float=deg_to_rad(Tune.SKEIN_LEAD_ROTATE)*dt
	for enemy: Dictionary in c.enemies:
		if enemy.health<=0 or not wave_ids.has(int(enemy.id)):continue
		# The director retires any contact the jet has blown past and culls it
		# once it has faded out. A 19 m/s flock is behind a 265 m/s jet within
		# seconds, so the flock is held present until the act is over: the geese
		# wait to be finished off instead of dissolving at the first overshoot.
		enemy.retiring=false
		enemy.fade=1.0
		# Held below the director's chase threshold so the flock keeps its own
		# slow course instead of being dragged up to jet speed.
		if enemy.age>7.5:enemy.age=7.5
		var course: Vector3=enemy.get("course",flock_course)
		course.y=0
		if course.length()<1.0:course=flock_course
		var to_jet: Vector3=f.position-enemy.position;to_jet.y=0
		if to_jet.length()>FLOCK_REGROUP_DISTANCE:
			var wanted: Vector3=to_jet.normalized()*course.length()
			var spread: float=course.angle_to(wanted)
			if spread>0.0001:course=course.slerp(wanted,clampf(turn/spread,0,1))
		enemy.course=course.normalized()*clampf(course.length(),16.0,24.0)
		# Each encounter keeps its own lane and height along the flight path.
		enemy.position.y=lerpf(enemy.position.y,float(enemy.get("formation_altitude",flock_altitude)),clampf(dt*.4,0,1))
		enemy.position.y=maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		enemy.node.position=enemy.position

func _publish_outcome() -> void:
	Outcome.cinematic_state={"total":skein_total(),"down":mini(skein_down,skein_total()),"cleared":skein_success}

## Where the autopilot points during the act: the middle of what is left of the
## flock, or straight ahead once the sky is clear.
func _skein_focus(f: FlightDynamics) -> Vector3:
	# Aim at one surviving bird rather than orbiting an empty formation centre.
	var choice: Dictionary={};var cost:=INF
	for enemy: Dictionary in app.combat.enemies:
		if enemy.health<=0 or not wave_ids.has(int(enemy.id)):continue
		var offset: Vector3=enemy.position-f.position
		var candidate: float=offset.length()+f.forward().angle_to(offset.normalized())*600
		if candidate<cost:cost=candidate;choice=enemy
	if not choice.is_empty():return app.combat.lead_point(choice)
	var ahead: Vector3=f.position+f.forward()*1400
	ahead.y=clampf(f.position.y,300,650)
	return ahead

func _showcase_controls() -> Vector3:
	var f: FlightDynamics=app.flight
	if not f.airborne:
		f.throttle=1;f.gear=true;f.flaps=1
		return Vector3(0,.85 if f.speed>f.effective_rotation_speed() else 0,clampf(-f.position.x*.03-f.heading*3,-1,1))
	if app.demo_auto_fire:f.gear=false;f.flaps=0
	var desired: Vector3=route_target()
	var wanted_speed: float=155 if phase in ["gather","skein","wave_break"] else 380 if clock<65 else 265
	if phase in ["skein","wave_break","aftermath"]:desired=_skein_focus(f)
	if app.demo_auto_fire:
		var tracked: Dictionary=app.combat.target()
		if not tracked.is_empty():
			var lead: Vector3=app.combat.lead_point(tracked)
			# Keep the fast SF route in view; only chase contacts already along it.
			var route_direction: Vector3=(desired-f.position).normalized()
			if phase=="skein" or route_direction.angle_to((lead-f.position).normalized())<deg_to_rad(14):desired=lead
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
	f.power_input=1 if f.afterburner else -.8 if phase in ["gather","skein","wave_break"] and f.speed>wanted_speed+8 else -.55 if clock>33 and clock<34 else 0
	return Vector3(clampf((bank-f.roll)*4-f.roll_velocity*.25,-1,1),clampf((pitch-f.pitch)*4.5-f.pitch_velocity*.25,-1,1),clampf(error*1.4,-1,1))
