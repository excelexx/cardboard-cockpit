extends "res://scenes/metropolitan_world.gd"
var distant_tree_mesh: Mesh
var photo_tiles: int=0
var photo_detail_tiles: int=0
var photo_lod_groups: Dictionary={}
var lod_clock: float=0.0
## Composed waterfront districts, oriented to their roads rather than a world grid.
func build(owner_world: Node3D) -> void:
	world=owner_world
	name="AzureWaterfront"
	rng.seed=57229
	unit_box.size=Vector3.ONE
	_build_materials()
	var paving: StandardMaterial3D=materials.paving
	paving.albedo_texture=load("res://assets/environment/aerial_asphalt_01_diff_2k.jpg")
	paving.uv1_triplanar=true
	paving.uv1_scale=Vector3.ONE*0.07
	paving.normal_enabled=true
	paving.normal_texture=load("res://assets/environment/aerial_asphalt_01_nor_gl_2k.jpg")
	paving.normal_scale=0.45
	# Restrained coastal stone and concrete, rather than saturated orange blocks.
	for i in range(6):
		materials["facade%d"%i].albedo_color=[Color(0.68,0.69,0.67),Color(0.49,0.48,0.45),Color(0.78,0.75,0.68),Color(0.47,0.43,0.39),Color(0.62,0.65,0.63),Color(0.50,0.55,0.56)][i]
	tree_mesh=_natural_tree()
	distant_tree_mesh=world._conifer_mesh()
	car_mesh=_merge(_car())
	if FileAccess.file_exists("res://assets/photogrammetry/helsinki/manifest.json"):
		_build_photographic_district()
		_district_edges()
		_marina()
		_port()
		_bridge()
		_flush()
		for root in kit_roots: root.free()
		kit_roots.clear()
		print("PHOTOGRAPHIC CITY: ",photo_tiles," source tiles")
		return
	_load_kit("apartments","modular_urban_apartments_facade",["wall_window_centered_large_01","window_centered_large_01"])
	_load_kit("factory","modular_factory_facade",["wall_window_centered_large_01","window_centered_large_01"])
	for i in range(6): house_meshes.append(_merge(_house(i)))
	for i in range(4): apartment_meshes.append(_merge(_apartment(i)))
	for i in range(4): tower_meshes.append(_merge(_tower(i)))
	_urban_ground()
	# Follow the shoreline with a continuous promenade and three curving avenues.
	for avenue in range(4):
		var last:=Vector2.ZERO
		for j in range(65):
			var z: float=-2500-j*78
			var p:=Vector2(world.coast_x(z)+150+avenue*220,z)
			if j>0: _road(last,p,10 if avenue==0 else 19)
			last=p
			if j%2==0:
				for side in [-1,1]:
					_tree_at(p+Vector2(side*19,0),1.5)
			if avenue==0 or j%2!=0: continue
			var angle: float=atan2(world.coast_x(z-30)-world.coast_x(z+30),-60)
			for side in [-1,1]:
				var lot: Vector2=p+Vector2(side*65,rng.randf_range(-16,16))
				var index: int=rng.randi_range(0,3)
				var downtown: bool=absf(z+4900)<640 and avenue<3 and (j+avenue)%3!=0
				var mesh: Mesh=tower_meshes[index] if downtown else apartment_meshes[index]
				var key: String=("tower" if downtown else "apartment")+str(index)
				var at: Vector3=_ground(lot,0.7)
				var skyline_weight: float=1.0-smoothstep(0.0,700.0,absf(z+4900))
				var height_scale: float=rng.randf_range(0.7,1.15)*(1.0+skyline_weight*0.65) if downtown else rng.randf_range(0.8,1.15)
				var footprint: float=rng.randf_range(1.0,1.45) if downtown else rng.randf_range(1.6,2.1)
				_put(key,mesh,at,Vector3(footprint,height_scale,footprint),angle)
				_solid("plaza",at-Vector3(0,0.4,0),Vector3(88,0.6,72),materials.paving,angle)
				if downtown:
					_solid("retail_podium",at+Vector3(0,4,0),Vector3(76,8,61),materials["facade2"],angle)
				_register_obstacle(AABB(at-Vector3(44,0,44),Vector3(88,260 if downtown else 60,88)))
				stats.buildings+=1
				_put("parked_car",car_mesh,at+Vector3(30,0,-24),Vector3.ONE,angle)
				stats.cars+=1
				# A street block includes side wings and a planted inner court.
				# These are attached buildings, not hundreds of isolated towers.
				if not downtown:
					for wing in [-1,1]:
						_put("apartment"+str(index),apartment_meshes[index],at+Basis(Vector3.UP,angle)*Vector3(wing*24,0,23),Vector3(0.48,height_scale*0.65,2.0),angle)
					for tree in range(3): _tree_at(lot+Vector2(-12+tree*12,24),1.5)
	# Cross streets connect the avenues; neighbourhoods follow sloping contours.
	for j in range(11):
		var z: float=-2850-j*410
		_road(Vector2(world.coast_x(z)+130,z),Vector2(world.coast_x(z)+1160,z+130),15)
		for i in range(11):
			var lot:=Vector2(world.coast_x(z)+860+i*43,z+120+sin(i*0.42)*90)
			var index: int=(i+j)%6
			_put("house"+str(index),house_meshes[index],_ground(lot,0.3),Vector3.ONE,-0.15)
			stats.buildings+=1
			_tree_at(lot+Vector2(-13,20),1.5)
	# Human-scale imported architecture anchors the waterfront, not distant filler.
	for i in range(12):
		var z: float=-3200-i*255
		_detailed_building(Vector2(world.coast_x(z)+85,z),"apartments",4+i%3)
	_marina()
	_port()
	_bridge()
	_flush()
	for root in kit_roots: root.free()
	kit_roots.clear()
	print("COASTAL CITY: ",stats)

func _build_photographic_district() -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/photogrammetry/helsinki/manifest.json"))
	var folder: String="res://assets/photogrammetry/helsinki/lod16"
	for file: String in manifest.lod16:
		var detail_file: String=file.replace("_L16_000","_L17_0000")
		var detailed: bool=ResourceLoader.exists("res://assets/photogrammetry/helsinki/lod17/"+detail_file)
		var tile: Node3D=_add_photo_tile(folder+"/"+file,false)
		if detailed:
			var mesh: MeshInstance3D=tile.find_children("*","MeshInstance3D",true,false)[0]
			photo_lod_groups[file.get_slice("_L16_",0)]={"low":tile,"high":[],"center":mesh.global_transform*mesh.get_aabb().get_center(),"detailed":false}
		photo_tiles+=1
	folder="res://assets/photogrammetry/helsinki/lod17"
	for file: String in manifest.lod17:
		var tile: Node3D=_add_photo_tile(folder+"/"+file,true)
		tile.visible=false
		photo_lod_groups[file.get_slice("_L17_",0)].high.append(tile)
		photo_detail_tiles+=1

func _process(delta: float) -> void:
	lod_clock-=delta
	if lod_clock>0: return
	lod_clock=0.1
	var camera: Camera3D=get_viewport().get_camera_3d()
	if camera==null: return
	for group in photo_lod_groups.values():
		var detailed: bool=camera.global_position.distance_to(group.center)<(1900 if group.detailed else 1700)
		if detailed==group.detailed: continue
		group.detailed=detailed
		group.low.visible=not detailed
		for tile in group.high: tile.visible=detailed

func _add_photo_tile(path: String,detail: bool) -> Node3D:
		var scene: PackedScene=load(path)
		assert(scene!=null,"Photogrammetry must be imported before running the demo")
		var tile: Node3D=scene.instantiate()
		tile.set_meta("photogrammetry_base",not detail)
		tile.rotation.x=-PI/2
		tile.position=Vector3(-4800,12,500)
		add_child(tile)
		for mesh in tile.find_children("*","MeshInstance3D",true,false):
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for surface in range(mesh.mesh.get_surface_count()):
				var material: StandardMaterial3D=mesh.mesh.surface_get_material(surface)
				if material:
					# Aerial imagery already contains diffuse lighting and shadows.
					material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
					material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var bounds: AABB=global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
			if not detail: _register_obstacle(bounds)
		return tile

func _natural_tree() -> Mesh:
	var asset: Node=load("res://assets/nature/tree_small_02.glb").instantiate()
	var source: Mesh=(asset.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
	var mesh:=ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(source,surface,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*2.7),Vector3.ZERO))
		st.set_material(source.surface_get_material(surface))
		st.commit(mesh)
	asset.free()
	return mesh

func _district_edges() -> void:
	# Wooded edges hide cropped source blocks and connect the city to the coast.
	for i in range(145):
		var z: float=-3470-i*28
		for side in [0,1]:
			var x: float=1130 if side==0 else 3250
			for row in range(3):
				_tree_at(Vector2(x+row*17+rng.randf_range(-9,9),z+rng.randf_range(-12,12)),rng.randf_range(1.8,2.6))
	for end_z in [-3430,-7570]:
		for i in range(77):
			for row in range(3):
				_tree_at(Vector2(1140+i*28+rng.randf_range(-10,10),end_z+row*18+rng.randf_range(-8,8)),rng.randf_range(1.8,2.6))
	var previous:=Vector2.ZERO
	for i in range(105):
		var z: float=-3400-i*40
		var p:=Vector2(minf(world.coast_x(z)+65,1100),z)
		if i>0: _road(previous,p,12)
		previous=p

func _tree_at(at: Vector2,size: float) -> void:
	if world.ground_height(at.x,at.y)<-2: return
	var detailed: bool=stats.trees%8==0
	_put("avenue_tree" if detailed else "street_tree_impostor",tree_mesh if detailed else distant_tree_mesh,_ground(at),Vector3.ONE*size*(1.0 if detailed else 0.8),rng.randf()*TAU)
	stats.trees+=1

func _urban_ground() -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(160):
		var z: float=-2530-j*32
		for column in range(43):
			var corners: Array[Vector3]=[]
			for uv in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
				var zz: float=z-uv.y*32
				var xx: float=world.coast_x(zz)+45+(column+uv.x)*32
				corners.append(Vector3(xx,world.ground_height(xx,zz)+0.18,zz))
			for index in [0,2,1,1,2,3]: st.add_vertex(corners[index])
	st.generate_normals()
	var ground:=MeshInstance3D.new()
	ground.name="WaterfrontUrbanGround"
	ground.mesh=st.commit()
	var urban: StandardMaterial3D=materials.paving.duplicate()
	# The district sits in coastal parkland, not one five-kilometre parking lot.
	# Asphalt belongs to roads and individual paved lots only.
	urban.albedo_texture=load("res://assets/environment/aerial_grass_rock_diff_1k.jpg")
	urban.albedo_color=Color(0.45,0.55,0.32)
	urban.uv1_scale=Vector3.ONE/45.0
	urban.normal_enabled=false
	ground.material_override=urban
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# Planted courtyards break up the hardscape between the street-facing blocks.
	for j in range(30):
		var z: float=-2670-j*160
		for avenue in range(3):
			var x: float=world.coast_x(z)+340+avenue*220
			_solid("courtyard",_ground(Vector2(x,z),0.28),Vector3(70,0.12,65),materials.park)
			for tree in range(7):
				_tree_at(Vector2(x+rng.randf_range(-28,28),z+rng.randf_range(-25,25)),rng.randf_range(1.4,2.4))

func _marina() -> void:
	var x: float=world.coast_x(-3800)
	_solid("seawall",Vector3(x-20,-3,-3800),Vector3(25,13,660),materials.paving)
	for i in range(8):
		var z: float=-3540-i*70
		_solid("marina_pier",Vector3(x-135,-6,z),Vector3(240,1.4,6),materials.roof)
		for j in range(7):
			var at:=Vector3(x-65-j*26,-7,z+13)
			_solid("yacht_hull",at,Vector3(5,2,16),materials.marking)
			_solid("yacht_cabin",at+Vector3(0,1.8,0),Vector3(3.8,1.8,6),materials.glass)
			_solid("yacht_mast",at+Vector3(0,10,0),Vector3(0.16,20,0.16),materials.metal)
	for i in range(18): _tree_at(Vector2(x+22,-3500-i*32),1.7)

func _port() -> void:
	var x: float=world.coast_x(-6600)
	_solid("port_quay",Vector3(x-50,2,-6600),Vector3(280,24,660),materials.paving)
	for i in range(5):
		var z: float=-6400-i*90
		_solid("crane_leg",Vector3(x-130,30,z),Vector3(5,60,5),materials.metal)
		_solid("crane_boom",Vector3(x-175,61,z),Vector3(140,4,5),materials.metal)
		_solid("crane_cable",Vector3(x-225,42,z),Vector3(0.4,40,0.4),materials.roof)
		for j in range(5):
			_solid("container"+str(j%3),Vector3(x+j*17,18.5,z),Vector3(12,9,25),materials["tile%d"%(j%6)])
		if photo_tiles==0: _detailed_building(Vector2(x+190,z),"factory",3)
	# Ferry: hull, passenger decks, windows, funnel, and a tapered wake.
	var at:=Vector3(x-490,-7,-6650)
	_solid("ferry_hull",at,Vector3(26,8,115),materials.marking)
	_solid("ferry_deck",at+Vector3(0,8,0),Vector3(23,8,85),materials.glass)
	_solid("ferry_roof",at+Vector3(0,13,0),Vector3(24,2,87),materials.marking)
	_solid("ferry_funnel",at+Vector3(0,19,22),Vector3(8,12,9),materials["tile0"])

func _bridge() -> void:
	var end_x: float=world.coast_x(-7700)+130
	var start_x: float=-1250
	var length: float=end_x-start_x
	var center: float=(end_x+start_x)/2
	_solid("suspension_deck",Vector3(center,85,-7700),Vector3(length,7,24),materials.road)
	for x in [start_x+length*0.22,start_x+length*0.78]:
		for side in [-1,1]:
			_solid("bridge_tower",Vector3(x,86,-7700+side*17),Vector3(13,190,12),materials["tile0"])
		_solid("bridge_crossbeam",Vector3(x,160,-7700),Vector3(16,12,46),materials["tile0"])
	for i in range(100):
		var x: float=start_x+i*length/99
		var t: float=float(i)/99
		var y: float=_suspension_height(t)
		for side in [-1,1]:
			if i<99:
				var a:=Vector3(x,y,-7700+side*15)
				var b:=Vector3(x+length/99,_suspension_height(float(i+1)/99),a.z)
				var segment:=MeshInstance3D.new()
				segment.mesh=unit_box
				segment.material_override=materials.roof
				var direction: Vector3=(b-a).normalized()
				var horizontal: Vector3=direction.cross(Vector3.FORWARD).normalized()
				segment.transform=Transform3D(Basis(horizontal,direction,horizontal.cross(direction)).scaled(Vector3(1.1,a.distance_to(b),1.1)),(a+b)/2)
				add_child(segment)
			_solid("bridge_hanger",Vector3(x,(y+89)/2,-7700+side*15),Vector3(0.6,y-89,0.6),materials.metal)
	world._batch_static_geometry(self)
	_register_obstacle(AABB(Vector3(start_x,78,-7725),Vector3(length,105,50)))

func _suspension_height(t: float) -> float:
	if t<0.22: return lerpf(91,180,t/0.22)
	if t>0.78: return lerpf(180,91,(t-0.78)/0.22)
	return 102+78*pow((t-0.5)/0.28,2)
