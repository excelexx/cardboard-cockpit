extends SceneTree
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Catalog = preload("res://data/aircraft.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("FLIGHT FAIL: "+label)
func fresh(airborne: bool = false):
	var f = Dynamics.new(); f.reset(Catalog.PROFILE)
	if airborne: f.spawn_airborne(Vector3(0,800,0),180)
	return f
func simulate(f,seconds: float,control: Vector3,brakes: bool = false) -> void:
	for i in range(int(seconds*120)): f.step(1.0/120.0,control,brakes,0,true)
func _initialize() -> void:
	check(Catalog.PLANES.size()==1,"Exactly one playable airframe")
	var f = fresh()
	simulate(f,1,Vector3(0,1,0))
	check(not f.airborne,"Stationary pull cannot lift off")
	f.throttle = 1; f.step(.1,Vector3.ZERO,false,0,true)
	check(f.engine>0 and f.engine<.1 and f.speed<1,"Engine thrust spools smoothly")
	f.speed = f.effective_rotation_speed()+1
	f.step(.02,Vector3(0,.7,0),false,0,true)
	check(f.airborne and f.position.y>3,"Rotation requires airspeed and pitch input")
	var right = fresh(true); var left = fresh(true)
	simulate(right,1,Vector3(.4,0,0)); simulate(left,1,Vector3(-.4,0,0))
	check(right.heading>0 and left.heading<0,"Banked turns follow pilot input")
	check(right.position.x>0 and left.position.x<0,"Momentum moves aircraft into the turn")
	check(absf(right.heading+left.heading)<.001,"Mirrored controls remain symmetric")
	var rate: float = right.roll_velocity
	right.step(.01,Vector3.ZERO,false,0,true)
	check(right.roll_velocity>0 and right.roll_velocity<rate,"Angular rates decay rather than snapping")
	f = fresh(true); f.heading = PI/2; f.step(.016,Vector3.ZERO,false,0,true)
	check(f.velocity.x<80 and f.velocity.z < -80,"Flight path retains inertia after attitude changes")
	var cruise = fresh(true); var hot = fresh(true)
	cruise.throttle = 1; hot.throttle = 1; hot.afterburner = true
	simulate(cruise,3,Vector3.ZERO); simulate(hot,3,Vector3.ZERO)
	check(hot.speed>cruise.speed+12,"Afterburner materially changes acceleration")
	f = fresh(true)
	var inverted := false
	for i in range(480):
		f.step(1.0/120.0,Vector3(1,0,0),false,-1000,false)
		inverted = inverted or absf(f.roll)>2.6
	check(inverted and f.position.is_finite(),"Pilot can roll through inverted flight with finite motion")
	f = fresh(true)
	check(f.start_barrel_roll(),"Quick roll available with safe altitude")
	simulate(f,2,Vector3.ZERO)
	check(f.barrel_remaining==0 and absf(f.roll)<.1,"Quick roll recovers cleanly")
	f.position.y = 15
	check(not f.start_barrel_roll(),"Quick roll blocked close to the ground")
	f = fresh(true); f.position = Vector3(0,3.03,-14200); f.gear = true; f.speed = 70; f.pitch = -.05; f.roll = .06; f.vertical_speed = -2
	f.velocity = Vector3(0,-2,-70)
	f.step(.033,Vector3.ZERO,false,0,true)
	check(f.contact=="landed","Stable gear-down touchdown succeeds")
	check(absf(f.pitch)>.035 and absf(f.roll)>.04,"Touchdown preserves attitude for gradual settling")
	var pitch: float = f.pitch; var at: Vector3 = f.position
	f.rollout_step(.016,true,0,true)
	check(absf(f.pitch-pitch)<.003 and f.position.distance_to(at)<1.3,"Rollout begins continuously")
	for i in range(1500): f.rollout_step(1.0/120.0,true,0,true)
	check(f.speed==0 and absf(f.pitch)<.001 and absf(f.roll)<.001,"Braking produces a stable full stop")
	for unsafe in ["gear","speed","sink","bank"]:
		f = fresh(true); f.position.y = 3.01; f.gear = true; f.speed = 70; f.vertical_speed = -3; f.velocity.y = -3
		if unsafe=="gear": f.gear = false
		if unsafe=="speed": f.speed = 150
		if unsafe=="sink": f.vertical_speed = -20; f.pitch = -.3
		if unsafe=="bank": f.roll = .7
		f.step(.05,Vector3.ZERO,false,0,true)
		check(f.contact=="crash","Unsafe touchdown rejected: "+unsafe)
	f = fresh(true); f.step(.4,Vector3.ONE,false,-10000,false)
	check(f.position.is_finite() and is_finite(f.g_load),"Frame hitches do not destabilize physics")
	f.reset(Catalog.PROFILE)
	check(f.velocity==Vector3.ZERO and f.roll_velocity==0 and f.g_load==1 and not f.afterburner,"Reset clears all dynamic state")
	print("FIGHTER MODEL: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
