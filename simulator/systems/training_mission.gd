extends DemoMission
class_name TrainingMission
const TARGET_COUNT := 16
const RING_RADIUS := 110.0
const DEPARTURE_Z := 1050.0
var airfield: Node3D
var points: Array[Vector3] = []
var ring_root: Node3D
var rings: Array[MeshInstance3D] = []
var previous_position := Vector3.ZERO
var runway_height := 0.0
var approach_index := 0
var landing_index := 0
var cruise_height := 0.0

func route_points() -> Array[Vector3]: return points
func route_names() -> Array[String]: return ["DEPARTURE","SIXTEEN TARGETS","CRUISE","LANDING STRIP"]
func route_target() -> Vector3:
	return points[mini(route_index,points.size()-1)] if not points.is_empty() else app.flight.position+app.flight.forward()*600

func reset(enabled: bool) -> void:
	cinematic=false
	if is_instance_valid(ring_root): ring_root.queue_free()
	if is_instance_valid(airfield): airfield.queue_free()
	airfield = null
	rings.clear(); points.clear(); visited_route.clear(); history.clear()
	active = enabled; phase = "takeoff"; clock = 0; phase_clock = 0; route_index = 0
	if not enabled: return
	runway_height = app.world.ground_height(0,DEPARTURE_Z)+float(app.profile().clearance)
	previous_position = app.flight.position
	points.assign([Vector3(0,runway_height+150,250),Vector3(0,runway_height+400,-1500),Vector3(0,runway_height+800,-3600)])
	history.append({"phase":phase,"time":0.0,"position":app.flight.position})
	app.combat.training_target_limit = TARGET_COUNT
	build_rings()

func transition(next: String) -> void:
	if phase==next: return
	phase = next; phase_clock = 0
	history.append({"phase":phase,"time":clock,"position":app.flight.position})
	if phase=="combat":
		build_cruise_route()
		app.combat.engagement_enabled = true
		for i in range(TARGET_COUNT): app.combat.spawn_contact()
	elif phase=="return":
		app.combat.announce("PREPARE TO LAND — REDUCE THROTTLE")
		app.audio.radio.say("checkpoint")
	update_visuals()
	print("DEMO PHASE: ",phase," time=",snappedf(clock,.01)," position=",app.flight.position)

func build_cruise_route() -> void:
	if is_instance_valid(airfield): airfield.queue_free()
	points.clear(); route_index = 0
	airfield = preload("res://systems/demo_airfield.gd").new(); app.add_child(airfield); airfield.setup(app)
	runway_height = airfield.position.y+float(app.profile().clearance)
	cruise_height = maxf(runway_height+900,app.flight.position.y+150)
	# Engage the geese along the high cruise section, then descend toward the field.
	for point: Vector3 in [Vector3(-600,0,24600),Vector3(-100,0,22000),Vector3(-750,0,19000),Vector3(100,0,16000),Vector3(-220,0,14000)]:
		var at: Vector3 = airfield.to_global(point)
		at.y = minf(cruise_height,app.flight.position.y+(airfield.DISTANCE-point.z)*.22)
		points.append(at)
	landing_index = points.size()
	# Begin landing preparation with ample distance to slow down and configure.
	for point: Vector3 in [Vector3(-150,0,12000),Vector3(-100,0,10000),Vector3(-50,0,8000),Vector3(0,0,6000),Vector3(0,0,4600),Vector3(0,0,3300),Vector3(0,0,2500),Vector3(0,0,1900),Vector3(0,0,1450),Vector3(0,0,1050)]:
		point.y = float(app.profile().clearance)+(point.z-airfield.AIM_Z)*.05241
		points.append(airfield.to_global(point))
	approach_index = landing_index+5
	build_rings()

func tick(dt: float) -> void:
	if not active: return
	clock += dt; phase_clock += dt
	_reposition_targets(false)
	var f: FlightDynamics = app.flight
	if phase in ["takeoff","combat","return","approach"] and f.airborne and route_index<(landing_index if phase=="combat" else points.size()):
		var target := route_target()
		var segment: Vector3 = f.position-previous_position
		var t := clampf((target-previous_position).dot(segment)/maxf(segment.length_squared(),.001),0,1)
		var crossed := false
		if is_instance_valid(airfield):
			var local: Vector3 = airfield.to_local(f.position)
			var gate: Vector3 = airfield.to_local(target)
			crossed = local.z<=gate.z and absf(local.x-gate.x)<2000
		if target.distance_to(previous_position+segment*t)<RING_RADIUS or crossed:
			visited_route.append(route_index); route_index += 1
			if phase=="takeoff" and route_index==points.size(): transition("combat")
			elif phase=="return" and route_index>=approach_index: transition("approach")
	if phase=="combat" and route_index>=landing_index:
		if app.combat.kills>=TARGET_COUNT: transition("return")
		else:
			# Give slower shooters more cruising room without circling or teleporting.
			build_cruise_route()
			_reposition_targets(true)
	# Rings guide the route; missing one must never lock the pilot above the runway.
	if phase in ["combat","return"] and app.combat.kills>=TARGET_COUNT and in_landing_corridor() and airfield.to_local(f.position).z<=4600:
		transition("approach")
		route_index = maxi(route_index,approach_index)
	if f.contact=="landed": transition("rollout")
	app.combat.engagement_enabled = phase=="combat"
	previous_position = f.position
	update_visuals()

func label() -> String:
	return {"takeoff":"01 / TAKE OFF","combat":"02 / CRUISE & CLEAR SIXTEEN GEESE","return":"03 / PREPARE TO LAND","approach":"04 / LAND","rollout":"TOUCHDOWN","secured":"DEMO COMPLETE"}.get(phase,"")

func instruction() -> String:
	var f: FlightDynamics = app.flight
	if phase=="takeoff":
		if not f.airborne: return "Increase throttle to take off" if f.speed<f.effective_rotation_speed() else "Gently tilt the yoke back to lift off"
		if f.gear: return "A / G: raise gear and flaps · follow the guide rings" if app.badge_prompts else "Raise gear and flaps · follow the guide rings"
		if f.flaps>0: return "F: retract flaps · follow the guide rings"
		return "Fly through the guide rings"
	if phase=="combat":
		if app.combat.kills>=TARGET_COUNT: return "Geese cleared · follow the guide rings toward the airfield"
		return ("Show plasma gun tag ID 4 to fire; cover it to stop" if app.vision.enabled else "HOLD SPACE / LEFT MOUSE: dual plasma")+(" · hold badge DOWN: tactical view" if app.badge_prompts else "")
	if phase in ["return","approach"]:
		if f.throttle>.3 or f.speed>(90 if phase=="approach" else 125): return "Reduce throttle and slow down · follow the landing guides"
		if not f.gear: return "A / G: lower landing gear · B / L: landing assist" if app.badge_prompts else "Lower landing gear or enable landing assist"
		if f.flaps<2: return "Deploy your landing flaps"
		if phase=="return": return "Follow the guide rings toward the landing strip"
		if f.position.y-runway_height<14: return "Throttle idle · gently raise the nose and touch down"
		return "Keep the wings level · descend through the rings"
	return "Touchdown · throttle idle · braking to a stop" if phase=="rollout" else "Sixteen targets cleared. Aircraft safely landed."

func in_landing_corridor() -> bool:
	if not active or not is_instance_valid(airfield): return false
	var at: Vector3 = airfield.to_local(app.flight.position)
	return at.z>=-airfield.LENGTH/2 and at.z<=14000 and absf(at.x)<clampf((at.z-airfield.AIM_Z)*.12,180,1600) and absf(wrapf(app.flight.heading-airfield.heading,-PI,PI))<deg_to_rad(60)

func guidance() -> Dictionary:
	var local: Vector3 = airfield.to_local(app.flight.position) if is_instance_valid(airfield) else app.flight.position
	var remaining: float = maxf(local.z-(airfield.AIM_Z if is_instance_valid(airfield) else DEPARTURE_Z),0)
	var height: float = runway_height+remaining*.05241
	return {"distance":remaining,"ideal_height":height,"localizer":clampf(-local.x/180,-1,1),"glideslope":clampf((height-app.flight.position.y)/75,-1,1),"center_error":local.x,"height_error":app.flight.position.y-height,"on_path":absf(local.x)<40 and absf(app.flight.position.y-height)<25}

func controls() -> Vector3:
	var f: FlightDynamics = app.flight
	if not f.airborne:
		f.throttle = 1 if clock>1.5 else 0; f.gear = true; f.flaps = 1
		return Vector3(0,.7 if f.speed>f.effective_rotation_speed() else 0,clampf(-f.position.x*.03-f.heading*3,-1,1))
	if phase=="approach": return landing_controls()
	var target := route_target()
	if phase=="combat":
		var nearest := 2200.0
		for enemy: Dictionary in app.combat.enemies:
			var offset: Vector3 = enemy.position-f.position
			if enemy.health>0 and offset.dot(f.forward())>100 and offset.length()<nearest:
				nearest = offset.length(); target = app.combat.lead_point(enemy)
		if route_index>=landing_index and nearest==2200.0:
			target = f.position+f.forward()*800; target.y = cruise_height
	var delta: Vector3 = target-f.position
	var error: float = wrapf(atan2(delta.x,-delta.z)-f.heading,-PI,PI)
	var bank: float = clampf(error*1.6,-.65,.65)
	var pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),220)),-.20,.27)
	var speed: float = 115 if phase=="takeoff" else 135 if phase=="combat" else 115
	if phase=="return" and app.landing_started:f.gear=true;f.flaps=2
	f.afterburner=false
	f.throttle = clampf(.1+(speed-f.speed)*.05,0,1)
	return Vector3(clampf((bank-f.roll)*4-f.roll_velocity*.3,-1,1),clampf((pitch-f.pitch)*5-f.pitch_velocity*.3,-1,1),clampf(error*.8,-1,1))

func landing_controls() -> Vector3:
	var f: FlightDynamics = app.flight
	var data := guidance()
	var local: Vector3 = airfield.to_local(f.position)
	var error: float = wrapf(airfield.heading+atan2(-local.x,1200)-f.heading,-PI,PI)
	var pitch: float = clampf(-atan(.05241)+(float(data.ideal_height)-f.position.y)*.003,-.14,.08)
	if f.position.y-runway_height<10: pitch = -.018
	f.gear = true; f.flaps = 2; f.afterburner = false
	f.throttle = clampf(.16+(68-f.speed)*.06,0,1)
	return Vector3(clampf((error*1.6-f.roll)*3-f.roll_velocity*.3,-1,1),clampf((pitch-f.pitch)*4-f.pitch_velocity*.3,-1,1),clampf(error*.7,-.5,.5))

func build_rings() -> void:
	if is_instance_valid(ring_root): ring_root.queue_free()
	rings.clear(); ring_root = Node3D.new(); ring_root.name = "DemoFlightRings"; app.add_child(ring_root)
	for i in range(points.size()):
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new(); mesh.inner_radius = RING_RADIUS-3; mesh.outer_radius = RING_RADIUS+3; mesh.rings = 48; mesh.ring_segments = 8
		ring.mesh = mesh; ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true; material.emission_energy_multiplier = 1.5
		ring.material_override = material
		ring_root.add_child(ring); ring.position = points[i]
		var tangent: Vector3 = points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]
		if tangent.length()<1: tangent = Vector3.FORWARD
		ring.basis = Basis.looking_at(tangent.normalized(),Vector3.UP)*Basis(Vector3.RIGHT,PI/2)
		rings.append(ring)
	update_visuals()

func update_visuals() -> void:
	if not is_instance_valid(ring_root): return
	if is_instance_valid(airfield): airfield.visible = active and app.mode not in ["title","tutorial"]
	ring_root.visible = active and app.mode in ["flight","paused"] and phase in ["takeoff","combat","return","approach"]
	for i in range(rings.size()):
		rings[i].visible = i>=route_index and i<route_index+5
		var color := Color(1,.71,.278) if i==route_index else Color(.553,1,.690)
		var material := rings[i].material_override as StandardMaterial3D
		material.albedo_color = color; material.emission = color

func cleanup_visuals() -> void:
	if is_instance_valid(ring_root):ring_root.queue_free()
	if is_instance_valid(airfield):airfield.queue_free()
	ring_root=null;airfield=null
func _reposition_targets(force: bool) -> void:
	if force and phase=="combat":app.combat.extend_demo_route()
func begin_assisted_landing() -> bool:
	if app.combat.kills<TARGET_COUNT or not is_instance_valid(airfield):return false
	app.landing_started=true;app.copilot=true;app.used_copilot=true
	app.flight.gear=true;app.flight.flaps=2;app.gear_override=1;app.flaps_override=2
	app.combat.gun_firing_time=0
	if phase=="combat":transition("return")
	return true
func badge_hint() -> String:
	if not app.badge_prompts:return ""
	if phase=="takeoff":return "BADGE A  GEAR + FLAPS  ·  UP  AUTO-FLY  ·  HOME  PAUSE"
	if phase=="combat":return "BADGE LEFT  VIEW  ·  RIGHT  TACTICAL VIEW  ·  HOLD DOWN  TACTICAL"
	if phase in ["return","approach"]:return "BADGE A  LANDING CONFIG  ·  B  LANDING ASSIST  ·  HOME  PAUSE"
	return "BADGE START  REPLAY  ·  HOME  PAUSE"
