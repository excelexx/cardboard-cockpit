extends Node3D
## Licensed FlightGear regional source meshes. No procedural terrain or buildings.
const ROOT := "res://assets/san_francisco/"
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
const SUN_ENERGY := 3.2
const EXPOSURE := 1.0
var terrain_detail: NoiseTexture2D
const TERRAIN_SHADER := preload("res://assets/look/sf_terrain.gdshader")
const WATER_SHADER := preload("res://assets/look/sf_water.gdshader")
var relief: Texture2D
var water_material: ShaderMaterial

func _ready() -> void: build()
func build() -> void:
	if _built: return
	_built = true
	name = "SanFranciscoBayArea"
	region = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"region.json"))
	heights = FileAccess.get_file_as_bytes(ROOT+"heights.f32").to_float32_array()
	var material := PanoramaSkyMaterial.new()
	material.panorama = load(ROOT+"sky.exr")
	material.energy_multiplier = 0.65
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Golden hour: a strong warm key, a cool dim sky fill, and distance haze that
	# takes its colour from the sky so far terrain melts into the horizon.
	env.ambient_light_energy = .55
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.16
	env.fog_enabled = true
	env.fog_density = 0.000030
	env.fog_light_color = Color(1.0,0.78,0.56)
	env.fog_light_energy = 0.9
	env.fog_sun_scatter = 0.10   # higher values white out every view toward the low sun
	env.fog_aerial_perspective = 0.9
	env.fog_sky_affect = 0.0
	env.fog_height = 60.0
	env.fog_height_density = 0.0009
	environment = WorldEnvironment.new(); environment.environment = env; add_child(environment)
	sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-16,-110,0)
	sun.light_color = Color(1.0,0.74,0.50); sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 1400
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.04; sun.directional_shadow_split_2 = 0.12; sun.directional_shadow_split_3 = 0.35
	sun.shadow_bias = 0.03; sun.shadow_normal_bias = 1.2; sun.shadow_blur = 1.4; add_child(sun)
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
		chunks.append({"path":ROOT+str(item.file),"kind":item.kind,"box":box,"node":null,"requested":false})
		# Use conservative source bounds only for compact tall landmarks. A bridge
		# AABB would incorrectly fill its open span, so bridges are excluded.
		if item.kind=="landmark" and box.size.y>60 and box.size.x<250 and box.size.z<250:
			var center: Vector3=box.get_center();var cell:=Vector2i(floori(center.x/512),floori(center.z/512))
			if not obstacle_cells.has(cell):obstacle_cells[cell]=[]
			obstacle_cells[cell].append(box)
	if DisplayServer.get_name()=="headless": return
	# Airport and terrain are ready before takeoff. City chunks stream ahead.
	for chunk in chunks:
		if chunk.kind=="terrain" or (chunk.box.grow(4500).has_point(Vector3.ZERO)):
			_mount(chunk,load(chunk.path))
	var tree_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"trees.json"))
	tree_chunks = tree_data.chunks
	tree_positions = FileAccess.get_file_as_bytes(ROOT+"tree_positions.f32").to_float32_array()
	_stream()

func _mount(chunk: Dictionary,scene: PackedScene) -> void:
	if scene==null: return
	var node := scene.instantiate(); add_child(node); chunk.node = node
	for mesh in node.find_children("*","GeometryInstance3D",true,false):
		if mesh is MeshInstance3D:
			for surface in range(mesh.mesh.get_surface_count()):
				var mat = mesh.get_active_material(surface)
				if mat is StandardMaterial3D and chunk.kind=="terrain" and mat.roughness>=0.4 and mat.albedo_texture!=null:
					var ground := ShaderMaterial.new(); ground.shader = TERRAIN_SHADER
					ground.set_shader_parameter("aerial",mat.albedo_texture)
					ground.set_shader_parameter("detail",terrain_detail)
					ground.set_shader_parameter("relief",relief)
					mesh.set_surface_override_material(surface,ground)
				elif mat is StandardMaterial3D and chunk.kind=="terrain" and mat.roughness<0.4:
					mesh.set_surface_override_material(surface,water_material)
				elif mat is StandardMaterial3D:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if chunk.kind=="terrain" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.visibility_range_end = _visual_range(chunk.kind)
		if chunk.kind=="city":
			mesh.visibility_range_end_margin = 400

func _stream() -> void:
	_stream_trees()
	# Nearest first, several per tick: at 330 m/s one chunk per tick left the
	# city empty under the jet for the first minute.
	var mounted := 0; var loading := 0; var wanted: Array[Dictionary] = []
	for chunk in chunks:
		if is_instance_valid(chunk.node): continue
		if chunk.requested:
			loading += 1
			if mounted<3 and ResourceLoader.load_threaded_get_status(chunk.path)==ResourceLoader.THREAD_LOAD_LOADED:
				_mount(chunk,ResourceLoader.load_threaded_get(chunk.path)); mounted += 1
		elif chunk.box.grow(4200 if chunk.kind=="city" else 9000 if chunk.kind=="road" else 28000).has_point(focus):
			wanted.append(chunk)
	if wanted.is_empty(): return
	wanted.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.box.get_center().distance_squared_to(focus)<b.box.get_center().distance_squared_to(focus))
	# A bounded queue without loader sub-threads: a burst of 24 sub-threaded
	# requests intermittently never completed.
	for chunk in wanted.slice(0,maxi(0,10-loading)):
		ResourceLoader.load_threaded_request(chunk.path,"PackedScene"); chunk.requested = true

func update_local_shadows(at: Vector3,dt: float) -> void:
	if DisplayServer.get_name()=="headless": return
	focus = at; elapsed += dt
	if elapsed>0.05: elapsed = 0; _stream()
func set_conditions(_id: String) -> void: pass
func _visual_range(kind: String) -> float:
	# The haze takes everything by ~6 km; drawing city blocks past that only costs frames.
	if kind=="terrain": return 90000
	if kind=="landmark": return 22000
	if kind=="road": return 6000 if detailed else 4500
	return 3800 if detailed else 3000
func apply_quality(high: bool) -> void:
	detailed = high
	if environment==null: return
	for chunk in chunks:
		if is_instance_valid(chunk.node):
			for mesh in chunk.node.find_children("*","GeometryInstance3D",true,false): mesh.visibility_range_end = _visual_range(chunk.kind)
	for chunk: Dictionary in tree_chunks:
		if chunk.has("node"): chunk.node.visibility_range_end = 4200 if detailed else 3000
	var forward: bool = RenderingServer.get_current_rendering_method()=="forward_plus"
	var e: Environment = environment.environment
	e.ssao_enabled = high and forward
	e.ssao_radius = 3.0; e.ssao_intensity = 2.2; e.ssao_power = 1.6; e.ssao_detail = 0.6
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
		var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D; multi.mesh = mesh
		multi.instance_count = points.size()/3
		for i in range(multi.instance_count):
			var at := Vector3(points[i*3],points[i*3+1],points[i*3+2])
			multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,fmod(at.x,TAU)).scaled(Vector3(15,25,15)),at-Vector3(center.x,0,center.y)))
		var batch := MultiMeshInstance3D.new(); batch.multimesh = multi
		batch.position = Vector3(center.x,0,center.y); batch.visibility_range_end = 4200 if detailed else 3000
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch); chunk.node = batch; mounted += 1
		if mounted>=3: return

# Localized marine atmosphere uses Godot's existing Forward+ fog implementation.
var fog_banks: Array[FogVolume] = []
var cloud_presence := 0.0
var atmosphere_clock := 0.0
func _build_marine_layer() -> void:
	if RenderingServer.get_current_rendering_method()!="forward_plus":return
	var env: Environment=environment.environment
	env.volumetric_fog_enabled=true;env.volumetric_fog_density=.00002;env.volumetric_fog_length=2200
	env.volumetric_fog_detail_spread=1.6;env.volumetric_fog_ambient_inject=.6
	for placement: Vector3 in [Vector3(15200,375,-18000),Vector3(17500,350,-12800),Vector3(6500,360,-5000)]:
		var volume:=FogVolume.new();volume.position=placement;volume.size=Vector3(2600,650,1500)
		var material:=FogMaterial.new();material.density=.0015;material.albedo=Color(.73,.84,.93);material.height_falloff=0.0;material.edge_fade=.7
		volume.material=material;add_child(volume);fog_banks.append(volume)
func update_showcase(at: Vector3,act: int,intensity: float,dt: float) -> void:
	atmosphere_clock+=dt
	if fog_banks.is_empty() and DisplayServer.get_name()!="headless":_build_marine_layer()
	cloud_presence=0
	for bank in fog_banks:
		var normalized: Vector3=(at-bank.position)/bank.size
		cloud_presence=maxf(cloud_presence,clampf(1-normalized.length()*2,0,1))
	var env: Environment=environment.environment
	# Broad cloud-light variation; one coherent sun remains the key light.
	sun.light_energy=SUN_ENERGY*(1.0-.05*sin(atmosphere_clock*.08)-cloud_presence*.22)
	env.tonemap_exposure=lerpf(env.tonemap_exposure,EXPOSURE-cloud_presence*.07,1-exp(-dt*2))
	env.fog_density=lerpf(env.fog_density,.000030+(0.000006 if act==2 else 0),1-exp(-dt))
	if act==2 and fog_banks.size()>1:
		fog_banks[1].material.density=.0022
	elif fog_banks.size()>1:fog_banks[1].material.density=.0012
