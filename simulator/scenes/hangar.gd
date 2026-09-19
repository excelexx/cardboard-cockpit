extends Node3D
class_name AircraftHangar

var pedestal: Node3D

func material(color: Color, metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

func box(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	add_child(node)
	return node

func build() -> void:
	var floor_mat := material(Color(0.10, 0.14, 0.16), 0.35, 0.35)
	var steel := material(Color(0.12, 0.16, 0.19), 0.65, 0.4)
	var panel := material(Color(0.20, 0.25, 0.27), 0.4, 0.5)
	var stripe := material(Color(0.62, 0.49, 0.29))
	box(Vector3(0,-0.5,0), Vector3(250,1,250), floor_mat)
	box(Vector3(0,25,-90), Vector3(220,50,1), panel)
	box(Vector3(0,25,115), Vector3(230,50,1), panel)
	box(Vector3(-115,25,0),Vector3(1,50,230),panel)
	box(Vector3(115,25,0),Vector3(1,50,230),panel)
	box(Vector3(0,51,0),Vector3(232,1,232),steel)
	for x: int in range(-110,111,10):
		box(Vector3(x,25,114),Vector3(0.25,50,0.35),steel)
	for x: int in range(-100, 101, 10):
		box(Vector3(x,25,-89),Vector3(0.3,50,0.4),steel)
	for x: int in [-95, -65, -35, 35, 65, 95]:
		box(Vector3(x,25,-84),Vector3(1.1,50,1.1),steel)
		box(Vector3(x,49,0),Vector3(1,1.5,170),steel)
		box(Vector3(x,0.025,0),Vector3(0.10,0.025,160),panel)
	for z: int in range(-80, 101, 20):
		box(Vector3(0,0.035,z),Vector3(200,0.03,0.10),panel)
	for x: int in [-48, 48]:
		box(Vector3(x,0.05,5),Vector3(0.18,0.04,100),stripe)
	box(Vector3(0,0.05,55),Vector3(96,0.04,0.18),stripe)
	for z: int in [-70,-30,10,50]:
		box(Vector3(0,49,z),Vector3(190,1.2,1.2),steel)
		var light_mat := material(Color(0.75,0.82,0.83))
		light_mat.emission_enabled = true
		light_mat.emission = Color(0.7,0.85,1.0)
		light_mat.emission_energy_multiplier = 3.0
		for x: int in [-50,0,50]:
			box(Vector3(x,48,z),Vector3(28,0.20,0.6),light_mat)
	for x: int in [-45,45]:
		var light := OmniLight3D.new()
		light.position = Vector3(x,25,15)
		light.omni_range = 130
		light.light_energy = 3.2
		light.light_color = Color(0.78,0.85,1.0)
		add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55, 120, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.66,0.78,1.0)
	add_child(fill)
	var title := Label3D.new()
	title.text = "C A R D B O A R D   C O C K P I T"
	title.font_size = 100
	title.pixel_size = 0.025
	title.position = Vector3(0,28,-88)
	title.modulate = Color(0.65,0.75,0.78)
	add_child(title)
	pedestal = Node3D.new()
	add_child(pedestal)
