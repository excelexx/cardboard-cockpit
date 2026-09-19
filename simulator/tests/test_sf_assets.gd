extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source := "res://assets/san_francisco/"
	var vegetation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"trees.json"))
	var points := FileAccess.get_file_as_bytes(source+"tree_positions.f32").to_float32_array()
	if points.size()!=int(vegetation.count)*3: failures.append("Tree coordinate stream length does not match the index")
	for chunk: Dictionary in vegetation.chunks:
		if int(chunk.offset)+int(chunk.count)*3>points.size(): failures.append("Tree chunk exceeds the coordinate stream")
	var photos: Array = JSON.parse_string(FileAccess.get_file_as_string(source+"aerial/manifest.json"))
	for photo: Dictionary in photos:
		var path := source+"aerial/"+str(photo.tile)+".jpg"
		var image: Texture2D = load(path)
		if image==null or image.get_width()!=4000 or image.get_height()!=2000: failures.append("Missing or invalid original aerial image: "+path)
		var scene: Node3D = load(source+"terrain_"+str(photo.tile)+".scn").instantiate()
		var photographed := false
		for geometry in scene.find_children("*","MeshInstance3D",true,false):
			for i in range(geometry.mesh.get_surface_count()):
				var material = geometry.mesh.surface_get_material(i)
				if material is StandardMaterial3D and material.albedo_texture!=null and material.albedo_texture.resource_path==path: photographed=true
		if not photographed: failures.append("Photo is not bound to its terrain: "+str(photo.tile))
		scene.free()
	var downtown: Node3D = load(source+"city_w130n30_w123n37_942066b000.scn").instantiate()
	var mesh: Mesh = downtown.find_children("*","MeshInstance3D",true,false)[0].mesh
	var imported := ImporterMesh.from_mesh(mesh)
	if imported.get_surface_lod_count(0)<1: failures.append("Downtown is missing distance detail levels")
	if mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()<1000000: failures.append("Full-detail downtown source geometry was removed")
	downtown.free()
	print("SF ASSETS: ",photos.size()," geographic photos / full-detail mesh plus LODs / ",failures.size()," failures")
	for failure in failures:printerr(failure)
	quit(0 if failures.is_empty() else 1)
