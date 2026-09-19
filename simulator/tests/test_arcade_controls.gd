extends SceneTree
const Dynamics = preload("res://systems/flight_dynamics.gd")
const Controls = preload("res://systems/arcade_controls.gd")
const Catalog = preload("res://data/aircraft.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures.append(label);push_error("CONTROL FEEL FAIL: "+label)
func advance(f,raw: Vector3,seconds: float):
	for i in range(int(seconds*120)):
		f.step(1.0/120,Controls.command(f,raw,f.position.y),false,0,false)
func _initialize():
	var f = Dynamics.new(); f.reset(Catalog.PROFILE); f.spawn_airborne(Vector3(0,450,0),165)
	advance(f,Vector3(.76,0,0),1.5)
	check(f.roll>deg_to_rad(35) and f.roll<deg_to_rad(46),"Holding an arrow produces a controlled bank, not endless rolling")
	check(f.position.x>10 and f.heading>0,"A held bank makes a meaningful turn")
	advance(f,Vector3.ZERO,1.5)
	check(absf(f.roll)<deg_to_rad(3),"Releasing steering smoothly levels the wings")
	advance(f,Vector3(0,.76,0),1.0)
	check(f.pitch>deg_to_rad(13) and f.pitch<deg_to_rad(23),"Pitch inputs are strong but bounded")
	advance(f,Vector3.ZERO,1.5)
	check(absf(f.pitch)<deg_to_rad(2),"Release-to-level prevents continued nose drift")
	advance(f,Vector3(-.76,0,0),.15)
	check(absf(f.roll)<deg_to_rad(16),"A short tap does not over-rotate the aircraft")
	f.spawn_airborne(Vector3(0,60,0),165); f.pitch=-.25; f.roll=0;f.vertical_speed=-40;f.velocity=Vector3(0,-40,-165)
	var before: Vector3 = f.position
	advance(f,Vector3.ZERO,1.5)
	check(f.contact!="crash" and f.vertical_speed>0,"Terrain protection recovers a descending aircraft continuously")
	check(f.position.distance_to(before)<350,"Terrain assistance moves through physics without teleporting")
	print("ARCADE CONTROLS: ",checks," checks / ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
