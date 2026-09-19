extends Node3D
## Deterministic, chunk-instanced city. Downloaded facade parts are used close to
## the route; modest geometric buildings carry the wider urban fabric.
var world: Node3D
var rng := RandomNumberGenerator.new()
var batches: Dictionary = {}
var obstacles: Dictionary = {}
var stats := {"buildings":0,"trees":0,"roads_km":0.0,"detailed_buildings":0,"cars":0}
var house_meshes: Array[Mesh] = []
var apartment_meshes: Array[Mesh] = []
var tower_meshes: Array[Mesh] = []
var materials: Dictionary = {}
var tree_mesh: Mesh
var car_mesh: Mesh
var tile_meshes: Dictionary = {}
var kit_roots: Array[Node] = []
var unit_box := BoxMesh.new()

func build(owner_world: Node3D) -> void:
	world=owner_world
	name="NorthstarMetropolitanRegion"
	rng.seed=612907
	unit_box.size=Vector3.ONE
	_build_materials()
	_load_kit("apartments","modular_urban_apartments_facade",["wall_window_centered_large_01","window_centered_large_01"])
	_load_kit("factory","modular_factory_facade",["wall_window_centered_large_01","window_centered_large_01"])
	for i in range(6): house_meshes.append(_merge(_house(i)))
	for i in range(4): apartment_meshes.append(_merge(_apartment(i)))
	for i in range(4): tower_meshes.append(_merge(_tower(i)))
	tree_mesh=_merge(_tree())
	car_mesh=_merge(_car())
	# A continuous city wraps the lake's eastern shore and the river.
	_district(Vector2(-2940,-7350),27,24,210.0,false)
	# Airport suburbs and the arrival-side satellite town retain runway clearance.
	_district(Vector2(1260,-2310),9,16,175.0,true)
	_district(Vector2(-2940,-12950),12,13,175.0,true)
	_district(Vector2(2100,-12800),7,12,175.0,true)
	_highway()
	_waterfront()
	_stadium(Vector2(-650,-3950))
	_flush()
	for kit in kit_roots: kit.free()
	kit_roots.clear()
	print("CITY BUILT: ",stats," batches=",get_child_count())

func _mat(key: String,color: Color,roughness: float=0.85) -> Material:
	var m:=StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=roughness
	materials[key]=m
	return m

func _build_materials() -> void:
	_mat("road",Color(0.105,0.12,0.13))
	_mat("paving",Color(0.45,0.44,0.40))
	_mat("marking",Color(0.78,0.76,0.63))
	_mat("roof",Color(0.24,0.25,0.25))
	_mat("glass",Color(0.10,0.18,0.23),0.22)
	_mat("metal",Color(0.47,0.50,0.50),0.4)
	_mat("park",Color(0.14,0.26,0.13))
	_mat("pitch",Color(0.12,0.30,0.17))
	_mat("bark",Color(0.17,0.14,0.10))
	for i in range(6):
		_mat("leaves%d"%i,Color(0.075,0.17,0.075).lerp(Color(0.23,0.31,0.12),i/5.0))
		_mat("tile%d"%i,[Color(0.26,0.16,0.12),Color(0.19,0.22,0.23),Color(0.39,0.27,0.19),Color(0.33,0.30,0.25),Color(0.18,0.20,0.19),Color(0.40,0.20,0.13)][i])
		var m:=StandardMaterial3D.new()
		m.albedo_texture=load("res://assets/city/modular_factory_facade/textures/modular_factory_facade_brick_diff_1k.jpg")
		if i%2==0:
			m.albedo_texture=load("res://assets/city/modular_urban_apartments_facade/textures/modular_urban_apartments_facade_plaster_diff_1k.jpg")
		m.albedo_color=[Color(0.70,0.63,0.53),Color(0.63,0.64,0.61),Color(0.80,0.76,0.64),Color(0.61,0.48,0.38),Color(0.76,0.72,0.65),Color(0.56,0.61,0.60)][i]
		m.uv1_triplanar=true
		m.uv1_scale=Vector3.ONE*0.15
		m.roughness=0.85
		materials["facade%d"%i]=m
	var tower:=StandardMaterial3D.new()
	tower.albedo_color=Color(0.13,0.24,0.29)
	tower.roughness=0.32
	tower.metallic=0.3
	materials["tower"]=tower

func _load_kit(key: String,asset: String,names: Array) -> void:
	var root: Node=load("res://assets/city/%s/%s_1k.gltf"%[asset,asset]).instantiate()
	kit_roots.append(root)
	var parts: Array[Mesh]=[]
	for part_name in names:
		var node: MeshInstance3D=root.find_child(part_name,true,false) as MeshInstance3D
		assert(node!=null,"Missing imported facade part: "+part_name)
		parts.append(node.mesh)
	tile_meshes[key]=parts

func _append(mesh: ArrayMesh,shape: Mesh,transform: Transform3D,material: Material) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(shape,0,transform)
	st.set_material(material)
	st.commit(mesh)

func _box(mesh: ArrayMesh,at: Vector3,size: Vector3,material: Material,angle: float=0) -> void:
	var box:=BoxMesh.new()
	box.size=size
	_append(mesh,box,Transform3D(Basis(Vector3.UP,angle),at),material)

func _house(index: int) -> Mesh:
	var mesh:=ArrayMesh.new()
	var width: float=12+index%3*3
	var depth: float=15+index%2*4
	var height: float=6.5+index%2*3
	_box(mesh,Vector3(0,height/2,0),Vector3(width,height,depth),materials["facade%d"%index])
	_windows(mesh,width,depth,height)
	# Continuous pitched roof with ridge, eaves, chimney and garage wing.
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float=width/2+0.8
	var d: float=depth/2+0.8
	var h: float=height+0.25
	var top: float=h+3.4
	for tri in [[Vector3(-w,h,-d),Vector3(0,top,-d),Vector3(-w,h,d)], [Vector3(-w,h,d),Vector3(0,top,-d),Vector3(0,top,d)], [Vector3(0,top,-d),Vector3(w,h,-d),Vector3(w,h,d)], [Vector3(0,top,-d),Vector3(w,h,d),Vector3(0,top,d)], [Vector3(-w,h,-d),Vector3(w,h,-d),Vector3(0,top,-d)], [Vector3(w,h,d),Vector3(-w,h,d),Vector3(0,top,d)]]:
		for p: Vector3 in tri: st.add_vertex(p)
	st.generate_normals()
	st.set_material(materials["tile%d"%index])
	st.commit(mesh)
	_box(mesh,Vector3(width*0.25,top,2),Vector3(1.2,2.7,1.2),materials["facade3"])
	_box(mesh,Vector3(width/2+2,2,1),Vector3(5,4,7),materials["facade%d"%index])
	_box(mesh,Vector3(width/2+2,4.2,1),Vector3(5.5,0.4,7.5),materials["roof"])
	return mesh

func _apartment(index: int) -> Mesh:
	var mesh:=ArrayMesh.new()
	var height: float=15+index*8
	_box(mesh,Vector3(0,height/2,0),Vector3(29,height,22),materials["facade%d"%index])
	_windows(mesh,29,22,height)
	_box(mesh,Vector3(0,height+0.6,0),Vector3(30.5,1.2,23.5),materials["roof"])
	for i in range(3): _box(mesh,Vector3(-8+i*8,height+2,3),Vector3(3.5,2,4),materials["metal"])
	for floor_index in range(1,3+index*2):
		_box(mesh,Vector3(0,floor_index*3.3,11.7),Vector3(26,0.3,2.4),materials["paving"])
	return mesh

func _tower(index: int) -> Mesh:
	var mesh:=ArrayMesh.new()
	var height: float=75+index*24
	_box(mesh,Vector3(0,7,0),Vector3(53,14,45),materials["facade1"])
	if index==1:
		var shaft:=CylinderMesh.new()
		shaft.top_radius=17
		shaft.bottom_radius=22
		shaft.height=height
		shaft.radial_segments=24
		_append(mesh,shaft,Transform3D(Basis.IDENTITY,Vector3(0,14+height/2,0)),materials.tower)
		for floor_index in range(1,int(height/4)):
			var ring:=CylinderMesh.new()
			ring.top_radius=22.25-5.0*(floor_index*4.0/height)
			ring.bottom_radius=ring.top_radius
			ring.height=0.25
			ring.radial_segments=24
			_append(mesh,ring,Transform3D(Basis.IDENTITY,Vector3(0,14+floor_index*4,0)),materials.metal)
		return mesh
	if index==2:
		for tier in range(4):
			var width: float=49-tier*8
			_box(mesh,Vector3(tier*2,14+tier*29+14.5,0),Vector3(width,29,33-tier*5),materials.tower)
			_box(mesh,Vector3(tier*2,14+(tier+1)*29,0),Vector3(width+1,1,34-tier*5),materials.roof)
		return mesh
	_box(mesh,Vector3(0,height/2+14,0),Vector3(32+index*3,height,29),materials["tower"])
	for floor_index in range(1,int(height/4)):
		_box(mesh,Vector3(0,14+floor_index*4,0),Vector3(32.3+index*3,0.22,29.3),materials.metal)
	for side in [-1,1]:
		for column in range(5):
			_box(mesh,Vector3(-12+column*6,height/2+14,side*14.7),Vector3(0.18,height,0.2),materials.metal)
	_box(mesh,Vector3(0,height+17,0),Vector3(25,6,21),materials["metal"])
	_box(mesh,Vector3(0,height+24,0),Vector3(0.7,15,0.7),materials["metal"])
	return mesh

func _windows(mesh: ArrayMesh,width: float,depth: float,height: float) -> void:
	for floor_index in range(1,int(height/3.3)):
		for side in [-1,1]:
			for column in range(int(width/4)):
				_box(mesh,Vector3(-width/2+2+column*4,floor_index*3.3,side*(depth/2+0.06)),Vector3(2.1,1.7,0.12),materials.glass)
			for column in range(int(depth/4)):
				_box(mesh,Vector3(side*(width/2+0.06),floor_index*3.3,-depth/2+2+column*4),Vector3(0.12,1.7,2.1),materials.glass)

func _tree() -> Mesh:
	var mesh:=ArrayMesh.new()
	var trunk:=CylinderMesh.new()
	trunk.top_radius=0.16
	trunk.bottom_radius=0.32
	trunk.height=7
	trunk.radial_segments=5
	_append(mesh,trunk,Transform3D(Basis.IDENTITY,Vector3(0,3.5,0)),materials.bark)
	for i in range(5):
		var crown:=SphereMesh.new()
		crown.radius=3.5 if i==0 else 2.6
		crown.height=crown.radius*1.6
		crown.radial_segments=8
		crown.rings=4
		var at:=Vector3(sin(i*2.4)*2.4,6.8+sin(i*1.3)*1.8,cos(i*2.4)*2.1)
		_append(mesh,crown,Transform3D(Basis.IDENTITY,at),materials["leaves2"])
	return mesh

func _car() -> Mesh:
	var mesh:=ArrayMesh.new()
	_box(mesh,Vector3(0,0.65,0),Vector3(1.8,0.9,4.3),materials.metal)
	_box(mesh,Vector3(0,1.3,-0.2),Vector3(1.6,0.6,2.1),materials.glass)
	return mesh

func _put(key: String,mesh: Mesh,at: Vector3,scale_value:=Vector3.ONE,angle: float=0,material: Material=null) -> void:
	var chunk:=Vector2i(floori(at.x/1890),floori(at.z/1890))
	var id: String=key+"_%d_%d"%[chunk.x,chunk.y]
	if not batches.has(id): batches[id]={"mesh":mesh,"material":material,"transforms":[]}
	batches[id].transforms.append(Transform3D(Basis(Vector3.UP,angle).scaled(scale_value),at))

func _solid(key: String,at: Vector3,size: Vector3,material: Material,angle: float=0) -> void:
	_put(key,unit_box,at,size,angle,material)

func _valid(at: Vector2) -> bool:
	var h: float=world.ground_height(at.x,at.y)
	if h< -2 or h>150: return false
	if absf(at.x-world._river_center(at.y))<235: return false
	if absf(at.x)<1180 and minf(absf(at.y),absf(at.y+15000))<2580: return false
	if at.x>570 and at.x<1290 and at.y> -7080 and at.y< -5480: return false
	if at.distance_to(Vector2(-650,-3950))<250: return false
	return true

func _ground(at: Vector2,offset: float=0) -> Vector3:
	return Vector3(at.x,world.ground_height(at.x,at.y)+offset,at.y)

func _district(origin: Vector2,columns: int,rows: int,spacing: float,suburb: bool) -> void:
	for x in range(columns+1): _road(origin+Vector2(x*spacing,0),origin+Vector2(x*spacing,rows*spacing),13.0)
	for z in range(rows+1): _road(origin+Vector2(0,z*spacing),origin+Vector2(columns*spacing,z*spacing),13.0)
	for x in range(columns):
		for z in range(rows):
			var center: Vector2=origin+Vector2((x+0.5)*spacing,(z+0.5)*spacing)
			if not _valid(center): continue
			var park: bool=(x*13+z*7)%19==0
			for u in range(4):
				for v in range(4):
					var lot: Vector2=center+Vector2((u-1.5)*spacing/4,(v-1.5)*spacing/4)
					if not _valid(lot): continue
					if park:
						_tree_at(lot,rng.randf_range(1.3,2.1))
						continue
					var downtown: bool=not suburb and lot.distance_to(Vector2(-150,-5600))<750
					var urban: bool=not suburb and lot.distance_to(Vector2(0,-5400))<1600
					var type_index: int=rng.randi_range(0,5)
					var size: Vector3=Vector3(22,15,24)
					var mesh: Mesh=house_meshes[type_index]
					var key: String="house%d"%type_index
					if downtown and (u+v)%3==0:
						if u%2==1 or v%2==1: continue
						type_index=rng.randi_range(0,3)
						mesh=tower_meshes[type_index]
						key="tower%d"%type_index
						size=Vector3(55,100+type_index*24,47)
					elif urban:
						type_index=rng.randi_range(0,3)
						mesh=apartment_meshes[type_index]
						key="apartment%d"%type_index
						size=Vector3(31,20+type_index*8,25)
					var h: float=world.ground_height(lot.x,lot.y)
					if absf(world.ground_height(lot.x+15,lot.y)-h)>4: continue
					var at: Vector3=_ground(lot,1.0)
					_solid("parcel",_ground(lot,0.3),Vector3(spacing/4-3,0.6,spacing/4-3),materials.paving)
					_put(key,mesh,at,Vector3.ONE,0 if (u+v)%2==0 else PI)
					_register_obstacle(AABB(at-Vector3(size.x/2,0,size.z/2),size))
					stats.buildings+=1
					_tree_at(lot+Vector2(-18,15),rng.randf_range(0.9,1.5))
					if rng.randf()>0.35:
						_put("parked_car",car_mesh,_ground(lot+Vector2(15,-17),0.8))
						stats.cars+=1
				# Imported close-up architecture on selected street-facing blocks.
			if not suburb and (x+z*3)%23==0:
				var location: Vector2=center+Vector2(0,spacing*0.35)
				if _valid(location): _detailed_building(location,"apartments",4)

func _tree_at(at: Vector2,size: float) -> void:
	if world.ground_height(at.x,at.y)< -2: return
	_put("avenue_tree",tree_mesh,_ground(at),Vector3.ONE*size,rng.randf()*TAU)
	stats.trees+=1

func _road(a: Vector2,b: Vector2,width: float) -> void:
	var distance: float=a.distance_to(b)
	var steps: int=ceili(distance/28.0)
	var direction: Vector2=(b-a).normalized()
	var side:=Vector2(-direction.y,direction.x)
	var road:=SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var valid_segments:=0
	for i in range(steps):
		var p: Vector2=a.lerp(b,float(i)/steps)
		var q: Vector2=a.lerp(b,float(i+1)/steps)
		if world.ground_height(p.x,p.y)>180: continue
		if absf(p.x)<1080 and minf(absf(p.y),absf(p.y+15000))<2200: continue
		# Bridge only the river; do not lay roads across the glacial lake.
		var river: bool=absf(p.x-world._river_center(p.y))<215
		if world.ground_height(p.x,p.y)< -2 and not river: continue
		var corners: Array[Vector3]=[]
		for point: Vector2 in [p-side*width/2,p+side*width/2,q-side*width/2,q+side*width/2]:
			corners.append(Vector3(point.x,maxf(world.ground_height(point.x,point.y)+0.55,2.0 if river else -100),point.y))
		for n in [0,2,1,1,2,3]: road.add_vertex(corners[n])
		valid_segments+=1
		if i%2==0 and not river:
			_solid("lane_marks",_ground(p,0.65),Vector3(0.22,0.02,7),materials.marking,atan2(direction.x,direction.y))
			if i%4==0:
				_tree_at(p+side*(width/2+6),1.3)
	if valid_segments==0: return
	road.generate_normals()
	var node:=MeshInstance3D.new()
	node.name="ConnectedStreet"
	node.mesh=road.commit()
	node.material_override=materials.road
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	stats.roads_km+=valid_segments*distance/steps/1000

func _detailed_building(at: Vector2,kit: String,floors: int) -> void:
	var origin: Vector3=_ground(at,1)
	var width: float=18
	var low: float=origin.y-1
	for corner in [Vector2(-10,-10),Vector2(-10,10),Vector2(10,-10),Vector2(10,10)]:
		var height: float=world.ground_height(at.x+corner.x,at.y+corner.y)
		origin.y=maxf(origin.y,height+0.15)
		low=minf(low,height)
	_solid("building_foundation",Vector3(at.x,(origin.y+low)/2,at.y),Vector3(20,maxf(0.3,origin.y-low),20),materials.paving)
	for side in range(4):
		var rotation:=Basis(Vector3.UP,side*PI/2)
		for floor_index in range(floors):
			for column in range(6):
				var offset: Vector3=rotation*Vector3(-width/2+(column+1)*3,floor_index*3,width/2)
				for mesh: Mesh in tile_meshes[kit]:
					_put("imported_%s_%d"%[kit,mesh.get_instance_id()],mesh,origin+offset,Vector3.ONE,side*PI/2)
	_solid("imported_roof",origin+Vector3(0,floors*3+0.2,0),Vector3(19,0.5,19),materials.roof)
	_register_obstacle(AABB(origin-Vector3(9,0,9),Vector3(18,floors*3+1,18)))
	stats.detailed_buildings+=1
	stats.buildings+=1

func _highway() -> void:
	# Eastern bypass joins the urban districts and both airport access networks.
	_road(Vector2(2700,1400),Vector2(2700,-14800),32)
	for z in [-1800,-4200,-6300,-11000,-12800]:
		_road(Vector2(-1200,z),Vector2(3000,z),24)
		for i in range(28):
			var theta: float=i*TAU/28
			var next: float=(i+1)*TAU/28
			_road(Vector2(2700+sin(theta)*110,z+cos(theta)*110),Vector2(2700+sin(next)*110,z+cos(next)*110),12)
	# Industrial campus: imported brick facades, loading courts and warehouses.
	for i in range(12):
		var at:=Vector2(2250+(i%3)*110,-2450-(i/3)*130)
		if not _valid(at): continue
		_detailed_building(at,"factory",3)
		_solid("warehouse",_ground(at+Vector2(42,0),8),Vector3(55,16,65),materials["facade3"])
		_solid("warehouse_roof",_ground(at+Vector2(42,0),16.3),Vector3(57,0.6,67),materials.roof)
		stats.buildings+=1

func _waterfront() -> void:
	# A long public promenade follows the eastern bank of the lake.
	for i in range(40):
		var angle: float=-PI/2+i*PI/40
		var next: float=-PI/2+(i+1)*PI/40
		var a:=Vector2(-2350+cos(angle)*1080,-4800+sin(angle)*1840)
		var b:=Vector2(-2350+cos(next)*1080,-4800+sin(next)*1840)
		_road(a,b,9)
		_tree_at(a+Vector2(16,0),1.6)
	# Marina piers, moored boats and waterfront apartments.
	for i in range(7):
		var z: float=-4100-i*90
		_solid("marina_pier",Vector3(-1530,-5.0,z),Vector3(160,1.0,5),materials.paving)
		for side in [-1,1]:
			for j in range(5):
				_solid("boat_hull",Vector3(-1570-j*17,-6.2,z+side*10),Vector3(4,2.3,13),materials.marking)
				_solid("boat_cabin",Vector3(-1570-j*17,-4.6,z+side*10),Vector3(3,1.4,5),materials.glass)

func _stadium(at: Vector2) -> void:
	var base: Vector3=_ground(at,1)
	_solid("stadium_pitch",base,Vector3(110,0.3,72),materials.pitch)
	for side in [-1,1]:
		for tier in range(4):
			_solid("stadium_stands",base+Vector3(0,3+tier*3,side*(48+tier*9)),Vector3(150,6,9),materials.paving)
		_solid("stadium_roof",base+Vector3(0,19,side*71),Vector3(165,1.2,33),materials.metal)
		_solid("pitch_touchline",base+Vector3(0,0.3,side*34),Vector3(104,0.1,0.3),materials.marking)
	_solid("pitch_centerline",base+Vector3(0,0.3,0),Vector3(0.3,0.1,68),materials.marking)
	_register_obstacle(AABB(base-Vector3(85,0,95),Vector3(170,22,190)))

func _register_obstacle(bounds: AABB) -> void:
	for x in range(floori(bounds.position.x/256),floori(bounds.end.x/256)+1):
		for z in range(floori(bounds.position.z/256),floori(bounds.end.z/256)+1):
			var cell:=Vector2i(x,z)
			if not obstacles.has(cell): obstacles[cell]=[]
			obstacles[cell].append(bounds)

func collides(at: Vector3,radius: float) -> bool:
	for x in range(floori((at.x-radius)/256),floori((at.x+radius)/256)+1):
		for z in range(floori((at.z-radius)/256),floori((at.z+radius)/256)+1):
			for bounds: AABB in obstacles.get(Vector2i(x,z),[]):
				if at.distance_squared_to(at.clamp(bounds.position,bounds.end))<=radius*radius: return true
	return false

func _flush() -> void:
	for key in batches:
		var batch: Dictionary=batches[key]
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=batch.mesh
		multi.instance_count=batch.transforms.size()
		for i in range(multi.instance_count): multi.set_instance_transform(i,batch.transforms[i])
		var node:=MultiMeshInstance3D.new()
		node.name=key
		node.multimesh=multi
		node.material_override=batch.material
		node.visibility_range_end=6500 if key.begins_with("tower") else 4300
		if key.begins_with("imported_"): node.visibility_range_end=1700
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if key.begins_with("avenue_tree") or key.begins_with("street_tree_impostor") or key.begins_with("lane_") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
	batches.clear()

func _merge(source: Mesh) -> Mesh:
	var grouped: Dictionary={}
	for index in range(source.get_surface_count()):
		var material: Material=source.surface_get_material(index)
		if not grouped.has(material):
			var st:=SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(material)
			grouped[material]=st
		# Explicit triangle expansion avoids corrupt index offsets when appending
		# many indexed primitive surfaces into the same material batch.
		var arrays: Array=source.surface_get_arrays(index)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int=indices.size() if not indices.is_empty() else vertices.size()
		var surface: SurfaceTool=grouped[material]
		for n in range(count):
			var vertex: int=indices[n] if not indices.is_empty() else n
			surface.set_normal(normals[vertex])
			surface.set_uv(uv[vertex] if uv.size()>vertex else Vector2.ZERO)
			surface.add_vertex(vertices[vertex])
	var mesh:=ArrayMesh.new()
	for material in grouped: grouped[material].commit(mesh)
	return mesh
