extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var district:=Node3D.new()
	root.add_child(district)
	var folder: String="res://assets/photogrammetry/helsinki/lod16"
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".glb"): continue
		var tile: Node3D=load(folder+"/"+file).instantiate()
		district.add_child(tile)
		tile.rotation.x=-PI/2
		tile.position=Vector3(-7000,0,5000)
		for mesh in tile.find_children("*","MeshInstance3D",true,false):
			for s in range(mesh.mesh.get_surface_count()):
				var mat: StandardMaterial3D=mesh.mesh.surface_get_material(s)
				if mat: mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(0.4,0.55,0.7)
	root.add_child(env)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(-1300,900,1400)
	camera.look_at(Vector3.ZERO)
	camera.far=10000
	for i in range(30):
		RenderingServer.force_draw()
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../docs/screenshots/city/photogrammetry-preview.png"))
	quit()
