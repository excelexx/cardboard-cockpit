extends Node3D
## Licensed FlightGear regional source meshes. No procedural terrain or buildings.
const ROOT := "res://assets/san_francisco/"
const RunwayLights := preload("res://systems/runway_lights.gd")
var region: Dictionary
var heights := PackedFloat32Array()
var chunks: Array[Dictionary] = []
var environment: WorldEnvironment
var sun: DirectionalLight3D
var tree_chunks: Array = []
var tree_meshes: Dictionary = {}
var tree_positions := PackedFloat32Array()
var elapsed := 0.0
var focus := Vector3.ZERO
var _built := false
var detailed := true
var obstacle_cells: Dictionary={}
const SUN_ENERGY := 3.0
# The panorama's sun glow is at azimuth 210.2 deg (atan2(x,-z)); the key light's is -70 deg.
const SKY_YAW_DEGREES := -79.8
const EXPOSURE := 1.0
# Near-geometry shadows. A ten-degree sun throws long shadows, so the cascades
# have to reach past the buildings: 3.2 km over four splits keeps the jet, the
# hills it flies over and the trees under it all casting.
const SHADOW_DISTANCE := 3200.0
const TERRAIN_SHADOW_RANGE := 3200.0
const TREE_SHADOW_RANGE := 1200.0
# LOD fade: the band has to end inside the streamed radius or blocks fade into
# nothing. It is also not free - FADE_SELF dithers every mesh inside the band
# through the alpha path, and measured at Ocean Beach a 4200/600/5200 setup cost
# 48 fps against 110 for 3900/500/4800 at the same primitive count.
const CITY_VISUAL_RANGE := 3900.0
const CITY_FADE_MARGIN := 500.0
const CITY_STREAM_RADIUS := 4800.0
const INTERNATIONAL_ORANGE := Color(0.753,0.212,0.173)
var terrain_detail: NoiseTexture2D
const TERRAIN_SHADER := preload("res://assets/look/sf_terrain.gdshader")
const WATER_SHADER := preload("res://assets/look/sf_water.gdshader")
var relief: Texture2D
var water_material: ShaderMaterial
var runway_lights = null
var bridge_lights = null
# 48 m cells covering the inland lakes and reservoirs, so no tree stands in one.
var lake_cells: Dictionary = {}
var airport_cells: Dictionary = {}
var airport_outline := PackedVector2Array()

func _ready() -> void: build()
func build() -> void:
	if _built: return
	_built = true
	name = "SanFranciscoBayArea"
	region = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"region.json"))
	heights = FileAccess.get_file_as_bytes(ROOT+"heights.f32").to_float32_array()
	# Photographed golden-hour cumulus (Poly Haven "Kloppenheim 06 (Pure Sky)", CC0), graded
	# by assets/look/sunset_sky.gdshader toward the key art: dark cloud bases, gold-lit edges.
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/look/sunset_sky.gdshader")
	material.set_shader_parameter("panorama",load("res://assets/look/kloppenheim_06_puresky_8k.hdr"))
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0,deg_to_rad(SKY_YAW_DEGREES),0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Golden hour: a strong warm key, a cool dim sky fill, and distance haze that
	# takes its colour from the sky so far terrain melts into the horizon.
	env.ambient_light_energy = .85
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.fog_enabled = true
	env.fog_density = 0.000026
	# Cooler and darker than the horizon sky, so far land and sea read as a band under a bright line.
	env.fog_light_color = Color(0.36,0.41,0.50)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.10   # higher values white out every view toward the low sun
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	env.fog_height = 40.0
	env.fog_height_density = 0.0004
	environment = WorldEnvironment.new(); environment.environment = env; add_child(environment)
	sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-10.0,-110,0)
	sun.light_color = Color(1.0,0.66,0.38); sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = SHADOW_DISTANCE
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	# A low sun needs a tight first split for the airframe and a long last one for hills.
	sun.directional_shadow_split_1 = 0.035; sun.directional_shadow_split_2 = 0.11; sun.directional_shadow_split_3 = 0.32
	sun.shadow_bias = 0.05; sun.shadow_normal_bias = 1.6; sun.shadow_blur = 1.1; add_child(sun)
	# Shared by the ground and water shaders: cellular noise for surface breakup
	# and the baked relief map (smooth normals + shore proximity).
	var noise := FastNoiseLite.new(); noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.045; noise.fractal_octaves = 3
	terrain_detail = NoiseTexture2D.new(); terrain_detail.width = 512; terrain_detail.height = 512
	terrain_detail.seamless = true; terrain_detail.generate_mipmaps = true; terrain_detail.noise = noise
	relief = load("res://assets/look/sf_relief.png")
	water_material = ShaderMaterial.new(); water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("waves",load(ROOT+"water_normal.png"))
	water_material.set_shader_parameter("relief",relief)
	water_material.set_shader_parameter("detail",terrain_detail)
	for item: Dictionary in region.chunks:
		var lo: Array = item.bounds[0]; var hi: Array = item.bounds[1]
		var box := AABB(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]))
		chunks.append({"path":ROOT+str(item.file),"kind":item.kind,"box":box,"node":null,"requested":false,"casting":false})
		# Use conservative source bounds only for compact tall landmarks. A bridge
		# AABB would incorrectly fill its open span, so bridges are excluded.
		if item.kind=="landmark" and box.size.y>60 and box.size.x<250 and box.size.z<250:
			var center: Vector3=box.get_center();var cell:=Vector2i(floori(center.x/512),floori(center.z/512))
			if not obstacle_cells.has(cell):obstacle_cells[cell]=[]
			obstacle_cells[cell].append(box)
	# The airfield lighting is pure geometry and needs no renderer, so it exists
	# headless too and the asset test can assert on it.
	runway_lights = RunwayLights.new(); runway_lights.build(self); add_child(runway_lights)
	_aim_water_at_sun()
	_load_airport_footprint()
	if DisplayServer.get_name()=="headless": return
	_build_marine_layer()
	# Airport and terrain are ready before takeoff. City chunks stream ahead.
	for chunk in chunks:
		if chunk.kind=="terrain" or (chunk.box.grow(4500).has_point(Vector3.ZERO)):
			_mount(chunk,load(chunk.path))
	var tree_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"trees.json"))
	tree_chunks = tree_data.chunks
	tree_positions = FileAccess.get_file_as_bytes(ROOT+"tree_positions.f32").to_float32_array()
	_stream()

## The relief shader clamps its photo (repeat_disable), so it may only be applied
## where the surface's own UVs stay inside the tile. FlightGear's airport ground
## is built from tiled line-marking strips whose V runs to 773; those keep their
## original material instead of smearing one edge texel across the runway.
static func relief_eligible(mesh: Mesh,surface: int) -> bool:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
	if uvs.is_empty(): return false
	for uv: Vector2 in uvs:
		if uv.x<-0.05 or uv.x>1.05 or uv.y<-0.05 or uv.y>1.05: return false
	return true

## International Orange only ever replaces the bridge's own salmon: the selector
## picks the two structural surfaces and nothing that carries a texture.
static func wears_international_orange(mat: StandardMaterial3D) -> bool:
	var c: Color = mat.albedo_color
	return mat.albedo_texture==null and c.r>c.b*1.3 and c.r>0.4

func _mount(chunk: Dictionary,scene: PackedScene) -> void:
	if scene==null: return
	var node := scene.instantiate(); add_child(node); chunk.node = node
	var bridge: bool = String(chunk.path).contains("ggb")
	var bay_bridge: bool = String(chunk.path).contains("baybridge")
	for mesh in node.find_children("*","GeometryInstance3D",true,false):
		if mesh is MeshInstance3D:
			for surface in range(mesh.mesh.get_surface_count()):
				var mat = mesh.get_active_material(surface)
				if not (mat is StandardMaterial3D):
					continue
				if chunk.kind=="terrain" and mat.roughness<0.4:
					_note_inland_water(mesh,surface)
					mesh.set_surface_override_material(surface,water_material)
				elif chunk.kind=="terrain" and mat.roughness>=0.4 and mat.albedo_texture!=null and relief_eligible(mesh.mesh,surface):
					var ground := ShaderMaterial.new(); ground.shader = TERRAIN_SHADER
					ground.set_shader_parameter("aerial",mat.albedo_texture)
					ground.set_shader_parameter("detail",terrain_detail)
					ground.set_shader_parameter("relief",relief)
					mesh.set_surface_override_material(surface,ground)
				elif bridge and wears_international_orange(mat):
					# Duplicate first: the imported material is shared across scenes.
					var paint: StandardMaterial3D = mat.duplicate()
					var scale: float = clampf(mat.albedo_color.v/0.9234,0.55,1.0)
					paint.albedo_color = Color(INTERNATIONAL_ORANGE.r*scale,INTERNATIONAL_ORANGE.g*scale,INTERNATIONAL_ORANGE.b*scale)
					paint.roughness = 0.62     # weathered alkyd topcoat, not chalk
					mesh.set_surface_override_material(surface,paint)
				elif bay_bridge and mat.albedo_texture==null:
					var steel: StandardMaterial3D = mat.duplicate()
					steel.roughness = 0.55     # the silver west span should catch a low sun
					mesh.set_surface_override_material(surface,steel)
				else:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if chunk.kind=="terrain" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.visibility_range_end = _visual_range(chunk.kind)
		# Dither-fade instead of popping out of existence in peripheral vision.
		mesh.visibility_range_end_margin = CITY_FADE_MARGIN if chunk.kind=="city" else 900.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if bridge: _light_the_gate(node)

## Lakes and reservoirs, rasterised into a coarse grid as they mount, so the
## tree streamer can refuse to plant anything standing in one.
func _note_inland_water(mesh: MeshInstance3D,surface: int) -> void:
	var arrays: Array = mesh.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty(): return
	var box := AABB(verts[0],Vector3.ZERO)
	for v in verts: box = box.expand(v)
	# Sea-level water is the bay and the Pacific; their shoreline trees are real.
	if box.position.y<=2.0 or maxf(box.size.x,box.size.z)>14000.0: return
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var count: int = index.size() if index.size()>0 else verts.size()
	for k in range(0,count-2,3):
		var a: Vector3 = verts[index[k]] if index.size()>0 else verts[k]
		var b: Vector3 = verts[index[k+1]] if index.size()>0 else verts[k+1]
		var c: Vector3 = verts[index[k+2]] if index.size()>0 else verts[k+2]
		var surface_y: float = maxf(a.y,maxf(b.y,c.y))
		var lo := Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z)))
		var hi := Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))
		for gx in range(floori(lo.x/48.0),floori(hi.x/48.0)+1):
			for gz in range(floori(lo.y/48.0),floori(hi.y/48.0)+1):
				var cell := Vector2i(gx,gz)
				lake_cells[cell] = maxf(float(lake_cells.get(cell,-1e9)),surface_y)

func _load_airport_footprint() -> void:
	var scene: Node=load(ROOT+"terrain_KSFO.scn").instantiate();add_child(scene)
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var material=mesh.get_active_material(surface)
			if material is StandardMaterial3D and material.roughness>=.4:_note_airport_surface(mesh,surface)
	remove_child(scene);scene.free()
	airport_outline=Geometry2D.convex_hull(airport_outline)

func _note_airport_surface(mesh: MeshInstance3D,surface: int) -> void:
	var arrays: Array=mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var count: int=indices.size() if not indices.is_empty() else vertices.size()
	for i in range(0,count-2,3):
		var triangle:=PackedVector2Array()
		for j in range(3):
			var at: Vector3=mesh.global_transform*vertices[indices[i+j] if not indices.is_empty() else i+j]
			triangle.append(Vector2(at.x,at.z));airport_outline.append(Vector2(at.x,at.z))
		var lo:=triangle[0].min(triangle[1]).min(triangle[2]);var hi:=triangle[0].max(triangle[1]).max(triangle[2])
		for x in range(floori(lo.x/128),floori(hi.x/128)+1):
			for z in range(floori(lo.y/128),floori(hi.y/128)+1):
				var key:=Vector2i(x,z)
				if not airport_cells.has(key):airport_cells[key]=[]
				airport_cells[key].append(triangle)

func is_airport_surface(x: float,z: float) -> bool:
	var point:=Vector2(x,z)
	# Grass gaps between the authored paving surfaces are still airport land.
	if airport_outline.size()>2 and Geometry2D.is_point_in_polygon(point,airport_outline) and (is_runway(x,z) or ground_height(x,z)>.35):return true
	for triangle: PackedVector2Array in airport_cells.get(Vector2i(floori(x/128),floori(z/128)),[]):
		if Geometry2D.is_point_in_polygon(point,triangle):return true
	return false

func standing_in_water(at: Vector3) -> bool:
	var level = lake_cells.get(Vector2i(floori(at.x/48.0),floori(at.z/48.0)))
	return level!=null and at.y<float(level)+4.0

## Tower obstruction beacons and a roadway lamp chain: at a ten-degree sun the
## bridge is already in its own shadow, and a dark silhouette reads as unfinished.
func _light_the_gate(node: Node3D) -> void:
	if DisplayServer.get_name()=="headless" or bridge_lights!=null: return
	var towers: Array[Vector3] = [Vector3(14645.7,226.96,-18014.0),Vector3(15709.3,226.96,-18726.1)]
	var lamps := RunwayLights.new()
	lamps.name = "GoldenGateLights"
	for tower: Vector3 in towers:
		for side in [-9.0,9.0]:
			lamps.place(tower+Vector3(0,3.0,side),Color(1.0,0.12,0.08),2.4,-1.0,0.0,2.2)
		var beacon := OmniLight3D.new()
		beacon.position = tower+Vector3(0,4.0,0)
		beacon.light_color = Color(1.0,0.18,0.10); beacon.light_energy = 6.0
		beacon.omni_range = 90.0; beacon.shadow_enabled = false
		beacon.distance_fade_enabled = true; beacon.distance_fade_begin = 6000.0
		node.add_child(beacon)
	# Roadway lamps along the deck, cambered like the measured carriageway.
	var deck_a := Vector3(14400.0,60.8,-17899.4)
	var deck_b := Vector3(15900.0,60.8,-18865.2)
	for i in range(31):
		var t: float = float(i)/30.0
		var at: Vector3 = deck_a.lerp(deck_b,t)
		at.y = 62.0+17.0*sin(PI*t)+5.0
		lamps.place(at,Color(1.0,0.72,0.36),1.5,-1.0,0.0,1.1)
	lamps.commit()
	lamps.visibility_range_end = 26000.0
	node.add_child(lamps); bridge_lights = lamps

func _stream() -> void:
	_stream_trees()
	_update_shadow_casters()
	# Nearest first, several per tick: at 330 m/s one chunk per tick left the
	# city empty under the jet for the first minute.
	var mounted := 0; var loading := 0; var wanted: Array[Dictionary] = []
	for chunk in chunks:
		if is_instance_valid(chunk.node): continue
		if chunk.requested:
			loading += 1
			if mounted<3 and ResourceLoader.load_threaded_get_status(chunk.path)==ResourceLoader.THREAD_LOAD_LOADED:
				_mount(chunk,ResourceLoader.load_threaded_get(chunk.path)); mounted += 1
		elif chunk.box.grow(CITY_STREAM_RADIUS if chunk.kind=="city" else 9000 if chunk.kind=="road" else 28000).has_point(focus):
			wanted.append(chunk)
	if wanted.is_empty(): return
	wanted.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.box.get_center().distance_squared_to(focus)<b.box.get_center().distance_squared_to(focus))
	# A bounded queue without loader sub-threads: a burst of 24 sub-threaded
	# requests intermittently never completed.
	for chunk in wanted.slice(0,maxi(0,10-loading)):
		ResourceLoader.load_threaded_request(chunk.path,"PackedScene"); chunk.requested = true

## Terrain is the biggest mesh in the world, so only the tiles the cascades can
## actually reach are allowed to cast. Toggled on transitions, never per frame.
func _update_shadow_casters() -> void:
	for chunk in chunks:
		if chunk.kind!="terrain" or not is_instance_valid(chunk.node): continue
		var near: bool = chunk.box.grow(TERRAIN_SHADOW_RANGE).has_point(focus)
		if near==bool(chunk.casting): continue
		chunk.casting = near
		for mesh in chunk.node.find_children("*","GeometryInstance3D",true,false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for chunk: Dictionary in tree_chunks:
		if not chunk.has("node"): continue
		var centre := Vector2(chunk.center[0],chunk.center[1])
		var near: bool = centre.distance_to(Vector2(focus.x,focus.z))<TREE_SHADOW_RANGE
		if near==bool(chunk.get("casting",false)): continue
		chunk["casting"] = near
		chunk.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_local_shadows(at: Vector3,dt: float) -> void:
	if DisplayServer.get_name()=="headless": return
	focus = at; elapsed += dt
	_drift_marine_layer(dt)
	if runway_lights!=null and absf(at.x)<4000.0 and at.z<9000.0 and at.z>-3000.0:
		runway_lights.update_papi(at)
	if elapsed>0.05: elapsed = 0; _stream()
func set_conditions(_id: String) -> void: pass
func _visual_range(kind: String) -> float:
	# The haze takes everything by ~6 km; drawing city blocks past that only costs frames.
	if kind=="terrain": return 90000
	if kind=="landmark": return 22000
	if kind=="road": return 6000 if detailed else 4500
	return CITY_VISUAL_RANGE if detailed else 3000
func apply_quality(high: bool) -> void:
	detailed = high
	if environment==null: return
	for chunk in chunks:
		if is_instance_valid(chunk.node):
			for mesh in chunk.node.find_children("*","GeometryInstance3D",true,false): mesh.visibility_range_end = _visual_range(chunk.kind)
	for chunk: Dictionary in tree_chunks:
		if chunk.has("node"): chunk.node.visibility_range_end = 4200 if detailed else 3000
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = SHADOW_DISTANCE if high else 1400.0
	var forward: bool = RenderingServer.get_current_rendering_method()=="forward_plus"
	var e: Environment = environment.environment
	e.ssao_enabled = high and forward
	e.ssao_radius = 3.0; e.ssao_intensity = 2.2; e.ssao_power = 1.6; e.ssao_detail = 0.6
	e.volumetric_fog_enabled = false
	for sheet in marine_deck: sheet.visible = high
	e.glow_enabled = forward
	e.glow_intensity=.22
	e.glow_bloom=.0
	e.glow_hdr_threshold=2.2
	e.glow_hdr_scale=1.2
	e.glow_blend_mode=Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(0,7): e.set_glow_level(level, 1.0 if level in [1,2,4,5] else 0.0)
func ground_height(x: float,z: float) -> float:
	var grid: Dictionary = region.grid
	var gx: float = clampf((x-float(grid.x))/float(grid.step),0,float(grid.size)-1.001)
	var gz: float = clampf((z-float(grid.z))/float(grid.step),0,float(grid.size)-1.001)
	var ix := int(gx); var iz := int(gz); var size := int(grid.size)
	return lerpf(lerpf(heights[iz*size+ix],heights[iz*size+ix+1],gx-ix),lerpf(heights[(iz+1)*size+ix],heights[(iz+1)*size+ix+1],gx-ix),gz-iz)
func is_runway(x: float,z: float) -> bool: return absf(x)<30.4 and absf(z)<1800
func obstacle_collision(_at: Vector3,_radius: float=2.0) -> bool: return false
func obstacle_proximity(at: Vector3) -> Dictionary:
	var cell:=Vector2i(floori(at.x/512),floori(at.z/512));var distance:=INF;var point:=at
	for x in range(-1,2):
		for z in range(-1,2):
			for box: AABB in obstacle_cells.get(cell+Vector2i(x,z),[]):
				var near: Vector3=at.clamp(box.position,box.end)
				var d:=at.distance_to(near)
				if d<distance:distance=d;point=near
	return {"distance":distance,"point":point}


func _stream_trees() -> void:
	var mounted := 0
	for chunk: Dictionary in tree_chunks:
		if chunk.has("node"): continue
		var center := Vector2(chunk.center[0],chunk.center[1])
		if center.distance_to(Vector2(focus.x,focus.z))>4500: continue
		if not tree_meshes.has(chunk.mesh):
			var prototype: Node3D = load(ROOT+str(chunk.mesh)).instantiate()
			var source: MeshInstance3D = prototype.find_children("*","MeshInstance3D",true,false)[0]
			tree_meshes[chunk.mesh] = source.mesh
			prototype.free()
		var mesh: Mesh = tree_meshes[chunk.mesh]
		var material: StandardMaterial3D = mesh.surface_get_material(0)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		var points := tree_positions.slice(int(chunk.offset),int(chunk.offset)+int(chunk.count)*3)
		# Skip anything the source data planted in a reservoir.
		var dry := PackedVector3Array()
		for i in range(points.size()/3):
			var at := Vector3(points[i*3],points[i*3+1],points[i*3+2])
			if not standing_in_water(at): dry.append(at)
		var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.mesh = mesh
		multi.instance_count = dry.size()
		for i in range(multi.instance_count):
			var at: Vector3 = dry[i]
			multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,fmod(at.x,TAU)).scaled(Vector3(15,25,15)),at-Vector3(center.x,0,center.y)))
		var batch := MultiMeshInstance3D.new(); batch.multimesh = multi
		batch.position = Vector3(center.x,0,center.y); batch.visibility_range_end = 4200 if detailed else 3000
		batch.visibility_range_end_margin = 500.0
		batch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch); chunk.node = batch; chunk["casting"] = false; mounted += 1
		if mounted>=3: return

# --- Marine layer -------------------------------------------------------------
# Godot's volumetric fog cannot hold a crisp low bank at this scale: a 1.7 km
# FogVolume two kilometres out lands in the outermost froxel slices and smears
# across most of the frame as a flat brown wash - exactly the "nothing may wash
# over the view" failure. So the layer is geometry instead: three horizontal
# sheets of drifting noise lying at 52-84 m over the water, always BELOW the
# 270-720 m flight path, masked to the coastal corridor and thickest in the
# Golden Gate throat. No god rays, no veil, and the cost is three quads.
var marine_deck: Array[MeshInstance3D] = []
var cloud_presence := 0.0
var atmosphere_clock := 0.0
const MARINE_SHEETS := 3
const MARINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, specular_disabled;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec2 wind = vec2(9.0, -3.0);
uniform float coverage = 0.42;
uniform float layer = 0.0;
uniform float opacity = 0.80;
uniform vec3 lit : source_color = vec3(1.0, 0.92, 0.84);
uniform vec3 shade : source_color = vec3(0.58, 0.66, 0.80);
uniform vec3 sun_direction = vec3(-0.925, 0.174, -0.337);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
// Distance from a point to a segment, in the ground plane.
float to_leg(vec2 p, vec2 a, vec2 b) {
	vec2 run = b - a;
	float t = clamp(dot(p - a, run) / max(dot(run, run), 1.0), 0.0, 1.0);
	return length(p - (a + run * t));
}
void fragment() {
	vec2 p = world_pos.xz;
	// The sea breeze runs up the coast and in through the Gate; the layer only
	// lies along that corridor, never over the hills or the inland basin.
	float corridor = min(min(min(min(min(
		to_leg(p, vec2(-5200.0, -6000.0), vec2(-2600.0, -10600.0)),
		to_leg(p, vec2(-2600.0, -10600.0), vec2(1200.0, -14100.0))),
		to_leg(p, vec2(1200.0, -14100.0), vec2(5300.0, -16700.0))),
		to_leg(p, vec2(5300.0, -16700.0), vec2(10200.0, -18800.0))),
		to_leg(p, vec2(10200.0, -18800.0), vec2(15200.0, -19000.0))),
		to_leg(p, vec2(15200.0, -19000.0), vec2(19600.0, -18300.0)));
	float lane = 1.0 - smoothstep(1100.0, 3400.0, corridor);
	float range = length(world_pos - CAMERA_POSITION_WORLD);
	// Never a sheet in the pilot's face, and gone before it can haze the horizon.
	float clearance = smoothstep(40.0, 150.0, abs(CAMERA_POSITION_WORLD.y - world_pos.y));
	float depth_fade = smoothstep(260.0, 900.0, range) * (1.0 - smoothstep(9000.0, 19000.0, range));
	float reach = lane * clearance * depth_fade;
	// Most of a 30 km sheet is outside the corridor or out of range: leave before
	// paying for any of the noise, or a grazing view costs three full-screen layers.
	if (reach < 0.004) discard;
	// Thicker where the layer squeezes through the strait.
	float throat = 1.0 - smoothstep(900.0, 3200.0, length(p - vec2(14400.0, -18900.0)));
	vec2 drift = wind * TIME;
	float a = texture(detail, (p + drift) / 4200.0 + layer * 0.21).r;
	float b = texture(detail, (p + drift * 1.7) / 1650.0 + 0.37 + layer * 0.13).r;
	float c = texture(detail, (p + drift * 2.6) / 640.0 + 0.71 + layer * 0.29).r;
	float field = a * 0.55 + b * 0.30 + c * 0.15;
	float body = smoothstep(0.0, 0.34, field - (1.0 - coverage - throat * 0.22));
	float alpha = body * reach * opacity;
	// Lit tops toward the sun, cool shadowed flanks away from it.
	float warmth = clamp(dot(normalize(vec3(sun_direction.x, 0.0, sun_direction.z)), normalize(vec3(drift.x, 0.0, drift.y) + vec3(0.001))) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(shade, lit, smoothstep(0.30, 0.85, field)) * mix(0.92, 1.16, warmth);
	ALPHA = clamp(alpha, 0.0, 0.86);
}
"""
func _build_marine_layer() -> void:
	if not marine_deck.is_empty(): return
	if RenderingServer.get_current_rendering_method()!="forward_plus": return
	var env: Environment = environment.environment
	env.volumetric_fog_enabled = false      # see the note above: it cannot hold a bank
	var shader := Shader.new(); shader.code = MARINE_SHADER
	var towards_sun: Vector3 = sun.transform.basis.z.normalized()
	for i in range(MARINE_SHEETS):
		var plane := PlaneMesh.new(); plane.size = Vector2(30000,24000)
		var sheet := MeshInstance3D.new(); sheet.mesh = plane
		sheet.position = Vector3(7000,52.0+16.0*float(i),-15000)
		var material := ShaderMaterial.new(); material.shader = shader
		material.set_shader_parameter("detail",terrain_detail)
		material.set_shader_parameter("layer",float(i))
		material.set_shader_parameter("wind",Vector2(9.0,-3.0)*(1.0+0.22*float(i)))
		material.set_shader_parameter("coverage",0.44-0.07*float(i))
		material.set_shader_parameter("opacity",0.80-0.15*float(i))
		material.set_shader_parameter("sun_direction",towards_sun)
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheet.extra_cull_margin = 20000.0
		sheet.sorting_offset = -50.0
		add_child(sheet); marine_deck.append(sheet)

func _drift_marine_layer(dt: float) -> void:
	if marine_deck.is_empty(): return
	# The sheets scroll in the shader; this only breathes the coverage so the
	# layer thickens and thins over the two and a half minutes of the sortie.
	var breath: float = 0.44+0.05*sin(atmosphere_clock*0.06)
	for i in range(marine_deck.size()):
		var material: ShaderMaterial = marine_deck[i].material_override
		material.set_shader_parameter("coverage",breath-0.07*float(i))
	atmosphere_clock += dt

## How much marine layer the aircraft is flying over, for the light modulation.
func _marine_presence(at: Vector3) -> float:
	if marine_deck.is_empty(): return 0.0
	var legs: Array = [Vector2(-5200,-6000),Vector2(-2600,-10600),Vector2(1200,-14100),Vector2(5300,-16700),Vector2(10200,-18800),Vector2(15200,-19000),Vector2(19600,-18300)]
	var here := Vector2(at.x,at.z)
	var nearest := INF
	for i in range(legs.size()-1):
		var a: Vector2 = legs[i]; var b: Vector2 = legs[i+1]
		var run: Vector2 = b-a
		var t: float = clampf((here-a).dot(run)/maxf(run.length_squared(),1.0),0.0,1.0)
		nearest = minf(nearest,here.distance_to(a+run*t))
	return clampf(1.0-nearest/4200.0,0.0,1.0)*clampf(1.0-(at.y-120.0)/900.0,0.0,1.0)

func update_showcase(at: Vector3,act: int,_intensity: float,dt: float) -> void:
	if marine_deck.is_empty() and DisplayServer.get_name()!="headless":_build_marine_layer()
	cloud_presence=_marine_presence(at)
	var env: Environment=environment.environment
	# Broad cloud-light variation; one coherent sun remains the key light.
	sun.light_energy=SUN_ENERGY*(1.0-.05*sin(atmosphere_clock*.08)-cloud_presence*.22)
	env.tonemap_exposure=lerpf(env.tonemap_exposure,EXPOSURE-cloud_presence*.07,1-exp(-dt*2))
	env.fog_density=lerpf(env.fog_density,.000030+(0.000006 if act==2 else 0),1-exp(-dt))

## The water shader draws its own sun road, so it needs the key light by hand.
func _aim_water_at_sun() -> void:
	if water_material==null or sun==null: return
	water_material.set_shader_parameter("sun_direction",sun.transform.basis.z.normalized())
	water_material.set_shader_parameter("sun_tint",Vector3(sun.light_color.r,sun.light_color.g,sun.light_color.b))
