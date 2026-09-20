extends RefCounted
class_name TargetIntent
## Extends the existing angular targeting and lead solver with intent/hysteresis.
const Tune = preload("res://data/balance.gd")
var confidence := 0.0
var help_amount := .55
var intensity := .22
var accuracy := .6
var time_since_reward := 0.0
var tracking_quality := .5
var overshoots := 0.0
var missile_misses := 0.0
var roll_losses := 0.0
var near_collisions := 0.0
var maneuver_flow := 0.0
var lock_time := 0.0
var selected_age := 0.0
var recent_events: Array[String] = []
var metrics := {"locks":0,"switches":0,"rolls":0,"boosts":0,"near_misses":0,"misses":0,"chains":0}
var previous_angles: Dictionary = {}
var previous_target := -1
var previous_rounds := 0
var previous_hits := 0
var sample_clock := 0.0
var last_boost := false
var last_roll := false
func reset() -> void:
	confidence=0;help_amount=.55;intensity=.22;accuracy=.6;time_since_reward=0
	tracking_quality=.5;overshoots=0;missile_misses=0;roll_losses=0;near_collisions=0;maneuver_flow=0
	selected_age=0;lock_time=0;previous_target=-1;previous_rounds=0;previous_hits=0;sample_clock=0
	previous_angles.clear();recent_events.clear();last_boost=false;last_roll=false
	for key in metrics:metrics[key]=0
func event(kind: String) -> void:
	recent_events.append(kind)
	if recent_events.size()>12:recent_events.pop_front()
	if kind=="kill":time_since_reward=0;intensity=minf(.95,intensity+.11);metrics.chains+=1
	elif kind=="miss":missile_misses=minf(1,missile_misses+.15);metrics.misses+=1
	elif kind=="near_miss":maneuver_flow=minf(1,maneuver_flow+.2);metrics.near_misses+=1
func tick(c: Node,dt: float) -> void:
	time_since_reward+=dt;sample_clock+=dt;selected_age+=dt
	var f: FlightDynamics=c.app.flight
	var rolling: bool=f.barrel_remaining>0
	if rolling and not last_roll:metrics.rolls+=1;maneuver_flow=minf(1,maneuver_flow+.15)
	if f.afterburner and not last_boost:metrics.boosts+=1;maneuver_flow=minf(1,maneuver_flow+.1)
	last_roll=rolling;last_boost=f.afterburner
	overshoots=move_toward(overshoots,0,dt*.025);missile_misses=move_toward(missile_misses,0,dt*.025)
	roll_losses=move_toward(roll_losses,0,dt*.02);near_collisions=move_toward(near_collisions,0,dt*.05)
	maneuver_flow=move_toward(maneuver_flow,0,dt*.025)
	if f.position.y-c.app.world.ground_height(f.position.x,f.position.z)<45:near_collisions=minf(1,near_collisions+dt*.25)
	if sample_clock>=.75:
		var fired: int=c.rounds_fired-previous_rounds
		if fired>0:accuracy=lerpf(accuracy,clampf(float(c.rounds_hit-previous_hits)/fired,0,1),.2)
		previous_rounds=c.rounds_fired;previous_hits=c.rounds_hit;sample_clock=0
	var frustration: float=clampf(time_since_reward/14,0,1)*.25+(1-accuracy)*.25+overshoots*.12+missile_misses*.14+roll_losses*.12+near_collisions*.12+(1-tracking_quality)*.08
	help_amount=lerpf(help_amount,clampf(.28+frustration,.28,.92),1-exp(-dt*.18))
	var flow: float=clampf(float(c.combo)/6,0,1)*.42+accuracy*.22+maneuver_flow*.24+.12
	intensity=lerpf(intensity,flow,1-exp(-dt*.12))
func acquire_degrees(c: Node) -> float:
	return lerpf(8.0,12.0,help_amount)+(2.0 if c.elapsed<15 else 0.0)
func retain_degrees(c: Node) -> float:
	return acquire_degrees(c)+5.0+(12.0 if c.app.flight.barrel_remaining>0 else 0.0)
func choose(c: Node,dt: float) -> int:
	var f: FlightDynamics=c.app.flight
	var facing: Vector3=c.forward()
	var right:=Vector3(cos(f.heading),0,sin(f.heading))
	var predicted: Vector3=facing.rotated(Vector3.UP,-f.yaw_velocity*.22).rotated(right,f.pitch_velocity*.18)
	var outer:=deg_to_rad(acquire_degrees(c));var retained:=deg_to_rad(retain_degrees(c))
	var best: int=-1;var best_score: float=-INF;var old_score: float=-INF;var old_angle: float=PI
	for enemy: Dictionary in c.enemies:
		if enemy.health<=0 or enemy.get("retiring",false) or enemy.fade<.25:continue
		var delta: Vector3=enemy.position-f.position;var distance:=delta.length()
		if distance<1 or distance>Tune.TARGET_RANGE:continue
		var direction:=delta/distance;var angle:=facing.angle_to(direction)
		var previous: float=previous_angles.get(enemy.id,angle)
		var convergence:=clampf((previous-angle)/maxf(dt,.001),-1,1)
		previous_angles[enemy.id]=angle
		if enemy.id==c.target_id and convergence<-.08 and angle<retained:overshoots=minf(1,overshoots+dt*.45)
		var occluded:=false
		for fraction in [.35,.7]:
			var p: Vector3=f.position.lerp(enemy.position,fraction)
			if c.app.world.ground_height(p.x,p.z)>p.y+8:occluded=true
		enemy.sensor_occluded=occluded
		enemy.occluded_time=float(enemy.get("occluded_time",0))+dt if occluded else 0.0
		var visual: float=1.0 if not c.app.camera.is_position_behind(enemy.position) else 0.0
		var angular: float=1-clampf(angle/outer,0,1)
		var future: float=1-clampf(predicted.angle_to(direction)/outer,0,1)
		var reach: float=1-clampf(absf(distance-650)/1900,0,1)
		var lead: Vector3=c.lead_point(enemy)-f.position
		var intercept: float=1-clampf(facing.angle_to(lead.normalized())/(outer*1.5),0,1)
		var score: float=angular*.47+future*.17+maxf(convergence,0)*.12+reach*.06+intercept*.08+visual*.06+float(enemy.get("presented",false))*.04
		if enemy.id==c.target_id:
			old_score=score+.18;old_angle=angle if enemy.occluded_time<.8 else PI
			if occluded:old_score-=.12
		if angle>outer or visual==0 or occluded:continue
		if score>best_score:best_score=score;best=enemy.id
	if c.target_id>=0 and old_angle<retained and (c.app.flight.barrel_remaining>0 or selected_age<.38 or old_score>best_score-.04):best=c.target_id;best_score=old_score
	if best!=c.target_id:
		if c.target_id>=0:metrics.switches+=1
		if best<0 and last_roll:roll_losses=minf(1,roll_losses+.2)
		selected_age=0;lock_time=0
	var wanted: float=clampf(best_score,0,1) if best>=0 else 0
	confidence=lerpf(confidence,wanted,1-exp(-dt*(24 if best>=0 else 12)))
	tracking_quality=lerpf(tracking_quality,wanted,1-exp(-dt*.8))
	if best>=0:lock_time+=dt
	previous_target=best
	return best
func steering_assist(raw: Vector3,c: Node) -> Vector3:
	if raw.length()<.035 or c.target_id<0 or not c.assist:return raw
	var target: Dictionary=c.target()
	if target.is_empty():return raw
	var f: FlightDynamics=c.app.flight
	if f.barrel_remaining>0:return raw
	var d: Vector3=(target.position-f.position).normalized()
	if c.forward().angle_to(d)>deg_to_rad(acquire_degrees(c)):return raw
	var horizontal: float=Vector3(cos(f.heading),0,sin(f.heading)).dot(d)
	var vertical: float=d.y-sin(f.pitch)
	var out:=raw
	var gain:=confidence*help_amount
	for axis in [0,1]:
		var error: float=horizontal if axis==0 else vertical
		if signf(raw[axis])==signf(error):out[axis]*=1+.18*gain
		elif absf(error)<.06:out[axis]*=1-.38*gain
	return out.clamp(-Vector3.ONE,Vector3.ONE)
