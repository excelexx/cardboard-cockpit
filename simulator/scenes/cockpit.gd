extends Node3D
class_name DetailedCockpit

const Display = preload("res://ui/cockpit_instruments.gd")
var displays: Array[CockpitInstruments] = []
var throttles: Array[Node3D] = []
var pilot_control: Node3D
var control_rest := Vector3.ZERO
var profile: Dictionary = {}
var airframe: String = "b737"
var navigation_kind: String = "valley"
var navigation_checkpoint: int = 0
var control_is_stick: bool = false
var trim := Vector3.ZERO
var shell: StandardMaterial3D
var trim_material: StandardMaterial3D
var metal: StandardMaterial3D
var black: StandardMaterial3D
var rubber: StandardMaterial3D
var lettering: Color = Color(0.7,0.77,0.78)
var presentation_state: int = -1

func build(aircraft: Dictionary) -> void:
	presentation_state = -1
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	displays.clear()
	throttles.clear()
	profile = aircraft
	airframe = str(profile.get("id","b737"))
	control_is_stick = airframe in ["a380","f35"]
	var boeing: bool = airframe in ["b737","b747"]
	var panel_color := Color(0.24,0.23,0.21) if boeing else Color(0.16,0.20,0.23)
	if airframe == "f35": panel_color = Color(0.115,0.13,0.145)
	if airframe == "b2": panel_color = Color(0.14,0.17,0.185)
	shell = _material(panel_color,0.91)
	trim_material = _material(panel_color.lightened(0.10),0.65)
	metal = _material(Color(0.36,0.40,0.42),0.36,0.65)
	black = _material(Color(0.015,0.02,0.024),0.76)
	rubber = _material(Color(0.035,0.04,0.044),0.96)
	_build_shell()
	if airframe == "f35":
		_fighter_panels()
	else:
		_transport_panels()
	_build_controls()
	_build_console()
	_build_lighting()
	# The pilot eye sits behind the instrument faces: show the full displays at 16:10.
	for child: Node in get_children():
		if child is Node3D:
			child.position += Vector3(0,0.08,-0.16)
	control_rest = pilot_control.position

func set_presentation_visible(value: bool) -> void:
	visible = value
	if presentation_state == int(value): return
	presentation_state = int(value)
	for geometry: Node in find_children("*","GeometryInstance3D",true,false):
		geometry.visible = value
	for viewport: Node in find_children("*","SubViewport",true,false):
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if value else SubViewport.UPDATE_DISABLED

func update_instruments(flight: FlightDynamics, control: Vector3, delta: float) -> void:
	for display: CockpitInstruments in displays:
		display.update_flight(flight,delta)
	trim = trim.lerp(control,1.0-exp(-delta*9.0))
	if is_instance_valid(pilot_control):
		if control_is_stick:
			pilot_control.rotation = Vector3(trim.y*0.28,0,-trim.x*0.28)
		else:
			pilot_control.rotation.z = -trim.x*0.55
			pilot_control.position.z = control_rest.z+trim.y*0.06
	for lever: Node3D in throttles:
		lever.rotation.x = lerpf(0.30,-0.38,flight.throttle)

func set_navigation(kind: String, checkpoint: int) -> void:
	navigation_kind = kind
	navigation_checkpoint = clampi(checkpoint,0,5)
	for display: CockpitInstruments in displays:
		display.set_navigation(navigation_kind,navigation_checkpoint)

func _material(color: Color, rough: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = rough
	result.metallic = metallic
	return result

func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material, rotate: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation = rotate
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, material: Material, rotate: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation = rotate
	parent.add_child(node)
	return node

func _beam(a: Vector3,b: Vector3,width: float,depth: float, material: Material) -> void:
	var node: MeshInstance3D = _box(self,Vector3(width,a.distance_to(b),depth),(a+b)*0.5,material)
	var direction: Vector3 = (b-a).normalized()
	var horizontal: Vector3 = direction.cross(Vector3.FORWARD).normalized()
	if horizontal.length() < 0.1: horizontal = Vector3.RIGHT
	node.basis = Basis(horizontal,direction,horizontal.cross(direction)).orthonormalized()

func _label(parent: Node3D, value: String, at: Vector3, height: float = 0.012, color: Color = Color(0.74,0.81,0.82)) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = 40
	label.pixel_size = height/40.0
	label.position = at
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(label)
	return label

func _build_shell() -> void:
	# A low, continuous coaming creates a convincing flight deck while leaving the horizon open.
	_box(self,Vector3(2.72,0.53,0.27),Vector3(0,-0.60,-1.02),shell)
	_box(self,Vector3(2.8,0.072,0.38),Vector3(0,-0.294,-1.09),rubber)
	_box(self,Vector3(2.68,0.018,0.015),Vector3(0,-0.334,-0.883),trim_material)
	_box(self,Vector3(2.7,0.10,0.13),Vector3(0,-0.89,-0.95),black)
	# Sidewalls, ledges, rivets and angled outer window pillars.
	for side: float in [-1.0,1.0]:
		_box(self,Vector3(0.16,0.86,1.4),Vector3(side*1.22,-0.79,-0.38),shell)
		_box(self,Vector3(0.31,0.065,1.14),Vector3(side*1.15,-0.43,-0.40),rubber)
		if airframe == "f35":
			_beam(Vector3(side*1.17,-0.27,-1.10),Vector3(side*0.94,0.08,-0.89),0.032,0.038,black)
		else:
			_beam(Vector3(side*1.17,-0.27,-1.10),Vector3(side*0.90,0.76,-1.27),0.075,0.10,trim_material)
			_beam(Vector3(side*0.90,0.76,-1.27),Vector3(side*0.54,0.89,-0.25),0.07,0.09,black)
		for row: int in 6:
			_cylinder(self,0.009,0.005,Vector3(side*1.16,-0.37-float(row)*0.065,-0.865),metal,Vector3(PI/2,0,0))
	if airframe == "f35":
		# Fighter canopy has a clear center and a narrow arch high above the pilot.
		for i: int in 32:
			var a: float = PI*float(i)/32.0
			var b: float = PI*float(i+1)/32.0
			_beam(Vector3(cos(a)*0.94,sin(a)*0.78+0.08,-0.89),Vector3(cos(b)*0.94,sin(b)*0.78+0.08,-0.89),0.032,0.037,black)
	else:
		var center_x: float = 0.67 if airframe != "b2" else 0.58
		_beam(Vector3(center_x,-0.29,-1.20),Vector3(center_x+0.07 if airframe != "b2" else 0.28,0.87,-1.41),0.047 if airframe != "b2" else 0.073,0.072,trim_material)
		_box(self,Vector3(2.1,0.12,0.12),Vector3(0,0.79,-1.20),shell)
		_build_overhead()
	# Windshield demist vents and stitching on the glare shield.
	for i: int in 19:
		_box(self,Vector3(0.048,0.006,0.057),Vector3(-1.17+i*0.13,-0.256,-1.14),black)
	for i: int in 45:
		_box(self,Vector3(0.024,0.002,0.003),Vector3(-1.27+i*0.058,-0.257,-0.955),trim_material)

func _transport_panels() -> void:
	var glass: bool = airframe == "a380"
	var b2: bool = airframe == "b2"
	var y: float = -0.555
	var sizes := Vector2(0.38,0.345)
	if glass: sizes = Vector2(0.40,0.345)
	if b2:
		_screen(Vector3(-0.49,y,-0.862),Vector2(0.91,0.345),"dual_flight")
		_screen(Vector3(0.31,y,-0.862),Vector2(0.58,0.345),"engine")
		_label(self,"FLIGHT / NAVIGATION",Vector3(-0.49,-0.753,-0.854),0.014)
		_label(self,"ENGINE / SYSTEMS",Vector3(0.31,-0.753,-0.854),0.014)
		_box(self,Vector3(0.29,0.30,0.027),Vector3(0.93,y,-0.862),black)
		_label(self,"MISSION\n\nFLIGHT DECK\n\nTRAINING",Vector3(0.93,y,-0.84),0.017,Color(0.42,0.8,0.64))
	else:
		_screen(Vector3(-0.58,y,-0.862),sizes,"pfd")
		_screen(Vector3(-0.135,y,-0.862),sizes,"nav")
		_screen(Vector3(0.31,y,-0.862),sizes,"engine")
		_screen(Vector3(0.90,y,-0.862),sizes,"pfd")
		_label(self,"PRIMARY FLIGHT",Vector3(-0.58,-0.753,-0.854),0.014)
		_label(self,"NAVIGATION",Vector3(-0.135,-0.753,-0.854),0.014)
		_label(self,"ENGINE / SYSTEMS",Vector3(0.31,-0.753,-0.854),0.014)
		_label(self,"FLIGHT DISPLAY",Vector3(0.90,-0.753,-0.854),0.014)
	# Raised autopilot control strip with illuminated settings and tactile knobs.
	_box(self,Vector3(1.8,0.078,0.06),Vector3(-0.05,-0.342,-0.826),trim_material)
	var labels: Array[String] = ["SPD / MACH","HDG / TRK","ALTITUDE","V / S"]
	var readouts: Array[String] = ["MAN","NAV","-----","MAN"]
	for i: int in 4:
		var x: float = -0.69+float(i)*0.375
		_box(self,Vector3(0.18,0.028,0.006),Vector3(x,-0.337,-0.79),black)
		_label(self,readouts[i],Vector3(x,-0.333,-0.784),0.021,Color(0.49,1,0.69))
		_label(self,labels[i],Vector3(x,-0.364,-0.786),0.009)
		_knob(Vector3(x+0.126,-0.334,-0.784),0.019)
	_label(self,"FLIGHT CONTROL UNIT" if glass else ("MISSION FLIGHT CONTROL" if b2 else "MODE CONTROL PANEL"),Vector3(0.03,-0.312,-0.882),0.010)
	# End panel switches and warning annunciators.
	for i: int in 3:
		var x: float = -1.01+float(i)*0.062
		_box(self,Vector3(0.049,0.038,0.02),Vector3(x,-0.362,-0.84),black)
		_label(self,["FIRE","WARN","CAUT"][i],Vector3(x,-0.36,-0.827),0.007,Color(0.69,0.36,0.22))
	_label(self,str(profile.get("name","AIRCRAFT")),Vector3(-0.52,-0.815,-0.856),0.017,lettering)
	_label(self,"CC / FLIGHT DECK",Vector3(0.42,-0.815,-0.856),0.01,Color(0.4,0.52,0.57))

func _fighter_panels() -> void:
	_screen(Vector3(0,-0.56,-0.856),Vector2(1.29,0.43),"panorama")
	_label(self,"PANORAMIC FLIGHT DISPLAY",Vector3(0,-0.81,-0.85),0.012)
	for side: float in [-1,1]:
		_box(self,Vector3(0.18,0.40,0.03),Vector3(side*0.78,-0.58,-0.846),black)
		for i: int in 5:
			_knob(Vector3(side*0.78,-0.4+i*-0.074,-0.822),0.018)
	_label(self,"MASTER ARM\nSAFE",Vector3(-0.96,-0.52,-0.84),0.017,Color(0.5,0.86,0.58))
	_label(self,"F-35\nLIGHTNING II",Vector3(0.99,-0.52,-0.84),0.02)
	_box(self,Vector3(0.41,0.038,0.11),Vector3(0,-0.316,-0.875),black)
	_label(self,"HUD / FLIGHT REFERENCE",Vector3(0,-0.313,-0.811),0.009,Color(0.46,0.76,0.58))

func _screen(at: Vector3, dimensions: Vector2, mode: String) -> void:
	_box(self,Vector3(dimensions.x+0.036,dimensions.y+0.037,0.035),at,black)
	_box(self,Vector3(dimensions.x+0.046,dimensions.y+0.047,0.008),at-Vector3(0,0,0.020),metal)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1638,650) if mode == "panorama" else Vector2i(768,768)
	if mode == "dual_flight": viewport.size = Vector2i(1536,768)
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.gui_disable_input = true
	add_child(viewport)
	var ui := Display.new()
	ui.size = Vector2(viewport.size)
	ui.display_mode = mode
	ui.aircraft_name = str(profile.get("short","737"))
	ui.engine_count = int(profile.get("engines",2))
	ui.set_navigation(navigation_kind,navigation_checkpoint)
	viewport.add_child(ui)
	displays.append(ui)
	var face := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	face.mesh = mesh
	face.position = at+Vector3(0,0,0.019)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	face.material_override = material
	add_child(face)
	# Screen keys and captive fasteners live on the bezel, never over the image.
	for side: float in [-1,1]:
		for i: int in 4:
			_box(self,Vector3(0.009,0.021,0.009),at+Vector3(side*(dimensions.x*0.5+0.010),dimensions.y*(0.30-float(i)*0.20),0.020),trim_material)
	for side_x: float in [-1,1]:
		for side_y: float in [-1,1]:
			_cylinder(self,0.0035,0.003,at+Vector3(side_x*(dimensions.x*0.5+0.012),side_y*(dimensions.y*0.5+0.012),0.020),metal,Vector3(PI/2,0,0))

func _knob(at: Vector3, radius: float) -> void:
	_cylinder(self,radius,0.024,at,black,Vector3(PI/2,0,0))
	_cylinder(self,radius*0.76,0.006,at+Vector3(0,0,0.015),trim_material,Vector3(PI/2,0,0))
	_box(self,Vector3(0.002,0.010,0.002),at+Vector3(0,radius*0.38,0.020),metal)

func _build_controls() -> void:
	pilot_control = Node3D.new()
	add_child(pilot_control)
	if control_is_stick:
		pilot_control.position = Vector3(-0.81 if airframe == "a380" else 0.65,-0.64,-0.54)
		_cylinder(pilot_control,0.053,0.07,Vector3.ZERO,rubber)
		_cylinder(pilot_control,0.021,0.19,Vector3(0,0.105,0),black,Vector3(-0.18,0,0))
		_box(pilot_control,Vector3(0.055,0.064,0.071),Vector3(0,0.218,-0.020),rubber,Vector3(-0.18,0,0))
		_cylinder(pilot_control,0.009,0.005,Vector3(-0.014,0.241,0.009),_material(Color(0.57,0.16,0.08)),Vector3(PI/2,0,0))
		_label(self,"SIDE STICK" if airframe == "a380" else "FLIGHT CONTROL",Vector3(pilot_control.position.x,-0.76,-0.45),0.009)
	else:
		pilot_control.position = Vector3(-0.46,-0.71,-0.54)
		_cylinder(pilot_control,0.035,0.28,Vector3(0,-0.09,0),metal,Vector3(-0.30,0,0))
		_box(pilot_control,Vector3(0.12,0.075,0.06),Vector3(0,0.074,0.008),black)
		_box(pilot_control,Vector3(0.31,0.031,0.04),Vector3(0,0.089,0.012),black)
		for side: float in [-1,1]:
			_box(pilot_control,Vector3(0.044,0.127,0.048),Vector3(side*0.146,0.139,0.012),rubber,Vector3(0,0,side*-0.22))
			_cylinder(pilot_control,0.01,0.006,Vector3(side*0.133,0.186,0.04),metal,Vector3(PI/2,0,0))
		_label(pilot_control,"CC",Vector3(0,0.075,0.041),0.014)
	# Pedals below the pilot and a stitched seat edge at each side.
	for side: float in [-1,1]:
		_box(self,Vector3(0.12,0.06,0.18),Vector3(-0.46+side*0.12,-1.13,-0.65),metal,Vector3(0.24,0,0))
		_box(self,Vector3(0.24,0.15,0.54),Vector3(side*0.90,-1.14,0.04),rubber)

func _build_console() -> void:
	var x: float = -0.91 if airframe == "f35" else 0.67
	_box(self,Vector3(0.34,0.19,0.63),Vector3(x,-0.80,-0.57),shell)
	_box(self,Vector3(0.31,0.026,0.54),Vector3(x,-0.691,-0.57),trim_material)
	var count: int = int(profile.get("engines",2))
	var lever_spacing: float = 0.047 if count > 2 else 0.079
	for i: int in count:
		var lx: float = (float(i)-float(count-1)*0.5)*lever_spacing
		_box(self,Vector3(0.017,0.004,0.21),Vector3(x+lx,-0.674,-0.55),black)
		var lever := Node3D.new()
		lever.position = Vector3(x+lx,-0.68,-0.55)
		add_child(lever)
		throttles.append(lever)
		_cylinder(lever,0.009,0.16,Vector3(0,0.075,0),metal)
		_box(lever,Vector3(0.039,0.034,0.063),Vector3(0,0.159,0),black)
		_label(lever,str(i+1),Vector3(0,0.163,0.033),0.011)
	_label(self,"THRUST",Vector3(x,-0.679,-0.275),0.011)
	# Tactile checklist keyboard on the far end of the center pedestal.
	for row: int in 4:
		for col: int in 5:
			_box(self,Vector3(0.029,0.013,0.026),Vector3(x+(col-2)*0.048,-0.677,-0.71-row*0.035),black)
	# Distinct landing gear handle, with white wheel-shaped grip.
	var gear_x: float = 1.01 if airframe == "f35" else 0.62
	_box(self,Vector3(0.056,0.16,0.021),Vector3(gear_x,-0.62,-0.85),black)
	_box(self,Vector3(0.012,0.073,0.04),Vector3(gear_x,-0.65,-0.82),metal)
	_cylinder(self,0.021,0.026,Vector3(gear_x,-0.69,-0.792),_material(Color(0.77,0.79,0.72)),Vector3(0,0,PI/2))
	_label(self,"GEAR",Vector3(gear_x,-0.53,-0.824),0.012)

func _build_overhead() -> void:
	_box(self,Vector3(0.70,0.24,0.042),Vector3(0.25,0.57,-0.82),shell,Vector3(0.25,0,0))
	var names: Array[String] = ["ELECTRICAL","FUEL","LIGHTS","AIR / PRESS"]
	for col: int in 4:
		var x: float = -0.02+col*0.18
		_label(self,names[col],Vector3(x,0.626,-0.788),0.01)
		for row: int in 2:
			_box(self,Vector3(0.12,0.003,0.002),Vector3(x,0.603-row*0.074,-0.794),trim_material)
			_cylinder(self,0.007,0.024,Vector3(x,0.574-row*0.069,-0.771),metal,Vector3(-0.6,0,0))
			_label(self,"ON",Vector3(x+0.033,0.576-row*0.07,-0.778),0.008)

func _build_lighting() -> void:
	var key := OmniLight3D.new()
	key.position = Vector3(-0.25,0.24,-0.35)
	key.light_color = Color(0.73,0.85,1.0)
	key.light_energy = 1.0
	key.omni_range = 2.4
	key.shadow_enabled = false
	add_child(key)
	var bounce := OmniLight3D.new()
	bounce.position = Vector3(0.40,-0.45,-0.47)
	bounce.light_color = Color(0.28,0.69,0.87)
	bounce.light_energy = 0.35
	bounce.omni_range = 1.0
	add_child(bounce)
