extends RefCounted
class_name ArcadeControls
const Tune = preload("res://data/balance.gd")
## Angle-demand controls: responsive banking, release-to-level and gentle terrain protection.
static func command(f: FlightDynamics, raw: Vector3, clearance: float, landing: bool = false) -> Vector3:
	if not f.airborne: return raw
	var roll_input: float = 0 if absf(raw.x)<Tune.INPUT_DEADZONE else raw.x
	var pitch_input: float = 0 if absf(raw.y)<Tune.INPUT_DEADZONE else raw.y
	var bank: float = roll_input*deg_to_rad(Tune.BANK_LIMIT_DEGREES)
	var trim: float = atan2((1-maxf(cos(f.roll),0))*6,maxf(f.speed,60))
	var pitch: float = pitch_input*deg_to_rad(Tune.LANDING_PITCH_LIMIT_DEGREES if landing else Tune.PITCH_LIMIT_DEGREES)+trim
	if landing and absf(pitch_input)<Tune.INPUT_DEADZONE:
		pitch = -atan(.05241) if clearance>14 else -.012
	if not landing:
		var safety: float = Tune.TERRAIN_MARGIN+f.speed*Tune.TERRAIN_SPEED_MARGIN
		# Take the LOWER of the raw and the low-passed vertical speed. The lag
		# stops a gust making the assist chatter and makes it HOLD longer, but it
		# may never make it arm later than the raw rate did - which is what a
		# plain vertical_trend test would do after a respawn or on a fresh bunt.
		if clearance<safety and minf(f.vertical_speed,f.vertical_trend)<3:
			pitch = maxf(pitch,clampf(.13+(safety-clearance)*.007,.13,.42))
	var roll: float = clampf((bank-f.roll)*Tune.ANGLE_RESPONSE-f.roll_velocity*Tune.ROLL_DAMPING,-1,1)
	var elevator: float = clampf((pitch-f.pitch)*Tune.ANGLE_RESPONSE-f.pitch_velocity*Tune.PITCH_DAMPING,-1,1)
	return Vector3(roll,elevator,raw.z*Tune.RUDDER_SCALE)
