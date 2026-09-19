extends Node3D
class_name FighterCanopy
## What the pilot sees of an F-35-style canopy: the forward bow, the sills that
## run toward the nose, and the acrylic itself. Built in cockpit space (the
## camera is the origin, -Z is forward), so it needs no model import.
const GLASS := preload("res://assets/look/canopy_glass.gdshader")
var glass: ShaderMaterial
var frame_material: StandardMaterial3D
var seal_material: StandardMaterial3D

func build() -> void:
	frame_material = StandardMaterial3D.new()
	# Matte and nearly non-specular: an enclosed cockpit does not see the whole
	# bright sky, but a sky-reflection probe would paint it on every dark surface.
	frame_material.albedo_color = Color(0.016,0.017,0.019)
	frame_material.roughness = 0.78; frame_material.metallic = 0.0; frame_material.metallic_specular = 0.18
	seal_material = StandardMaterial3D.new()
	seal_material.albedo_color = Color(0.008,0.008,0.009); seal_material.roughness = 0.95; seal_material.metallic_specular = 0.08
	var bow: Array[Vector3] = []
	for i in range(33):
		var a: float = PI*float(i)/32.0
		# Slightly squared arch: wider shoulders than a circle, like the real bow.
		bow.append(Vector3(cos(a)*0.60*(1.0+0.10*sin(a)*sin(a)),-0.31+pow(sin(a),0.82)*0.80,-0.98-sin(a)*0.08))
	add_child(_sweep(bow,0.021,0.040,Vector3.BACK,frame_material))
	add_child(_sweep(bow,0.008,0.050,Vector3.BACK,seal_material,Vector3(0,0,0.004)))
	for side: float in [-1.0,1.0]:
		var sill: Array[Vector3] = []
		for i in range(25):
			var t: float = float(i)/24.0   # 0 behind the pilot, 1 at the nose
			var z: float = lerpf(0.70,-2.05,t)
			var width: float = lerpf(0.66,0.20,pow(t,1.7))
			var y: float = -0.33+0.05*sin(t*PI)-0.10*pow(t,3.0)
			sill.append(Vector3(side*width,y,z))
		add_child(_sweep(sill,0.042,0.030,Vector3.UP,frame_material))
		add_child(_sweep(sill,0.016,0.036,Vector3.UP,seal_material,Vector3(-side*0.02,0.012,0)))
	add_child(_glass_shell())

func set_sun(direction_view: Vector3,energy: float) -> void:
	if glass==null: return
	glass.set_shader_parameter("sun_view",direction_view)
	glass.set_shader_parameter("strength",clampf(energy,0.0,1.4))

## Elliptical tube along `path`; `reference` fixes the section's orientation.
func _sweep(path: Array[Vector3],half_a: float,half_b: float,reference: Vector3,material: Material,offset: Vector3=Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var rings: Array = []
	for i in range(path.size()):
		var tangent: Vector3 = (path[mini(i+1,path.size()-1)]-path[maxi(i-1,0)]).normalized()
		var binormal: Vector3 = (reference-tangent*reference.dot(tangent)).normalized()
		var normal: Vector3 = tangent.cross(binormal).normalized()
		var ring: Array = []
		for s in range(sides):
			var a: float = TAU*float(s)/sides
			var direction: Vector3 = normal*cos(a)*half_a+binormal*sin(a)*half_b
			ring.append([path[i]+offset+direction,(normal*cos(a)/half_a+binormal*sin(a)/half_b).normalized()])
		rings.append(ring)
	for i in range(rings.size()-1):
		for s in range(sides):
			var n: int = (s+1)%sides
			for corner in [[i,s],[i+1,s],[i+1,n],[i,s],[i+1,n],[i,n]]:
				var vertex: Array = rings[corner[0]][corner[1]]
				st.set_normal(vertex[1]); st.add_vertex(vertex[0])
	var instance := MeshInstance3D.new(); instance.mesh = st.commit(); instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _glass_shell() -> MeshInstance3D:
	var noise := FastNoiseLite.new(); noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED; noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new(); texture.width = 1024; texture.height = 512; texture.seamless = true
	texture.generate_mipmaps = true; texture.noise = noise
	glass = ShaderMaterial.new(); glass.shader = GLASS; glass.set_shader_parameter("scratches",texture)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 28; var columns := 24
	var grid: Array = []
	for r in range(rows+1):
		var t: float = float(r)/rows
		var z: float = lerpf(0.75,-2.0,t)
		var half_width: float = lerpf(0.68,0.22,pow(t,1.7))
		var height: float = lerpf(0.80,0.10,pow(t,2.2))
		var base: float = -0.33+0.05*sin(t*PI)-0.10*pow(t,3.0)
		var row: Array = []
		for c in range(columns+1):
			var a: float = PI*float(c)/columns
			var point := Vector3(cos(a)*half_width,base+pow(sin(a),0.85)*height,z)
			row.append([point,Vector3(-cos(a)/half_width,-sin(a)/height,0.0).normalized(),Vector2(float(c)/columns,t)])
		grid.append(row)
	for r in range(rows):
		for c in range(columns):
			for corner in [[r,c],[r+1,c],[r+1,c+1],[r,c],[r+1,c+1],[r,c+1]]:
				var vertex: Array = grid[corner[0]][corner[1]]
				st.set_normal(vertex[1]); st.set_uv(vertex[2]); st.add_vertex(vertex[0])
	var instance := MeshInstance3D.new(); instance.mesh = st.commit(); instance.material_override = glass
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
