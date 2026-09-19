extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=load("res://scenes/coastal_world.gd").new()
	# Height math does not need to load/render the entire asset collection.
	for center in [0.0,-15000.0]:
		for x in range(-150,1001,25):
			for z in range(-1800,1801,25):
				checks+=1
				# Sample the actual heightfield, not the runway collision override.
				var height: float=world._terrain_height(x,z+center)
				if height>-0.30: failures.append("Airport terrain intersects deck at "+str(Vector2(x,z+center)))
		for point in [Vector2(685,540),Vector2(880,565),Vector2(245,1450),Vector2(730,175)]:
			checks+=1
			if world.ground_height(point.x,point.y+center)>-0.30: failures.append("Interpolated airport surface too high")
	print("GROUNDING RESULT: ",checks," samples, ",failures.size()," failures")
	for failure in failures.slice(0,10): printerr(failure)
	world.free()
	quit(0 if failures.is_empty() else 1)
