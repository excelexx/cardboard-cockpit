extends SceneTree
## Compile downloaded-format conversions to portable, compressed native scenes.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source_root := "res://assets/san_francisco/"
	var directory := DirAccess.open(source_root)
	var paths := directory.get_files()
	var count := 0
	var textures: Dictionary = {}
	for name: String in paths:
		if not name.ends_with(".gltf"): continue
		var path := source_root+name
		var target := path.trim_suffix(".gltf")+".scn"
		if FileAccess.file_exists(target): continue
		var doc := GLTFDocument.new(); var state := GLTFState.new()
		var error := doc.append_from_file(path,state)
		if error!=OK: printerr("FAILED ",path," ",error); quit(1); return
		var scene := doc.generate_scene(state)
		for mesh in scene.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var mat: StandardMaterial3D = mesh.mesh.surface_get_material(surface)
				if mat==null: continue
				var texture_path := source_root+"textures/"+mat.resource_name+".png"
				if FileAccess.file_exists(texture_path):
					if not textures.has(texture_path):
						if ResourceLoader.exists(texture_path): textures[texture_path] = load(texture_path)
						else:
							var original := Image.load_from_file(texture_path); original.generate_mipmaps()
							var imported := ImageTexture.create_from_image(original); imported.take_over_path(texture_path)
							textures[texture_path] = imported
					mat.albedo_texture = textures[texture_path]
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					mat.alpha_scissor_threshold = .4
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mat.roughness = .88 if mat.roughness>.5 else mat.roughness
		var packed := PackedScene.new(); packed.pack(scene)
		error = ResourceSaver.save(packed,target,ResourceSaver.FLAG_COMPRESS)
		scene.free()
		if error!=OK: printerr("SAVE FAILED ",target); quit(1); return
		count += 1
		if count%50==0: print("BAKED ",count," ",name)
	print("NATIVE SCENES BAKED ",count)
	quit()
