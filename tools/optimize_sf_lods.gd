extends SceneTree
## Preserve full source geometry and add standard Godot distance-dependent index buffers.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var count := 0; var surfaces := 0; var levels := 0
	for name: String in DirAccess.open("res://assets/san_francisco/").get_files():
		if not name.ends_with(".scn") or not (name.begins_with("city_") or name.begins_with("road_")): continue
		var path := "res://assets/san_francisco/"+name
		var packed: PackedScene = load(path); var scene := packed.instantiate()
		if scene.has_meta("sf_source_lods"): scene.free(); continue
		for node in scene.find_children("*","MeshInstance3D",true,false):
			var original: Mesh = node.mesh
			var mesh := ImporterMesh.from_mesh(original)
			mesh.generate_lods(60.0,0.0,[])
			for i in range(mesh.get_surface_count()):
				# Full-resolution vertex positions and the original surface topology are retained.
				assert(mesh.get_surface_arrays(i)[Mesh.ARRAY_VERTEX]==original.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
				surfaces += 1; levels += mesh.get_surface_lod_count(i)
			node.mesh = mesh.get_mesh()
		scene.set_meta("sf_source_lods",true)
		var out := PackedScene.new(); out.pack(scene)
		assert(ResourceSaver.save(out,path,ResourceSaver.FLAG_COMPRESS)==OK)
		scene.free();count+=1
		if count%100==0:print("LOD SCENES ",count," levels ",levels)
	print("LOD COMPLETE scenes=",count," surfaces=",surfaces," levels=",levels);quit()
