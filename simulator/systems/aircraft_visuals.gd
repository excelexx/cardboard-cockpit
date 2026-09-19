extends Node3D
class_name AircraftVisuals
## Non-destructive presentation for the normalized, nose--Z aircraft assets.
## Keep this helper beside the model. Effects are attached to the model so that
## aircraft-specific ground-clearance offsets also apply to every light.

const GEAR_TRAVEL_SECONDS := 2.0
var gear_progress: float = 1.0 # 0 = stowed, 1 = fully extended; command remains in FlightDynamics.
var model_bounds := AABB()
var _model: Node3D
var _profile: Dictionary
var _gear: Node3D
var _gear_groups: Array[Dictionary] = []
var _surfaces: Array[Dictionary] = []
var _mesh_nodes: Array[MeshInstance3D] = []
var _vertices := PackedVector3Array()
var _effects: Node3D
var _strobes: Array[MeshInstance3D] = []
var _beacons: Array[MeshInstance3D] = []
var _engine_glow: MeshInstance3D
var _engine_material: StandardMaterial3D
var _clock := 0.0
var _control := Vector3.ZERO
var _origin_removed := Vector3.ZERO
var bay_doors: Array[Dictionary] = []
var bay_amount := 0.0
var bay_timer := 0.0
var bay_side := -1.0

func initialize(model: Node3D, profile: Dictionary) -> void:
	# Reinitializing on an existing aircraft restores every captured transform.
	reset()
	if is_instance_valid(_effects):
		_effects.get_parent().remove_child(_effects)
		_effects.queue_free()
	_model = model
	_profile = profile
	_gear_groups.clear()
	_surfaces.clear()
	_mesh_nodes.clear()
	_vertices.clear()
	model_bounds = AABB()
	_strobes.clear()
	_beacons.clear()
	_engine_glow = null
	_engine_material = null
	_gear = model.get_node_or_null("Airframe/LandingGear")
	_collect_meshes(model)
	var first := true
	for mesh_node in _mesh_nodes:
		var mesh_to_model := _relative_transform(mesh_node)
		var bounds: AABB = mesh_to_model * mesh_node.get_aabb()
		model_bounds = bounds if first else model_bounds.merge(bounds)
		first = false
		if _gear != null and _gear.is_ancestor_of(mesh_node):
			continue
		for surface_index in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point in points:
				_vertices.append(mesh_to_model * point)
	var metadata_path := "res://assets/aircraft/%s/manifest.json" % str(profile.get("id", ""))
	_origin_removed = Vector3.ZERO
	if FileAccess.file_exists(metadata_path):
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		var origin: Array = metadata.get("source_origin_removed", [0.0, 0.0, 0.0])
		_origin_removed = Vector3(origin[0], origin[1], origin[2])
	_effects = Node3D.new()
	_effects.name = "FlightPresentation"
	_model.add_child(_effects)
	_build_gear_groups()
	_build_lights()
	_build_control_surfaces()
	_build_weapon_bays()
	_build_engine_glow()
	reset()

func update_visuals(delta: float, flight: FlightDynamics, controls: Vector3) -> void:
	if not is_instance_valid(_model):
		return
	var dt := maxf(delta, 0.0)
	_clock += dt
	bay_timer = maxf(0,bay_timer-dt)
	bay_amount = move_toward(bay_amount,1.0 if bay_timer>0.2 else 0.0,dt*5)
	for door: Dictionary in bay_doors:
		var amount: float = bay_amount if door.side==bay_side else 0.0
		if door.inner: amount = clampf((amount-0.3)/0.7,0,1)
		_apply_rotation(door,door.angle*smoothstep(0,1,amount))
	gear_progress = move_toward(gear_progress, 1.0 if flight.gear else 0.0, dt / GEAR_TRAVEL_SECONDS)
	_apply_gear()
	_control = _control.lerp(controls.clamp(Vector3(-1, -1, -1), Vector3.ONE), 1.0 - exp(-dt * 9.0))
	for surface in _surfaces:
		_apply_rotation(surface, deg_to_rad(_control.dot(surface.response)))
	# A paired white flash and a slower red beacon remain visible in daylight.
	var strobe_phase := fposmod(_clock, 1.25)
	var strobe_on := strobe_phase < 0.055 or (strobe_phase > 0.13 and strobe_phase < 0.185)
	for lamp in _strobes:
		lamp.visible = strobe_on
	var beacon_phase := fposmod(_clock, 1.6)
	for index in _beacons.size():
		_beacons[index].visible = fposmod(beacon_phase + index * 0.8, 1.6) < 0.16
	if _engine_glow != null:
		var power := clampf((flight.engine - 0.25) / 0.75, 0.0, 1.0)
		_engine_glow.visible = power > 0.005
		_engine_material.emission_energy_multiplier = power * (1.5 + 0.12 * sin(_clock * 24.0))

func reset() -> void:
	gear_progress = 1.0
	bay_amount = 0; bay_timer = 0
	for door: Dictionary in bay_doors:
		if is_instance_valid(door.node): door.node.transform = door.original
	_clock = 0.0
	_control = Vector3.ZERO
	for group in _gear_groups:
		for record in group.parts:
			if is_instance_valid(record.node):
				record.node.transform = record.original
	for surface in _surfaces:
		if is_instance_valid(surface.node):
			surface.node.transform = surface.original
	if is_instance_valid(_gear):
		_gear.visible = true
	for lamp in _strobes:
		if is_instance_valid(lamp):
			lamp.visible = false
	for lamp in _beacons:
		if is_instance_valid(lamp):
			lamp.visible = false
	if is_instance_valid(_engine_glow):
		_engine_glow.visible = false

func is_gear_moving() -> bool:
	return gear_progress > 0.001 and gear_progress < 0.999

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_mesh_nodes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

func _relative_transform(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != _model and cursor is Node3D:
		result = cursor.transform * result
		cursor = cursor.get_parent()
	return result

func _record(node: Node3D) -> Dictionary:
	return {"node": node, "original": node.transform, "parent_to_model": _relative_transform(node.get_parent())}

func _build_gear_groups() -> void:
	if _gear == null:
		return
	var parts: Array[MeshInstance3D] = []
	var wheel_clusters: Array[Array] = []
	var join_distance := maxf(1.15, model_bounds.size.z * 0.028)
	for node in _mesh_nodes:
		if not _gear.is_ancestor_of(node):
			continue
		parts.append(node)
		var mesh_name := str(node.name).to_lower()
		if "wheel" not in mesh_name and "tyre" not in mesh_name and "tire" not in mesh_name:
			continue
		var center: Vector3 = (_relative_transform(node) * node.get_aabb()).get_center()
		var joined: Array = [center]
		# Connected wheel sets preserve an entire bogie, including multi-axle trucks.
		for index in range(wheel_clusters.size() - 1, -1, -1):
			var touches := false
			for other: Vector3 in wheel_clusters[index]:
				if Vector2(center.x, center.z).distance_to(Vector2(other.x, other.z)) < join_distance:
					touches = true
					break
			if touches:
				joined.append_array(wheel_clusters[index])
				wheel_clusters.remove_at(index)
		wheel_clusters.append(joined)
	if wheel_clusters.is_empty():
		return # Unknown assets retain their intact, extended undercarriage.
	for cluster in wheel_clusters:
		var center := Vector3.ZERO
		for wheel: Vector3 in cluster:
			center += wheel
		center /= float(cluster.size())
		_gear_groups.append({"center": center, "parts": [], "bounds": AABB(), "has_bounds": false})
	for node in parts:
		var bounds: AABB = _relative_transform(node) * node.get_aabb()
		var center := bounds.get_center()
		var best := 0
		var distance := INF
		for index in _gear_groups.size():
			var other: Vector3 = _gear_groups[index].center
			var current := Vector2(center.x, center.z).distance_squared_to(Vector2(other.x, other.z))
			if current < distance:
				distance = current
				best = index
		var group: Dictionary = _gear_groups[best]
		group.parts.append(_record(node))
		group.bounds = group.bounds.merge(bounds) if group.has_bounds else bounds
		group.has_bounds = true
	for group in _gear_groups:
		var bounds: AABB = group.bounds
		var center: Vector3 = group.center
		group.pivot = Vector3(center.x, bounds.end.y, center.z)
		var nose := absf(center.x) < model_bounds.size.x * 0.035
		group.axis = Vector3.RIGHT if nose else Vector3.BACK
		group.angle = deg_to_rad(-85.0 if nose else -signf(center.x) * 83.0)
		# A small final rise seats folded assemblies inside their existing bays.
		group.rise = minf(bounds.size.y * 0.24, 0.7)

func _apply_gear() -> void:
	if _gear == null or _gear_groups.is_empty():
		return
	var t := smoothstep(0.0, 1.0, 1.0 - gear_progress)
	_gear.visible = gear_progress > 0.001
	for group in _gear_groups:
		var rotation_basis := Basis(group.axis, group.angle * t)
		var pivot: Vector3 = group.pivot
		var motion := Transform3D(rotation_basis, pivot - rotation_basis * pivot + Vector3.UP * group.rise * t)
		for record in group.parts:
			var parent: Transform3D = record.parent_to_model
			record.node.transform = parent.affine_inverse() * motion * parent * record.original

func _find_mesh(mesh_name: String) -> MeshInstance3D:
	for node in _mesh_nodes:
		if str(node.name).to_lower() == mesh_name.to_lower():
			return node
	return null

func _wingtip(side: float) -> Vector3:
	# Use actual outermost surface vertices, rather than catalog dimensions or
	# fuselage-center guesses; this also follows swept and flying-wing aircraft.
	var edge := model_bounds.end.x if side > 0 else model_bounds.position.x
	var total := Vector3.ZERO
	var count := 0
	var band := maxf(0.12, model_bounds.size.x * 0.0025)
	for point in _vertices:
		if absf(point.x - edge) <= band:
			total += point
			count += 1
	return total / float(count) if count > 0 else Vector3(edge, 0, 0)

func _body_surface(top: bool) -> Vector3:
	var station := model_bounds.position.z + model_bounds.size.z * 0.42
	var best := Vector3(0, model_bounds.get_center().y, station)
	var found := false
	var band := maxf(0.25, model_bounds.size.x * 0.015)
	for point in _vertices:
		if absf(point.x) > band or absf(point.z - station) > model_bounds.size.z * 0.04:
			continue
		if not found or (point.y > best.y if top else point.y < best.y):
			best = point
			found = true
	return best + Vector3.UP * (0.035 if top else -0.035)

func _build_lights() -> void:
	if _vertices.is_empty():
		return
	var radius := clampf(model_bounds.size.x * 0.0022, 0.075, 0.16)
	var left := _wingtip(-1.0)
	var right := _wingtip(1.0)
	# The 737 includes accurately positioned lamp housings in the original mesh.
	for entry in [["navlight", -1.0], ["rhnavlight", 1.0]]:
		var housing := _find_mesh(entry[0])
		if housing != null:
			var position: Vector3 = (_relative_transform(housing) * housing.get_aabb()).get_center()
			if entry[1] < 0:
				left = position
			else:
				right = position
	_lamp("PortNavigation", left, Color(1.0, 0.025, 0.015), radius, 3.5)
	_lamp("StarboardNavigation", right, Color(0.02, 1.0, 0.16), radius, 3.5)
	_strobes.append(_lamp("PortStrobe", left + Vector3(0, radius, radius * 2.0), Color.WHITE, radius * 1.15, 8.0))
	_strobes.append(_lamp("StarboardStrobe", right + Vector3(0, radius, radius * 2.0), Color.WHITE, radius * 1.15, 8.0))
	_beacons.append(_lamp("UpperBeacon", _body_surface(true), Color(1.0, 0.035, 0.01), radius, 5.0))
	_beacons.append(_lamp("LowerBeacon", _body_surface(false), Color(1.0, 0.035, 0.01), radius, 5.0))

func _lamp(label: String, location: Vector3, color: Color, radius: float, energy: float) -> MeshInstance3D:
	var lamp := MeshInstance3D.new()
	lamp.name = label
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 8
	shape.rings = 4
	lamp.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	lamp.material_override = material
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.position = location
	_effects.add_child(lamp)
	return lamp

func _source_point(value: Vector3) -> Vector3:
	# Source XML coordinates: X aft, Y right, Z up. Conversion centers AC3D
	# coordinates (X aft, Y up, Z left) using the manifest's original offset.
	return Vector3(value.y + _origin_removed.z, value.z - _origin_removed.y, value.x - _origin_removed.x)

func _source_axis(value: Vector3) -> Vector3:
	return Vector3(value.y, value.z, value.x).normalized()

func _surface(names: Array, pivot: Vector3, axis: Vector3, response: Vector3) -> void:
	for mesh_name: String in names:
		var node := _find_mesh(mesh_name)
		if node == null:
			continue
		var record := _record(node)
		record.pivot = _source_point(pivot)
		record.axis = _source_axis(axis)
		record.response = response
		_surfaces.append(record)

func _build_control_surfaces() -> void:
	# Pivots/axes come from each bundled FlightGear model XML, not mesh-center
	# guesses. Only separately authored surfaces move; structural wings stay fixed.
	match str(_profile.get("id", "")):
		"f35":
			_surface(["flaperonL"], Vector3(3.55, -1.79, 0.47), Vector3(-0.63, -3.06, 0.04), Vector3(-25, 0, 0))
			_surface(["flaperonR"], Vector3(3.55, 1.79, 0.47), Vector3(-0.63, 3.06, 0.04), Vector3(-25, 0, 0))
			_surface(["elevators"], Vector3(6.18, -0.87, 0.32), Vector3(0, 1.74, 0), Vector3(0, -25, 0))
			_surface(["rudderL"], Vector3(5.14, -1.30, 0.61), Vector3(0.94, -0.80, 2.22), Vector3(0, 0, 20))
			_surface(["rudderR"], Vector3(5.14, 1.30, 0.61), Vector3(0.94, 0.80, 2.22), Vector3(0, 0, 20))
		"b737":
			_surface(["lhaileron", "ailerontablh"], Vector3(11.547, -13.14, 0.44), Vector3(-0.28, 1, -0.1), Vector3(18, 0, 0))
			_surface(["rhaileron", "ailerontabrh"], Vector3(11.547, 13.14, 0.44), Vector3(0.28, 1, 0.1), Vector3(-18, 0, 0))
			_surface(["lhelevator", "lhelevatortab"], Vector3(23.74, -5, 2.275), Vector3(-1.44, 4.327, -0.807), Vector3(0, -15, 0))
			_surface(["rhelevator", "rhelevatortab"], Vector3(22.3, 0.673, 1.468), Vector3(1.44, 4.327, 0.807), Vector3(0, -15, 0))
			_surface(["rudder"], Vector3(21.422, 0, 2.23), Vector3(0.4, 0, 1), Vector3(0, 0, 25))
		"b2":
			_surface(["left_aileron"], Vector3(5.16, -14.59, 0.03), Vector3(1, -1.33, 0), Vector3(-24, 18, 0))
			_surface(["right_aileron"], Vector3(5.16, 14.55, 0.03), Vector3(1, 1.33, 0), Vector3(-24, -18, 0))

func _apply_rotation(record: Dictionary, angle: float) -> void:
	var rotation_basis := Basis(record.axis, angle)
	var pivot: Vector3 = record.pivot
	var motion := Transform3D(rotation_basis, pivot - rotation_basis * pivot)
	var parent: Transform3D = record.parent_to_model
	record.node.transform = parent.affine_inverse() * motion * parent * record.original

func _build_engine_glow() -> void:
	if str(_profile.get("id", "")) != "f35":
		return
	var bounds := AABB()
	var found := false
	for node in _mesh_nodes:
		if not str(node.name).begins_with("NozzlePetal"):
			continue
		var current: AABB = _relative_transform(node) * node.get_aabb()
		bounds = bounds.merge(current) if found else current
		found = true
	if not found:
		return
	var shape := TorusMesh.new()
	shape.inner_radius = minf(bounds.size.x, bounds.size.y) * 0.20
	shape.outer_radius = minf(bounds.size.x, bounds.size.y) * 0.245
	shape.rings = 40
	shape.ring_segments = 12
	_engine_glow = MeshInstance3D.new()
	_engine_glow.name = "EngineCoreGlow"
	_engine_glow.mesh = shape
	_engine_glow.rotation.x = PI / 2.0
	_engine_glow.position = Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z - 0.38)
	_engine_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_engine_material = StandardMaterial3D.new()
	_engine_material.albedo_color = Color(0.07, 0.025, 0.008)
	_engine_material.emission_enabled = true
	_engine_material.emission = Color(1.0, 0.21, 0.035)
	_engine_glow.material_override = _engine_material
	_effects.add_child(_engine_glow)

func open_weapon_bay(side: float) -> void:
	bay_side = -1.0 if side<0 else 1.0
	bay_timer = 1.0
func _build_weapon_bays() -> void:
	bay_doors.clear()
	for spec: Array in [
		["door bayLI",Vector3(-1.48,-0.32,-0.74),Vector3(1.82,-0.31,-0.73),110.0,-1.0,true],
		["door bayLO",Vector3(-1.94,-1.45,-0.49),Vector3(0.40,-1.44,-0.69),-100.0,-1.0,false],
		["door bayRI",Vector3(-1.48,0.32,-0.74),Vector3(1.82,0.31,-0.73),-110.0,1.0,true],
		["door bayRO",Vector3(-1.94,1.45,-0.49),Vector3(0.40,1.44,-0.69),100.0,1.0,false]]:
		var node: MeshInstance3D = _find_mesh(spec[0])
		if node==null: continue
		var record: Dictionary = _record(node)
		record.pivot = _source_point(spec[1])
		record.axis = _source_axis(spec[2]-spec[1])
		record.angle = deg_to_rad(spec[3]); record.side = spec[4]; record.inner = spec[5]
		bay_doors.append(record)
