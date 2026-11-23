extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source := "res://assets/san_francisco/"
	var region: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+"region.json"))
	var flat := 0; var area := 0.0
	for item: Dictionary in region.chunks:
		if item.kind!="terrain": continue
		var node: Node3D = load(source+str(item.file)).instantiate()
		for geometry in node.find_children("*","MeshInstance3D",true,false):
			for i in range(geometry.mesh.get_surface_count()):
				var mat = geometry.mesh.surface_get_material(i)
				if not (mat is StandardMaterial3D) or mat.roughness<0.4 or mat.albedo_texture==null: continue
				var verts: PackedVector3Array = geometry.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				if verts.is_empty(): continue
				var box := AABB(verts[0],Vector3.ZERO)
				for v in verts: box = box.expand(v)
				if box.size.y<0.9 and box.end.y<1.6 and box.position.y>-1.6:
					flat += 1
					area += box.size.x*box.size.z
					if flat<24: print("FLAT ",item.file," surf",i," aabb=",box," tex=",mat.albedo_texture.resource_path.get_file()," tris=",verts.size()/3)
		node.free()
	print("flat sea-level photo surfaces=",flat," area=",area/1e6," km2")
	quit(0)
