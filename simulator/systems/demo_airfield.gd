extends Node3D
## Small destination field, placed ahead of the completed target encounter.
const DISTANCE := 27000.0
const LENGTH := 2600.0
const WIDTH := 90.0
const AIM_Z := 900.0
var heading := 0.0

func setup(app: Node) -> void:
	heading = app.flight.heading
	rotation.y = -heading
	var forward := Vector3(sin(heading),0,-cos(heading))
	var right := Vector3(cos(heading),0,sin(heading))
	position = app.flight.position+forward*DISTANCE+right*550
	var surface := -INF
	var floor_height := INF
	for z: float in range(-1400,1401,100):
		for x: float in [-160,0,160]:
			var at: Vector3 = position+forward*(-z)+right*x
			surface = maxf(surface,app.world.ground_height(at.x,at.z))
			floor_height = minf(floor_height,app.world.ground_height(at.x,at.z))
	# Keep the complete final approach above terrain, including ridge edges before the runway.
	for z: float in range(1600,14001,400):
		for x: float in [-150,0,150]:
			var at: Vector3 = position+forward*(-z)+right*x
			surface = maxf(surface,app.world.ground_height(at.x,at.z)-(z-AIM_Z)*.05241)
	# An embankment keeps the demo field clear of the sourced ground geometry.
	position.y = surface+36
	var grass := material(Color(.23,.29,.18))
	var asphalt := material(Color(.085,.105,.12))
	var white := material(Color(.94,.95,.87))
	embankment(floor_height-position.y-8,grass)
	box(Vector3(0,-.2,0),Vector3(320,.4,2800),grass)
	box(Vector3(0,.06,0),Vector3(WIDTH,.12,LENGTH),asphalt)
	for side: int in [-1,1]:
		box(Vector3(side*(WIDTH/2-2),.14,0),Vector3(1.2,.04,LENGTH-30),white)
		for z: float in range(-1200,1201,150):
			box(Vector3(side*(WIDTH/2+3),.45,z),Vector3(1.5,.7,1.5),material(Color(.5,.85,1),2))
	for z: float in range(-1100,1101,90): box(Vector3(0,.15,z),Vector3(2.4,.04,35),white)
	for z: float in [-1220,1220]:
		for x: float in [-32,-24,-16,16,24,32]: box(Vector3(x,.16,z),Vector3(5,.04,65),white)
	for z: float in [-450,-180,150]:
		box(Vector3(112,7,z),Vector3(48,14,80),material(Color(.48,.53,.53)))
		box(Vector3(112,14.3,z),Vector3(51,.6,84),material(Color(.19,.24,.27)))
	box(Vector3(-110,13,0),Vector3(12,26,12),material(Color(.68,.7,.65)))
	box(Vector3(-110,29,0),Vector3(24,7,24),material(Color(.13,.32,.38)))
	var label := Label3D.new(); label.text = "LANDING AIRFIELD"
	label.font_size = 96; label.pixel_size = .32; label.outline_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0,65,1050); add_child(label)

func local_ground(x: float, z: float) -> Vector3:
	return to_local(Vector3(x,position.y,z))
func contains_surface(x: float, z: float) -> bool:
	var at := local_ground(x,z)
	return absf(at.x)<160 and absf(at.z)<1400
func contains_runway(x: float, z: float) -> bool:
	var at := local_ground(x,z)
	return absf(at.x)<WIDTH/2 and absf(at.z)<LENGTH/2
func target() -> Vector3: return to_global(Vector3(0,3,AIM_Z))
func material(color: Color, emission: float = 0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new(); result.albedo_color = color; result.roughness = .9
	if emission>0: result.emission_enabled = true; result.emission = color; result.emission_energy_multiplier = emission
	return result
func box(at: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new(); mesh.size = size
	var node := MeshInstance3D.new(); node.mesh = mesh; node.material_override = mat
	node.position = at; add_child(node)

func embankment(bottom: float, mat: Material) -> void:
	var top: Array[Vector3] = [Vector3(-160,0,1400),Vector3(160,0,1400),Vector3(160,0,-1400),Vector3(-160,0,-1400)]
	var base: Array[Vector3] = [Vector3(-260,bottom,1500),Vector3(260,bottom,1500),Vector3(260,bottom,-1500),Vector3(-260,bottom,-1500)]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var j := (i+1)%4
		for vertex: Vector3 in [top[i],base[i],top[j],top[j],base[i],base[j]]: surface.add_vertex(vertex)
	surface.generate_normals()
	var node := MeshInstance3D.new(); node.mesh = surface.commit(); node.material_override = mat; add_child(node)
