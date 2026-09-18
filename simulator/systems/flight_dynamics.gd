extends RefCounted
class_name FlightDynamics

var profile: Dictionary
var position := Vector3(0, 4, 1100)
var speed: float = 0.0
var throttle: float = 0.0
var engine: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
var heading: float = 0.0
var vertical_speed: float = 0.0
var airborne := false
var ever_airborne := false
var gear := true
var elapsed: float = 0.0
var airborne_time: float = 0.0
var distance: float = 0.0
var roughness: float = 0.0
var contact := ""
var touchdown_speed: float = 0.0
var touchdown_sink: float = 0.0
var touchdown_bank: float = 0.0
var stall_time: float = 0.0

func reset(aircraft: Dictionary) -> void:
	profile = aircraft
	position = Vector3(0, float(profile.clearance), 1100)
	speed = 0.0
	throttle = 0.0
	engine = 0.0
	pitch = 0.0
	roll = 0.0
	heading = 0.0
	vertical_speed = 0.0
	airborne = false
	ever_airborne = false
	gear = true
	elapsed = 0.0
	airborne_time = 0.0
	distance = 0.0
	roughness = 0.0
	contact = ""
	stall_time = 0.0
	touchdown_speed = 0.0
	touchdown_sink = 0.0
	touchdown_bank = 0.0

func step(dt: float, control: Vector3, brakes: bool, ground: float, runway: bool) -> void:
	if contact != "":
		return
	elapsed += dt
	engine = move_toward(engine, throttle, dt * 0.32)
	var rotation_speed: float = profile.rotation_speed
	var max_speed: float = profile.max_speed
	var acceleration: float = profile.acceleration
	var drag: float = acceleration * pow(speed / max_speed, 2.0) + (0.45 if gear else 0.12)
	if not airborne:
		drag += 0.25 + (18.0 if brakes else 0.0)
	speed = clampf(speed + (engine * acceleration - drag - sin(pitch) * 3.4) * dt, 0.0, max_speed * 1.12)
	var authority: float = clampf(speed / rotation_speed, 0.0, 1.5)
	if airborne:
		roll += control.x * float(profile.roll_rate) * dt
		roll = move_toward(roll, 0.0, dt * (0.10 if absf(control.x) < 0.05 else 0.0))
		roll = clampf(roll, -0.95, 0.95)
		pitch += control.y * float(profile.pitch_rate) * dt * authority
		pitch = move_toward(pitch, 0.0, dt * (0.018 if absf(control.y) < 0.05 else 0.0))
		pitch = clampf(pitch, -0.40, 0.48)
		heading += (tan(roll) * 18.0 / maxf(speed, 30.0) + control.z * 0.06) * dt
		var lift_factor: float = clampf(speed / (rotation_speed * 0.85), 0.0, 1.0)
		var desired_vertical: float = sin(pitch) * speed - (1.0 - lift_factor) * 32.0
		# Forgiving initial departure, but landing remains under player control.
		if airborne_time < 8.0 and position.y - ground < 30.0 and desired_vertical < 1.0:
			desired_vertical = 2.0
		vertical_speed = lerpf(vertical_speed, desired_vertical, 1.0 - exp(-dt * 2.5))
		position.y += vertical_speed * dt
		airborne_time += dt
		stall_time = stall_time + dt if lift_factor < 0.85 else 0.0
		roughness += (absf(control.x) * 0.2 + absf(control.y) * 0.15) * dt
	else:
		heading += control.z * 0.35 * clampf(speed / 20.0, 0.0, 1.0) * dt
		roll = 0.0
		pitch = move_toward(pitch, maxf(control.y, 0.0) * 0.14, dt * 0.12)
		position.y = ground + float(profile.clearance)
		vertical_speed = 0.0
		if speed >= rotation_speed and control.y > 0.12:
			airborne = true
			ever_airborne = true
			vertical_speed = 4.0
			position.y += 0.3
	var forward := Vector3(sin(heading), 0, -cos(heading))
	position += forward * speed * cos(pitch) * dt
	distance += speed * dt
	if airborne and position.y <= ground + float(profile.clearance):
		touchdown_speed = speed
		touchdown_sink = vertical_speed
		touchdown_bank = roll
		if runway and gear and speed < 105.0 and vertical_speed > -10.0 and absf(roll) < 0.40:
			airborne = false
			position.y = ground + float(profile.clearance)
			pitch = 0.0
			roll = 0.0
			vertical_speed = 0.0
			contact = "landed"
		else:
			contact = "crash"
	if not airborne and not runway and speed > 50.0:
		contact = "excursion"

func get_heading_degrees() -> float:
	return fposmod(rad_to_deg(heading), 360.0)

func get_smoothness() -> int:
	return clampi(int(100.0 - roughness / maxf(elapsed, 1.0) * 220.0 - stall_time), 0, 100)
