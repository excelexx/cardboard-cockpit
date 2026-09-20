extends RefCounted
## Visual snapshots only: physics, collision, controls and weapons keep the live state.
const Flight=preload("res://systems/flight_dynamics.gd")
var previous:Dictionary={}
var current:Dictionary={}
var visual:FlightDynamics=Flight.new()
var fields:PackedStringArray=[]
func _init()->void:
	for info:Dictionary in visual.get_property_list():
		if int(info.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:fields.append(str(info.name))
func capture(live:FlightDynamics)->Dictionary:
	var state:Dictionary={}
	for field:String in fields:state[field]=live.get(field)
	return state
func reset(live:FlightDynamics)->void:
	current=capture(live);previous=current
func record(live:FlightDynamics)->void:
	if current.is_empty():reset(live);return
	previous=current;current=capture(live)
	# Approach restart, recovery and scene changes must snap, never fly across the map.
	if Vector3(previous.position).distance_to(current.position)>maxf(50.0,live.speed*.1):previous=current
func sample(live:FlightDynamics,fraction:float)->FlightDynamics:
	if current.is_empty() or not Vector3(current.position).is_equal_approx(live.position) or not is_equal_approx(float(current.heading),live.heading):reset(live)
	for field:String in fields:visual.set(field,live.get(field))
	var alpha:float=clampf(fraction,0,1)
	visual.position=Vector3(previous.position).lerp(current.position,alpha)
	visual.velocity=Vector3(previous.velocity).lerp(current.velocity,alpha)
	visual.pose_offset=Vector3(previous.pose_offset).lerp(current.pose_offset,alpha)
	for field:String in ["pitch","roll","heading"]:visual.set(field,lerp_angle(float(previous[field]),float(current[field]),alpha))
	for field:String in ["aoa","beta","barrel_angle","speed","vertical_speed","engine","g_load"]:visual.set(field,lerpf(float(previous[field]),float(current[field]),alpha))
	return visual
