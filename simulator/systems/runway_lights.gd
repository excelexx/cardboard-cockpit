extends MultiMeshInstance3D
## SFO 28R approach and runway lighting.
##
## One MultiMesh of unshaded additive billboards: an ALSF-2 approach system with
## a sequenced flasher ("the rabbit"), a four-box PAPI on the 3.00 degree path
## that ApproachGuidance already flies, touchdown-zone barrettes, centreline,
## edge and threshold bars. Landing runs toward -Z, so the threshold is the +Z
## end of the strip and the approach lights reach out over the bay behind it.
##
## Everything is one draw call, casts no shadow and disappears past 12 km, so a
## thousand lights on short final cost nothing the frame budget can feel.

const THRESHOLD_Z := 1800.0
const END_Z := -1800.0
const HALF_WIDTH := 30.4
const APPROACH_STATIONS := 30      # 30.5 m apart, ALSF-2 reaches ~915 m out
const STATION_STEP := 30.5
const PAPI_Z := 1300.0
const PAPI_X := -52.0              # left hand side for an aircraft heading -Z
const PAPI_SPACING := 9.0
const GLIDE_DEGREES := 3.0

const WHITE := Color(1.0, 0.96, 0.88)
const GREEN := Color(0.12, 1.0, 0.42)
const RED := Color(1.0, 0.13, 0.08)
const AMBER := Color(1.0, 0.62, 0.16)

var papi_first := -1               # instance index of the innermost PAPI box
var papi_height := 0.0
var _ground: Callable
var _places: Array[Transform3D] = []
var _colours := PackedColorArray()
var _data := PackedColorArray()

## One light. custom data is (flash phase or -1 for steady, directional, size, unused).
func place(at: Vector3, colour: Color, energy: float, phase: float = -1.0, aimed: float = 0.0, scale: float = 1.0) -> void:
	_places.append(Transform3D(Basis.IDENTITY, at))
	_colours.append(Color(colour.r, colour.g, colour.b, energy))
	_data.append(Color(phase, aimed, scale, 0.0))

func build(world: Node) -> void:
	name = "RunwayLights"
	_ground = func(x: float, z: float) -> float: return world.ground_height(x, z)
	var add := func(x: float, z: float, lift: float, colour: Color, energy: float, phase: float, aimed: float, scale: float) -> void:
		place(Vector3(x, _ground.call(x, z) + lift, z), colour, energy, phase, aimed, scale)

	# --- ALSF-2 approach system, out over the bay behind the threshold --------
	for station in range(APPROACH_STATIONS):
		var z: float = THRESHOLD_Z + STATION_STEP * float(station + 1)
		# Fixtures stand on stanchions: taller the further out, as the real pier does.
		var lift: float = 1.1 + 0.02 * float(station)
		for k in range(-2, 3):
			add.call(float(k) * 1.05, z, lift, WHITE, 1.0, -1.0, 1.0, 1.0)
		# The rabbit: the outer 21 stations flash in sequence toward the runway.
		if station >= APPROACH_STATIONS - 21:
			var phase: float = float(APPROACH_STATIONS - 1 - station) / 21.0
			add.call(0.0, z, lift + 0.2, Color(0.85, 0.95, 1.0), 2.6, phase, 1.0, 1.9)
		# Red side rows flank the first three stations.
		if station < 3:
			for side in [-1.0, 1.0]:
				for k in range(3):
					add.call(side * (4.5 + 1.5 * float(k)), z, lift, RED, 0.8, -1.0, 1.0, 0.9)
	# 500 ft and 1000 ft crossbars.
	for bar: Array in [[152.0, 15.0], [305.0, 21.0]]:
		var z: float = THRESHOLD_Z + float(bar[0])
		var half: float = float(bar[1])
		var count: int = int(half / 3.0) * 2
		for i in range(count + 1):
			add.call(-half + 2.0 * half * float(i) / float(count), z, 1.3, WHITE, 1.0, -1.0, 1.0, 1.0)

	# --- Threshold: green bar plus wing bars ---------------------------------
	for i in range(17):
		add.call(-HALF_WIDTH + 2.0 * HALF_WIDTH * float(i) / 16.0, THRESHOLD_Z, 0.35, GREEN, 1.3, -1.0, 1.0, 1.05)
	for side in [-1.0, 1.0]:
		for k in range(6):
			add.call(side * (HALF_WIDTH + 2.5 + 2.5 * float(k)), THRESHOLD_Z, 0.5, GREEN, 1.1, -1.0, 1.0, 1.0)

	# --- Runway edges, centreline, touchdown zone and far end ----------------
	var z_edge := THRESHOLD_Z
	while z_edge >= END_Z:
		var colour: Color = AMBER if z_edge < END_Z + 600.0 else WHITE
		add.call(-HALF_WIDTH, z_edge, 0.5, colour, 1.0, -1.0, 0.0, 1.0)
		add.call(HALF_WIDTH, z_edge, 0.5, colour, 1.0, -1.0, 0.0, 1.0)
		z_edge -= 45.0
	var z_line := THRESHOLD_Z
	while z_line >= END_Z:
		var remaining: float = z_line - END_Z
		var colour: Color = RED if remaining < 300.0 else (RED if remaining < 900.0 and int(remaining / 15.0) % 2 == 0 else WHITE)
		add.call(0.0, z_line, 0.3, colour, 0.9, -1.0, 1.0, 0.85)
		z_line -= 15.0
	var z_tdz := THRESHOLD_Z - 30.0
	while z_tdz >= THRESHOLD_Z - 900.0:
		for side in [-1.0, 1.0]:
			for k in range(3):
				add.call(side * (4.5 + 3.0 * float(k)), z_tdz, 0.3, WHITE, 0.85, -1.0, 1.0, 0.8)
		z_tdz -= 30.0
	for i in range(17):
		add.call(-HALF_WIDTH + 2.0 * HALF_WIDTH * float(i) / 16.0, END_Z, 0.35, RED, 1.0, -1.0, 1.0, 1.0)

	# --- PAPI: four boxes, 3.00 degrees, red/white driven from the cockpit ----
	papi_first = _places.size()
	papi_height = _ground.call(PAPI_X, PAPI_Z) + 1.1
	for k in range(4):
		add.call(PAPI_X - PAPI_SPACING * float(k), PAPI_Z, 1.1, WHITE, 2.2, -1.0, 1.0, 1.6)

	commit()

## Turns whatever has been placed into one drawable batch.
func commit() -> void:
	var places: Array[Transform3D] = _places
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var grid := MultiMesh.new()
	grid.transform_format = MultiMesh.TRANSFORM_3D
	grid.use_colors = true
	grid.use_custom_data = true
	grid.mesh = quad
	grid.instance_count = places.size()
	for i in range(places.size()):
		grid.set_instance_transform(i, places[i])
		grid.set_instance_color(i, _colours[i])
		grid.set_instance_custom_data(i, _data[i])
	multimesh = grid

	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	material.shader = shader
	quad.surface_set_material(0, material)
	material_override = material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = 12000.0
	visibility_range_end_margin = 1500.0
	visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Box k (0 is the box nearest the runway) shows white when the aircraft is above
## that box's own threshold: 2.50, 2.83, 3.17 and 3.50 degrees around the 3.00
## degree path. On path that is white-white-red-red.
func papi_white(k: int, viewer: Vector3) -> bool:
	var box := Vector3(PAPI_X - PAPI_SPACING * float(k), papi_height, PAPI_Z)
	if viewer.z <= box.z: return false
	var flat: float = maxf(Vector2(viewer.x - box.x, viewer.z - box.z).length(), 1.0)
	var angle: float = rad_to_deg(atan2(viewer.y - box.y, flat))
	return angle > GLIDE_DEGREES - 0.5 + 0.3333 * float(k)

## Red over white, you're all right. Called with the pilot's eye position.
func update_papi(viewer: Vector3) -> void:
	if papi_first < 0 or multimesh == null: return
	for k in range(4):
		var white: bool = papi_white(k, viewer)
		var colour: Color = WHITE if white else RED
		multimesh.set_instance_color(papi_first + k, Color(colour.r, colour.g, colour.b, 2.2 if white else 2.0))

const SHADER := """
shader_type spatial;
// Airfield lights: camera-facing additive points that keep a floor on their
// screen size, so a light still reads as a light from ten kilometres out.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, specular_disabled;
uniform float size_near = 2.0;      // metres, close up
uniform float size_angular = 0.0028; // metres per metre of range: a screen-size floor
uniform float intensity = 3.4;   // cores sit above the glow threshold, so they read as lights
uniform vec3 beam = vec3(0.0, 0.0, 1.0);  // lights face the approach, +Z
varying vec4 tint;
varying float aim_gain;
void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 to_camera = CAMERA_POSITION_WORLD - centre;
	float range = max(length(to_camera), 1.0);
	float scale = max(size_near, range * size_angular) * INSTANCE_CUSTOM.z;
	vec3 forward = to_camera / range;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
	vec3 up = cross(forward, right);
	vec3 placed = centre + (right * VERTEX.x + up * VERTEX.y) * scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(placed, 1.0);
	tint = COLOR;
	// Directional fixtures dim hard when you are not on the approach side.
	float facing = dot(forward, beam);
	aim_gain = mix(1.0, smoothstep(-0.12, 0.30, facing), INSTANCE_CUSTOM.y);
	// The rabbit: one 40 ms pulse per fixture, sweeping twice a second.
	if (INSTANCE_CUSTOM.x >= 0.0) {
		float cycle = fract(TIME * 2.0);
		float lead = fract(cycle - INSTANCE_CUSTOM.x);
		aim_gain *= smoothstep(0.055, 0.0, lead);
	}
	// Distance haze: lights fade with range rather than vanishing at the cut.
	aim_gain *= mix(1.0, 0.80, smoothstep(2500.0, 11000.0, range));
}
void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float halo = pow(max(0.0, 1.0 - radius), 2.6);
	float core = pow(max(0.0, 1.0 - radius * 2.4), 2.0);
	// Unshaded output comes straight from ALBEDO, and values above one are what
	// the glow pass picks up as a light rather than a white dot.
	ALBEDO = tint.rgb * (halo * 0.55 + core * 1.25) * tint.a * intensity * aim_gain;
	ALPHA = 1.0;
}
"""
