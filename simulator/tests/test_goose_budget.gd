extends SceneTree
func _initialize() -> void:
	var model=load("res://systems/goose_model.gd")
	var failures:=0
	for lod in range(3):
		var goose: Node3D=model.create(lod)
		var triangles:=0
		for path in ["Body","WingL/Feathers","WingR/Feathers"]:
			var mesh: MeshInstance3D=goose.get_node(path)
			triangles+=mesh.mesh.surface_get_array_index_len(0)/3
		if triangles>512:failures+=1
		print("GOOSE LOD ",lod," triangles=",triangles)
		goose.free()
	print("GOOSE BUDGET failures=",failures)
	quit(failures)
