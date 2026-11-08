class_name KnifeScene
extends Node3D
## Original four-stage, sixteen-second knife-cut.js; only the ending camera moves.
const CAPTIONS := ["（压在头顶的手停住了。）","「管制刀具。」","门外是正常的日光。登记单上盖了章，刀锁进了柜子。","上课铃响了。东西被收走了。你还在这里。"]
var stages: Array[Node3D]=[]
var blade: MeshInstance3D
var hand: MeshInstance3D
var form: Node3D
var stamp: MeshInstance3D
var last_stage := -1


static func frame(k: float) -> Dictionary:
	var t:=k*16
	var s:=0 if t<3 else (1 if t<7 else (2 if t<11 else 3))
	var from: Vector3
	var to: Vector3
	var out: Dictionary={"stage":s}
	match s:
		0:
			from=Vector3(0,1.5,.15)
			to=Vector3(.05,1.25,-1)
			out["blade_y"]=1.12+.1*minf(1,t/1.2)
			out["hand_y"]=1.85+.04*maxf(0,t-1.5)
		1:
			from=Vector3(40,1.45,.6)
			to=Vector3(40,1.25,-.6)
			out["form_x"]=.22+.05*sin(t)
		2:
			var u: float=(t-7)/4
			from=Vector3(80.2,1.6,.8)
			to=Vector3(79.8+.8*u,1.1,-1.2)
			out["stamp_y"]=1.35-.2*maxf(0,sin(minf(1,u*2)*PI))
		3:
			var v: float=(t-11)/5
			from=Vector3(120,1.25+.2*v,.9+.3*v)
			to=Vector3(120,.75,0)
	var edge:=0.0
	for cut: float in [3,7,11]: edge=maxf(edge,maxf(0,1-absf(t-cut)/.25))
	out.merge({"from":from,"to":to,"fade":maxf(edge,(t-15.2)/.8 if t>15.2 else 0.0)})
	return out


func _box(g: Node3D, size: Vector3, col: String, at: Vector3, alpha: float = 1.0) -> MeshInstance3D:
	var m:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=size
	m.mesh=box
	var mat:=StandardMaterial3D.new()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog=true
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.albedo_color=Color(col)
	mat.albedo_color.a=alpha
	if alpha<1: mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override=mat
	m.position=at
	g.add_child(m)
	return m


func _form(g: Node3D, lines: Array, size: Vector2, at: Vector3) -> Node3D:
	var n:=Node3D.new()
	n.position=at
	g.add_child(n)
	_box(n,Vector3(size.x,size.y,.001),"#f2efe4",Vector3.ZERO)
	for i in lines.size():
		var text:=Label3D.new()
		text.text=lines[i]
		text.font_size=24 if i==0 else 18
		text.pixel_size=size.x/256
		text.outline_size=0
		text.modulate=Color("#222222")
		text.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
		text.position=Vector3(-size.x/2+16*size.x/256,size.y/2-(26+i*34)*size.x/256,.001)
		n.add_child(text)
	return n


func _person(g: Node3D, at: Vector3) -> void:
	var fig:=FigureModel.make("tall",Color("#0f1214"),true)
	# The original cut's MeshBasicMaterial explicitly ignores campus fog.
	for mesh: Node in fig.find_children("*","MeshInstance3D",true,false):
		(mesh as MeshInstance3D).material_override.disable_fog=true
	fig.position=at
	fig.rotation.y=PI
	g.add_child(fig)


func begin() -> void:
	for i in 4:
		var stage:=Node3D.new()
		stage.position.x=i*40
		add_child(stage)
		stages.append(stage)
	for i in 2:
		_box(stages[i],Vector3(6,.05,6),"#24292a",Vector3.ZERO)
		_box(stages[i],Vector3(6,3,.1),"#3a4244",Vector3(0,1.5,-2.5))
		_person(stages[i],Vector3(0,0,-1.2 if i==0 else -1.1))
	blade=_box(stages[0],Vector3(.02,.16,.012),"#c9ced2",Vector3(.12,1.2,-.55))
	_box(stages[0],Vector3(.03,.1,.02),"#2a2522",Vector3(.12,1.08,-.55))
	hand=_box(stages[0],Vector3(.16,.05,.2),"#1a1d20",Vector3(0,1.85,-.3))
	_box(stages[1],Vector3(.22,.3,.03),"#dfe8ea",Vector3(-.25,1.25,-.6),.35)
	_box(stages[1],Vector3(.02,.16,.012),"#c9ced2",Vector3(-.25,1.25,-.6))
	form=_form(stages[1],["管制刀具登记","姓名：（已填好）","班级：高二（二）班","处理："],Vector2(.42,.56),Vector3(.22,1.2,-.55))
	var c:=stages[2]
	_box(c,Vector3(6,.05,6),"#5a5448",Vector3.ZERO)
	_box(c,Vector3(6,3,.1),"#8a8172",Vector3(0,1.5,-2.5))
	_box(c,Vector3(1,2.1,.02),"#fff6dc",Vector3(-1.2,1.05,-2.44))
	_box(c,Vector3(1.1,2.2,.04),"#4a4036",Vector3(-1.2,1.1,-2.47))
	_box(c,Vector3(.8,1.8,.5),"#6d7472",Vector3(1,.9,-2.1))
	_box(c,Vector3(.78,1.76,.03),"#7d8482",Vector3(1,.9,-1.83))
	stamp=_box(c,Vector3(.08,.08,.08),"#a02424",Vector3(0,1.35,-.6))
	_form(c,["管制刀具登记","处理：留校"],Vector2(.42,.3),Vector3(0,1.1,-.6)).rotation.x=-1.2
	var d:=stages[3]
	_box(d,Vector3(8,.05,8),"#3c3a35",Vector3.ZERO)
	_box(d,Vector3(8,3,.1),"#55574f",Vector3(0,1.5,-3))
	_box(d,Vector3(1.1,.05,.6),"#7a6748",Vector3(0,.76,0))
	_box(d,Vector3(.9,.12,.5),"#5a4a36",Vector3(0,.62,.02))
	_box(d,Vector3(.3,.03,.4),"#3f6c8c",Vector3(.1,.8,.02))
	_form(d,["姓名：　　　","留校"],Vector2(.3,.2),Vector3(-.22,.787,.05)).rotation.x=-PI/2
	_box(d,Vector3(2.4,1.2,.05),"#9fb3bd",Vector3(1.5,1.7,-2.94))


func apply(k: float, camera: Camera3D) -> Dictionary:
	var f:=frame(k)
	for i in stages.size(): stages[i].visible=i==int(f["stage"])
	if f.has("blade_y"): blade.position.y=f["blade_y"]
	if f.has("hand_y"): hand.position.y=f["hand_y"]
	if f.has("form_x"): form.position.x=f["form_x"]
	if f.has("stamp_y"): stamp.position.y=f["stamp_y"]
	camera.global_position=f["from"]
	camera.look_at(f["to"],Vector3.UP)
	if last_stage!=int(f["stage"]):
		last_stage=int(f["stage"])
		f["caption"]=CAPTIONS[last_stage]
	return f
