class_name InceptionScene
extends Node3D
## The original 20-second dream-cut.js. Saved body position and view are never animated.
const CAPTIONS := ["（风声。呼吸越来越轻。）","广播：「请各班同学，回到自己的——」","我醒了。阳光照在床头的课本上。窗外很安静，没有广播。","桌上的陀螺还在转。"]
var stages: Array[Node3D]=[]
var top_b: Node3D
var top_d: Node3D
var window_b: MeshInstance3D
var finger: MeshInstance3D
var _stage := -1


static func frame(k: float) -> Dictionary:
	var t:=k*20
	var stage:=0 if t<4 else (1 if t<9 else (2 if t<15 else 3))
	var out: Dictionary={"stage":stage}
	match stage:
		0:
			out["from"]=Vector3(0,-t*7+.4,0)
			out["to"]=Vector3(.4,-t*7-6,.3)
		1:
			var u: float=(t-4)/5
			out["from"]=Vector3(40+sin(u*1.6)*1.1,1.15,cos(u*1.6)*1.1)
			out["to"]=Vector3(40,.82,0)
			out["window"]=0x8e98a0 if u<.6 else 0x3a4046
			out["spin_b"]=24.0
		2:
			var v: float=(t-9)/6
			out["from"]=Vector3(78.4,.7+v*.6,-1.6+v*.4)
			out["to"]=Vector3(80.4,1.4,-2.6)
		3:
			var w: float=(t-15)/5
			var speed:=maxf(.15,1-w*.85)
			out["from"]=Vector3(120.25,1.05-w*.08,.55-w*.15)
			out["to"]=Vector3(120,.79,.02)
			out["spin_d"]=20*speed
			out["tilt_d"]=.08*(1-speed)*sin(t*6)
			out["finger"]=Vector3(.3-minf(1,w*2)*.12,.83,.25-minf(1,w*2)*.09)
	var edge:=0.0
	for cut: float in [4,9,15]: edge=maxf(edge,maxf(0,1-absf(t-cut)/.25))
	out["fade"]=maxf(edge,t-19 if t>19 else 0.0)
	return out


func _material(color: String, alpha: float = 1.0) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog=true
	m.albedo_color=Color(color)
	m.albedo_color.a=alpha
	if alpha<1: m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(g: Node3D, size: Vector3, color: String, at: Vector3) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=_material(color)
	node.position=at
	g.add_child(node)
	return node


func _enclose(g: Node3D, size: Vector3, color: String) -> void:
	var box:=_box(g,size,color,Vector3(0,size.y/2-.01,0))
	box.material_override.cull_mode=BaseMaterial3D.CULL_FRONT


func begin() -> void:
	for i in 4:
		var node:=Node3D.new()
		node.position.x=i*40
		add_child(node)
		stages.append(node)
	var a:=stages[0]
	for i in 14:
		var ring:=Node3D.new()
		ring.position.y=-i*3.2
		a.add_child(ring)
		_box(ring,Vector3(6,.12,.4),"#c9ccd0",Vector3(0,0,-2.6))
		_box(ring,Vector3(6,.12,.4),"#c9ccd0",Vector3(0,0,2.6))
		_box(ring,Vector3(.4,.12,5.6),"#b9bcc0",Vector3(-2.8,0,0))
		_box(ring,Vector3(.4,.12,5.6),"#b9bcc0",Vector3(2.8,0,0))
		_box(ring,Vector3(.9,2,.05),"#6b5a44",Vector3(1.4 if i%2 else -1.4,1,-2.45))
	_box(a,Vector3(.3,60,.3),"#a7abb0",Vector3(-2.6,-20,-2.4))
	_box(a,Vector3(.3,60,.3),"#a7abb0",Vector3(2.6,-20,2.4))
	var b:=stages[1]
	_enclose(b,Vector3(9,4.2,7),"#16191c")
	_box(b,Vector3(1.2,.05,.6),"#6f5c43",Vector3(0,.76,0))
	_box(b,Vector3(.05,.76,.05),"#3a3128",Vector3(-.55,.38,-.25))
	_box(b,Vector3(.05,.76,.05),"#3a3128",Vector3(.55,.38,.25))
	_box(b,Vector3(8,4,.1),"#2a2f33",Vector3(0,2,-3))
	window_b=_box(b,Vector3(2.2,1.3,.05),"#8e98a0",Vector3(0,1.9,-2.9))
	top_b=TopModel.make(true)
	top_b.position=Vector3(0,.785,0)
	b.add_child(top_b)
	var c:=stages[2]
	_enclose(c,Vector3(6.2,3.1,6.2),"#cbbfa8")
	_box(c,Vector3(6,.05,6),"#9a8b78",Vector3.ZERO)
	_box(c,Vector3(6,3,.1),"#d9cdb8",Vector3(0,1.5,-3))
	_box(c,Vector3(.1,3,6),"#cfc2ab",Vector3(-3,1.5,0))
	_box(c,Vector3(1.6,1.2,.05),"#fff3d6",Vector3(.6,1.8,-2.94))
	_box(c,Vector3(1.9,.5,.9),"#e8e2d6",Vector3(-1.6,.25,-1.8))
	_box(c,Vector3(1.9,.12,.9),"#f3efe8",Vector3(-1.6,.56,-1.8))
	_box(c,Vector3(.5,.5,.4),"#8a7356",Vector3(-.3,.25,-2.4))
	_box(c,Vector3(.26,.04,.34),"#3f6c8c",Vector3(-.3,.52,-2.4)).rotation.y=.3
	var beam:=MeshInstance3D.new()
	var plane:=QuadMesh.new()
	plane.size=Vector2(1.6,3.2)
	beam.mesh=plane
	beam.material_override=_material("#fff0c8",.12)
	beam.rotation.x=-1
	beam.position=Vector3(.6,.9,-1.6)
	c.add_child(beam)
	var d:=stages[3]
	_enclose(d,Vector3(8,4.2,6),"#c9bca4")
	_box(d,Vector3(2,.05,1.2),"#7b6649",Vector3(0,.76,0))
	_box(d,Vector3(8,4,.1),"#d4c7b0",Vector3(0,2,-2))
	top_d=TopModel.make(true)
	top_d.position=Vector3(0,.785,0)
	d.add_child(top_d)
	var shadow:=MeshInstance3D.new()
	var circle:=ImmediateMesh.new()
	circle.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 20:
		circle.surface_add_vertex(Vector3.ZERO)
		circle.surface_add_vertex(Vector3(cos(TAU*(i+1)/20)*.07,0,sin(TAU*(i+1)/20)*.07))
		circle.surface_add_vertex(Vector3(cos(TAU*i/20)*.07,0,sin(TAU*i/20)*.07))
	circle.surface_end()
	shadow.mesh=circle
	shadow.material_override=_material("#2a2218",.55)
	shadow.position=Vector3(.05,.787,.04)
	d.add_child(shadow)
	finger=_box(d,Vector3(.03,.03,.18),"#e2c3a6",Vector3(.3,.83,.25))
	finger.rotation.y=.9


func apply(k: float, camera: Camera3D, dt: float) -> Dictionary:
	var f:=frame(k)
	for i in stages.size(): stages[i].visible=i==int(f["stage"])
	camera.global_position=f["from"]
	camera.look_at(f["to"],Vector3.UP)
	var step:=dt if dt>0 else .016
	if f.has("spin_b"):
		top_b.rotation.y+=step*f["spin_b"]
		window_b.material_override.albedo_color=Color.hex((int(f["window"])<<8)|255)
	if f.has("spin_d"):
		top_d.rotation.y+=step*f["spin_d"]
		top_d.rotation.z=f["tilt_d"]
		finger.position=f["finger"]
	if _stage!=int(f["stage"]):
		_stage=int(f["stage"])
		f["caption"]=CAPTIONS[_stage]
	return f
