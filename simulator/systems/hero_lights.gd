extends Node3D
## Lights that only the player's jet can see (render layer 2).
##
## A near-black airframe has almost no diffuse response, so under the world's low sun
## it collapses into a flat cut-out from the chase camera: no form, no panel detail,
## and no separation from dark asphalt or dark water. A film crew solves that with
## lights that only hit the hero, and so does this. Three sources travel with the jet:
##   key   - warm, from the sun's side but lifted, so the sun-side facets go gold;
##   sky   - cool, from above and slightly behind, so the upper surfaces read as slate
##           gunmetal with facet-to-facet shading instead of one black shape;
##   glint - placed where the dorsal deck mirrors it into the camera, so a sheen runs
##           down the spine and the creases catch an edge from the chase view.
## Nothing here lights the world, casts a shadow or is visible as a source, so it can
## never veil the forward view.
var app: Node
var key: DirectionalLight3D
var sky: DirectionalLight3D
var glint: DirectionalLight3D

const LAYER := 2
const KEY_ELEVATION := 0.66          # radians above the horizon, on the sun's azimuth
const KEY_ENERGY := 2.2
const SKY_ENERGY := 0.8
const GLINT_ENERGY := 0.75
const KEY_COLOR := Color(1.0,0.74,0.46)
const SKY_COLOR := Color(0.62,0.74,1.0)
const GLINT_COLOR := Color(0.86,0.92,1.0)

func _ready() -> void:
	key = _lamp(KEY_COLOR,KEY_ENERGY)
	sky = _lamp(SKY_COLOR,SKY_ENERGY)
	glint = _lamp(GLINT_COLOR,GLINT_ENERGY)
	# Runs after the camera rig so the glint is placed for THIS frame's view.
	process_priority = 100

func _lamp(color: Color, energy: float) -> DirectionalLight3D:
	var lamp := DirectionalLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.light_cull_mask = LAYER
	lamp.shadow_enabled = false
	lamp.light_specular = 1.0
	lamp.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(lamp)
	return lamp

## Point a directional light so that it arrives FROM `toward_light`.
func _aim(lamp: DirectionalLight3D, toward_light: Vector3) -> void:
	var up := Vector3.UP if absf(toward_light.dot(Vector3.UP))<0.98 else Vector3.FORWARD
	lamp.global_basis = Basis.looking_at(-toward_light,up)

func _process(_dt: float) -> void:
	if app==null or app.get("flight")==null or app.get("camera")==null: return
	var show: bool = app.mode!="title" and (not app.cockpit or app.mode in ["ejected","crashed","results"])
	key.visible = show; sky.visible = show; glint.visible = show
	if not show: return
	var f: FlightDynamics = app.flight
	var airframe := Basis.from_euler(Vector3(f.pitch,-f.heading,-f.roll))
	var to_camera: Vector3 = app.camera.global_position-f.position
	if to_camera.length()<0.5: return
	to_camera = to_camera.normalized()
	var flat_camera := Vector3(to_camera.x,0,to_camera.z)
	flat_camera = flat_camera.normalized() if flat_camera.length()>0.05 else Vector3.BACK
	# Key: the world sun's azimuth, lifted so it rakes the upper surfaces instead of grazing them.
	var to_sun := Vector3(-0.35,0.17,-0.92)
	var world: Node = app.get("world")
	if world!=null and world.get("sun")!=null: to_sun = world.sun.global_basis.z
	var flat_sun := Vector3(to_sun.x,0,to_sun.z)
	flat_sun = flat_sun.normalized() if flat_sun.length()>0.05 else Vector3.LEFT
	_aim(key,(flat_sun*cos(KEY_ELEVATION)+Vector3.UP*sin(KEY_ELEVATION)).normalized())
	# Sky: from above, leaning toward the viewer so the faces the camera sees are the lit ones.
	_aim(sky,(Vector3.UP*0.90+flat_camera*0.44).normalized())
	# Glint: the direction the dorsal deck mirrors into the camera, pulled a little toward
	# the sun so the sheen favours one side and the facets do not all flash together.
	var deck: Vector3 = airframe.y
	var mirror: Vector3 = (deck*2.0*deck.dot(to_camera)-to_camera)
	if mirror.length()<0.05: mirror = -flat_camera
	_aim(glint,(mirror.normalized()+flat_sun*0.45+Vector3.UP*0.25).normalized())
