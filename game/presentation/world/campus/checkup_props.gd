class_name CheckupProps
extends Node3D
## Original checkup ruler, scale, chart and door paper. Queue and rules belong to their existing owners.
const LINES := ["十二点五十 坐回座位","熄灯以后 别吃那碗饭","镜子先动 就别再看","喇叭叫你 先查记录本","电梯的门 不等人"]

func material(color: String, emission: String = "000000") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.emission_enabled = emission!="000000"
	mat.emission = Color(emission)
	mat.roughness = 1
	return mat

func add_mesh(parent: Node3D, shape: Mesh, mat: Material, position: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = position
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func box(parent: Node3D, extent: Vector3, mat: Material, position: Vector3) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = extent
	return add_mesh(parent,shape,mat,position)

func paper(file: String, emission: String, extent: Vector2, position: Vector3) -> MeshInstance3D:
	var mat := material("ffffff",emission)
	mat.albedo_texture = load("res://assets/campus/checkup/"+file+".png")
	mat.emission_texture = mat.albedo_texture
	var quad := QuadMesh.new()
	quad.size = extent
	return add_mesh(self,quad,mat,position)

func build(room: Dictionary, line: String) -> void:
	name = "MedicalProps"
	var at := func(c: float,r: float) -> Vector3:
		var point := CampusGeometry.to_scene(room,Vector2(room["ox"]+c*room["tw"],room["oy"]+r*room["th"]))
		return Vector3(point.x,0,point.y)
	var white := material("e9e9e4","2e302e")
	var metal := material("8d9396")
	var dark := material("2c3033")
	var ruler := Node3D.new()
	add_child(ruler)
	ruler.position = at.call(1.16,15.45)
	box(ruler,Vector3(.05,2,.16),white,Vector3(0,1,0))
	for i in 20: box(ruler,Vector3(.006,.006,.1 if i%5==0 else .05),dark,Vector3(.028,.2+i*.09,0))
	box(ruler,Vector3(.26,.025,.12),metal,Vector3(.14,1.92,0))
	box(ruler,Vector3(.34,.04,.36),metal,Vector3(.17,.02,0))
	var scale := Node3D.new()
	add_child(scale)
	scale.position = at.call(2.7,15.45)
	box(scale,Vector3(.34,.06,.4),white,Vector3(0,.03,0))
	var dial := CylinderMesh.new()
	dial.top_radius = .06
	dial.bottom_radius = .06
	dial.height = .012
	dial.radial_segments = 20
	add_mesh(scale,dial,material("f6f3e8","1a1a14"),Vector3(0,.066,-.12))
	var red := material("a02020")
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box(scale,Vector3(.004,.004,.05),red,Vector3(.01,.074,-.13)).rotation.y = .9
	var index := maxi(0,LINES.find(line))
	var chart := paper("checkup-chart-%d" % index,"8a8a84",Vector2(.5,.88),at.call(8.84,15.45)+Vector3(0,1.45,0))
	chart.rotation.y = -PI/2
	paper("checkup-sign","77756e",Vector2(.36,.18),at.call(7,17.14)+Vector3(0,1.55,0))
