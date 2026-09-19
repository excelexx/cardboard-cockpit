extends RefCounted
## Original low-poly aircraft and a fan-made freighter silhouette.
static func part(parent: Node3D, shape: Mesh, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.35
	mat.roughness = 0.55
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3
	node.material_override = mat
	parent.add_child(node)
	return node
static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow: bool = false) -> void:
	var shape := BoxMesh.new()
	shape.size = size
	part(parent,shape,at,color,glow)
static func create(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var frame := Node3D.new()
	frame.name = "Airframe"
	root.add_child(frame)
	var steel := Color(0.54,0.58,0.61)
	var dark := Color(0.16,0.2,0.24)
	if id in ["trainer","vx9"]:
		var model: Node3D = online_ship("craft_speederA" if id=="trainer" else "craft_speederD",6.8 if id=="trainer" else 18.0,8.0 if id=="trainer" else 24.0)
		frame.add_child(model)
		return root
	if id=="falcon":
		var detail: Node3D = online_ship("craft_cargoB",8.0,10.0)
		for surface: Node in detail.find_children("*","MeshInstance3D",true,false):
			var finish := StandardMaterial3D.new()
			finish.albedo_color = Color(0.44,0.47,0.49)
			finish.metallic = 0.45
			surface.material_override = finish
		detail.position.y = 1.5
		frame.add_child(detail)
		var disc := CylinderMesh.new()
		disc.top_radius = 11.8
		disc.bottom_radius = 12.5
		disc.height = 3.2
		disc.radial_segments = 64
		part(frame,disc,Vector3.ZERO,steel)
		for side in [-1,1]:
			box(frame,Vector3(4.2,2.0,15),Vector3(side*4.2,0,-12),steel)
			box(frame,Vector3(3.0,0.12,10),Vector3(side*4.2,1.08,-12),dark)
		var cockpit := CapsuleMesh.new()
		cockpit.radius = 1.25
		cockpit.height = 9
		part(frame,cockpit,Vector3(10.5,0.4,-4),steel).rotation.x = PI/2
		box(frame,Vector3(5,2,3),Vector3(8,0,-1),steel)
		box(frame,Vector3(1.6,0.9,1),Vector3(10.5,0.9,-8),Color(0.08,0.25,0.31))
		box(frame,Vector3(16,0.7,0.3),Vector3(0,0,11.6),Color(0.2,0.75,1),true)
		for spoke in range(16):
			var angle: float = TAU*spoke/16
			var panel := BoxMesh.new()
			panel.size = Vector3(0.07,0.035,7.5)
			part(frame,panel,Vector3(sin(angle)*6.8,1.62,cos(angle)*6.8),dark).rotation.y = angle
		for i in range(8):
			var vent := CylinderMesh.new()
			vent.top_radius = 1.0
			vent.bottom_radius = 1.0
			vent.height = 0.16
			part(frame,vent,Vector3(-7+i*2,1.66,4+absf(i-3.5)),dark)
		var dish := SphereMesh.new()
		dish.radius = 1.9
		dish.height = 0.45
		part(frame,dish,Vector3(-5,3,-1),steel).rotation.x = -0.3
		box(frame,Vector3(0.7,1.3,0.7),Vector3(-5,2,-1),dark)
		box(frame,Vector3(1.5,0.9,1.5),Vector3(0,2,0),dark)
		for side in [-1,1]: box(frame,Vector3(0.14,0.14,3),Vector3(side*0.35,2.4,-1.3),dark)
	else:
		var advanced: bool = id=="vx9"
		var length: float = 22.0 if advanced else 8.0
		var span: float = 18.0 if advanced else 6.8
		var body := CapsuleMesh.new()
		body.radius = 1.0 if advanced else 0.55
		body.height = length
		part(frame,body,Vector3.ZERO,Color(0.23,0.3,0.37) if advanced else steel).rotation.x = PI/2
		box(frame,Vector3(span,0.2,length*0.2),Vector3(0,0,1),dark)
		box(frame,Vector3(span*0.45,0.15,1.2),Vector3(0,0.4,length*0.35),steel)
		box(frame,Vector3(0.2,2,1.3),Vector3(0,0.9,length*0.35),dark)
		var canopy := SphereMesh.new()
		canopy.radius = 0.9 if advanced else 0.48
		canopy.height = 0.7
		part(frame,canopy,Vector3(0,0.8,-length*0.2),Color(0.1,0.3,0.4))
		if advanced:
			for side in [-1,1]:
				box(frame,Vector3(2,1.7,12),Vector3(side*5,0,3),steel)
				box(frame,Vector3(1.5,0.7,0.1),Vector3(side*5,0,9.1),Color(0.3,0.75,1),true)
	return root

static func bounds(node: Node3D, accumulated: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform: Transform3D = accumulated*node.transform
	var result := AABB()
	if node is MeshInstance3D: result = transform*node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = bounds(child,transform)
			if child_bounds.size.length()>0:
				result = child_bounds if result.size.length()==0 else result.merge(child_bounds)
	return result
static func online_ship(name: String, span: float, length: float) -> Node3D:
	var wrapper := Node3D.new()
	var model: Node3D = load("res://assets/ships/%s.glb" % name).instantiate()
	wrapper.add_child(model)
	var size: AABB = bounds(model)
	var factor := Vector3(span/maxf(size.size.x,0.01),span/maxf(size.size.x,0.01),length/maxf(size.size.z,0.01))
	model.scale = factor
	model.position = -size.get_center()*factor
	return wrapper
