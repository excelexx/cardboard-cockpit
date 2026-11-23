extends RefCounted
class_name GustField
const Tune = preload("res://data/balance.gd")
## Spatially varying air. One noise field, built once, sampled along the path the
## aircraft has actually flown, so the same stretch of coast always feels the same.
##
## It is a LOOK system first: most of what it produces is pose (a little wing
## rock, a nodding nose), and the part that reaches the trajectory is bounded to
## a few metres and washed out by the flight-path lag. It is deliberately gentle
## near the ground below 15 m AGL so it can never interfere with a rotation,
## a flare or a rollout.
##
## STEADINESS (binding, from the owner's "vibrates very fast" bug report). Nothing
## this field produces may read as per-frame noise. Three rules keep that true and
## all three must still hold if the numbers are ever retuned:
##   1. ONE octave. A fractal stack multiplies the top frequency by the lacunarity
##      for every extra octave: three octaves at the old scale put a 24 Hz term on
##      the airframe at combat speed, which is what the owner saw vibrating.
##   2. The sample scales set the field's frequency directly - SCALE*speed Hz -
##      and are chosen to stay under 1 Hz on the pose channel and 2 Hz on the wind
##      across the whole speed range. Frequency, not amplitude, is what turns a
##      wallow into a buzz: per-frame motion is amplitude*2*PI*f/fps.
##   3. Both noise shapes go through a first-order lag at SMOOTH_RATE, which is
##      transparent to the wallow and removes anything above ~10 Hz.
## The ROUGHNESS is deliberately NOT lagged: it is a smooth function of height
## above terrain and is what instruments and the camera read, and lagging it would
## make the field answer late to a ridge. The near-ground gate is likewise applied
## after the lag and instantaneously, so "no gust below 15 m AGL" stays an exact
## guarantee rather than a filtered approximation.
var noise: FastNoiseLite
## Last sampled roughness, 0-1. Cameras and instruments read this; sample() sets it.
var intensity := 0.0
## Steady sea breeze off the Pacific, the term the old two-sine model provided.
const BREEZE := Vector3(3.5,0.0,0.0)
## Cycles per metre flown. SCALE*speed is the frequency in Hz: at 322 m/s the wind
## runs at 0.7 Hz and the pose wobble at 0.39 Hz; flat out, 1.1 Hz and 0.6 Hz.
## The spatial feature sizes that fall out - 450 m of gust, 830 m of wallow - are
## the sizes real low-level turbulence comes in, so slow is also correct here.
const PATH_SCALE := 0.0022
const POSE_SCALE := 0.0012
## First-order lag on the wind, the pose wobble and the roughness, in 1/s.
## -3 dB at 3.2 Hz, -11 dB at 10 Hz.
const SMOOTH_RATE := 20.0
## Longest step the lag will honour. A frame hitch must not snap the filter open.
const SMOOTH_MAX_STEP := 0.25
const GROUND_FADE_START := 15.0
const GROUND_FADE_SPAN := 45.0
const SLOPE_PROBE := 60.0

## Filter state. `_dt` is the simulated time since the previous sample(), worked
## out from the distance the aircraft covered, so the lag is frame-rate
## independent without sample() needing a dt argument scenes/main.gd cannot give.
var _dt := 0.0
var _last_distance := -1.0
var _gust := Vector3.ZERO
var _pose := Vector3.ZERO
var _primed := false
var _pose_primed := false

func _init() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 20260918
	noise.frequency = 1.0
	# One octave. See rule 1 of the STEADINESS note above before changing this.
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = 1

## Seconds since the last sample, from the distance flown. Zero when the aircraft
## has not moved, so sampling the same state twice is still deterministic. A
## reset, a respawn or a jump to another fixture moves `distance` BACKWARDS: that
## is a new aircraft, so the filter re-primes on the next sample instead of
## drifting there - and, just as important, instead of freezing, which is what a
## "return 0" would do forever once `distance` restarted at zero.
func _advance(flight) -> float:
	var travelled: float = float(flight.distance)
	var step := 0.0
	if _last_distance<0.0 or travelled<_last_distance: _primed = false
	elif travelled>_last_distance:
		step = clampf((travelled-_last_distance)/maxf(float(flight.speed),1.0),0.0,SMOOTH_MAX_STEP)
	_last_distance = travelled
	return step

func _lag() -> float:
	return 1.0-exp(-_dt*SMOOTH_RATE)

## Wind vector in m/s. Deterministic for a given aircraft state and world.
func sample(world, flight) -> Vector3:
	_dt = _advance(flight)
	var has_ground: bool = world!=null and world.has_method("ground_height")
	var ground: float = world.ground_height(flight.position.x,flight.position.z) if has_ground else 0.0
	var agl: float = maxf(flight.position.y-ground,0.0)
	var slope := 0.0
	if has_ground:
		var dx: float = world.ground_height(flight.position.x+SLOPE_PROBE,flight.position.z)-world.ground_height(flight.position.x-SLOPE_PROBE,flight.position.z)
		var dz: float = world.ground_height(flight.position.x,flight.position.z+SLOPE_PROBE)-world.ground_height(flight.position.x,flight.position.z-SLOPE_PROBE)
		slope = clampf(Vector2(dx,dz).length()/(2.0*SLOPE_PROBE)*3.0,0.0,1.6)
	var terrain: float = Tune.GUST_AMBIENT+clampf(1.0-agl/Tune.GUST_TERRAIN_RANGE,0.0,1.0)*(0.35+slope)
	var cloud := 0.0
	if world!=null:
		var presence: Variant = world.get("cloud_presence")
		if presence is float or presence is int: cloud = clampf(float(presence),0.0,1.0)
	var rough: float = clampf(terrain+cloud*Tune.GUST_CLOUD_GAIN,0.0,1.0)
	var t: float = flight.distance*PATH_SCALE
	var shape := Vector3(noise.get_noise_1d(t),noise.get_noise_1d(t+31.7)*0.55,noise.get_noise_1d(t+63.1))
	if _primed: _gust = _gust.lerp(shape,_lag())
	else:
		_gust = shape; _primed = true; _pose_primed = false
	# Hard, unlagged: below 15 m AGL there is no gust at all, ever.
	var near_ground: float = clampf((agl-GROUND_FADE_START)/GROUND_FADE_SPAN,0.0,1.0)
	intensity = clampf(rough*near_ground,0.0,1.0)
	var amplitude: float = Tune.GUST_SCALE*intensity*clampf(flight.speed/200.0,0.3,1.4)
	return (_gust*amplitude+BREEZE*near_ground).limit_length(Tune.GUST_MAX)

## Pitch, yaw and roll offsets in radians for the airframe POSE. Under a degree,
## and never applied to the flight path. Call sample() first in the same frame:
## it is what advances this filter's clock and sets the intensity this scales by.
func pose_offset(flight) -> Vector3:
	var t: float = flight.distance*POSE_SCALE
	var shape := Vector3(
		noise.get_noise_1d(t+11.3),
		noise.get_noise_1d(t+43.9),
		noise.get_noise_1d(t+77.1))
	if _pose_primed: _pose = _pose.lerp(shape,_lag())
	else:
		_pose = shape; _pose_primed = true
	return Vector3(
		_pose.x*deg_to_rad(Tune.GUST_POSE_PITCH_DEGREES),
		_pose.y*deg_to_rad(Tune.GUST_POSE_YAW_DEGREES),
		_pose.z*deg_to_rad(Tune.GUST_POSE_ROLL_DEGREES))*clampf(intensity,0.0,1.0)

## 0-1 buffet level for camera shake and instrument jitter.
func buffet() -> float: return clampf(intensity,0.0,1.0)

## Speed through the air rather than over the ground, for the airspeed tape.
func true_airspeed(flight) -> float:
	return (flight.velocity-flight.wind).length()
