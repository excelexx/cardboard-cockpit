extends CombatDirector
class_name GooseCampaign
const Catalog = preload("res://data/aircraft.gd")
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
func reset(enabled: bool) -> void:
	super.reset(enabled)
	automatic_waves = false
	showcase = app.showcase_mode
	developer = app.developer_mode
	wave_counts = [3,5,7,9,12,16]
	stage_clock = 0
	transition_time = 0
	total_shots = 0
	if enabled:
		spawn_wave()
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
	if showcase:
		hull = maxf(hull,35)
		base_health = maxf(base_health,35)
	for enemy: Dictionary in enemies:
		enemy.position += forward()*app.flight.speed*cos(app.flight.pitch)*dt
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
	if showcase:
		if stage_clock>=30:
			if wave>=STAGES.size():
				complete(true,"Three-minute showcase complete. Every aircraft and weapon demonstrated.")
			else: spawn_wave()
		elif enemies.is_empty() and stage_clock<27:
			spawn_flock(maxi(2,int(stage().count)/2))
	else:
		stage_clear_clock = stage_clear_clock+dt if enemies.is_empty() else 0
		if stage_clear_clock>1.5:
			if wave>=STAGES.size(): complete(true,"The final flock is contained. Waterloo's skies are yours.")
			else: spawn_wave()
	if elapsed>600 and app.test_mode:
		complete(false,"Campaign test timed out")
func fire_gun() -> bool:
	return fire_weapon()
func fire_missile() -> bool:
	return fire_weapon()
func fire_weapon() -> bool:
	if not active or gun_cooldown>0 or ammo<=0 or gun_heat>0.95: return false
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
	if not assist or not app.vision.enabled or not app.vision.tracking: return
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
