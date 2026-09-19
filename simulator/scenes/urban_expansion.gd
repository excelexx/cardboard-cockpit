extends "res://scenes/metropolitan_world.gd"
## Shared, chunked architecture: a metropolitan region around both airfields.
const STEP:=200.0
var traffic: Array[Dictionary]=[]
var traffic_batch: MultiMesh
var traffic_time:=0.0
var traffic_tick:=0.0
var footprint_km2:=0.0
var lot_bounds: Array[AABB]=[]
var skyscraper_count:=0
var height_min:=INF
var height_max:=0.0
var train: Node3D
var block_sizes: Array[Vector2]=[]
var block_angles: Array[float]=[]
var district_noise:=FastNoiseLite.new()
var road_material: ShaderMaterial
var connected_blocks:=0
var park_blocks:=0
var industrial_blocks:=0
var office_blocks:=0
var detailed_tree_mesh: Mesh
var detailed_tree_count:=0

static func reserved(p: Vector2) -> bool:
	# Keep the complete airport and both approach corridors unobstructed.
	if p.x> -600 and p.x<1250 and minf(absf(p.y),absf(p.y+15000))<2450: return true
	if absf(p.x)<150 and minf(absf(p.y),absf(p.y+15000))<4200: return true
	if p.x>1000 and p.x<3400 and p.y> -7800 and p.y< -3200: return true
	if p.x> -1500 and p.x<1300 and p.y> -8050 and p.y< -7400: return true
	return false

func build(owner_world: Node3D) -> void:
	world=owner_world
	name="GreaterAzureMetropolis"
	rng.seed=981728
	unit_box.size=Vector3.ONE
	_build_materials()
	_load_kit("apartments","modular_urban_apartments_facade",["wall_window_centered_large_01","window_centered_large_01"])
	district_noise.seed=7821
	district_noise.frequency=0.0007
	materials.paving.albedo_color=Color(.25,.265,.25)
	materials.paving.albedo_texture=load("res://assets/environment/aerial_asphalt_01_diff_2k.jpg")
	materials.paving.uv1_triplanar=true
	materials.paving.uv1_world_triplanar=true
	materials.paving.uv1_scale=Vector3.ONE*.1
	materials.roof.albedo_texture=load("res://assets/environment/aerial_asphalt_01_diff_2k.jpg")
	materials.roof.uv1_triplanar=true
	materials.roof.uv1_world_triplanar=true
	materials.roof.uv1_scale=Vector3.ONE*.15
	materials.roof.albedo_color=Color(.55,.57,.56)
	road_material=ShaderMaterial.new()
	road_material.shader=load("res://assets/environment/coastal/city_street.gdshader")
	var architecture: Array[Mesh]=[]
	for variant in range(9): architecture.append(_architecture(variant))
	car_mesh=_merge(_car())
	tree_mesh=world._conifer_mesh()
	var tree_asset: Node=load("res://assets/nature/tree_small_02.glb").instantiate()
	detailed_tree_mesh=(tree_asset.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
	tree_asset.free()
	materials.park.albedo_texture=load("res://assets/environment/aerial_grass_rock_diff_1k.jpg")
	materials.park.uv1_triplanar=true
	materials.park.uv1_scale=Vector3.ONE*0.15
	# Variable-size blocks and gently bending avenues replace the repeated 200m lattice.
	var xs: Array[float]=[-3600.0]
	var zs: Array[float]=[-18000.0]
	for i in range(45): xs.append(xs[-1]+rng.randf_range(155,285))
	for i in range(105): zs.append(zs[-1]+rng.randf_range(145,245))
	for iz in range(zs.size()-1):
		for ix in range(xs.size()-1):
			var a: Vector2=_street_point(xs[ix],zs[iz])
			var b: Vector2=_street_point(xs[ix+1],zs[iz])
			var c: Vector2=_street_point(xs[ix],zs[iz+1])
			var d: Vector2=_street_point(xs[ix+1],zs[iz+1])
			var center: Vector2=(a+b+c+d)*0.25
			if not _buildable(center,35): continue
			var width: float=minf(a.distance_to(b),c.distance_to(d))-34.0
			var depth: float=minf(a.distance_to(c),b.distance_to(d))-34.0
			var angle: float=-atan2(b.y-a.y,b.x-a.x)
			var rotation:=Basis(Vector3.UP,angle)
			var size:=Vector2(width,depth)
			# No rotated lot corner may enter protected airport/scan/approach areas.
			var fits:=true
			for corner in [Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(-width/2,0,depth/2),Vector3(width/2,0,depth/2)]:
				var p: Vector3=rotation*corner
				if not _buildable(center+Vector2(p.x,p.z),0): fits=false
			if not fits: continue
			# The rail alignment is a protected greenway, never through building interiors.
			if center.y> -6350 and center.y< -2450 and minf(a.x,c.x)< -960 and maxf(b.x,d.x)> -1040: continue
			footprint_km2+=a.distance_to(b)*a.distance_to(c)/1000000.0
			block_sizes.append(size)
			block_angles.append(angle)
			_street(a,b,22.0 if iz%6==0 else 13.0)
			_street(a,c,24.0 if ix%7==0 else 13.0)
			_solid("block_paving",_ground(center,0.10),Vector3(width+6,0.16,depth+6),materials.paving,angle)
			var density: float=maxf(exp(-center.distance_squared_to(Vector2(-2300,-3600))/1500000.0),exp(-center.distance_squared_to(Vector2(4500,-6000))/1500000.0))
			var district: float=district_noise.get_noise_2d(center.x,center.y)
			var park: bool=district_noise.get_noise_2d(center.x+4500,center.y-8100)>0.28 or rng.randf()<0.025
			if park:
				_park_block(center,size,angle)
			elif density>0.32:
				_office_block(center,size,angle,density,architecture)
			elif district< -0.24:
				_industrial_block(center,size,angle,architecture)
			else:
				_perimeter_block(center,size,angle,district,architecture)
			# Dense street trees belong to real sidewalks, not scattered lot centers.
			for edge in [[a,b],[a,c]]:
				var p: Vector2=edge[0]; var q: Vector2=edge[1]
				var toward: Vector2=(center-(p+q)*0.5).normalized()*12
				for i in range(1,int(p.distance_to(q)/24)):
					var tree_at: Vector2=p.lerp(q,float(i)/int(p.distance_to(q)/24))+toward
					_street_tree(tree_at,rng.randf_range(.7,1.05))
	_build_transit()
	_flush()
	for kit in kit_roots: kit.free()
	kit_roots.clear()
	# Spread a fixed vehicle budget over the whole city, including departure districts.
	while traffic.size()>650: traffic.remove_at(rng.randi_range(0,traffic.size()-1))
	traffic_batch=MultiMesh.new()
	traffic_batch.transform_format=MultiMesh.TRANSFORM_3D
	traffic_batch.mesh=car_mesh
	traffic_batch.instance_count=traffic.size()
	var cars:=MultiMeshInstance3D.new()
	cars.name="MovingStreetTraffic"
	cars.multimesh=traffic_batch
	cars.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cars)
	_update_traffic()
	print("METRO EXPANSION: ",stats.buildings," buildings / ",snappedf(footprint_km2,0.1)," km2 / ",traffic.size()," moving vehicles / skyscrapers=",skyscraper_count," height range=",height_min,"–",height_max)

func _street_point(x: float,z: float) -> Vector2:
	return Vector2(x+sin(z*.00075)*145+sin(x*.0011+z*.0005)*42,z+sin(x*.0010)*110+sin(z*.0014)*33)

func _street_tree(at: Vector2,scale_value: float) -> void:
	# A bounded set of scanned, lit 3D trees at the low-altitude departure edge.
	# Silhouettes remain cheap in the distant metropolitan background.
	if detailed_tree_count<160 and at.y> -2500 and at.y< -1200 and at.x>1250 and at.x<2400:
		_put("departure_tree_3d",detailed_tree_mesh,_ground(at),Vector3.ONE*scale_value*2.7,fposmod(at.x*.73,TAU))
		detailed_tree_count+=1
	else:
		_put("street_tree_impostor",tree_mesh,_ground(at),Vector3.ONE*scale_value)

func _buildable(p: Vector2,margin: float) -> bool:
	if reserved(p) or world._in_settlement(p.x,p.y): return false
	if margin>0:
		for delta in [Vector2(margin,0),Vector2(-margin,0),Vector2(0,margin),Vector2(0,-margin)]:
			if reserved(p+delta): return false
	var h: float=world.ground_height(p.x,p.y)
	return h>5 and h<20

func _local(center: Vector2,p: Vector2,angle: float) -> Vector2:
	var rotated: Vector3=Basis(Vector3.UP,angle)*Vector3(p.x,0,p.y)
	return center+Vector2(rotated.x,rotated.z)

func _street(a: Vector2,b: Vector2,width: float) -> void:
	var delta: Vector2=b-a
	var angle: float=atan2(delta.x,delta.y)
	var steps: int=ceili(delta.length()/32)
	for i in range(steps):
		var p: Vector2=a.lerp(b,(i+0.5)/steps)
		if reserved(p) or world.ground_height(p.x,p.y)<0: continue
		_solid("road_surface",_ground(p,.24),Vector3(width,.16,delta.length()/steps+.5),road_material,angle)
	stats.roads_km+=delta.length()/1000.0
	if rng.randf()<.14 and not reserved(a) and not reserved(b):
		var side:=Vector2(delta.y,-delta.x).normalized()*3.1
		traffic.append({"a":a+side,"b":b+side,"length":delta.length(),"angle":angle,"speed":rng.randf_range(8,15),"phase":rng.randf()*delta.length()})

func _building(p: Vector2,size: Vector3,angle: float,kind: int,architecture: Array[Mesh]) -> void:
	var rotation:=Basis(Vector3.UP,angle)
	var base: float=-100
	for corner in [Vector3(-size.x*.53,0,-size.z*.53),Vector3(size.x*.53,0,-size.z*.53),Vector3(-size.x*.53,0,size.z*.53),Vector3(size.x*.53,0,size.z*.53)]:
		var q: Vector3=rotation*corner
		base=maxf(base,world.ground_height(p.x+q.x,p.y+q.z))
	var at:=Vector3(p.x,base+.14,p.y)
	var height: float=size.y
	if absf(p.x)<1700 and minf(absf(p.y),absf(p.y+15000))<2800:
		height=minf(height,32)
	size.y=height
	_put("tower_building_"+str(kind),architecture[kind],at,size,angle)
	var bounds: AABB=Transform3D(rotation,at)*AABB(Vector3(-size.x*.53,0,-size.z*.53),Vector3(size.x*1.06,size.y*1.35,size.z*1.06))
	_register_obstacle(bounds); lot_bounds.append(bounds)
	stats.buildings+=1
	height_min=minf(height_min,height); height_max=maxf(height_max,height*1.35)
	if height>150: skyscraper_count+=1

func _perimeter_block(center: Vector2,size: Vector2,angle: float,district: float,architecture: Array[Mesh]) -> void:
	connected_blocks+=1
	var pattern: int=rng.randi_range(0,5)
	if pattern==0:
		_terrace_block(center,size,angle,architecture)
		return
	if pattern==1:
		_slab_block(center,size,angle,architecture)
		return
	var floor_height: float=3.3
	var floors: int=2 if district>.22 else (5 if district<0 else 3)
	var depth: float=17 if floors<4 else 23
	var kind: int=5 if floors==2 else (1 if district>0 else 8)
	# Street-facing joined buildings enclose a planted shared interior.
	_solid("courtyard_green",_ground(center,.23),Vector3(maxf(8,size.x-depth*2-12),.14,maxf(8,size.y-depth*2-12)),materials.park,angle)
	for side in [-1.0,1.0]:
		var count: int=maxi(3,int(size.x/22))
		var frontage: float=size.x/count
		for i in range(count):
			if pattern==2 and side==1 and i>0 and i<count-1: continue
			if pattern==3 and side==-1 and i==count/2: continue
			var offset:=Vector2(-size.x/2+(i+.5)*frontage,side*(size.y/2-depth/2))
			var h: float=(floors+rng.randi_range(0,2))*floor_height
			_building(_local(center,offset,angle),Vector3(frontage-.6,h,depth),angle,kind,architecture)
		var length: float=size.y-depth*2-2
		var count_side: int=maxi(2,int(length/24))
		for i in range(count_side):
			if pattern==4 and side==1: continue
			var offset:=Vector2(side*(size.x/2-depth/2),-length/2+(i+.5)*length/count_side)
			_building(_local(center,offset,angle),Vector3(depth,(floors+rng.randi_range(0,1))*floor_height,length/count_side-.6),angle,1 if kind==5 else kind,architecture)
	if pattern==5:
		# Interior service wing divides a large perimeter block into two courts.
		_building(center,Vector3(size.x-depth*2,9,14),angle,8,architecture)
	for i in range(8):
		var p: Vector2=_local(center,Vector2(rng.randf_range(-size.x*.25,size.x*.25),rng.randf_range(-size.y*.25,size.y*.25)),angle)
		_put("street_tree_impostor",tree_mesh,_ground(p),Vector3.ONE*rng.randf_range(.8,1.4))

func _terrace_block(center: Vector2,size: Vector2,angle: float,architecture: Array[Mesh]) -> void:
	_solid("terrace_gardens",_ground(center,.23),Vector3(size.x,.14,size.y),materials.park,angle)
	var rows: int=3 if size.y>150 else 2
	for row in range(rows):
		var count: int=int(size.x/16)
		var frontage: float=size.x/count
		var z: float=-size.y/2+20+row*(size.y-40)/maxi(1,rows-1)
		for i in range(count):
			var p: Vector2=_local(center,Vector2(-size.x/2+(i+.5)*frontage,z),angle)
			_building(p,Vector3(frontage-.7,rng.randf_range(6.6,9.9),13),angle,5,architecture)
			if i%2==0:
				var tree_at: Vector2=_local(center,Vector2(-size.x/2+(i+.5)*frontage,z+14),angle)
				_put("street_tree_impostor",tree_mesh,_ground(tree_at),Vector3.ONE*.8)

func _slab_block(center: Vector2,size: Vector2,angle: float,architecture: Array[Mesh]) -> void:
	_solid("estate_lawn",_ground(center,.23),Vector3(size.x,.14,size.y),materials.park,angle)
	for i in range(3):
		var p: Vector2=_local(center,Vector2(-size.x*.32+i*size.x*.32,(i%2-.5)*size.y*.15),angle)
		# Real recessed window geometry and scanned materials along departure streets.
		# A bounded accent budget keeps the metropolitan background inexpensive.
		if i==1 and center.y> -3200 and center.y<1000 and stats.detailed_buildings<48:
			_detailed_building(p,"apartments",rng.randi_range(6,10))
			continue
		_building(p,Vector3(19,18+i*9,size.y*.68),angle,8,architecture)
	for i in range(16):
		var local:=Vector2(rng.randf_range(-size.x*.45,size.x*.45),rng.randf_range(-size.y*.45,size.y*.45))
		if minf(absf(local.x+size.x*.32),minf(absf(local.x),absf(local.x-size.x*.32)))<14: continue
		var p: Vector2=_local(center,local,angle)
		_put("street_tree_impostor",tree_mesh,_ground(p),Vector3.ONE*.85)

func _office_block(center: Vector2,size: Vector2,angle: float,density: float,architecture: Array[Mesh]) -> void:
	office_blocks+=1
	# One asymmetrical podium + a landmark tower, not four interchangeable towers.
	_building(_local(center,Vector2(-size.x*.12,0),angle),Vector3(size.x*.65,12,size.y*.80),angle,1,architecture)
	var height: float=65+pow(density,1.8)*rng.randf_range(180,330)
	var tower_size: float=minf(54,size.x*.31)
	var kind: int=3 if rng.randf()<.28 else (7 if rng.randf()<.35 else 2)
	_building(_local(center,Vector2(-size.x*.18,-size.y*.16),angle),Vector3(tower_size,height,tower_size*.82),angle,kind,architecture)
	# Tower is intentionally attached to its retail podium; same foundation, no floating crown.
	_building(_local(center,Vector2(size.x*.32,size.y*.16),angle),Vector3(size.x*.23,rng.randf_range(24,65),size.y*.45),angle,4,architecture)
	for i in range(6):
		var p: Vector2=_local(center,Vector2(size.x*.34,-size.y*.4+i*12),angle)
		_put("street_tree_impostor",tree_mesh,_ground(p),Vector3.ONE)

func _industrial_block(center: Vector2,size: Vector2,angle: float,architecture: Array[Mesh]) -> void:
	industrial_blocks+=1
	_building(_local(center,Vector2(-size.x*.10,-size.y*.1),angle),Vector3(size.x*.72,rng.randf_range(8,15),size.y*.60),angle,6,architecture)
	_building(_local(center,Vector2(-size.x*.2,size.y*.33),angle),Vector3(size.x*.35,9,size.y*.13),angle,1,architecture)
	# Loading bays, containers and parked delivery trailers communicate commercial use.
	for i in range(5):
		var p: Vector2=_local(center,Vector2(-size.x*.25+i*15,size.y*.24),angle)
		_solid("delivery_trailer",_ground(p,2),Vector3(3.2,3.5,12),materials.marking,angle)

func _park_block(center: Vector2,size: Vector2,angle: float) -> void:
	park_blocks+=1
	_solid("park_lawn",_ground(center,.23),Vector3(size.x,.15,size.y),materials.park,angle)
	_solid("park_path",_ground(center,.33),Vector3(4,.10,size.y),materials.paving,angle)
	for i in range(30):
		var p: Vector2=_local(center,Vector2(rng.randf_range(-size.x*.44,size.x*.44),rng.randf_range(-size.y*.44,size.y*.44)),angle)
		_put("street_tree_impostor",tree_mesh,_ground(p),Vector3.ONE*rng.randf_range(.9,1.8))

func _architecture(kind: int) -> Mesh:
	var wall:=ShaderMaterial.new()
	wall.shader=load("res://assets/environment/coastal/urban_facade.gdshader")
	wall.set_shader_parameter("masonry_texture",load("res://assets/city/modular_urban_apartments_facade/textures/modular_urban_apartments_facade_plaster_diff_1k.jpg"))
	wall.set_shader_parameter("masonry_normal",load("res://assets/city/modular_urban_apartments_facade/textures/modular_urban_apartments_facade_plaster_nor_gl_1k.jpg"))
	if kind in [1,6]:
		wall.set_shader_parameter("masonry_texture",load("res://assets/city/modular_factory_facade/textures/modular_factory_facade_brick_diff_1k.jpg"))
		wall.set_shader_parameter("masonry_normal",load("res://assets/city/modular_factory_facade/textures/modular_factory_facade_brick_nor_gl_1k.jpg"))
	wall.set_shader_parameter("glazing",1.0 if kind in [2,3,7] else 0.0)
	wall.set_shader_parameter("tint",[Vector3(.52,.48,.40),Vector3(.28,.23,.19),Vector3(.22,.31,.34),Vector3(.17,.25,.30),Vector3(.57,.56,.52),Vector3(.40,.35,.29),Vector3(.38,.40,.41),Vector3(.21,.28,.32),Vector3(.53,.50,.43)][kind])
	var mesh:=ArrayMesh.new()
	if kind==3:
		# Tapered elliptical glass tower with a recessed crown.
		var shaft:=CylinderMesh.new()
		shaft.top_radius=0.36; shaft.bottom_radius=0.5; shaft.height=1.0; shaft.radial_segments=16
		_append(mesh,shaft,Transform3D(Basis.IDENTITY,Vector3(0,0.5,0)),wall)
		var cap:=CylinderMesh.new()
		cap.top_radius=0.36; cap.bottom_radius=0.36; cap.height=0.016; cap.radial_segments=16
		_append(mesh,cap,Transform3D(Basis.IDENTITY,Vector3(0,1.01,0)),materials.metal)
	elif kind in [4,7]:
		for tier in range(3):
			var width: float=1.0-tier*0.21
			_box(mesh,Vector3(tier*0.035,0.19+tier*0.35,0),Vector3(width,0.38,width),wall)
			_box(mesh,Vector3(tier*0.035,0.385+tier*0.35,0),Vector3(width+0.02,0.012,width+0.02),materials.roof)
		if kind==7:
			_box(mesh,Vector3(.07,1.16,0),Vector3(.016,.25,.016),materials.metal)
	elif kind==0:
		# Connected courtyard wings instead of a single solid block.
		_box(mesh,Vector3(-.30,.5,0),Vector3(.40,1,1),wall)
		_box(mesh,Vector3(.30,.38,0),Vector3(.40,.76,1),wall)
		_box(mesh,Vector3(0,.44,-.33),Vector3(.8,.88,.34),wall)
		_box(mesh,Vector3(-.30,1.01,0),Vector3(.42,.02,1.02),materials.roof)
		_box(mesh,Vector3(.30,.77,0),Vector3(.42,.02,1.02),materials.roof)
	elif kind==5:
		_box(mesh,Vector3(0,.5,0),Vector3(1,1,1),wall)
		# Pitched copper roofs give the older district a different silhouette.
		var roof:=PrismMesh.new()
		roof.size=Vector3(1.06,.28,1.06)
		_append(mesh,roof,Transform3D(Basis.IDENTITY,Vector3(0,1.12,0)),materials.tile3)
	else:
		_box(mesh,Vector3(0,.5,0),Vector3(1,1,1),wall)
		_box(mesh,Vector3(0,1.01,0),Vector3(1.025,.02,1.025),materials.roof)
		_box(mesh,Vector3(.12,1.035,.12),Vector3(.2,.04,.24),materials.metal)
		if kind==6:
			for i in range(4): _box(mesh,Vector3(-.3+i*.2,1.02,0),Vector3(.09,.02,.75),materials.glass)
	return _merge(mesh)

func _build_transit() -> void:
	# Elevated urban rail, clear of both airport approaches and the harbor.
	_solid("rail_deck",Vector3(-1000,25,-4400),Vector3(10,2,3600),materials.paving)
	for x in [-1002.0,-998.0]:
		_solid("rail_track",Vector3(x,26.1,-4400),Vector3(.18,.15,3600),materials.metal)
	for z in range(-6100,-2600,160):
		_solid("rail_pier",Vector3(-1000,18,z),Vector3(3,14,3),materials.paving)
	_register_obstacle(AABB(Vector3(-1006,11,-6200),Vector3(12,17,3600)))
	train=Node3D.new(); train.name="MetroTrain"; train.position.x=-1000; train.position.y=27
	add_child(train)
	var body:=ArrayMesh.new()
	_box(body,Vector3(0,1.5,0),Vector3(3.2,3,17),materials.marking)
	_box(body,Vector3(0,2,0),Vector3(3.25,1,15),materials.glass)
	_box(body,Vector3(0,.6,0),Vector3(3.3,.35,17),materials.tile0)
	var shared: Mesh=_merge(body)
	for i in range(5):
		var carriage:=MeshInstance3D.new(); carriage.mesh=shared; carriage.position.z=i*18
		train.add_child(carriage)

func _process(dt: float) -> void:
	traffic_time+=dt
	if is_instance_valid(train): train.position.z=-6100+fmod(traffic_time*24,3400)
	traffic_tick+=dt
	if traffic_tick<0.1: return
	traffic_tick=0
	_update_traffic()

func _update_traffic() -> void:
	if traffic_batch==null: return
	for i in range(traffic.size()):
		var car: Dictionary=traffic[i]
		var p: Vector2=car.a.lerp(car.b,fmod(traffic_time*car.speed+car.phase,car.length)/car.length)
		var at:=Vector3(p.x,world.ground_height(p.x,p.y)+.4,p.y)
		traffic_batch.set_instance_transform(i,Transform3D(Basis(Vector3.UP,car.angle),at))
