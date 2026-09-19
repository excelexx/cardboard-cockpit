extends RefCounted
class_name ArcadeControls
## Angle-demand controls: responsive banking, release-to-level and gentle terrain protection.
static func command(f: FlightDynamics, raw: Vector3, clearance: float, landing: bool = false) -> Vector3:
	if not f.airborne: return raw
	var roll_input: float = 0 if absf(raw.x)<.04 else raw.x
	var pitch_input: float = 0 if absf(raw.y)<.04 else raw.y
	var bank: float = roll_input*deg_to_rad(55)
	var trim: float = atan2((1-maxf(cos(f.roll),0))*6,maxf(f.speed,60))
	var pitch: float = pitch_input*deg_to_rad(12 if landing else 24)+trim
	if landing and absf(pitch_input)<.04:
		pitch = -atan(.05241) if clearance>14 else -.012
	if not landing:
		var safety: float = 80+f.speed*.12
		if clearance<safety and f.vertical_speed<3:
			pitch = maxf(pitch,clampf(.13+(safety-clearance)*.007,.13,.42))
	var roll: float = clampf((bank-f.roll)*3.0-f.roll_velocity*.40,-1,1)
	var elevator: float = clampf((pitch-f.pitch)*3.0-f.pitch_velocity*.35,-1,1)
	return Vector3(roll,elevator,raw.z*.8)
