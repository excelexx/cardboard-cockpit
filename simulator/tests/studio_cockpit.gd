extends SceneTree
## Standalone look harness for the fighter interior. Native GPU, no world load,
## so a look-and-fix round costs seconds instead of a full mission boot.
##
## Godot --path simulator --windowed --resolution 1600x1000 --script tests/studio_cockpit.gd
##   optional: -- <view> <view> ... | flat | nosun
##
## Sky, sun and tonemap are copied from scenes/san_francisco_world.gd so what the
## studio shows is what the golden-hour mission shows.
const World := preload("res://scenes/san_francisco_world.gd")
const Catalog := preload("res://data/aircraft.gd")
const Cockpit := preload("res://scenes/cockpit.gd")
const Dynamics := preload("res://systems/flight_dynamics.gd")

var camera: Camera3D
var cockpit: DetailedCockpit
var flight: FlightDynamics
var environment: Environment
var sun: DirectionalLight3D

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("STUDIO cockpit: native GPU required")
		quit(2)
		return
	var wanted := OS.get_cmdline_user_args()
	var folder := ProjectSettings.globalize_path("res://../build/cockpit")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage := Node3D.new()
	root.add_child(stage)
	_build_sky(stage)
	camera = Camera3D.new()
	camera.fov = 76.0            # the game's cockpit field of view
	camera.near = 0.02
	camera.far = 3000.0
	camera.current = true
	stage.add_child(camera)
	# A horizon to sit against: the interior has to separate from something.
	_build_ground(stage)
	var began := Time.get_ticks_msec()
	cockpit = Cockpit.new()
	stage.add_child(cockpit)
	cockpit.build(Catalog.PROFILE)
	cockpit.set_presentation_visible(true)
	var build_ms := Time.get_ticks_msec() - began
	flight = Dynamics.new()
	flight.reset(Catalog.PROFILE)
	flight.spawn_airborne(Vector3(0, 620, 0), 240.0)
	flight.throttle = 0.72
	flight.gear = false
	flight.pitch = 0.035
	flight.roll = -0.12
	cockpit.set_navigation("sf", 4)
	cockpit.set_tactical({"gun": true, "missiles": false, "tracking": true, "target": "GOOSE 04", "range": 1180.0})
	for i in 6:
		cockpit.update_instruments(flight, Vector3(0.22, -0.16, 0.0), 0.2)
		await process_frame
	if "flat" in wanted:
		# Strip every directional contribution to see the baked occlusion alone.
		sun.light_energy = 0.0
		if cockpit.fighter != null:
			cockpit.fighter.key_spot.light_energy = 0.0
			cockpit.fighter.sky_fill.light_energy = 2.4
	if "key" in wanted:
		# Cockpit key only: this is the view that proves the shadow rig works.
		sun.light_energy = 0.0
		if cockpit.fighter != null: cockpit.fighter.sky_fill.light_energy = 0.12
	if "nosun" in wanted:
		sun.light_energy = 0.35
	var views := {
		"eye": [Vector3.ZERO, Vector2(0.0, 0.0), 76.0],
		"eye_down": [Vector3.ZERO, Vector2(0.0, -20.0), 76.0],
		"left": [Vector3.ZERO, Vector2(50.0, -28.0), 76.0],
		"right": [Vector3.ZERO, Vector2(-50.0, -28.0), 76.0],
		"clay": [Vector3(1.55, 0.95, 1.35), Vector2(-999.0, 0.0), 42.0],
	}
	var fighter: FighterCockpit = cockpit.fighter
	var cost: Dictionary = {}
	var voids: Dictionary = {}
	for name: String in views:
		if not wanted.is_empty() and not _only_views(wanted).is_empty() and name not in wanted: continue
		var entry: Array = views[name]
		var look: Vector2 = entry[1]
		camera.fov = float(entry[2])
		if look.x < -900.0:
			# External three-quarter clay: hide the glass so the tub is readable.
			if fighter != null and is_instance_valid(fighter.canopy) and is_instance_valid(fighter.canopy.glass_mesh):
				fighter.canopy.glass_mesh.visible = false
			camera.position = entry[0]
			camera.look_at(Vector3(0.0, -0.42, -0.45), Vector3.UP)
			cockpit.basis = Basis.IDENTITY
		else:
			if fighter != null and is_instance_valid(fighter.canopy) and is_instance_valid(fighter.canopy.glass_mesh):
				fighter.canopy.glass_mesh.visible = true
			var basis := Basis.from_euler(Vector3(deg_to_rad(look.y), deg_to_rad(look.x), 0.0))
			camera.position = Vector3.ZERO
			camera.basis = basis
			# The interior stays welded to the airframe and only the head turns.
			# In the game cockpit_frame is a CHILD of the camera and carries
			# look_basis.inverse(), which cancels the camera's own rotation. Here
			# the interior is a sibling at the origin, so airframe-fixed simply
			# means identity: counter-rotating it as well turned a 50 degree look
			# into a 100 degree one and framed the tub from outside its own walls.
			cockpit.basis = Basis.IDENTITY
		cockpit.set_sun(sun.global_basis.z, 1.0)
		for i in 4:
			cockpit.update_instruments(flight, Vector3(0.22, -0.16, 0.0), 0.05)
			await process_frame
		await RenderingServer.frame_post_draw
		var shot: Image = root.get_texture().get_image()
		shot.save_png(folder + "/studio_" + name + ".png")
		var tally: Vector2i = _void_fraction(shot, _screen_rect(fighter, shot))
		var void_fraction: float = float(tally.x) / float(maxi(tally.y, 1))
		voids[name] = void_fraction
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		cost[name] = draws
		print("STUDIO view ", name, " draws=", draws,
			" prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			" void=", "%.2f%%" % (void_fraction * 100.0), " (", tally.x, " black of ", tally.y, " sampled)")
	# ---------------------------------------------------------- sight lines
	# The two pieces of cockpit that can cost the player a goose, measured rather
	# than eyeballed. Numbers to beat are the bow this build replaced (legs at
	# 29.8 deg off boresight, 3.8 deg of opaque bar, inner edge at 27.9) and a
	# 38 deg half frame for the hands.
	var bow: Dictionary = fighter.bow_metrics() if fighter != null else {}
	if not bow.is_empty():
		print("STUDIO bow leg=%.1f deg  bar=%.2f deg  inner_edge=%.1f deg  crown=%.1f deg up" % [
			bow.leg_deg, bow.width_deg, bow.inner_deg, bow.crown_deg])
	var grips: Array = []
	for level: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		grips.append(fighter.grip_angles(level) if fighter != null else {})
	if fighter != null:
		var report := PackedStringArray()
		for item: Dictionary in grips: report.append("%.1f" % float(item.throttle_deg))
		print("STUDIO throttle grip below boresight: ", ", ".join(report),
			" deg (idle first)   stick hand %.1f deg" % float(grips[0].stick_deg))
	# The standby flight display is the only live backup instrument in the tub and
	# the centre pedestal stands directly between it and the eye, so its clearance
	# is measured too. Negative means the pedestal is eating the face again.
	var standby: Dictionary = fighter.standby_sight() if fighter != null else {}
	var faults: Array = []
	if fighter != null and fighter.mesh != null: faults = fighter.mesh.placard_faults
	if not standby.is_empty():
		print("STUDIO standby sight line clears the pedestal by %.0f mm   back-facing legends: %d" % [
			float(standby.clear_m) * 1000.0, faults.size()])
	for fault: String in faults: print("STUDIO   back-facing legend: ", fault)
	var triangles: int = fighter.triangles if fighter != null else 0
	# Godot counts the Forward+ depth prepass and the cockpit key's shadow pass as
	# draw calls, so the interior's own mesh count is roughly a third of this.
	var worst: int = 0
	for name: String in cost: worst = maxi(worst, int(cost[name]))
	print("STUDIO cockpit build_ms=", build_ms, " triangles=", triangles, " meshes=", _mesh_count(cockpit),
		" worst_draws=", worst, " fps=", Engine.get_frames_per_second(), " size=", root.size)
	var failures: Array[String] = []
	if triangles > 60000: failures.append("triangles %d over 60k" % triangles)
	if _mesh_count(cockpit) > 40: failures.append("%d mesh instances over budget" % _mesh_count(cockpit))
	if build_ms > 2500: failures.append("build took %d ms" % build_ms)
	# PLAYABILITY GUARD. Geese are tracked and shot through the middle of this
	# frame; the bow may not creep back into it and the hands may not fall out.
	if not bow.is_empty():
		if float(bow.inner_deg) < 27.5:
			failures.append("bow leg inner edge %.1f deg, inside the 27.5 deg guard" % bow.inner_deg)
		# 3.8, not 4.6. The guard used to be set wide enough to admit the bow this
		# build shipped (4.24 deg) instead of the one it replaced (3.8 at the same
		# inner edge), which let a 12 percent regression in sky lost per leg pass
		# as a PASS. The number in the comment above is now the number enforced.
		if float(bow.width_deg) > 3.8:
			failures.append("bow bar %.2f deg wide, over the 3.8 deg guard" % bow.width_deg)
	for i in range(grips.size()):
		var item: Dictionary = grips[i]
		if item.is_empty(): continue
		if float(item.throttle_deg) > 34.0:
			failures.append("throttle grip %.1f deg below boresight at throttle %.2f" % [
				item.throttle_deg, float(i) / float(maxi(grips.size() - 1, 1))])
	if not grips.is_empty() and not grips[0].is_empty() and float(grips[0].stick_deg) > 34.0:
		failures.append("stick hand %.1f deg below boresight" % grips[0].stick_deg)
	# Every corner of the standby face and its placard has to be reachable from
	# the eye over the top of the centre pedestal.
	if not standby.is_empty() and float(standby.clear_m) < 0.010:
		failures.append("pedestal cuts the standby display sight line by %.0f mm" % [
			-float(standby.clear_m) * 1000.0])
	# A legend whose glyph normal faces into the panel it is painted on renders
	# nothing at all, and costs triangles doing it.
	if not faults.is_empty():
		failures.append("%d back-facing legends (first: %s)" % [faults.size(), faults[0]])
	# Nothing in this interior may render as a flat black cut-out: that is the
	# exact 2D look the package exists to kill. The four pilot views are the ones
	# that gate: `clay` is an external diagnostic that deliberately frames the
	# UNLIT OUTSIDE of the tub - the back of the sidewalls, the underside of the
	# floor, the rear bulkhead - which is a surface no player can ever be looking
	# at and which has no business being lit. Its number is printed so a real
	# regression inside the tub still shows up there, but it cannot fail the run.
	for name: String in voids:
		if name == "clay": continue
		if float(voids[name]) > 0.020:
			failures.append("view %s is %.1f%% pure black" % [name, float(voids[name]) * 100.0])
	print("STUDIO ", "PASS" if failures.is_empty() else "FAIL ", ", ".join(failures))
	quit(0 if failures.is_empty() else 1)

## Fraction of the frame that came out at (near) zero in every channel. Sky,
## ground and lit interior all sit well above this; only an unlit surface does
## not.
##
## `skip` is the panoramic display's glass, as a convex quad in the same 320x200
## space, and those pixels are not counted. The PCD's artwork is a black-backed
## instrument: its unlit background is exactly what it should be, and letting
## six percent of black screen sit in this number drowned out the defects the
## metric exists to catch - a canopy bow whose inner rim rendered at literally
## 0,0,0 against the sky, and a hood whose top slope did the same.
##
## The quad itself rather than its bounding box, because at a 50 degree head
## turn the display's box is nearly a quarter of the frame and would have hidden
## a whole lower corner of the tub along with it.
func _void_fraction(shot: Image, skip: PackedVector2Array) -> Vector2i:
	var small: Image = shot.duplicate()
	small.resize(320, 200, Image.INTERPOLATE_BILINEAR)
	var black: int = 0
	var counted: int = 0
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			if skip.size() == 4 and _inside(skip, Vector2(float(x), float(y))): continue
			counted += 1
			var pixel: Color = small.get_pixel(x, y)
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.012: black += 1
	return Vector2i(black, counted)

func _inside(quad: PackedVector2Array, point: Vector2) -> bool:
	var sign_seen: float = 0.0
	for i in range(4):
		var a: Vector2 = quad[i]
		var edge: Vector2 = quad[(i + 1) % 4] - a
		var side: float = edge.cross(point - a)
		if absf(side) < 1e-6: continue
		if sign_seen == 0.0: sign_seen = signf(side)
		elif signf(side) != sign_seen: return false
	return true

## The panoramic display's glass in the 320x200 space `_void_fraction` works in,
## pushed out a pixel and a half so the bezel's inner wall cannot creep back in.
##
## Projected by hand rather than with unproject_position: on this machine the
## window reports root.size 3024 wide while the frame that actually comes back
## from get_texture() is 2739, so viewport pixels and image pixels are not the
## same thing and the mask landed ten percent off - excluding a slab of lit panel
## and none of the black screen it was aimed at. Camera3D keeps its height by
## default, so `fov` is the vertical angle and the shot's own aspect gives the
## horizontal one.
func _screen_rect(fighter: FighterCockpit, shot: Image) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if fighter == null or camera == null: return empty
	var view: Transform3D = camera.global_transform.affine_inverse()
	var tan_half: float = tan(deg_to_rad(camera.fov) * 0.5)
	var aspect: float = float(shot.get_width()) / float(maxi(shot.get_height(), 1))
	var quad := PackedVector2Array()
	var centroid := Vector2.ZERO
	for corner: Vector3 in fighter.screen_corners():
		var local: Vector3 = view * (fighter.global_transform * corner)
		if local.z > -0.01: return empty
		var point := Vector2(
			(0.5 + 0.5 * (local.x / -local.z) / (tan_half * aspect)) * 320.0,
			(0.5 - 0.5 * (local.y / -local.z) / tan_half) * 200.0)
		quad.append(point)
		centroid += point
	centroid /= 4.0
	for i in range(4): quad[i] = quad[i] + (quad[i] - centroid).normalized() * 1.5
	return quad

func _mesh_count(node: Node) -> int:
	var total := 0
	for item: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if item is GeometryInstance3D and item.visible: total += 1
	return total

func _only_views(wanted: PackedStringArray) -> Array:
	var out: Array = []
	for item: String in wanted:
		if item not in ["flat", "nosun", "key"]: out.append(item)
	return out

func _build_sky(stage: Node3D) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/look/sunset_sky.gdshader")
	material.set_shader_parameter("panorama", load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(World.SKY_YAW_DEGREES), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = World.EXPOSURE
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.fog_enabled = true
	env.fog_density = 0.000026
	env.fog_light_color = Color(0.36, 0.41, 0.50)
	env.fog_sun_scatter = 0.10
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	environment = env
	var holder := WorldEnvironment.new()
	holder.environment = env
	stage.add_child(holder)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10.0, -110.0, 0.0)
	sun.light_color = Color(1.0, 0.66, 0.38)
	sun.light_energy = World.SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1400.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.04
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	stage.add_child(sun)

func _build_ground(stage: Node3D) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60000, 60000)
	plane.mesh = mesh
	plane.position = Vector3(0, -620, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.085, 0.105, 0.095)
	material.roughness = 0.92
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(plane)
