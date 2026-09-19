extends "res://scenes/world.gd"
var elevation_samples:=PackedFloat32Array()
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
	water.shader=load("res://assets/environment/water.gdshader")
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
	env.glow_intensity=0.18
	env.fog_density=0.000035
	env.fog_aerial_perspective=0.55
	env.fog_light_color=Color(0.56,0.65,0.70)
	_sun.shadow_bias=0.06
	_sun.shadow_normal_bias=1.2
	_sun.directional_shadow_max_distance=3500
	if preset=="golden":
		_sun.rotation_degrees=Vector3(-24,-68,0)
		_sun.light_color=Color(1.0,0.88,0.72)
		_sun.light_energy=1.8
		env.ambient_light_energy=0.24
		env.tonemap_exposure=0.95

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
		if absf(x)<1250 and minf(absf(z),absf(z+15000))<2550: continue
		if x>1150 and x<3250 and z> -7550 and z< -3450: continue
		var size: float=_rng.randf_range(1.2,2.0)
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
	material.alpha_scissor_threshold=0.025
	material.billboard_mode=BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(0.66,0.74,0.69)
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
	material.alpha_scissor_threshold=0.025
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
