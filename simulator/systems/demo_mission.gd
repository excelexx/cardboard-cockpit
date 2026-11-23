extends RefCounted
class_name DemoMission
const Tune = preload("res://data/balance.gd")
## A continuous departure, valley engagement, recovery and landing.
const CoastalRoute = preload("res://systems/scenic_route.gd")
const SFRoute = preload("res://systems/san_francisco_route.gd")
const Outcome = preload("res://systems/sortie_result.gd")
const GOOSE_FLIGHT_PATH := "res://systems/goose_flight.gd"
## Fallback flock course, used only when GooseFlight has none: a crossing
## course at goose cruise, never the player's vector and never the player's
## speed.
const FLOCK_CROSS_DEGREES := 40.0
const FLOCK_SPEED := 19.0
const FLOCK_REGROUP_DISTANCE := 900.0
const FLOCK_SPREAD := 130.0
const FLOCK_CLOSE_RATE := 70.0
## The big skein arrives as three chevrons of four strung along the run-in, the
## nearest one first. Twelve birds inside one 200 m clump is a single missile
## salvo and the act is over in a second and a half; spread down the approach
## they are three merges and a real act, with every individual bird exactly as
## big, as slow and as easy to hit as it was before.
const FLOCK_CHEVRON := 4
const FLOCK_CHEVRON_GAP := 1700.0
const FLOCK_CHEVRON_OFFSET := 340.0
## Life in the held formation. The director drives every contact's weave off
## enemy.age, and the act pins age below the chase threshold, so the weave has
## to be flown from here instead: one slow undulation and one slow bob per
## chevron, shared by the four birds of a V so the shape holds while the whole
## line moves. Small next to a 16-24 m/s course - the flock reads alive, never
## evasive.
const FLOCK_FROZEN_AGE := 7.5
const FLOCK_WANDER_RATE := 0.55
const FLOCK_WANDER_SPEED := 7.0
const FLOCK_BOB_RATE := 0.4
const FLOCK_BOB_HEIGHT := 7.0
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
var flock_course := Vector3.ZERO
var flock_altitude := 0.0
var flock_chevron: Dictionary = {}
## Each bird's own leader heading, kept here rather than read back out of
## enemy.course: the course handed to the director carries the wander, and
## reading that back would let the wander integrate into the heading.
var flock_heading: Dictionary = {}
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
	flock_course=Vector3.ZERO;flock_altitude=0.0;flock_chevron.clear();flock_heading.clear();Outcome.cinematic_state={}
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
	if cinematic:return {"opening":"TAKE OFF","combat":"PACIFIC COAST","gather":"BIG FLOCK INCOMING","skein":"THE BIG FLOCK","aftermath":"HEAD HOME","approach":"LANDING","rollout":"BRAKING"}.get(phase,"FREE FLIGHT")
	return {"takeoff":"TAKE OFF","combat":"GEESE","return":"HEAD HOME","approach":"LANDING","rollout":"BRAKING"}.get(phase,"")
## "TITLE|words|[KEY]|words": the HUD draws the title in colour and [KEY] as a keycap.
func instruction() -> String:
	if cinematic:
		if phase=="aftermath":return "LAND AT SFO|Press badge|[B]|or|[L]"
		if phase=="approach":return "LANDING|The jet lands itself"
		if phase=="rollout":return "LANDED|Braking"
		if phase=="gather":return "BIG FLOCK INCOMING|Twelve geese, twelve o'clock"
		if phase=="skein":
			var left: int=skein_remaining()
			if phase_clock<4:return "SHOOT DOWN %d GEESE|Put the ring on a goose" % maxi(left,Tune.SKEIN_SIZE)
			if left==1:return "1 GOOSE LEFT|Put the ring on it"
			return "%d GEESE LEFT|Put the ring on a goose" % left if left>0 else ""
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
	if phase in ["approach","rollout"]:return
	if phase=="opening" and clock>=22:act=1;transition("combat")
	elif phase=="combat" and clock>=60:
		# Act 2 keeps its number so the world's act==2 fog beat is untouched.
		act=2;transition("gather");app.audio.radio.say("warning",2)
		var signature: Vector3=app.flight.position+app.flight.forward()*1700
		c.event("skein_signature",signature,4)
		c.event("scan",signature,1)
	elif phase=="gather" and clock>=64:
		act=3;transition("skein");_open_skein(c)
	if phase=="gather":
		# Clear the sky so the flock arrives on an empty stage.
		for enemy: Dictionary in c.enemies:
			if enemy.health>0:enemy.retiring=true
	elif phase=="skein":
		_drive_skein(c,dt)
		for enemy: Dictionary in c.enemies:
			# Strays that are not part of the flock bow out; the objective is
			# exactly the twelve birds that arrived together.
			if enemy.health>0 and not skein_has(int(enemy.id)):enemy.retiring=true
		if skein_spawned() and skein_remaining()==0:
			_close_skein(clock,skein_down>=skein_total());app.audio.radio.say("cleared",2)
		elif clock>=Tune.SKEIN_DEADLINE:
			_close_skein(clock,false)
			for enemy: Dictionary in c.enemies:enemy.retiring=true
	_publish_outcome()
	if phase=="aftermath" and (clock-skein_cleared_at>=7 or clock>=Tune.DEMO_LIMIT):
		app.begin_landing()
		return
	if clock>=Tune.DEMO_LIMIT:
		app.finish_sortie(skein_success,"The flock is down." if skein_success else "Time is up.");return
	c.engagement_enabled=phase in ["opening","combat","skein"]
	var delta: Vector3=route_target()-app.flight.position
	if Vector2(delta.x,delta.z).length()<550 and route_index<SHOWCASE_POINTS.size()-1:
		visited_route.append(route_index);route_index+=1
	if app.demo_auto_fire and app.copilot and clock>14 and not roll_demo_done:
		roll_demo_done=app.flight.start_barrel_roll(1)
		if roll_demo_done:c.event("roll",app.flight.position,1)
	if app.world.has_method("update_showcase"):app.world.update_showcase(app.flight.position,act,c.intent.intensity,dt)

## ---------------------------------------------------------------------------
## The big flock. One V of twelve arrives at clock 64 and is the whole objective
## from there to the SKEIN_DEADLINE. Every accessor prefers the combat
## director's own flock API and falls back to mission-side bookkeeping, so the
## showcase runs whether or not the director has landed its half yet.
## ---------------------------------------------------------------------------
func _combat_flock() -> bool: return app.combat.has_method("spawn_skein")

func skein_has(id: int) -> bool:
	var ids: Variant=app.combat.get("skein_ids")
	if ids is Array:return (ids as Array).has(id)
	return skein_ids.has(id)

func skein_total() -> int:
	if skein_final:return skein_size
	var reported: Variant=app.combat.get("skein_total")
	if reported!=null and int(reported)>0:return int(reported)
	return skein_ids.size()+skein_pending

func skein_remaining() -> int:
	if skein_final:return maxi(0,skein_total()-skein_down)
	if _combat_flock() and app.combat.has_method("skein_remaining"):return int(app.combat.skein_remaining())+skein_pending
	return skein_alive.size()+skein_pending

func skein_spawned() -> bool: return skein_pending==0 and skein_total()>0

## Open the act: twelve geese in one V, a couple of birds per frame so the
## flock forms in the air instead of popping in whole.
func _open_skein(c: CombatDirector) -> void:
	flock_course=_flock_course(c)
	if _combat_flock():
		c.spawn_skein(Tune.SKEIN_SIZE,flock_course)
		var ids: Variant=c.get("skein_ids")
		if ids is Array:
			for id: int in ids as Array:
				if not skein_ids.has(id):skein_ids.append(id);skein_alive.append(id)
		skein_pending=0
		return
	skein_pending=Tune.SKEIN_SIZE

## Latch the tally before the stragglers retire, so the debrief stays honest:
## only birds actually shot down count, never birds that simply went away.
func _close_skein(at: float,won: bool) -> void:
	skein_size=maxi(skein_total(),Tune.SKEIN_SIZE if skein_ids.is_empty() else skein_ids.size())
	skein_down=clampi(skein_down,0,skein_size)
	skein_success=won and skein_down>=skein_size
	skein_final=true
	skein_cleared_at=at;transition("aftermath");act=4

func _drive_skein(c: CombatDirector,dt: float) -> void:
	if skein_pending>0:_spawn_slice(c)
	_tally_skein(c)
	if not _combat_flock():_hold_formation(c,dt)

## A goose does not fly the player's heading at the player's speed. The flock
## takes its course and its slot shape from GooseFlight when that file is
## present, and falls back to a crossing course at goose cruise when it is not.
func _goose_call(method: String,argument: Variant) -> Variant:
	if not ResourceLoader.exists(GOOSE_FLIGHT_PATH):return null
	var flight_script: Variant=load(GOOSE_FLIGHT_PATH)
	if flight_script==null:return null
	for entry: Dictionary in flight_script.get_script_method_list():
		if entry.name!=method or entry.args.size()!=1:continue
		var wanted: int=int(Dictionary(entry.args[0]).get("type",TYPE_NIL))
		if wanted==TYPE_OBJECT and not (argument is Object):return null
		if wanted in [TYPE_INT,TYPE_FLOAT] and argument is Object:return null
		return flight_script.call(method,argument)
	return null

func _flock_course(c: CombatDirector) -> Vector3:
	var supplied: Variant=_goose_call("skein_course",c)
	if supplied is Vector3 and (supplied as Vector3).length()>0.5 and (supplied as Vector3).length()<40.0:
		return supplied
	var track: float=app.flight.heading+deg_to_rad(FLOCK_CROSS_DEGREES)
	return Vector3(sin(track),0,-cos(track))*FLOCK_SPEED

## A seat on the V, leader-relative, in the flock's own frame.
func _flock_slot(course: Vector3,rank: int) -> Vector3:
	var flat:=Vector3(course.x,0.0,course.z)
	flat=flat.normalized() if flat.length()>0.01 else Vector3.FORWARD
	var wing: Vector3=flat.cross(Vector3.UP)
	wing=wing.normalized() if wing.length()>0.001 else Vector3.RIGHT
	var slot: Variant=_goose_call("formation_slot",rank)
	var seat: Vector3=slot if slot is Vector3 else Vector3.ZERO
	if not (slot is Vector3) and rank>0:
		var step: int=(rank+1)/2
		seat=Vector3((1.0 if rank%2==1 else -1.0)*float(step)*Tune.SKEIN_SLOT_SIDE,float(step)*Tune.SKEIN_SLOT_RISE,float(step)*Tune.SKEIN_SLOT_BACK)
	return wing*seat.x+Vector3.UP*seat.y-flat*seat.z

func _spawn_slice(c: CombatDirector) -> void:
	var f: FlightDynamics=app.flight
	var forward:=Vector3(sin(f.heading),0,-cos(f.heading))
	var right:=Vector3(cos(f.heading),0,sin(f.heading))
	# One leader heading for the whole skein, taken once when the act opened.
	# Asking for it per bird spreads the birds of a single chevron across ~21
	# degrees (GooseFlight fans the heading by contact id), which fans the V
	# open before it is even built and never closes again.
	if flock_course.length()<1.0:flock_course=_flock_course(c)
	var course: Vector3=flock_course
	for i in range(mini(Tune.SKEIN_SPAWN_PER_FRAME,skein_pending)):
		var index: int=skein_ids.size()
		var chevron: int=index/FLOCK_CHEVRON
		var seat: int=index%FLOCK_CHEVRON
		var lead: Vector3=f.position+Vector3.UP*Tune.SKEIN_SPAWN_HEIGHT
		lead+=forward*(Tune.SKEIN_SPAWN_DISTANCE+float(chevron)*FLOCK_CHEVRON_GAP)
		lead+=right*(float(chevron)*FLOCK_CHEVRON_OFFSET*(1.0 if chevron%2==1 else -1.0))
		var place: Vector3=lead+_flock_slot(course,seat)
		c.spawn_contact("goose")
		if c.enemies.is_empty():break
		var bird: Dictionary=c.enemies.back()
		bird.position=place
		bird.position.y=maxf(place.y,app.world.ground_height(place.x,place.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		bird.node.position=bird.position
		bird.course=course
		bird.velocity=course
		bird.retiring=false
		bird.age=0.0
		skein_ids.append(int(bird.id));skein_alive.append(int(bird.id))
		flock_chevron[int(bird.id)]=chevron
		flock_heading[int(bird.id)]=course
		skein_pending-=1

func _tally_skein(c: CombatDirector) -> void:
	var health: Dictionary={}
	for enemy: Dictionary in c.enemies:health[enemy.id]=enemy.health
	for i in range(skein_alive.size()-1,-1,-1):
		var id: int=skein_alive[i]
		if not health.has(id):skein_alive.remove_at(i)
		elif float(health[id])<=0.0:skein_down+=1;skein_alive.remove_at(i)

## Hold each chevron together and let it wheel back toward the fight after the
## jet has blown through it. Geese bank and regroup, they do not evaporate - and
## a flock that turns back is easier to finish, never harder.
func _hold_formation(c: CombatDirector,dt: float) -> void:
	var f: FlightDynamics=app.flight
	var centres: Dictionary={}
	var counts: Dictionary={}
	for enemy: Dictionary in c.enemies:
		if enemy.health<=0 or not skein_ids.has(int(enemy.id)):continue
		var chevron: int=int(flock_chevron.get(int(enemy.id),0))
		centres[chevron]=Vector3(centres.get(chevron,Vector3.ZERO))+enemy.position
		counts[chevron]=int(counts.get(chevron,0))+1
	if counts.is_empty():return
	for chevron: int in counts:centres[chevron]=Vector3(centres[chevron])/float(counts[chevron])
	if flock_altitude<=0.0:flock_altitude=Vector3(centres.values()[0]).y
	else:flock_altitude+=flock_course.y*dt
	var turn: float=deg_to_rad(Tune.SKEIN_LEAD_ROTATE)*dt
	for enemy: Dictionary in c.enemies:
		if enemy.health<=0 or not skein_ids.has(int(enemy.id)):continue
		# The director retires any contact the jet has blown past and culls it
		# once it has faded out. A 19 m/s flock is behind a 265 m/s jet within
		# seconds, so the flock is held present until the act is over: the geese
		# wait to be finished off instead of dissolving at the first overshoot.
		enemy.retiring=false
		enemy.fade=1.0
		# Held below the director's chase threshold so the flock keeps its own
		# slow course instead of being dragged up to jet speed.
		if enemy.age>FLOCK_FROZEN_AGE:enemy.age=FLOCK_FROZEN_AGE
		# Pinning age also pins the director's own weave, which is a sin/cos of
		# age: every bird would freeze into a constant cross-drift of up to
		# +/-16 m/s and tear the V apart. Subtract that frozen term back out and
		# fly the wander from the mission clock instead.
		var bird_phase: float=float(enemy.get("phase",0.0))
		# The director advances age by dt before it weaves, and mission.tick
		# runs first (main.gd), so this is exactly the term it will add.
		var weave_age: float=float(enemy.age)+dt
		var frozen: Vector3=Vector3(enemy.get("right",Vector3.RIGHT))*sin(weave_age*.55+bird_phase)*Tune.CONTACT_WEAVE_SPEED
		frozen+=Vector3.UP*cos(weave_age*.4+bird_phase)*Tune.CONTACT_VERTICAL_SPEED
		var chevron_index: int=int(flock_chevron.get(int(enemy.id),0))
		var course: Vector3=Vector3(flock_heading.get(int(enemy.id),flock_course))
		course.y=0
		if course.length()<1.0:course=Vector3(flock_course.x,0,flock_course.z)
		if course.length()<1.0:course=Vector3.FORWARD*FLOCK_SPEED
		var to_jet: Vector3=f.position-enemy.position;to_jet.y=0
		if to_jet.length()>FLOCK_REGROUP_DISTANCE:
			var wanted: Vector3=to_jet.normalized()*course.length()
			var spread: float=course.angle_to(wanted)
			if spread>0.0001:course=course.slerp(wanted,clampf(turn/spread,0,1))
		course=course.normalized()*clampf(course.length(),16.0,24.0)
		flock_heading[int(enemy.id)]=course
		# One undulation per chevron, shared by its four birds, so the V holds
		# its shape while the whole line snakes the way a skein does.
		var wing: Vector3=Vector3(course.z,0,-course.x).normalized()
		var wander: Vector3=wing*sin(clock*FLOCK_WANDER_RATE+float(chevron_index)*2.1)*FLOCK_WANDER_SPEED
		enemy.course=course+wander-frozen
		# Cohesion, chevron by chevron. While the jet is past them the director
		# pushes stray contacts sideways and up; the chevron closes that gap back
		# up instead of smearing across the sky, and holds its altitude band.
		var pull: Vector3=Vector3(centres[chevron_index])-enemy.position;pull.y=0
		var gap: float=pull.length()
		if gap>FLOCK_SPREAD:enemy.position+=pull/gap*minf(gap-FLOCK_SPREAD,FLOCK_CLOSE_RATE*dt)
		var band: float=flock_altitude+sin(clock*FLOCK_BOB_RATE+float(chevron_index)*1.7)*FLOCK_BOB_HEIGHT
		enemy.position.y=lerpf(enemy.position.y,band,clampf(dt*.9,0,1))
		enemy.position.y=maxf(enemy.position.y,app.world.ground_height(enemy.position.x,enemy.position.z)+Tune.CONTACT_FLIGHT_CLEARANCE)
		enemy.node.position=enemy.position

func _publish_outcome() -> void:
	Outcome.cinematic_state={"total":skein_total(),"down":mini(skein_down,skein_total()),"cleared":skein_success}

## Where the autopilot points during the act: the middle of what is left of the
## flock, or straight ahead once the sky is clear.
func _skein_focus(f: FlightDynamics) -> Vector3:
	var centre:=Vector3.ZERO;var count:=0
	for enemy: Dictionary in app.combat.enemies:
		if enemy.health>0 and skein_has(int(enemy.id)):centre+=enemy.position;count+=1
	if count==0:
		var ahead: Vector3=f.position+f.forward()*1400
		ahead.y=clampf(f.position.y,300,650)
		return ahead
	return centre/float(count)

func _showcase_controls() -> Vector3:
	var f: FlightDynamics=app.flight
	if not f.airborne:
		f.throttle=1;f.gear=true;f.flaps=1
		return Vector3(0,.85 if f.speed>f.effective_rotation_speed() else 0,clampf(-f.position.x*.03-f.heading*3,-1,1))
	f.gear=false;f.flaps=0
	var desired: Vector3=route_target()
	var wanted_speed: float=380 if clock<65 else 265
	if phase in ["skein","aftermath"]:desired=_skein_focus(f)
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
	f.power_input=1 if f.afterburner else -.55 if clock>33 and clock<34 else 0
	return Vector3(clampf((bank-f.roll)*4-f.roll_velocity*.25,-1,1),clampf((pitch-f.pitch)*4.5-f.pitch_velocity*.25,-1,1),clampf(error*1.4,-1,1))
