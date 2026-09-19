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
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_density = 0.000016
	env.fog_light_color = Color(0.69,0.73,0.78)
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.08
	environment = WorldEnvironment.new(); environment.environment = env; add_child(environment)
	sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-18,-110,0)
	sun.light_color = Color(1.0,0.79,0.60); sun.light_energy = 1.0
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 2200
	sun.shadow_bias = 0.025; sun.shadow_normal_bias = 1.0; add_child(sun)
	for item: Dictionary in region.chunks:
		var lo: Array = item.bounds[0]; var hi: Array = item.bounds[1]
		var box := AABB(Vector3(lo[0],lo[1],lo[2]),Vector3(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2]))
		chunks.append({"path":ROOT+str(item.file),"kind":item.kind,"box":box,"node":null,"requested":false})
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
				if mat is StandardMaterial3D:
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if chunk.kind=="terrain" and mat.roughness<0.4:
						mat.normal_enabled = true; mat.normal_texture = load(ROOT+"water_normal.png")
						mat.normal_scale = 0.12; mat.roughness = 0.32
						mat.uv1_triplanar = true; mat.uv1_world_triplanar = true; mat.uv1_scale = Vector3.ONE*0.003
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if chunk.kind=="terrain" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.visibility_range_end = _visual_range(chunk.kind)

func _stream() -> void:
	_stream_trees()
	for chunk in chunks:
		if is_instance_valid(chunk.node): continue
		if chunk.requested:
			if ResourceLoader.load_threaded_get_status(chunk.path)==ResourceLoader.THREAD_LOAD_LOADED:
				_mount(chunk,ResourceLoader.load_threaded_get(chunk.path)); return
		elif chunk.box.grow(14000 if chunk.kind=="city" else 28000).has_point(focus):
			ResourceLoader.load_threaded_request(chunk.path,"PackedScene",true);chunk.requested = true

func update_local_shadows(at: Vector3,dt: float) -> void:
	if DisplayServer.get_name()=="headless": return
	focus = at; elapsed += dt
	if elapsed>0.15: elapsed = 0; _stream()
func set_conditions(_id: String) -> void: pass
func _visual_range(kind: String) -> float:
	if kind=="terrain": return 90000
	if kind=="landmark": return 22000
	if kind=="road": return 12000 if detailed else 8000
	return 9000 if detailed else 6000
func apply_quality(high: bool) -> void:
	detailed = high
	if environment==null: return
	for chunk in chunks:
		if is_instance_valid(chunk.node):
			for mesh in chunk.node.find_children("*","GeometryInstance3D",true,false): mesh.visibility_range_end = _visual_range(chunk.kind)
	for chunk: Dictionary in tree_chunks:
		if chunk.has("node"): chunk.node.visibility_range_end = 4200 if detailed else 3000
	var forward: bool = RenderingServer.get_current_rendering_method()=="forward_plus"
	environment.environment.ssao_enabled = high and forward
	environment.environment.glow_enabled = high and forward
func ground_height(x: float,z: float) -> float:
	var grid: Dictionary = region.grid
	var gx: float = clampf((x-float(grid.x))/float(grid.step),0,float(grid.size)-1.001)
	var gz: float = clampf((z-float(grid.z))/float(grid.step),0,float(grid.size)-1.001)
	var ix := int(gx); var iz := int(gz); var size := int(grid.size)
	return lerpf(lerpf(heights[iz*size+ix],heights[iz*size+ix+1],gx-ix),lerpf(heights[(iz+1)*size+ix],heights[(iz+1)*size+ix+1],gx-ix),gz-iz)
func is_runway(x: float,z: float) -> bool: return absf(x)<30.4 and absf(z)<1800
func obstacle_collision(_at: Vector3,_radius: float=2.0) -> bool: return false

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
