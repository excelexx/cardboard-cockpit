extends "res://scenes/coastal_base_world.gd"
var elevation_samples:=PackedFloat32Array()
const VILLAGES: Array[Vector2]=[Vector2(1750,-2650),Vector2(2050,-8450),Vector2(1900,-10200),Vector2(2150,-12300),Vector2(2100,-1450)]
var village_home_count: int=0

func _in_settlement(x: float,z: float) -> bool:
	for center in VILLAGES:
		if Vector2((x-center.x)/245.0,(z-center.y-50)/280.0).length()<1: return true
	return false

func _build_countryside() -> void:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/kominka/layout.json"))
	var prototype:=Node3D.new()
	add_child(prototype)
	var modules: Dictionary={}
	for item in layout.instances:
		if item.group=="Furnishings": continue
		if item.id in ["ceiling","tatami","floor_wood","fusuma"]: continue
		var path: String="res://assets/kominka/"+str(item.id)+".gltf"
		if not modules.has(path): modules[path]=load(path)
		var model: Node3D=modules[path].instantiate()
		prototype.add_child(model)
		model.position=Vector3(item.position[0],item.position[1],item.position[2])
		model.rotation.y=deg_to_rad(float(item.rotation_y_degrees))
		model.scale=Vector3.ONE*float(item.scale)
	var flattened:=Node3D.new()
	add_child(flattened)
	var shared_materials: Dictionary={}
	for mesh in prototype.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var part:=MeshInstance3D.new()
			var geometry:=ArrayMesh.new()
			geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.mesh.surface_get_arrays(surface))
			part.mesh=geometry
			part.material_override=mesh.get_active_material(surface)
			var material: StandardMaterial3D=part.material_override as StandardMaterial3D
			if material!=null:
				var key: String=str(material.albedo_color)+str(material.roughness)+str(material.metallic)
				for texture in [material.albedo_texture,material.normal_texture,material.orm_texture]:
					key+="|"+(texture.resource_path if texture!=null else "none")
				if not shared_materials.has(key): shared_materials[key]=material
				part.material_override=shared_materials[key]
			part.transform=global_transform.affine_inverse()*mesh.global_transform
			flattened.add_child(part)
	_batch_static_geometry(flattened)
	prototype.free()
	var scenery:=Node3D.new()
	scenery.name="KominkaCoastalVillages"
	add_child(scenery)
	var road: Material=_mat("country_lane",Color(0.22,0.23,0.20))
	var foundation: Material=_mat("village_stone",Color(0.36,0.38,0.32))
	for i in range(3):
		var crop:=_mat("crop"+str(i),[Color(0.30,0.48,0.19),Color(0.52,0.48,0.25),Color(0.38,0.27,0.17)][i])
		crop.albedo_texture=load("res://assets/environment/aerial_grass_rock_diff_1k.jpg")
		crop.uv1_triplanar=true
		crop.uv1_scale=Vector3.ONE*0.08
	for center in VILLAGES:
		var placements: Array[Transform3D]=[]
		for row in range(3):
			for col in range(4):
				var x: float=center.x+(col-1.5)*54+sin(row*1.4)*9
				var z: float=center.y+(row-1)*70+sin(col*0.9)*8
				var height: float=ground_height(x,z)
				for dx in [-19.0,19.0]:
					for dz in [-19.0,19.0]: height=maxf(height,ground_height(x+dx,z+dz))
				if height<0: continue
				var angle: float=PI if row==2 else 0.0
				placements.append(Transform3D(Basis(Vector3.UP,angle).scaled(Vector3.ONE*2.0),Vector3(x,height+0.25,z)))
				village_home_count+=1
				_box(scenery,"TerracedFoundation",Vector3(x,height-1.0,z),Vector3(36,2.5,34),foundation)
				_airport_obstacles.append(AABB(Vector3(x-18,height,z-17),Vector3(36,12,34)))
		for part in flattened.get_children():
			var multi:=MultiMesh.new()
			multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=part.mesh
			multi.instance_count=placements.size()
			for i in placements.size(): multi.set_instance_transform(i,placements[i]*part.transform)
			var batch:=MultiMeshInstance3D.new()
			batch.multimesh=multi
			batch.material_override=part.material_override
			batch.visibility_range_end=4500
			scenery.add_child(batch)
		# Fine road segments follow the actual terrain instead of intersecting it.
		for i in range(30):
			var x: float=center.x-180+i*12
			var z: float=center.y+38
			_box(scenery,"VillageLane",Vector3(x,ground_height(x,z)+0.2,z),Vector3(12.2,0.35,8),road)
		# Patchwork fields, separated by banks, at the edges of each settlement.
		for field in range(6):
			var x: float=center.x-180+field*65
			for strip in range(12):
				var z: float=center.y+155+strip*6
				var shade: Color=[Color(0.19,0.27,0.10),Color(0.30,0.32,0.13),Color(0.25,0.19,0.10)][field%3]
				_box(scenery,"CropRows",Vector3(x,ground_height(x,z)+0.16,z),Vector3(56,0.25,5.3),_mat("crop"+str(field%3),shade))
	_batch_static_geometry(scenery)
	flattened.free()
	print("COASTAL VILLAGES: ",village_home_count," modular homes")
## Fictional Pacific coast: a maritime airbase, inhabited headland and islands.
func build() -> void:
	if _built: return
	_built=true
	_load_elevation()
	name="AzureCoast"
	_build_atmosphere()
	_sun.shadow_bias=0.12
	_sun.shadow_normal_bias=2.5
	_build_terrain()
	var terrain: MeshInstance3D=get_node("AlpineTerrain")
	terrain.material_override.set_shader_parameter("rock_texture",load("res://assets/environment/aerial_rocks_02_diff_2k.jpg"))
	terrain.material_override.set_shader_parameter("rock_normal",load("res://assets/environment/aerial_rocks_02_nor_gl_2k.jpg"))
	terrain.material_override.set_shader_parameter("shore_texture",load("res://assets/environment/coast_sand_rocks_02_diff_2k.jpg"))
	var sea:=MeshInstance3D.new()
	sea.name="PacificOcean"
	var plane:=PlaneMesh.new()
	plane.size=Vector2(65000,65000)
	sea.mesh=plane
	sea.position=Vector3(0,-8.5,-7500)
	var water:=ShaderMaterial.new()
	water.shader=load("res://assets/environment/coastal/water.gdshader")
	sea.material_override=water
	add_child(sea)
	_build_airport(0,"AZURE AIR STATION","36","18")
	_build_airport(-15000,"CAPE NORTH","36","18")
	metropolis=load("res://scenes/coastal_city.gd").new()
	add_child(metropolis)
	metropolis.build(self)
	_airbase_activity()
	_coastal_forest()
	_shore_details()
	_build_countryside()
	# The photographic HDR sky already contains natural clouds; avoid overlaying
	# the old flat, repeating cloud cards on top of it.
	set_conditions(_condition_id)

func _airbase_activity() -> void:
	var parking:=Node3D.new()
	parking.name="AirbaseGroundActivity"
	add_child(parking)
	var aircraft_scene: PackedScene=load("res://assets/aircraft/f35/f35.tscn")
	var prototype: Node3D=aircraft_scene.instantiate()
	parking.add_child(prototype)
	var flattened:=Node3D.new()
	parking.add_child(flattened)
	for source in prototype.find_children("*","MeshInstance3D",true,false):
		for surface in range(source.mesh.get_surface_count()):
			var part:=MeshInstance3D.new()
			var mesh:=ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.mesh.surface_get_arrays(surface))
			part.mesh=mesh
			part.material_override=source.get_active_material(surface)
			part.transform=parking.global_transform.affine_inverse()*source.global_transform
			flattened.add_child(part)
	_batch_static_geometry(flattened)
	for airport_z in [0.0,-15000.0]:
		for part in flattened.get_children():
			var multi:=MultiMesh.new()
			multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.mesh=part.mesh
			multi.instance_count=6
			for i in range(6): multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,PI/2),Vector3(450,3.03,airport_z+110+i*145))*part.transform)
			var batch:=MultiMeshInstance3D.new()
			batch.multimesh=multi
			batch.material_override=part.material_override
			batch.visibility_range_end=2500
			parking.add_child(batch)
		for i in range(6):
			_airport_obstacles.append(AABB(Vector3(440,0,airport_z+103+i*145),Vector3(20,6,14)))
	prototype.free()
	flattened.free()

func set_conditions(preset: String) -> void:
	super.set_conditions(preset)
	if _environment==null: return
	var env: Environment=_environment.environment
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.tonemap_exposure=1.0
	env.ssao_enabled=true
	env.ssao_radius=3.0
	env.ssao_intensity=1.4
	env.ssil_enabled=false
	env.ssil_radius=5.0
	env.ssil_intensity=0.55
	env.ssr_enabled=false
	env.glow_enabled=true
	env.glow_intensity=0.30
	env.fog_density=0.000065
	env.fog_aerial_perspective=0.55
	env.fog_light_color=Color(0.62,0.71,0.75)
	_sun.shadow_bias=0.06
	_sun.shadow_normal_bias=1.2
	_sun.directional_shadow_max_distance=3500
	if preset=="golden":
		_sun.rotation_degrees=Vector3(-24,-68,0)
		_sun.light_color=Color(1.0,0.88,0.72)
		_sun.light_energy=1.8
		env.ambient_light_energy=0.36
		env.tonemap_exposure=0.95
		env.fog_light_color=Color(0.78,0.72,0.61)

func coast_x(z: float) -> float:
	return 1050+sin(z*0.0007)*220+sin(z*0.0016)*95

func _load_elevation() -> void:
	if not elevation_samples.is_empty(): return
	elevation_samples.resize(256*512)
	for tile in range(2):
		var texture: Texture2D=load("res://assets/environment/"+("rainier_terrarium.png" if tile==0 else "rainier_south_terrarium.png"))
		var data: Image=texture.get_image()
		if data.is_compressed(): data.decompress()
		for y in range(256):
			for x in range(256):
				var c: Color=data.get_pixel(x,y)
				elevation_samples[(tile*256+y)*256+x]=c.r*65280.0+c.g*255.0+c.b*255.0/256.0-32768.0

func _mountain_height(x: float,z: float) -> float:
	# Real eroded ridgelines from USGS/Mapzen elevation, rescaled and relocated
	# into this fictional coast. Never used as real-world navigation geography.
	if elevation_samples.is_empty(): _load_elevation()
	var u: float=clampf((x-1800.0)/14000.0*255.0,0,254.999)
	var v: float=clampf((z+22000.0)/34000.0*511.0,0,510.999)
	var column: int=floori(u)
	var row: int=floori(v)
	return lerpf(lerpf(elevation_samples[row*256+column],elevation_samples[row*256+column+1],u-column),lerpf(elevation_samples[(row+1)*256+column],elevation_samples[(row+1)*256+column+1],u-column),v-row)*0.74

func _terrain_height(x: float,z: float) -> float:
	var broad: float=_noise.get_noise_2d(x,z)
	var detail: float=_detail_noise.get_noise_2d(x,z)
	var shore: float=x-coast_x(z)
	var mainland: float=lerpf(-45,12,_smooth(-130,100,shore))
	mainland+=_smooth(1500,4800,shore)*_mountain_height(x,z)
	var h: float=mainland
	# Airfield headlands have long beaches and flat runway surfaces.
	for airport_z in [0.0,-15000.0]:
		var r: float=Vector2((x-100)/1450,(z-airport_z)/2350).length()
		h=maxf(h,lerpf(0,-45,_smooth(0.78,1.13,r)))
	# Irregular wooded islands frame a navigable channel instead of a valley wall.
	for island in [Vector4(-2900,-8500,1250,420),Vector4(-4500,-5100,1400,270),Vector4(-1300,-10800,850,150),Vector4(-800,-7700,520,105),Vector4(-4700,-12500,1500,520)]:
		var r: float=Vector2((x-island.x)/island.z,(z-island.y)/(island.z*1.3)).length()+detail*0.12
		var mound: float=pow(maxf(0,1-r),1.7)*island.w
		var edge: float=lerpf(4,-45,_smooth(0.90,1.12,r))
		h=maxf(h,edge+mound+detail*8*(1-_smooth(0.6,1.1,r)))
	# Recess the complete airfield, not just its runway centerline. All airport
	# meshes were authored around elevation zero; coast terrain must respect it.
	var city_pad: float=(1.0-_smooth(1100,1300,absf(x-2200)))*(1.0-_smooth(2200,2450,absf(z+5500)))
	h=lerpf(h,11.5,city_pad)
	for airport_z in [0.0,-15000.0]:
		var pad: float=(1.0-_smooth(1050,1350,absf(x-250)))*(1.0-_smooth(2050,2350,absf(z-airport_z)))
		h=lerpf(h,-0.35,pad)
	return h

func _coastal_forest() -> void:
	var chunks: Dictionary={}
	var meshes: Array[Mesh]=[]
	for variant in range(3): meshes.append(_fir_mesh(variant))
	_rng.seed=44092
	for i in range(850000):
		var x: float=_rng.randf_range(-6500,9400)
		var z: float=_rng.randf_range(-20000,3200)
		var h: float=ground_height(x,z)
		if h<8 or h>1750: continue
		# Broad groves and natural openings replace evenly peppered hillsides.
		var grove: float=_noise.get_noise_2d(x*1.6+700,z*1.6-400)
		if grove< -0.12: continue
		if absf(x)<1250 and minf(absf(z),absf(z+15000))<2550: continue
		if x>1150 and x<3250 and z> -7550 and z< -3450: continue
		# Leave deliberate clearings for villages, meadows and their access lanes.
		if _in_settlement(x,z): continue
		var size: float=_rng.randf_range(0.95,1.6)
		var key:=Vector3i(floori(x/900),floori(z/900),i%3)
		if not chunks.has(key): chunks[key]=[]
		chunks[key].append(Transform3D(Basis(Vector3.UP,_rng.randf()*TAU).scaled(Vector3(size*0.85,size,size*0.85)),Vector3(x,h-0.4,z)))
	var forest:=Node3D.new()
	forest.name="CoastalWoodland"
	add_child(forest)
	for key in chunks:
		var transforms: Array=chunks[key]
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=meshes[key.z]
		multi.instance_count=transforms.size()
		for i in range(transforms.size()): multi.set_instance_transform(i,transforms[i])
		var tile:=MultiMeshInstance3D.new()
		tile.multimesh=multi
		tile.visibility_range_end=8000
		tile.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		forest.add_child(tile)

func _fir_mesh(variant: int) -> Mesh:
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(10,20)
	mesh.center_offset=Vector3(0,10,0)
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/nature/fir_%d.png"%variant)
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold=0.12
	material.billboard_mode=BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(0.95,1.0,0.94)
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material=material
	return mesh

func _conifer_mesh() -> Mesh:
	# A photographed silhouette baked from the full-resolution CC0 tree.
	# Close waterfront trees retain their 3D PBR model; distant woods use two triangles.
	var mesh:=QuadMesh.new()
	mesh.size=Vector2(13,17)
	mesh.center_offset=Vector3(0,7.2,0)
	var material:=StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/nature/tree_impostor.png")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold=0.12
	material.billboard_mode=BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(0.7,0.78,0.7)
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material=material
	return mesh
func _shore_details() -> void:
	var details:=Node3D.new()
	details.name="CoastalLandmarks"
	add_child(details)
	for point in [Vector2(-1200,-7900),Vector2(-850,-11300)]:
		var h: float=ground_height(point.x,point.y)
		_cylinder(details,"Lighthouse",Vector3(point.x,h+20,point.y),5,40,_mat("lighthouse_white",Color(0.86,0.83,0.71)),3.7)
		_cylinder(details,"Lantern",Vector3(point.x,h+42,point.y),5,5,_mat("lantern",Color(0.30,0.38,0.37)),5)
		_cylinder(details,"LighthouseCap",Vector3(point.x,h+47,point.y),6,5,_mat("cap",Color(0.28,0.13,0.10)),0)
	# Rocky shore outcrops, each settled into the terrain rather than floating.
	var source: Node=load("res://assets/nature/coast_land_rocks_04.glb").instantiate()
	var rock_mesh: Mesh=(source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
	for i in range(150):
		var z: float=-2400-i*70
		var x: float=coast_x(z)-70+sin(i*2.3)*55
		var rock:=MeshInstance3D.new()
		rock.mesh=rock_mesh
		rock.scale=Vector3(3+_rng.randf()*4,7+_rng.randf()*5,3+_rng.randf()*4)
		rock.rotation.y=_rng.randf()*TAU
		rock.position=Vector3(x,ground_height(x,z)-0.4,z)
		details.add_child(rock)
	# Preserve the scan's separate PBR surfaces; share its mesh between instances.
	source.free()

func cloud_immersion(_at: Vector3) -> float: return 0.0

func apply_quality(high: bool) -> void:
	if _environment==null: return
	_environment.environment.ssao_enabled=high
	_sun.directional_shadow_max_distance=3500 if high else 2000
