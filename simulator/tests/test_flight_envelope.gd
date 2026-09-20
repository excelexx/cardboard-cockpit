extends SceneTree
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Controls = preload("res://systems/arcade_controls.gd")
const Gust = preload("res://systems/gust_field.gd")
const Catalog = preload("res://data/aircraft.gd")
const Tune = preload("res://data/balance.gd")
## Guard rail for P1. Every check here exists to prove that the new pose state
## (angle of attack, sideslip, Mach, signed g) is PRESENTATION and that the
## aircraft is no harder to fly than it was before the change.
class RidgeWorld extends RefCounted:
	var cloud_presence := 0.4
	func ground_height(x: float,z: float) -> float:
		return 120.0+sin(x*0.004)*90.0+cos(z*0.003)*60.0

var checks := 0
var failures: Array[String] = []
var notes: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error("FLIGHT ENVELOPE FAIL: "+label)
func fresh(airborne: bool = false,airspeed: float = 165.0):
	var f = Dynamics.new(); f.reset(Catalog.PROFILE)
	if airborne: f.spawn_airborne(Vector3(0,800,0),airspeed)
	return f
func settle(f,seconds: float,control: Vector3 = Vector3.ZERO) -> void:
	for i in range(int(seconds*120)): f.step(1.0/120.0,control,false,-4000,false)

func _initialize() -> void:
	# Opt-in visual pass for this package's LOOK deliverable. Native GPU only:
	#   Godot --path simulator --windowed --resolution 1600x1000 \
	#     --script tests/test_flight_envelope.gd -- capture
	# It draws the aircraft BOTH ways - from the path, the way scenes/main.gd
	# apply_aircraft_pose() draws it today, and from pose_basis(), the way it will
	# be drawn once P4 lands the three-line change - so the difference, and the
	# anchored effects that do NOT follow it, can be seen side by side.
	if "capture" in OS.get_cmdline_user_args():
		call_deferred("capture_run")
		return
	trim_and_alpha()
	path_is_not_slower()
	alpha_is_pose_only()
	signed_g()
	nose_low_in_a_bunt()
	respawn_arms_the_terrain_assist()
	constants_cannot_make_it_harder()
	speed_and_roll_are_not_worse()
	takeoff_rotation()
	flown_barrel_roll()
	gusts()
	for line in notes: print(line)
	print("FLIGHT ENVELOPE: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func trim_and_alpha() -> void:
	var f = fresh(true,165.0)
	f.throttle = 0.52
	for i in range(int(8.0*120)):
		f.speed = 165.0
		f.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
	var horizontal: float = Vector2(f.velocity.x,f.velocity.z).length()
	var gamma: float = atan2(f.vertical_speed,maxf(horizontal,1.0))
	notes.append("  cruise 165 m/s: aoa=%.2f deg g=%.2f mach=%.2f gamma=%.4f pitch=%.4f" % [rad_to_deg(f.aoa),f.g_load,f.mach,gamma,f.pitch])
	check(f.aoa>deg_to_rad(0.5) and f.aoa<deg_to_rad(4.0),"Cruise angle of attack is small but visible")
	check(absf(f.pitch-gamma)<0.01,"pitch remains the flight path angle, so autopilots need no change")
	check(f.mach>0.4 and f.mach<0.6,"Mach is published and plausible at cruise")
	# Approach: gear down, flaps out, on speed. The nose must be clearly up.
	var a = fresh(true,Tune.APPROACH_SPEED)
	a.gear = true; a.flaps = 2; a.throttle = 0.30
	for i in range(int(6.0*120)):
		a.speed = Tune.APPROACH_SPEED
		a.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
	notes.append("  approach %.0f m/s: aoa=%.2f deg (gear down, flaps 2)" % [a.speed,rad_to_deg(a.aoa)])
	check(a.aoa>deg_to_rad(9.0) and a.aoa<deg_to_rad(12.0),"Approach angle of attack is nose-up like a real fighter on speed")
	check(a.aoa<=Dynamics.ALPHA_MAX,"Angle of attack is bounded by ALPHA_MAX")
	# A hard turn raises it further.
	var t = fresh(true,160.0); t.throttle = 1.0
	var peak_alpha := 0.0; var peak_g := 0.0
	for i in range(int(4.0*120)):
		t.step(1.0/120.0,Vector3(0,1,0),false,-9000,false)
		peak_alpha = maxf(peak_alpha,t.aoa); peak_g = maxf(peak_g,t.g_load)
	notes.append("  hard pull: peak aoa=%.2f deg at peak g=%.2f" % [rad_to_deg(peak_alpha),peak_g])
	check(peak_alpha>deg_to_rad(3.0),"Angle of attack rises under load")
	# Sideslip stays an odd function of rudder, which the symmetry suite relies on.
	var r = fresh(true); var l = fresh(true)
	settle(r,1.0,Vector3(0,0,0.8)); settle(l,1.0,Vector3(0,0,-0.8))
	check(absf(r.beta+l.beta)<1e-6 and r.beta>0.0,"Sideslip is signed and mirror symmetric")

func path_is_not_slower() -> void:
	# PLAYABILITY GUARD. The load-factor rate limiter may smooth the flight path
	# but may never answer the stick more slowly than the first-order lag the
	# aircraft shipped with, whose time constant was 1/3.0 s.
	var f = fresh(true,200.0); f.throttle = 0.6; f.pitch = 0.20
	var target: float = sin(f.pitch)*f.speed
	var reached := -1.0
	var clock := 0.0
	for i in range(600):
		f.step(1.0/120.0,Vector3.ZERO,false,-9000,false)
		clock += 1.0/120.0
		if reached<0.0 and f.vertical_speed>=target*0.632: reached = clock
	notes.append("  step response: 63%% of %.0f m/s in %.3f s (previous model 0.333 s)" % [target,reached])
	check(reached>0.0 and reached<=1.0/Dynamics.LEGACY_VERTICAL_RESPONSE,"The flight path answers the stick at least as fast as it did before")
	# The terrain assist's worst case: arrest a 40 m/s descent.
	var d = fresh(true,165.0); d.throttle = 0.8
	d.position.y = 600.0; d.pitch = -0.25; d.vertical_speed = -40.0; d.velocity = Vector3(0,-40,-165)
	var arrest := 0.0
	for i in range(360):
		d.step(1.0/120.0,Controls.command(d,Vector3.ZERO,60.0),false,-9000,false)
		arrest += 1.0/120.0
		if d.vertical_speed>0.0: break
	notes.append("  terrain assist arrests a 40 m/s descent in %.2f s" % arrest)
	check(d.vertical_speed>0.0 and arrest<1.2,"A dive is arrested as quickly as before")

func alpha_is_pose_only() -> void:
	# Identical inputs, but one aircraft has absurd pose state forced on it every
	# substep. If any of it reached the integrator the paths would diverge.
	var clean = fresh(true,240.0); var poisoned = fresh(true,240.0)
	clean.throttle = 1.0; poisoned.throttle = 1.0
	var control := Vector3(0.6,0.5,0.3)
	for i in range(900):
		poisoned.aoa = 0.4; poisoned.beta = -0.11; poisoned.mach = 3.7
		clean.step(1.0/120.0,control,false,-4000,false)
		poisoned.step(1.0/120.0,control,false,-4000,false)
	notes.append("  pose isolation: path delta=%.9f m over 7.5 s" % clean.position.distance_to(poisoned.position))
	check(clean.position.distance_to(poisoned.position)<1e-6,"Angle of attack, sideslip and Mach never move the aircraft")
	check(absf(clean.speed-poisoned.speed)<1e-6,"Pose state never touches the energy state")
	check(absf(clean.g_load-poisoned.g_load)<1e-6,"Pose state never touches the load factor")
	check(clean.stall_time==poisoned.stall_time,"Pose state never touches the stall logic")

func signed_g() -> void:
	var pull = fresh(true,330.0); pull.throttle = 1.0
	var peak := 0.0
	for i in range(480):
		pull.step(1.0/120.0,Vector3(0,1,0),false,-9000,false)
		peak = maxf(peak,pull.g_load)
	var push = fresh(true,330.0); push.throttle = 1.0
	var trough := 0.0
	for i in range(480):
		push.step(1.0/120.0,Vector3(0,-1,0),false,-9000,false)
		trough = minf(trough,push.g_load)
	notes.append("  load factor: full pull peak=%.2f g / full bunt trough=%.2f g" % [peak,trough])
	check(peak<=7.2 and peak>2.0,"A full pull loads the airframe without exceeding the structural limit")
	check(trough<-0.2 and trough>=-2.6,"A bunt reads NEGATIVE g rather than a magnitude")
	var level = fresh(true,200.0); level.throttle = 0.55
	settle(level,6.0)
	notes.append("  level 1 g reads %.2f" % level.g_load)
	check(absf(level.g_load-1.0)<0.25,"Wings level reads about 1 g")
	# Throttle alone is not g.
	var slam = fresh(true,140.0); slam.throttle = 1.0; slam.afterburner = true; slam.power_input = 1.0
	settle(slam,3.0)
	notes.append("  full burner acceleration reads %.2f g" % slam.g_load)
	check(absf(slam.g_load-1.0)<0.4,"Acceleration on the throttle does not show up as load factor")
	var bank = fresh(true,265.0); bank.throttle = 0.8
	for i in range(int(6.0*120)):
		bank.step(1.0/120.0,Controls.command(bank,Vector3(0.9,0,0),2000.0),false,-9000,false)
	notes.append("  sustained %.0f deg bank reads %.2f g" % [rad_to_deg(absf(bank.roll)),bank.g_load])
	check(bank.g_load>1.2,"A sustained bank loads the airframe")

## The manoeuvre the pose matters most in: the push-over onto a goose. The
## published g goes negative there, so the drawn attitude must go nose-low with
## it - an airframe drawn 0.8 deg nose-UP in a bunt is the tell this package
## exists to remove.
func nose_low_in_a_bunt() -> void:
	var push = fresh(true,330.0); push.throttle = 1.0
	var trough := 0.0
	var alpha_at_trough := 0.0
	var floor_alpha := 0.0
	for i in range(480):
		push.step(1.0/120.0,Vector3(0,-1,0),false,-9000,false)
		if push.g_load<trough: trough = push.g_load; alpha_at_trough = push.aoa
		floor_alpha = minf(floor_alpha,push.aoa)
	notes.append("  bunt at 330 m/s: g trough=%.2f with aoa=%.2f deg (floor %.2f deg)" % [trough,rad_to_deg(alpha_at_trough),rad_to_deg(floor_alpha)])
	check(alpha_at_trough<0.0,"A bunt draws the nose BELOW the flight path")
	check(alpha_at_trough<deg_to_rad(-0.5),"The nose-low pose is worth a readable fraction of a degree, not a rounding error")
	var level = fresh(true,330.0); level.throttle = 1.0
	settle(level,3.0)
	notes.append("  pose swing at 330 m/s: level %.2f deg -> bunt %.2f deg" % [rad_to_deg(level.aoa),rad_to_deg(alpha_at_trough)])
	check(level.aoa-alpha_at_trough>deg_to_rad(1.5),"The drawn attitude swings by degrees between level flight and a push")
	check(floor_alpha>=Dynamics.ALPHA_MIN-1e-9,"Negative angle of attack is bounded by ALPHA_MIN")
	# Slower air needs more of it, exactly as the positive branch does.
	var slow = fresh(true,200.0); slow.throttle = 0.5
	var slow_alpha := 0.0
	for i in range(480):
		slow.step(1.0/120.0,Vector3(0,-1,0),false,-9000,false)
		slow_alpha = minf(slow_alpha,slow.aoa)
	notes.append("  bunt at manoeuvring speed: aoa floor %.2f deg" % rad_to_deg(slow_alpha))
	check(slow_alpha<deg_to_rad(-1.0),"A bunt at manoeuvring speed is clearly nose-low")
	# The single hook the anchored effects switch to with main.gd.
	var expected := Basis.from_euler(Vector3(push.pose_pitch(),-push.pose_heading(),-push.pose_roll()))
	check(push.pose_basis().is_equal_approx(expected),"pose_basis is the airframe basis every anchored effect must use")
	var flown := Basis.from_euler(Vector3(push.pitch,-push.heading,-push.roll))
	check(not push.pose_basis().is_equal_approx(flown),"The pose basis differs from the path basis, which is why the anchors must switch")

## PLAYABILITY GUARD regression. A crash recovery calls spawn_airborne(), and the
## terrain assist must be armed on the very first frame afterwards.
func respawn_arms_the_terrain_assist() -> void:
	var f = fresh(true,180.0)
	f.vertical_speed = 60.0; f.vertical_trend = 60.0; f.aoa = 0.2; f.stall_time = 4.0
	f.spawn_airborne(Vector3(0,300.0,0),180.0)
	check(f.vertical_trend==0.0 and f.vertical_speed==0.0,"A respawn clears the low-passed vertical speed as well as the raw one")
	check(f.aoa==0.0 and f.stall_time==0.0,"A respawn clears the pose and stall state it inherited from the crash")
	var d = fresh(true,180.0); d.throttle = 0.7
	d.vertical_speed = -40.0; d.vertical_trend = 20.0
	var command: Vector3 = Controls.command(d,Vector3.ZERO,60.0)
	notes.append("  fresh push-over inside the terrain margin commands elevator %.2f" % command.y)
	check(command.y>0.2,"The terrain assist arms on the raw descent rate, never only on the lagged one")
	d.vertical_speed = 20.0; d.vertical_trend = -40.0
	check(Controls.command(d,Vector3.ZERO,60.0).y>0.2,"...and the lag still holds it on through a bump")

## The constants contract, measured against what the game ACTUALLY does today.
## Every one of these is a value another package is about to wire in.
func constants_cannot_make_it_harder() -> void:
	# combat.gd:168 hit_radius, plus combat.gd:437's cannon and missile bonuses.
	check(Tune.CONTACT_HIT_RADIUS>=22.0,"The published hit sphere is no smaller than the live 22.0 m one")
	check(Tune.MISSILE_HIT_RADIUS>=27.0,"The proximity fuse is no smaller than the live 22.0+5.0 m contact test")
	# target_intent.gd retain_degrees() peaks at 18.68 deg outside a barrel roll.
	check(Tune.AIM_DEFLECTION_DEGREES>=18.7,"The aim assist cone is no narrower than the live capture cone")
	check(Tune.GUN_MAGAZINE<0 and Tune.MISSILE_STORES<0,"Ordnance stays unlimited")
	# Cadence at the 60 Hz physics tick, the way combat.gd:180 actually counts it.
	var ticks := 0
	var cooldown: float = Tune.GUN_INTERVAL
	while cooldown>0.0 and ticks<16:
		cooldown = maxf(0.0,cooldown-1.0/60.0)
		if cooldown<.0001: cooldown = 0.0
		ticks += 1
	var packets: float = 60.0/float(maxi(ticks,1))
	var dps: float = packets*Tune.GUN_ROUNDS_PER_PACKET*Tune.GUN_DAMAGE_PER_ROUND
	notes.append("  cannon at 60 Hz: %d ticks -> %.0f packets/s, %.0f rounds/s, %.0f dps" % [ticks,packets,packets*Tune.GUN_ROUNDS_PER_PACKET,dps])
	check(dps>=400.0,"Cannon damage per second is no lower than the 400 dps the game shipped with")
	check(packets*Tune.GUN_ROUNDS_PER_PACKET>=48.0,"Counted rounds per second clear the dual-fire suite's 1200 over 25 s")
	check(Tune.GUN_ROUNDS_PER_PACKET*Tune.GUN_DAMAGE_PER_ROUND>=Tune.CONTACT_HEALTH,"One cannon packet still kills a goose outright")

func speed_and_roll_are_not_worse() -> void:
	# PLAYABILITY GUARD: nothing here may be slower than the profile shipped.
	var dry = fresh(true,200.0); dry.position.y = 40.0; dry.throttle = 1.0; dry.power_input = 1.0
	for i in range(30*120): dry.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
	notes.append("  dry sea level top speed: %.1f m/s (Mach %.2f)" % [dry.speed,dry.mach])
	check(dry.speed>340.0,"Dry level top speed is no lower than the profile shipped")
	var hot = fresh(true,200.0); hot.position.y = 40.0; hot.throttle = 1.0; hot.power_input = 1.0; hot.afterburner = true
	for i in range(30*120): hot.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
	notes.append("  burner top speed: %.1f m/s (Mach %.2f)" % [hot.speed,hot.mach])
	check(hot.speed>dry.speed+10.0,"Afterburner still buys a clear speed margin")
	# A sustained turn must NOT bleed energy: the guard forbids it outright.
	var turn = fresh(true,265.0); turn.throttle = 1.0
	for i in range(int(2.0*120)):
		turn.step(1.0/120.0,Controls.command(turn,Vector3(0.9,0,0),2000.0),false,-9000,false)
	var before: float = turn.speed
	for i in range(int(10.0*120)):
		turn.step(1.0/120.0,Controls.command(turn,Vector3(0.9,0,0),2000.0),false,-9000,false)
	notes.append("  10 s sustained %.0f deg bank: %.1f -> %.1f m/s" % [rad_to_deg(absf(turn.roll)),before,turn.speed])
	check(turn.speed>before-3.0,"A sustained bank does not bleed the player's energy")
	# Roll authority: quicker with speed, never slower than the 160 deg/s baseline.
	var rates := {}
	for airspeed in [90.0,165.0,300.0]:
		var f = fresh(true,airspeed); f.throttle = 1.0
		var peak := 0.0
		for i in range(120):
			f.step(1.0/120.0,Vector3(1,0,0),false,-9000,false)
			peak = maxf(peak,absf(f.roll_velocity))
		rates[airspeed] = rad_to_deg(peak)
	notes.append("  roll rate: 90 m/s=%.0f deg/s  165 m/s=%.0f deg/s  300 m/s=%.0f deg/s" % [rates[90.0],rates[165.0],rates[300.0]])
	check(rates[300.0]>rates[90.0]+30.0,"Roll authority grows with dynamic pressure")
	check(rates[165.0]>=150.0,"Cruise roll rate is not lower than the aircraft had before")
	# Full throttle no longer halves the roll rate.
	var idle = fresh(true,240.0); idle.throttle = 0.0
	var wet = fresh(true,240.0); wet.throttle = 1.0; wet.afterburner = true
	var idle_peak := 0.0; var wet_peak := 0.0
	for i in range(120):
		idle.speed = 240.0; wet.speed = 240.0
		idle.step(1.0/120.0,Vector3(1,0,0),false,-9000,false); wet.step(1.0/120.0,Vector3(1,0,0),false,-9000,false)
		idle_peak = maxf(idle_peak,absf(idle.roll_velocity)); wet_peak = maxf(wet_peak,absf(wet.roll_velocity))
	notes.append("  roll rate idle=%.0f deg/s vs burner=%.0f deg/s" % [rad_to_deg(idle_peak),rad_to_deg(wet_peak)])
	check(absf(idle_peak-wet_peak)<0.01,"Throttle no longer inverts roll authority")

func takeoff_rotation() -> void:
	var f = fresh(); f.throttle = 1.0
	var reference := -1.0
	var lifted := -1.0
	var pitch_at_lift := 0.0
	var clock := 0.0
	for i in range(30*120):
		var demand: float = 0.85 if f.speed>f.effective_rotation_speed() else 0.0
		f.step(1.0/120.0,Vector3(0,demand,0),false,0,true)
		clock += 1.0/120.0
		# The moment the aircraft would have left the ground BEFORE this change.
		if reference<0.0 and f.speed>=f.effective_rotation_speed() and demand>0.12: reference = clock
		if f.airborne:
			lifted = clock; pitch_at_lift = f.pitch; break
	var run: float = f.distance
	notes.append("  takeoff: airborne at %.2f s (previous model %.2f s, cost %.2f s) over %.0f m, nose up %.1f deg" % [lifted,reference,lifted-reference,run,rad_to_deg(pitch_at_lift)])
	check(lifted>0.0,"The aircraft still takes off")
	check(lifted-reference<=1.0,"Rotation costs under one second of takeoff roll")
	check(pitch_at_lift>deg_to_rad(5.0),"The nose visibly comes up before the mains leave the ground")
	# ...and keeps coming up once airborne, over roughly a second and a half.
	var climb := pitch_at_lift
	for i in range(180):
		f.step(1.0/120.0,Vector3(0,0.30,0),false,0,true)
		climb = maxf(climb,f.pitch)
	notes.append("  post-rotation pitch reaches %.1f deg" % rad_to_deg(climb))
	check(climb>pitch_at_lift,"Rotation continues into the climb out")

func flown_barrel_roll() -> void:
	var control = fresh(true,260.0); var roller = fresh(true,260.0)
	control.throttle = 0.7; roller.throttle = 0.7
	settle(control,0.5); settle(roller,0.5)
	check(roller.start_barrel_roll(1),"A barrel roll is available")
	var pitch_swing := 0.0
	var heading_swing := 0.0
	var unwrapped_monotonic := true
	var peak_angle := 0.0
	var previous_angle: float = roller.barrel_angle
	for i in range(int(2.0*120)):
		control.step(1.0/120.0,Vector3.ZERO,false,-9000,false)
		roller.step(1.0/120.0,Vector3.ZERO,false,-9000,false)
		if roller.barrel_remaining>0:
			pitch_swing = maxf(pitch_swing,absf(roller.pitch-control.pitch))
			heading_swing = maxf(heading_swing,absf(roller.heading-control.heading))
			if roller.barrel_angle<previous_angle-1e-9: unwrapped_monotonic = false
			previous_angle = roller.barrel_angle
			peak_angle = maxf(peak_angle,roller.barrel_angle)
	notes.append("  barrel roll: nose circle %.2f deg pitch / %.2f deg heading, residual %.5f / %.5f" % [rad_to_deg(pitch_swing),rad_to_deg(heading_swing),absf(roller.pitch-control.pitch),absf(roller.heading-control.heading)])
	check(pitch_swing>deg_to_rad(3.0) and heading_swing>deg_to_rad(2.0),"The nose traces a circle instead of the airframe spinning in place")
	check(absf(roller.pitch-control.pitch)<1e-4 and absf(roller.heading-control.heading)<1e-4,"The roll returns the aircraft to its original path")
	check(absf(roller.roll)<0.1 and roller.barrel_remaining==0,"The roll finishes wings level")
	check(unwrapped_monotonic and peak_angle>TAU-0.05,"barrel_angle is unwrapped for the chase camera")

func gusts() -> void:
	var field = Gust.new()
	var f = fresh(true,220.0)
	f.distance = 4100.0
	var first: Vector3 = field.sample(null,f)
	var again: Vector3 = field.sample(null,f)
	check(first==again,"GustField is deterministic for a fixed point on the route")
	var peak := 0.0
	var vertical := 0.0
	for i in range(4000):
		f.distance = float(i)*9.0
		f.position.y = 60.0+float(i%700)
		var w: Vector3 = field.sample(null,f)
		peak = maxf(peak,w.length()); vertical = maxf(vertical,absf(w.y))
	notes.append("  gusts: peak %.2f m/s, peak vertical %.2f m/s" % [peak,vertical])
	check(peak<=Tune.GUST_MAX+1e-4,"Gusts stay inside the published ceiling")
	# Below 15 m AGL there is no gust at all, so it can never spoil a landing.
	f.position.y = 8.0
	check(field.sample(null,f).length()<1e-6,"No gust near the ground")
	# The terrain-slope and cloud paths, through a world that answers.
	var ridge := RidgeWorld.new()
	var r = fresh(true,220.0)
	r.position = Vector3(1200.0,300.0,-4000.0); r.distance = 8800.0
	var over_ridge: Vector3 = ridge_sample(field,ridge,r)
	var ridge_intensity: float = field.intensity
	r.position.y = 3000.0
	var high: Vector3 = ridge_sample(field,ridge,r)
	notes.append("  over terrain: |wind|=%.2f m/s intensity=%.2f / at 3000 m: |wind|=%.2f m/s intensity=%.2f" % [over_ridge.length(),ridge_intensity,high.length(),field.intensity])
	check(ridge_intensity>field.intensity,"Buffet is stronger near terrain than in the smooth air above it")
	check(over_ridge.length()<=Tune.GUST_MAX+1e-4 and high.length()<=Tune.GUST_MAX+1e-4,"The ceiling holds over real terrain")
	check(over_ridge.is_finite(),"Sampling a world with slope stays finite")
	# Pose offsets stay under a degree and the path nudge stays under a few metres.
	f.position.y = 400.0
	field.sample(null,f)
	var pose: Vector3 = field.pose_offset(f)
	notes.append("  gust pose: pitch %.3f deg yaw %.3f deg roll %.3f deg, buffet %.2f" % [rad_to_deg(pose.x),rad_to_deg(pose.y),rad_to_deg(pose.z),field.buffet()])
	check(absf(pose.x)<deg_to_rad(1.0) and absf(pose.y)<deg_to_rad(1.0) and absf(pose.z)<deg_to_rad(1.5),"Gust pose offsets are a wobble, not a manoeuvre")
	# The pose channel is drawn, never flown.
	var posed = fresh(true,220.0); var plain = fresh(true,220.0)
	posed.throttle = 0.6; plain.throttle = 0.6
	for i in range(600):
		posed.pose_offset = Vector3(0.3,-0.2,0.25)
		posed.step(1.0/120.0,Vector3(0.2,0.1,0),false,-4000,false)
		plain.step(1.0/120.0,Vector3(0.2,0.1,0),false,-4000,false)
	check(posed.position.distance_to(plain.position)<1e-6,"Gust pose offsets never move the aircraft")
	check(absf(posed.pose_pitch()-(posed.pitch+posed.aoa+posed.pose_offset.x))<1e-9,"pose_pitch folds angle of attack and the gust wobble together")
	check(absf(posed.pose_roll()-(posed.roll+posed.pose_offset.z))<1e-9,"pose_roll folds the gust wobble into the bank")
	var still = fresh(true,220.0); var bumpy = fresh(true,220.0)
	still.position.y = 260.0; bumpy.position.y = 260.0
	still.throttle = 0.6; bumpy.throttle = 0.6
	var felt := 0.0
	var drift := 0.0
	for i in range(1200):
		bumpy.wind = field.sample(null,bumpy)
		felt = maxf(felt,absf(bumpy.wind.y))
		still.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
		bumpy.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
		drift = maxf(drift,absf(bumpy.position.y-still.position.y))
	notes.append("  gust vertical displacement over 10 s: %.2f m (peak vertical gust %.2f m/s)" % [drift,felt])
	check(drift>0.05 and drift<12.0,"Gusts move the aircraft by metres, not by hundreds of metres")
	check(field.true_airspeed(bumpy)>0.0,"True airspeed is available for the airspeed tape")
	# Worst case the field can produce, squared against the guard: a few metres.
	var calm = fresh(true,220.0); var thrown = fresh(true,220.0)
	calm.position.y = 260.0; thrown.position.y = 260.0
	calm.throttle = 0.6; thrown.throttle = 0.6
	var worst := 0.0
	for i in range(1800):
		thrown.wind = Vector3(0.0,sin(float(i)/120.0*2.4)*Tune.GUST_MAX*0.55,0.0)
		calm.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
		thrown.step(1.0/120.0,Vector3.ZERO,false,-4000,false)
		worst = maxf(worst,absf(thrown.position.y-calm.position.y))
	notes.append("  worst-case gust displacement: %.2f m" % worst)
	check(worst<12.0,"Even the strongest gust the field can produce moves the aircraft a few metres")

func ridge_sample(field,world,flight) -> Vector3:
	return field.sample(world,flight)

# ---------------------------------------------------------------- visual pass
var app: Node3D
func capture_run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("Native GPU required for the capture pass")
		quit(2); return
	var folder: String = ProjectSettings.globalize_path("res://../build/p1-flight")
	DirAccess.make_dir_recursive_absolute(folder)
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	for i in 30: await process_frame
	app.audio.muted = true; app.set_quality(true); app.capture_file = "review"
	app.set_process(false); app.set_physics_process(false)
	await pose_pair(folder,"cruise",165.0,Vector3.ZERO,3.0,false,false,0.0)
	await pose_pair(folder,"approach",Tune.APPROACH_SPEED,Vector3.ZERO,3.0,true,false,0.0)
	# Photograph the pull and the push AT the load factor, not after the aircraft
	# has swapped ends and settled back to 1 g on a new path.
	await pose_pair(folder,"pull",250.0,Vector3(0,1,0),2.0,false,true,4.5)
	await pose_pair(folder,"bunt",250.0,Vector3(0,-1,0),2.0,false,false,-1.8)
	# Diagnostic for the anchored effects: the dirty configuration's 10 deg of
	# angle of attack with the burner lit, framed on the nozzle. In the -pose
	# frame the hull turns and the plume does not, which is the whole of the
	# fighter_effects/combat/combat_visuals handoff in one picture.
	await pose_pair(folder,"anchor",Tune.APPROACH_SPEED,Vector3.ZERO,3.0,true,true,0.0)
	app.queue_free(); await process_frame; await process_frame
	quit(0)

## Fly one manoeuvre for real, then photograph it twice from the same camera.
func pose_pair(folder: String,name: String,airspeed: float,control: Vector3,seconds: float,dirty: bool,burner: bool,stop_g: float) -> void:
	app.start_flight("combat"); app.copilot = false; app.cockpit = false
	app.combat.spawn_clock = 999; app.hud.visible = false
	app.flight.spawn_airborne(Vector3(-4200,420,-8300),airspeed)
	app.flight.heading = 0.7; app.flight.throttle = 0.9 if burner else 0.55
	app.flight.gear = dirty; app.flight.flaps = 2 if dirty else 0
	app.flight.afterburner = burner
	app.apply_aircraft_pose(); app.camera_rig.reset()
	# Let the terrain stream in before the manoeuvre starts.
	var settled: int = Time.get_ticks_msec()
	while Time.get_ticks_msec()-settled<3500:
		drive(1.0/60.0,Vector3.ZERO,airspeed if dirty else -1.0)
		await process_frame
	var began: int = Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<int(seconds*1000.0):
		drive(1.0/60.0,control,airspeed if dirty else -1.0)
		await process_frame
		var reached: bool = (stop_g>0.0 and app.flight.g_load>=stop_g) or (stop_g<0.0 and app.flight.g_load<=stop_g)
		if reached:
			# Hold the load while the pose catches up: aoa is a lagged display
			# value, so the frame the limiter is reached is not the frame to shoot.
			for i in 24:
				drive(1.0/60.0,control,airspeed if dirty else -1.0)
				await process_frame
			break
	var f = app.flight
	print("CAPTURE ",name," speed=%.0f aoa=%.2f deg g=%.2f pitch=%.2f deg pose_pitch=%.2f deg" % [f.speed,rad_to_deg(f.aoa),f.g_load,rad_to_deg(f.pitch),rad_to_deg(f.pose_pitch())])
	# Side-on, so the angle between the hull and the flight path is readable.
	var subject: Vector3 = f.position
	var offset: Vector3 = f.forward().cross(Vector3.UP)*17.0+Vector3.UP*1.0
	var lens := 34.0
	if name=="anchor":
		subject = f.position-f.forward()*4.0
		offset = f.forward().cross(Vector3.UP)*15.0+Vector3.UP*0.5
		lens = 26.0
	app.camera.global_position = subject+offset
	app.camera.look_at(subject,Vector3.UP); app.camera.fov = lens
	app.aircraft.rotation = Vector3(f.pitch,-f.heading,-f.roll)
	for i in 6: await process_frame
	await shot(folder,name+"-path")
	app.aircraft.rotation = Vector3(f.pose_pitch(),-f.pose_heading(),-f.pose_roll())
	for i in 6: await process_frame
	await shot(folder,name+"-pose")

func drive(dt: float,control: Vector3,hold_speed: float) -> void:
	if hold_speed>0.0: app.flight.speed = hold_speed
	app.combat.tick(dt)
	app.flight.step(dt,control,false,app.world.ground_height(app.flight.position.x,app.flight.position.z),false,false)
	app.apply_aircraft_pose()
	app._process(dt)

func shot(folder: String,name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
