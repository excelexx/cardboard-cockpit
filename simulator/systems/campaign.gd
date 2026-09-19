extends CombatDirector
class_name GooseCampaign
const Catalog = preload("res://data/aircraft.gd")
const Route = preload("res://systems/scenic_route.gd")
var route_index := 0
var visited_route: Array[int] = []
const STAGES: Array[Dictionary] = [
	{"name":"CAMPUS PATROL","plane":"trainer","aircraft":"KESTREL TRAINER","weapon":"WORN GATLING","color":Color(1,0.76,0.32),"count":3,"damage":13.0,"delay":0.10},
	{"name":"THE FLOCK STRIKES","plane":"f35","aircraft":"F-35 INTERCEPTOR","weapon":"GUIDED MISSILE","color":Color(1,0.55,0.2),"count":5,"damage":150.0,"delay":0.65},
	{"name":"GOOSE AIRSPACE","plane":"b2","aircraft":"B-2 VANGUARD","weapon":"HEAVY AUTOCANNON","color":Color(1,0.85,0.45),"count":7,"damage":65.0,"delay":0.12},
	{"name":"HEAVY REINFORCEMENTS","plane":"an225","aircraft":"AN-225 ARSENAL CARRIER","weapon":"MISSILE BATTERY","color":Color(1,0.45,0.22),"count":9,"damage":150.0,"delay":0.70},
	{"name":"PLASMA DAWN","plane":"vx9","aircraft":"VX-9 INTERCEPTOR","weapon":"PULSE PLASMA","color":Color(0.3,0.8,1),"count":12,"damage":130.0,"delay":0.16},
	{"name":"THE FINAL HONK","plane":"falcon","aircraft":"MILLENNIUM FALCON","weapon":"TWIN PLASMA CANNONS","color":Color(0.45,0.9,1),"count":16,"damage":180.0,"delay":0.13}
]
var showcase := true
var developer := false
var stage_clock := 0.0
var transition_time := 0.0
var stage_clear_clock := 0.0
var total_shots := 0
var unlimited := false
var phase := "takeoff"
const STAGE_SECONDS := 15.0
func reset(enabled: bool) -> void:
	super.reset(enabled)
	automatic_waves = false
	showcase = app.showcase_mode
	developer = app.developer_mode
	wave_counts = [3,5,7,9,12,16]
	stage_clock = 0
	transition_time = 0
	total_shots = 0
	route_index = 0
	visited_route.clear()
	if enabled:
		phase = "takeoff"
		wave = 1
		app.apply_campaign_aircraft(plane_profile(0))
		app.flight.reset(app.profile())
		app.aircraft.position = app.flight.position
		announce("AZURE TOWER · Cleared for takeoff. Advance throttle.")
		app.copilot = showcase and not app.vision.enabled
		app.used_copilot = showcase
func stage() -> Dictionary:
	return STAGES[clampi(wave-1,0,STAGES.size()-1)]
func plane_profile(index: int) -> Dictionary:
	var spec: Dictionary = STAGES[index]
	var profile: Dictionary = Catalog.PLANES[1].duplicate(true)
	for candidate: Dictionary in Catalog.PLANES:
		if candidate.id==spec.plane: profile = candidate.duplicate(true)
	profile.id = spec.plane
	profile.name = spec.aircraft
	profile.short = spec.aircraft
	profile.clearance = 3.0
	if index==0:
		profile.span = 6.8
		profile.length = 8.0
		profile.engines = 1
		profile.max_speed = 140.0
		profile.acceleration = 7.0
		profile.rotation_speed = 40.0
		profile.roll_rate = 0.7
		profile.pitch_rate = 0.4
	elif index==4:
		profile.span = 18.0
		profile.length = 24.0
		profile.engines = 2
		profile.max_speed = 320.0
		profile.roll_rate = 1.4
	elif index==5:
		profile.span = 25.0
		profile.length = 35.0
		profile.engines = 2
		profile.max_speed = 360.0
		profile.roll_rate = 1.2
	return profile
func clear_encounter() -> void:
	for enemy: Dictionary in enemies: enemy.node.queue_free()
	for shot: Dictionary in shots: shot.node.queue_free()
	for effect: Dictionary in bursts: effect.node.queue_free()
	enemies.clear()
	shots.clear()
	bursts.clear()
	target_id = -1
	lock_progress = 0
func spawn_wave() -> void:
	phase = "combat"
	clear_encounter()
	wave = mini(wave+1,STAGES.size())
	stage_clock = 0
	stage_clear_clock = 0
	transition_time = 3
	ammo = 600 if wave not in [2,4] else 80
	gun_heat = 0
	gun_cooldown = 0
	hull = minf(100,hull+30)
	base_health = minf(100,base_health+25)
	app.apply_campaign_aircraft(plane_profile(wave-1))
	spawn_flock(int(stage().count))
	announce("LEVEL %d  /  %s" % [wave,stage().weapon])
	app.audio.ping()
func goose() -> Node3D:
	var root := Node3D.new()
	var model: Node3D = load("res://assets/goose/goose.glb").instantiate()
	root.add_child(model)
	model.scale = Vector3.ONE*0.065
	model.rotation.y = PI
	var feather := Color(0.50,0.46,0.37)
	var black := Color(0.06,0.075,0.09)
	for side in [-1,1]:
		var wing := Node3D.new()
		wing.name = "WingL" if side<0 else "WingR"
		wing.position = Vector3(side*0.8,0.0,0)
		root.add_child(wing)
		box(wing,Vector3(3.9,0.16,1.65),Vector3(side*1.6,0,0.2),feather)
		for finger in range(4): box(wing,Vector3(1.1,0.13,0.28),Vector3(side*3.5,-0.1,-0.5+finger*0.4),black)
	root.scale = Vector3.ONE*(7.5+wave*0.3)
	return root
func spawn_flock(count: int) -> void:
	var ahead: Vector3 = forward()
	var right := Vector3(cos(app.flight.heading),0,sin(app.flight.heading))
	for i: int in count:
		var node := goose()
		add_child(node)
		var pos: Vector3 = app.flight.position+ahead*(650+i*35)+right*(i-(count-1)*0.5)*60
		pos.y = maxf(app.flight.position.y+sin(i*1.4)*90,350)
		node.position = pos
		enemies.append({"id":next_id,"node":node,"position":pos,"health":100.0+(wave-1)*10,"max_health":100.0+(wave-1)*10,"cooldown":8.0+i,"age":0.0,"phase":float(i)})
		next_id += 1
func tick(dt: float) -> void:
	if not active: return
	if phase != "combat":
		elapsed += dt
		if phase == "takeoff" and app.flight.airborne and app.flight.position.y > 180:
			wave = 0
			spawn_wave()
		return
	if showcase:
		hull = maxf(hull,35)
		base_health = maxf(base_health,35)
	update_route()
	if phase != "combat": return
	for enemy: Dictionary in enemies:
		# Encounters lead through the scenery instead of pulling the pilot off route.
		var direction: Vector3 = (route_target()-app.flight.position).normalized()
		var side := Vector3(-direction.z,0,direction.x)
		var lead: Vector3 = app.flight.position+direction*780+side*sin(float(enemy.phase)*1.7)*180
		lead.y = maxf(lead.y,app.world.ground_height(lead.x,lead.z)+180)
		enemy.position = enemy.position.lerp(lead,1.0-exp(-dt*0.8))
	super.tick(dt)
	if not active: return
	stage_clock += dt
	transition_time = maxf(0,transition_time-dt)
	for enemy: Dictionary in enemies:
		var flap: float = sin(elapsed*5+enemy.phase)*0.35
		enemy.node.get_node("WingL").rotation.z = flap
		enemy.node.get_node("WingR").rotation.z = -flap
	if assist and lock_progress>=1:
		fire_weapon()
	# Location, not a timer, advances the journey. Quiet gaps leave time to look out.
	stage_clear_clock = stage_clear_clock+dt if enemies.is_empty() else 0
	if stage_clear_clock>8 and route_index not in [2,6,7,8,9,10]:
		spawn_flock(maxi(2,int(stage().count)/2))
		stage_clear_clock = 0
	if elapsed>600 and app.test_mode:
		complete(false,"Campaign test timed out")
func fire_gun() -> bool:
	return fire_weapon()
func fire_missile() -> bool:
	return fire_weapon()
func fire_weapon() -> bool:
	if phase != "combat" or not active or gun_cooldown>0 or ammo<=0 or gun_heat>0.95: return false
	var spec: Dictionary = stage()
	var enemy: Dictionary = target()
	if wave in [2,4] and (enemy.is_empty() or lock_progress<1): return false
	gun_cooldown = float(spec.delay)
	gun_heat = minf(1,gun_heat+(0.036 if wave==1 else 0.02))
	ammo -= 1
	total_shots += 1
	var direction: Vector3 = forward()
	if not enemy.is_empty(): direction = (enemy.position-app.flight.position).normalized()
	var count: int = 3 if wave==4 else 2 if wave==6 else 1
	for index in range(count):
		var kind: String = "missile" if wave in [2,4] else "cannon"
		var target_value: int = target_id
		if wave==4 and not enemies.is_empty(): target_value = enemies[(index)%enemies.size()].id
		spawn_shot(app.flight.position+direction*18+Vector3((index-(count-1)*0.5)*3,0,0),direction*(400 if kind=="missile" else 1150),kind,target_value,float(spec.damage))
		if wave>=5:
			var node: Node3D = shots.back().node
			node.scale = Vector3(4,4,1.6)
			for child: Node in node.get_children():
				if child is MeshInstance3D:
					child.material_override = material(spec.color,5)
	app.audio.play_effect("missile" if wave in [2,4] else "plasma" if wave>=5 else "cannon",-18)
	return true
func cardboard_controls() -> void:
	# Aim-and-fire works with either keyboard steering or tracked cardboard.
	# No weapon-switch gesture exists: each stage has exactly one weapon.
	if phase != "combat" or not assist or not app.vision.enabled or not app.vision.tracking: return
	if lock_progress>=1: fire_weapon()
	if absf(app.vision.yoke.x)>0.85 and not roll_latched:
		roll_latched = true
		app.flight.start_barrel_roll(signf(app.vision.yoke.x))
	if absf(app.vision.yoke.x)<0.3: roll_latched = false
func skip_to(index: int) -> bool:
	if not developer: return false
	wave = clampi(index,0,STAGES.size()-1)
	spawn_wave()
	return true
func complete(success: bool, reason: String) -> void:
	super.complete(success,reason)

func begin_approach() -> void:
	phase = "landing"
	clear_encounter()
	app.ring_index = 5
	app.flight.gear = true
	app.flight.flaps = 2
	app.show_toast("CAPE NORTH · Weapons safe. Gear down. Follow the approach diamonds.")
	app.audio.ping()

func pilot_controls() -> Vector3:
	if phase == "combat": return scenic_controls()
	if phase == "takeoff":
		app.flight.throttle = 1.0
		return Vector3(-app.flight.roll*3,0.7 if app.flight.speed>app.flight.effective_rotation_speed() else 0,0)
	return app.approach_pilot_controls()

func route_target() -> Vector3:
	return Route.POINTS[mini(route_index,Route.POINTS.size()-1)]

func update_route() -> void:
	var delta: Vector3 = route_target()-app.flight.position
	# Require physical arrival, including altitude: manual flight cannot skip a reveal.
	if Vector2(delta.x,delta.z).length()>290 or absf(delta.y)>190: return
	visited_route.append(route_index)
	if app.test_mode: print("SCENIC CHECKPOINT ",route_index," ",Route.NAMES[route_index]," pos=",app.flight.position)
	route_index += 1
	if route_index>=Route.POINTS.size():
		begin_approach()
		return
	var next_stage: int = Route.stage_for(route_index)
	if next_stage>wave:
		wave = next_stage-1
		spawn_wave()
	app.show_toast(Route.NAMES[route_index]+" · "+Route.HINTS[route_index])

func scenic_controls() -> Vector3:
	var f: FlightDynamics = app.flight
	var delta: Vector3 = route_target()-f.position
	var error: float = wrapf(atan2(delta.x,-delta.z)-f.heading,-PI,PI)
	var desired_roll: float = clampf(error*1.6,-0.66,0.66)
	var desired_pitch: float = clampf(atan2(delta.y,maxf(Vector2(delta.x,delta.z).length(),250)),-0.36,0.40)
	var desired_speed: float = 105.0 if route_index<4 else 115.0
	if route_index>=8: desired_speed = 100.0
	f.gear = false
	f.flaps = 0
	f.throttle = clampf(0.24+(desired_speed-f.speed)*0.065,0,1)
	return Vector3(clampf((desired_roll-f.roll)*5,-1,1),clampf((desired_pitch-f.pitch)*6,-1,1),clampf(error*1.4,-1,1))
