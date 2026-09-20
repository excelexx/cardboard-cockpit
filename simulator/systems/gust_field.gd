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
var noise: FastNoiseLite
## Last sampled roughness, 0-1. Cameras and instruments read this; sample() sets it.
var intensity := 0.0
## Steady sea breeze off the Pacific, the term the old two-sine model provided.
const BREEZE := Vector3(3.5,0.0,0.0)
const PATH_SCALE := 0.006
const POSE_SCALE := 0.020
const GROUND_FADE_START := 15.0
const GROUND_FADE_SPAN := 45.0
const SLOPE_PROBE := 60.0

func _init() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 20260918
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.45

## Wind vector in m/s. Deterministic for a given aircraft state and world.
func sample(world, flight) -> Vector3:
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
	var near_ground: float = clampf((agl-GROUND_FADE_START)/GROUND_FADE_SPAN,0.0,1.0)
	intensity = clampf((terrain+cloud*Tune.GUST_CLOUD_GAIN)*near_ground,0.0,1.0)
	var amplitude: float = Tune.GUST_SCALE*intensity*clampf(flight.speed/200.0,0.3,1.4)
	var t: float = flight.distance*PATH_SCALE
	var gust := Vector3(noise.get_noise_1d(t),noise.get_noise_1d(t+31.7)*0.55,noise.get_noise_1d(t+63.1))*amplitude
	return (gust+BREEZE*near_ground).limit_length(Tune.GUST_MAX)

## Pitch, yaw and roll offsets in radians for the airframe POSE. Under a degree,
## and never applied to the flight path. Call sample() first in the same frame.
func pose_offset(flight) -> Vector3:
	var t: float = flight.distance*POSE_SCALE
	return Vector3(
		noise.get_noise_1d(t+11.3)*deg_to_rad(Tune.GUST_POSE_PITCH_DEGREES),
		noise.get_noise_1d(t+43.9)*deg_to_rad(Tune.GUST_POSE_YAW_DEGREES),
		noise.get_noise_1d(t+77.1)*deg_to_rad(Tune.GUST_POSE_ROLL_DEGREES))*clampf(intensity,0.0,1.0)

## 0-1 buffet level for camera shake and instrument jitter.
func buffet() -> float: return clampf(intensity,0.0,1.0)

## Speed through the air rather than over the ground, for the airspeed tape.
func true_airspeed(flight) -> float:
	return (flight.velocity-flight.wind).length()
