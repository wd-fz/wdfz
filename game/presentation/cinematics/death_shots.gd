class_name DeathShots
extends RefCounted
## Sets and actions for death cinematics. Every transform is a function of normalized
## elapsed time; scrubbing, low frame rates and replay never advance gameplay state.
## Props are authored relative to the captured eye, independent of floors or sitting.

const INK := Color("10191e")
const COAL := Color("29363b")
const JADE := Color("476964")
const PAPER := Color("d8d0b8")
const RUST := Color("b56243")
const LIGHT := Color("e8dcb4")
var c: DeathStage
var root: Node3D
var layout := ""
var focus: Node3D
var p := {}
var actors: Array[Node3D] = []
var pieces: Array[Node3D] = []
var base_camera: Vector3

func _init(stage: DeathStage) -> void:
	c = stage

func build() -> void:
	layout = DeathSceneCatalog.layout(c.fx)
	root = Node3D.new()
	root.name = "EyeLevelSet"
	c.F.add_child(root)
	base_camera = c.F.to_local(c.cam.global_position)
	root.position = base_camera
	c.cam.near = minf(c._camera_near,.025)
	c.hide_world(Color("111b22"))
	c.veil(Color("03070a"))
	call("_build_"+layout)
	c.d["scene"] = root
	c.d["focus"] = focus
	c.d["layout"] = layout

func present(t: float) -> void:
	# Start each frame from the captured transform: no additive camera drift.
	c.cam.transform = c._camera_transform
	_pose(t)
	call("_show_"+layout,t)
	c.shade(.94*c.ss(t,.88,1))
	var bed := "scene.engine" if layout in ["garage","backseat","crash"] else "scene.hum"
	c.cue("establish",t,.04,func() -> void: c.snd(bed,{"k":.55}))
	var impact := "event.bigBell" if layout=="bell" else ("world.crackle" if layout in ["crash","mirror","frost"] else "threat.sting")
	c.cue("contact",t,.56,func() -> void: c.snd(impact,{"k":.7}))
	c.cue("close",t,.88,func() -> void: c.snd("foley.vanish"))

func _pose(t: float, pitch: float = 0, yaw: float = 0, lift: float = 0, roll: float = 0, zoom: float = 0) -> void:
	c.view(t*c.dur,yaw,pitch,lift)
	c.cam.rotation.z = roll*c.shk
	c.cam.fov = c._camera_fov + zoom*c.shk

func _box(size: Vector3, at: Vector3, color: Color, parent: Node3D = null, alpha: float = -1) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return c.mesh(shape,c._mat(color,alpha,false,false,false),at.x,at.y,at.z,parent if parent != null else root)

func _rod(a: Vector3, b: Vector3, width: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var result := _box(Vector3(width,a.distance_to(b),width),(a+b)*.5,color,parent)
	result.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return result

func _sphere(at: Vector3, radius: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius=radius
	shape.height=radius*2
	shape.radial_segments=16
	shape.rings=8
	return c.mesh(shape,c._mat(color,-1,false,false,false),at.x,at.y,at.z,parent if parent != null else root)

func _text(words: String, at: Vector3, height: float, color: Color = PAPER, parent: Node3D = null) -> Label3D:
	var label := Label3D.new()
	label.text=words
	label.font=GameUI.BASE_THEME.default_font
	label.font_size=64
	label.pixel_size=height/64
	label.modulate=color
	label.outline_size=0
	label.shaded=false
	label.no_depth_test=false
	label.rotation.y=PI
	c.put(label,at.x,at.y,at.z,parent if parent != null else root)
	return label

func _ring(at: Vector3, radius: float, width: float, color: Color, parent: Node3D = null) -> Node3D:
	return c.torus(radius,width,c._mat(color,-1,true,false,false),at.x,at.y,at.z,parent if parent != null else root,6,40)

func _person(at: Vector3, scale: float = 1, color: Color = INK, kind: String = "person") -> Node3D:
	var actor := c.fig(kind,color,scale,0,0)
	actor.reparent(root,false)
	actor.position=at
	actors.append(actor)
	return actor

func _anchor(at: Vector3) -> Node3D:
	var node := Node3D.new()
	c.put(node,at.x,at.y,at.z,root)
	return node

func _room(width: float = 7, depth: float = 16, tone: Color = COAL) -> void:
	_box(Vector3(width,.08,depth),Vector3(0,-1.6,depth*.5-1),Color("263738"))
	_box(Vector3(width,.08,depth),Vector3(0,1.9,depth*.5-1),Color("4c5550"))
	_box(Vector3(.08,3.5,depth),Vector3(-width*.5,.15,depth*.5-1),tone)
	_box(Vector3(.08,3.5,depth),Vector3(width*.5,.15,depth*.5-1),tone)
	_box(Vector3(width,3.5,.08),Vector3(0,.15,depth-1),tone)
	for side in [-1,1]:
		_box(Vector3(.1,.04,depth),Vector3(side*(width*.5-.04),-.55,depth*.5-1),JADE)
		_box(Vector3(.1,.12,depth),Vector3(side*(width*.5-.04),-1.5,depth*.5-1),INK)
	for z in range(1,int(depth),3):
		_box(Vector3(1.1,.03,.2),Vector3(0,1.82,z),LIGHT)
		_box(Vector3(width,.01,.018),Vector3(0,-1.55,z),Color("4c5853"))

func _window(at: Vector3, size: Vector2 = Vector2(2.3,2)) -> Node3D:
	var group := _anchor(at)
	for side in [-1,1]:
		_box(Vector3(.06,size.y+.12,.08),Vector3(side*(size.x+.06)*.5,0,0),INK,group)
		_box(Vector3(size.x+.12,.06,.08),Vector3(0,side*(size.y+.06)*.5,0),INK,group)
	var pane:=_box(Vector3(size.x,size.y,.02),Vector3(0,0,-.05),Color("6f9698"),group)
	pane.name="GlassPane"
	_box(Vector3(.055,size.y,.05),Vector3(0,0,-.08),COAL,group)
	_box(Vector3(size.x,.055,.05),Vector3(0,0,-.08),COAL,group)
	return group

func _desk(at: Vector3) -> Node3D:
	var desk := _anchor(at)
	_box(Vector3(1.1,.09,.65),Vector3(0,-.65,0),Color("8e8265"),desk)
	_box(Vector3(.96,.3,.5),Vector3(0,-.84,0),JADE,desk)
	for x in [-.43,.43]:
		_box(Vector3(.045,.63,.045),Vector3(x,-1.22,.2),COAL,desk)
		_box(Vector3(.045,.63,.045),Vector3(x,-1.22,-.2),COAL,desk)
	_box(Vector3(.4,.01,.3),Vector3(.12,-.595,0),PAPER,desk)
	_box(Vector3(.45,.06,.4),Vector3(0,-1.05,-.75),Color("625f4f"),desk)
	_box(Vector3(.45,.45,.05),Vector3(0,-.8,-.92),Color("625f4f"),desk)
	return desk

func _build_rollcall() -> void:
	_room(5,9)
	_box(Vector3(3.5,1.5,.08),Vector3(0,.45,7.7),JADE)
	_text("到你了。",Vector3(0,.7,7.62),.3)
	p["man"]=_person(Vector3(0,-1.6,5),.85,Color("1d2b2d"),"teacher")
	focus=_anchor(Vector3(0,.15,5))
	var book := _anchor(Vector3(.45,-.28,3.8))
	book.rotation.y=-.18
	_box(Vector3(.5,.66,.025),Vector3.ZERO,COAL,book)
	_box(Vector3(.44,.6,.012),Vector3(0,0,-.02),PAPER,book)
	_text("巡查登记",Vector3(0,.2,-.031),.065,INK,book)
	for i in 5:
		_box(Vector3(.32,.009,.003),Vector3(0,.08-i*.06,-.03),Color("66756c"),book)
	p["book"]=book
	p["name"]=_text("未到",Vector3(.07,-.22,-.033),.07,RUST,book)
	p["beam"]=_box(Vector3(.7,.025,.1),Vector3(0,.6,3.7),LIGHT)

func _show_rollcall(t: float) -> void:
	var step := c.ss(t,.12,.69)
	var z := lerpf(5,1.2,step)
	p["man"].position.z=z
	p["man"].rotation.z=.025*sin(t*22)*(1-step)
	focus.position=Vector3(0,.15,z)
	p["book"].position=Vector3(.45,-.28+step*.14,lerpf(3.8,.9,step))
	p["book"].rotation.x=-.25*c.ss(t,.5,.8)
	p["beam"].position.z=z-.25
	p["name"].visible=t>.61
	p["name"].text="已到" if t>.78 else ("下一位" if c.fx=="names" else "未到")
	_pose(t,-.08*c.ss(t,.6,.8),0,-.12*step,0,-5*step)

func _build_garage() -> void:
	_room(10,22,Color("233034"))
	for x in [-3.4,3.4]:
		for z in [4,9,14,19]:
			_box(Vector3(.45,3.5,.45),Vector3(x,.15,z),Color("49514a"))
			_box(Vector3(.46,.22,.46),Vector3(x,-.4,z),RUST)
			_box(Vector3(2,.01,.06),Vector3(x*.6,-1.54,z),PAPER)
	p["lights"]=[]
	for x in [-.8,.8]:
		p["lights"].append(_box(Vector3(.55,.18,.06),Vector3(x,-.4,3),LIGHT))
		for i in 3:
			_box(Vector3(.7+i*.5,.006,2),Vector3(x,-1.53,1+i*1.8),Color("69736b"))
	p["man"]=_person(Vector3(0,-1.6,14),.78,Color("080e12"),"roam")
	p["shadow"]=_box(Vector3(.4,.015,4),Vector3(0,-1.5,6),Color("070c10"))
	focus=_anchor(Vector3(0,0,14))

func _show_garage(t: float) -> void:
	var close := c.ss(t,.28,.84)
	var z := lerpf(14,.8,close)
	p["man"].position=Vector3(.2*sin(t*9)*(1-close),-1.6,z)
	focus.position=Vector3(0,.1,z)
	p["shadow"].scale.z=1+close*2
	p["shadow"].position.z=lerpf(6,2,close)
	for i in 2: p["lights"][i].visible=t<.4+i*.14
	_pose(t,0,.025*sin(t*12)*close,0,0,-7*close)

func _build_backseat() -> void:
	_room(4.4,7,INK)
	_box(Vector3(3,.7,.5),Vector3(0,-1.25,1),Color("18232c"))
	_box(Vector3(3,1,.2),Vector3(0,-.7,4.6),Color("344249"))
	for x in [-.9,.9]: _box(Vector3(.65,.45,.2),Vector3(x,0,4.5),COAL)
	var mirror := _anchor(Vector3(0,.48,1.2))
	_box(Vector3(1.25,.48,.08),Vector3.ZERO,Color("857e6b"),mirror)
	_box(Vector3(1.13,.37,.02),Vector3(0,0,-.06),Color("657d80"),mirror)
	p["mirror"]=mirror
	p["reflection"]=_sphere(Vector3(0,.48,1.12),.15,INK)
	p["man"]=_person(Vector3(.85,-1.62,4.2),1,INK)
	focus=p["mirror"]
	for x in [-1.7,1.7]: _box(Vector3(.12,2.7,.15),Vector3(x,-.1,2.8),PAPER)

func _show_backseat(t: float) -> void:
	var turn := c.ss(t,.35,.8)
	p["reflection"].visible=t>.2
	p["reflection"].position.x=.28*sin(t*4)*(1-turn)
	p["reflection"].scale=Vector3.ONE*(1+.45*turn)
	p["man"].position=Vector3(lerpf(.85,0,turn),-1.62,lerpf(4.2,.8,turn))
	p["mirror"].rotation.z=.12*turn
	_pose(t,.08*(1-turn),0,0,-.03*turn,-4*turn)

func _build_crash() -> void:
	_box(Vector3(22,.1,60),Vector3(0,-1.55,25),Color("1f2b31"))
	for i in 14:
		pieces.append(_box(Vector3(.08,.015,1),Vector3(0,-1.48,2+i*3),PAPER))
	for x in [-2,2]:
		_box(Vector3(.14,2.4,.12),Vector3(x,0,1.4),COAL).rotation.z=x*.08
		_box(Vector3(.1,.2,45),Vector3(x*2,-1.15,20),Color("718277"))
	_box(Vector3(4.5,.65,.9),Vector3(0,-1.25,.45),COAL)
	_ring(Vector3(0,-.75,.6),.4,.05,INK).rotation.x=.25
	p["lights"]=[]
	for x in [-.65,.65]: p["lights"].append(_sphere(Vector3(x,-.25,18),.24,LIGHT))
	p["cracks"]=[]
	for i in 13:
		var a:=i*TAU/13
		p["cracks"].append(_rod(Vector3(0,0,.72),Vector3(cos(a)*(1.1+i%3*.3),sin(a)*.8,.74),.008,PAPER))
	focus=_anchor(Vector3(0,-.15,6))

func _show_crash(t: float) -> void:
	var hit:=c.ss(t,.49,.64)
	for i in pieces.size():
		pieces[i].position.z=1+fposmod(i*3-t*38,42)
	for light: Node3D in p["lights"]:
		light.position.z=lerpf(18,1.3,c.ss(t,.05,.62))
		light.scale=Vector3.ONE*(1+hit*.8)
	for i in p["cracks"].size(): p["cracks"][i].visible=t>.53+i*.008
	_pose(t,.06*hit,.07*hit,.05*sin(t*70)*hit*c.shk,.09*hit,3*hit)

func _build_classroom() -> void:
	_room(8,18,Color("64736d"))
	_box(Vector3(6,1.6,.08),Vector3(0,.45,16.8),Color("294c48"))
	p["writing"]=_text("请 回 到 你 的 座 位",Vector3(0,.6,16.72),.38)
	for row in 4:
		for col in 3:
			var x:float=(col-1)*1.9
			var z:float=3+row*2.6
			pieces.append(_desk(Vector3(x,0,z)))
			var student:=_person(Vector3(x,-1.6,z-.75),1.0,Color("233e40"),"sit")
			if c.fx=="stare": _sphere(Vector3(0,1.17,.1),.09,PAPER,student)
	for z in [3,8,13]:
		var window := _window(Vector3(3.92,.4,z))
		window.rotation.y=PI/2
	p["own"]=_desk(Vector3(0,0,.7))
	p["blank"]=_box(Vector3(5.9,1.5,.04),Vector3(0,.45,16.65),Color("bbc2b1"))
	p["blank"].hide()
	focus=_anchor(Vector3(0,-.15,5.6))

func _show_classroom(t: float) -> void:
	var change:=c.ss(t,.22,.78)
	var assimilated:=c.fx=="assimilation"
	for i in actors.size():
		var actor:=actors[i]
		if assimilated or c.fx=="follow":
			actor.rotation.y=lerpf(.3*sin(i*3),0,change)
			actor.position.z=3+floori(i/3.0)*2.6-.75-.15*change
		elif c.fx=="stare":
			actor.rotation.y=PI*c.ss(t,.15+i*.025,.45+i*.025)
		else:
			actor.visible=t<.35+(i%4)*.09
	for i in pieces.size():
		pieces[i].position.x=(i%3-1)*1.9*(1-.16*change if assimilated else 1+.35*change)
	p["blank"].visible=not assimilated and t>.5
	p["blank"].scale.x=c.ss(t,.5,.82)
	p["own"].position.z=lerpf(.7,.33,change) if assimilated else .7
	p["writing"].text="已 归 队" if assimilated and t>.6 else "请 回 到 你 的 座 位"
	_pose(t,-.1*change if assimilated else .07*change,0,-.25*change if assimilated else 0,.025*sin(t*9)*change, -6*change if assimilated else 7*change)

func _build_assembly() -> void:
	_box(Vector3(24,.1,35),Vector3(0,-1.6,15),Color("465e54"))
	_box(Vector3(22,6,.2),Vector3(0,1.3,20),COAL)
	for i in 8:
		_box(Vector3(.035,.01,28),Vector3((i-3.5)*1.8,-1.54,12),PAPER)
	for row in 4:
		for col in 4:
			var student:=_person(Vector3((col-1.5)*1.6,-1.6,4+row*2.5),.92,INK)
			_box(Vector3(.26,.06,.04),Vector3(0,1.3,-.16),PAPER,student)
	_text("保持队形",Vector3(0,1.2,19.8),.7)
	focus=_anchor(Vector3(0,0,4))

func _show_assembly(t: float) -> void:
	var enter:=c.ss(t,.18,.82)
	for i in actors.size():
		var row:=floori(i/4.0)
		var col:=i%4
		actors[i].position=Vector3((col-1.5)*(1.6-enter*.8),-1.6+.05*sin(t*32+i)*enter,4+row*2.5-enter*2.4)
		actors[i].rotation.z=.08*sin(t*24)*enter
		actors[i].rotation.y=PI*c.ss(t,.45+row*.025,.7+row*.025)
	_pose(t,-.04*enter,0,-.1*enter,0,-4*enter)


func _build_fence() -> void:
	_box(Vector3(14,.1,12),Vector3(0,-1.6,5),Color("354840"))
	for i in 15: _box(Vector3(.04,2.8,.04),Vector3((i-7)*.27,-.2,2.5),Color("73918a"))
	for y in [-.6,.75]: _box(Vector3(4.1,.055,.055),Vector3(0,y,2.48),Color("73918a"))
	p["head"]=_sphere(Vector3(2.7,.45,3.2),.27,PAPER)
	p["neck"]=_box(Vector3(.13,.14,.13),Vector3(2.7,.4,3.2),Color("b8b99f"))
	p["eyes"]=[]
	for x in [-.09,.09]: p["eyes"].append(_sphere(Vector3(x,.48,2.88),.036,INK))
	focus=p["head"]

func _show_fence(t: float) -> void:
	var creep:=c.ss(t,.1,.6)
	var reach:=c.ss(t,.55,.86)
	p["head"].position=Vector3(lerpf(2.7,0,creep),.45-.35*reach,lerpf(3.2,.7,reach))
	var a:=Vector3(2.8,.35,3.2)
	var b:Vector3=p["head"].position
	p["neck"].position=(a+b)*.5
	p["neck"].scale.y=maxf(1,a.distance_to(b)/.14)
	p["neck"].quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	for i in 2: p["eyes"][i].position=p["head"].position+Vector3(-.09+i*.18,.025,-.26)
	_pose(t,.06*reach,0,0,-.035*reach)

func _build_double() -> void:
	_room(5,13,Color("435854"))
	for z in [3,7,11]: _window(Vector3(2.45,.2,z)).rotation.y=PI/2
	p["one"]=_person(Vector3(-.7,-1.6,6),1,Color("87978b"))
	p["two"]=_person(Vector3(.7,-1.6,6),1,INK)
	focus=_anchor(Vector3(0,0,6))
	_box(Vector3(2,.015,.08),Vector3(0,-1.54,4),PAPER)

func _show_double(t: float) -> void:
	var close:=c.ss(t,.36,.83)
	p["one"].rotation.z=.12*sin(t*9)
	p["two"].rotation.z=.12*sin((t-.1)*9)
	p["one"].position.x=-.7*(1-close)
	p["two"].position.x=.7*(1-close)
	p["two"].position.z=lerpf(6,.65,close)
	p["one"].visible=t<.73
	focus.position.z=p["two"].position.z
	_pose(t,0,.04*sin(t*9)*close,0,0,-6*close)

func _build_flood() -> void:
	_room(7,14,Color("384e54"))
	_window(Vector3(0,.4,9),Vector2(3,2.4))
	for x in [-2,2]: _desk(Vector3(x,0,4))
	p["water"]=_box(Vector3(7,.035,15),Vector3(0,-1.5,5),Color("628c91"),null,.82)
	p["wash"]=_box(Vector3(6,4,.025),Vector3(0,0,.32),Color("164c60"),null,.55)
	p["ripples"]=[]
	for i in 5:
		var ripple:=_ring(Vector3(0,-1.48,3),.4+i*.3,.009,LIGHT)
		ripple.rotation.x=PI/2
		p["ripples"].append(ripple)
	p["bubbles"]=[]
	for i in 18: p["bubbles"].append(_sphere(Vector3.ZERO,.018+(i%3)*.01,Color("8eafb0")))
	focus=_anchor(Vector3(0,0,3))

func _show_flood(t: float) -> void:
	var level:=lerpf(-1.5,.5,c.ss(t,.05,.84))
	p["water"].position.y=level
	p["water"].rotation.z=.012*sin(t*13)*c.shk
	p["wash"].visible=level>-.05
	for i in 5: p["ripples"][i].position.y=level+.025
	for i in 18:
		p["bubbles"][i].position=Vector3(sin(i*7.3)*1.4,-1.5+fposmod(i*.23+t*3,2.7),.5+(i%7)*.45)
		p["bubbles"][i].visible=t>.4
	_pose(t,.14*c.ss(t,.5,.8),0,-.08*c.ss(t,.5,.8),.025*sin(t*8)*c.ss(t,.5,.8))

func _build_frost() -> void:
	_room(5,12,Color("5f777c"))
	_window(Vector3(0,.4,10),Vector2(3,2.5))
	for i in 7:
		var coat:=_anchor(Vector3((i-3)*.55,.5,4.5))
		_box(Vector3(.35,.8,.1),Vector3(0,-.5,0),Color("466571"),coat)
		for side in [-1,1]: _box(Vector3(.13,.65,.1),Vector3(side*.25,-.5,0),Color("466571"),coat).rotation.z=side*.2
		_rod(Vector3(0,.2,0),Vector3(.2,0,0),.018,PAPER,coat)
		pieces.append(coat)
	p["ice"]=[]
	for i in 24:
		var a:=i*TAU/24
		p["ice"].append(_rod(Vector3(cos(a)*2,sin(a)*1.2,.48),Vector3(cos(a)*.5,sin(a)*.3,.48),.012,Color("bfd8cf")))
	focus=_anchor(Vector3(0,0,4.5))

func _show_frost(t: float) -> void:
	var close:=c.ss(t,.22,.84)
	for i in pieces.size():
		pieces[i].position.z=4.5-close*(1+sin(i*4)*.3)
		pieces[i].rotation.z=.04*sin(t*10+i)*close
	for i in 24:
		p["ice"][i].visible=t>.2+i*.021
		p["ice"][i].scale.y=.15+.85*close
	_pose(t,0,0,0,.02*sin(t*19)*close,-4*close)

func _build_broadcast() -> void:
	_room(6,10,Color("526761"))
	p["speaker"]=_anchor(Vector3(0,.55,3.5))
	_box(Vector3(1.3,.75,.18),Vector3.ZERO,INK,p["speaker"])
	for i in 11: _box(Vector3(1.15,.018,.02),Vector3(0,-.28+i*.055,-.11),COAL,p["speaker"])
	p["lamp"]=_sphere(Vector3(.51,.23,-.14),.035,RUST,p["speaker"])
	p["notice"]=_anchor(Vector3(0,-.45,3.8))
	_box(Vector3(1.8,1.3,.04),Vector3.ZERO,PAPER,p["notice"])
	p["words"]=_text("请停止阅读",Vector3(0,.1,-.03),.16,INK,p["notice"])
	_text("校 内 广 播",Vector3(0,.9,3.4),.19)
	p["lines"]=[]
	for i in 8:
		p["lines"].append(_box(Vector3(2,.025,.015),Vector3(0,1.4-i*.36,2.7),INK))
	focus=p["speaker"]

func _show_broadcast(t: float) -> void:
	var close:=c.ss(t,.28,.79)
	p["speaker"].position.z=lerpf(3.5,1.1,close)
	p["notice"].position.z=lerpf(3.8,1.3,close)
	p["words"].text="你正在被记录" if t>.58 else ("不要念出名字" if c.fx=="voice" else "请停止阅读")
	for i in 8:
		p["lines"][i].visible=t>.45+i*.025
		p["lines"][i].scale.x=1+.3*sin(t*11+i)
	_pose(t,.045*sin(t*13)*close,0,0,0,-3*close)

func _build_bell() -> void:
	_room(6,12,Color("394d50"))
	p["bell"]=_anchor(Vector3(0,.45,4))
	var body:=c.fxm("bell",.8,0,0,0)
	body.reparent(p["bell"],false)
	# The imported mesh is authored at y=1.21..2.78, not around its pivot.
	body.position.y=-1.6
	p["bell_model"]=body
	_rod(Vector3(0,.9,4),Vector3(0,1.9,4),.04,COAL)
	p["clapper"]=_sphere(Vector3(0,-.15,3.8),.12,RUST)
	p["waves"]=[]
	for i in 5: p["waves"].append(_ring(Vector3(0,.3,3),.8+i*.35,.018,PAPER))
	focus=p["bell"]

func _show_bell(t: float) -> void:
	var swing:=sin(t*20)*c.ss(t,.05,.25)*(1-c.ss(t,.65,.83))
	p["bell"].rotation.z=.25*swing
	p["clapper"].position.x=.22*swing
	for i in 5:
		var wave:Node3D=p["waves"][i]
		wave.visible=t>.32+i*.06
		wave.scale=Vector3.ONE*(1+c.ss(t,.32+i*.06,.9)*1.8)
		wave.position.z=lerpf(3,.5,c.ss(t,.32+i*.06,.95))
	_pose(t,.12,0,0,.025*swing,3*c.ss(t,.5,.8))

func _build_banquet() -> void:
	_room(8,24,Color("455a51"))
	p["table"]=_anchor(Vector3(0,0,0))
	_box(Vector3(2.2,.1,20),Vector3(0,-.75,11),Color("a59b7f"),p["table"])
	for i in 12:
		var plate:=_ring(Vector3((-1 if i%2 else 1)*.65,-.68,2+i*1.3),.25,.025,PAPER,p["table"])
		plate.rotation.x=PI/2
		_person(Vector3((-1 if i%2 else 1)*1.45,-1.6,2+i*1.3),.9,INK,"sit").rotation.y=PI/2*(-1 if i%2 else 1)
	p["mouth"]=_ring(Vector3(0,.05,10),1.1,.18,INK)
	focus=p["mouth"]

func _show_banquet(t: float) -> void:
	var stretch:=c.ss(t,.15,.8)
	p["table"].scale.z=1+stretch*1.5
	p["mouth"].position.z=lerpf(10,1.4,c.ss(t,.4,.87))
	p["mouth"].scale=Vector3.ONE*(1+stretch)
	for i in actors.size(): actors[i].rotation.y=(PI/2*(-1 if i%2 else 1))*(1-stretch)
	_pose(t,-.08*stretch,0,0,0,8*stretch)

func _build_cup() -> void:
	_room(6,11,Color("506b66"))
	_window(Vector3(0,.5,5),Vector2(3,2.5))
	_box(Vector3(3,.13,.8),Vector3(0,-.65,3.7),PAPER)
	p["cup"]=_anchor(Vector3(0,-.42,3.5))
	# Keep the recognizable original school cup and its printed texture.
	var body:=FallingProps.model("cup",CampusData.tier)
	body.scale=Vector3.ONE*3
	c.put(body,0,-.25,0,p["cup"])
	p["lid"]=FallingProps.model("lid",CampusData.tier)
	p["lid"].scale=Vector3.ONE*3
	c.put(p["lid"],0,.25,0,p["cup"])
	p["rim"]=_ring(Vector3(0,.02,3.4),.5,.14,PAPER)
	p["inside"]=_box(Vector3(9,7,.03),Vector3(0,0,6),Color("a8b6a6"))
	focus=p["cup"]

func _show_cup(t: float) -> void:
	var grow:=c.ss(t,.25,.8)
	p["cup"].scale=Vector3.ONE*(1+grow*6)
	p["cup"].position.y=-.42+grow*.65
	p["cup"].rotation.x=-grow*.9
	p["lid"].position=Vector3(-.5*grow,.25+grow*.55,.15*grow)
	p["lid"].rotation.z=grow*2.6
	p["rim"].visible=t>.62
	p["rim"].position.z=lerpf(3.4,.4,c.ss(t,.58,.88))
	p["rim"].scale=Vector3.ONE*(.5+grow*3)
	p["inside"].visible=t>.76
	_pose(t,.15*grow,0,0,0,-5*grow)

func _build_ritual() -> void:
	_room(8,14,Color("384641"))
	p["circle"]=_ring(Vector3(0,-1.52,5),2.4,.025,PAPER)
	p["circle"].rotation.x=PI/2
	for i in 8:
		var a:float=i*TAU/8
		_person(Vector3(cos(a)*2.4,-1.6,5+sin(a)*2.4),1,INK).rotation.y=-a+PI/2
		_ring(Vector3(cos(a)*2.4,-1.51,5+sin(a)*2.4),.25,.015,RUST).rotation.x=PI/2
	p["sigil"]=_ring(Vector3(0,0,5),.5,.035,RUST)
	for i in 5:
		var a:float=i*TAU/5
		_rod(Vector3(cos(a)*.5,sin(a)*.5,5),Vector3(cos(a+TAU*.4)*.5,sin(a+TAU*.4)*.5,5),.015,RUST)
	focus=p["sigil"]

func _show_ritual(t: float) -> void:
	var close:=c.ss(t,.28,.8)
	for i in 8:
		var a:float=i*TAU/8
		actors[i].position=Vector3(cos(a)*(2.4-close*1.5),-1.6,5+sin(a)*(2.4-close*1.5)-close*2)
		actors[i].rotation.y=lerpf(-a+PI/2,0,close)
	p["sigil"].rotation.z=t*.5
	p["sigil"].scale=Vector3.ONE*(1+close*2)
	_pose(t,-.06*close,0,-.12*close,0,-4*close)

func _build_corridor() -> void:
	_room(4.5,30,Color("435f59"))
	p["doors"]=[]
	p["lamps"]=[]
	for i in 7:
		var z:float=3+i*3.6
		for side in [-1,1]:
			var door:=_anchor(Vector3(side*2.12,-.25,z))
			_box(Vector3(.1,2.4,1.3),Vector3.ZERO,INK,door)
			_box(Vector3(.11,2.25,1.15),Vector3(0,0,0),JADE,door)
			p["doors"].append(door)
		p["lamps"].append(_box(Vector3(1,.025,.3),Vector3(0,1.79,z),LIGHT))
	p["exit"]=_anchor(Vector3(0,0,26))
	_box(Vector3(1.8,2.8,.08),Vector3(0,-.2,0),INK,p["exit"])
	_box(Vector3(1.55,2.6,.1),Vector3(0,-.2,-.02),Color("9aa790"),p["exit"])
	_text("出口",Vector3(0,1.4,-.08),.18,LIGHT,p["exit"])
	p["left"]=_box(Vector3(.1,3.4,26),Vector3(-2.1,.1,12),JADE)
	p["right"]=_box(Vector3(.1,3.4,26),Vector3(2.1,.1,12),JADE)
	focus=p["exit"]

func _show_corridor(t: float) -> void:
	var close:=c.ss(t,.15,.84)
	var narrow:bool=c.fx in ["wall","squeeze","trap_wall"]
	p["left"].position.x=-2.1+(1.85*close if narrow else 0)
	p["right"].position.x=2.1-(1.85*close if narrow else 0)
	p["exit"].position.z=26+close*20 if not narrow else 26
	for i in p["doors"].size():
		p["doors"][i].position.z=2+fposmod(floori(i/2.0)*3.6-t*8,25)
	for i in p["lamps"].size():
		p["lamps"][i].visible=t<.2+(6-i)*.09 if c.fx=="lamps" else true
	_pose(t,0,0,0,.035*sin(t*7)*close,8*close if not narrow else -5*close)

func _build_face() -> void:
	_room(6,12,Color("30494c"))
	var through_glass:=c.fx=="window_gaze"
	if through_glass: p["window"]=_window(Vector3(0,.1,2.5),Vector2(3,2.7))
	p["face"]=_anchor(Vector3(0,.05,4.2))
	_sphere(Vector3.ZERO,.46,Color("a9b6a4"),p["face"])
	for x in [-.15,.15]:
		_sphere(Vector3(x,.08,-.46),.06,INK,p["face"])
		_sphere(Vector3(x,.08,-.515),.016,LIGHT,p["face"])
	p["smile"]=_ring(Vector3(0,-.12,-.41),.18,.023,INK,p["face"])
	# Lower half hidden under a cheek, leaving an understated curved smile.
	_box(Vector3(.5,.25,.08),Vector3(0,.04,-.43),Color("a9b6a4"),p["face"])
	p["shoulders"]=_person(Vector3(0,-1.8,4.4),1.1,INK)
	p["breath"]=_sphere(Vector3(.32,-.2,2.4),.22,Color("acbcb3"))
	p["breath"].scale=Vector3(1,.6,.04)
	var condensation:=p["breath"].material_override as StandardMaterial3D
	condensation.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	condensation.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	condensation.albedo_color.a=.16
	focus=p["face"]

func _show_face(t: float) -> void:
	var approach:=c.ss(t,.22,.82)
	var glass:=c.fx=="window_gaze"
	var z:=lerpf(4.2,2.9 if glass else .73,approach)
	p["face"].position=Vector3(.32*sin(t*5)*(1-approach),.05,z)
	p["face"].rotation.z=.22*approach*(1 if c.fx in ["laugh","face"] else -1)
	p["shoulders"].position.z=z+.2
	p["smile"].scale.x=1+approach*.8
	p["breath"].visible=glass and t>.5
	p["breath"].scale.x=c.ss(t,.5,.8)*3
	if glass:
		p["window"].get_node("GlassPane").visible=false
	_pose(t,0,.12*(1-approach) if c.fx=="gaze" else 0,0,0,-5*approach)

func _build_mirror() -> void:
	_room(5,9,Color("536d69"))
	p["frame"]=_anchor(Vector3(0,0,3))
	_box(Vector3(2.5,2.7,.08),Vector3.ZERO,Color("77755d"),p["frame"])
	_box(Vector3(2.3,2.5,.02),Vector3(0,0,-.06),Color("75908c"),p["frame"])
	p["reflection"]=_person(Vector3(0,-1.6,2.85),1,INK)
	p["head"]=_sphere(Vector3(0,1.68,-.14),.16,PAPER,p["reflection"])
	p["fractures"]=[]
	for i in 9:
		var a:float=i*TAU/9
		p["fractures"].append(_rod(Vector3(.1,.1,2.65),Vector3(cos(a),sin(a)*1.2,2.65),.008,PAPER))
	focus=p["head"]

func _show_mirror(t: float) -> void:
	var lean:=c.ss(t,.24,.77)
	p["reflection"].position.z=2.85-lean*1.8
	p["reflection"].rotation.z=-.18*lean
	for i in 9: p["fractures"][i].visible=t>.42+i*.018
	_pose(t,0,.045*sin(t*11)*(1-lean),0,.035*lean,-4*lean)

func _build_paper() -> void:
	_room(6,12,Color("4d6966"))
	_window(Vector3(0,.3,6),Vector2(3,2.5))
	p["plane"]=_anchor(Vector3(-1.8,.5,5))
	var vertices:=PackedVector3Array([Vector3(0,0,-.4),Vector3(-.5,0,.35),Vector3(0,.1,.15),Vector3(.5,0,.35)])
	var shape:=ArrayMesh.new()
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	c.mesh(shape,c._mat(PAPER,-1,true,false,false),0,0,0,p["plane"])
	p["sheets"]=[]
	for i in 16:
		var page:=_box(Vector3(.45,.65,.008),Vector3.ZERO,PAPER)
		p["sheets"].append(page)
	p["eye"]=_sphere(Vector3(0,.1,4),.17,INK)
	focus=p["plane"]

func _show_paper(t: float) -> void:
	var flight:=c.ss(t,.05,.64)
	p["plane"].position=Vector3(lerpf(-1.8,.1,flight),.5-.5*flight+sin(t*8)*.12,lerpf(5,.65,flight))
	p["plane"].rotation=Vector3(.15+flight*.6,flight*.4,.3*sin(t*7))
	p["plane"].visible=t<.72
	p["eye"].position.z=lerpf(4,1.2,c.ss(t,.5,.84))
	for i in 16:
		var a:float=i*TAU/16+t*1.4
		var r:=lerpf(2,.45,c.ss(t,.5,.86))
		p["sheets"][i].visible=t>.45
		p["sheets"][i].position=Vector3(cos(a)*r,sin(a)*r*.6,1.8+i*.04)
		p["sheets"][i].rotation.z=-a
	_pose(t,.03,0,0,-.025*c.ss(t,.5,.8))

func _build_fall() -> void:
	p["facade"]=_anchor(Vector3(0,0,0))
	_box(Vector3(18,55,.2),Vector3(0,-18,4),Color("526e69"),p["facade"])
	for row in 12:
		for col in 5:
			var window:=_window(Vector3((col-2)*3.2,-row*3.6,3.85),Vector2(1.9,1.8))
			window.reparent(p["facade"],true)
	p["rail"]=_box(Vector3(7,.08,.08),Vector3(0,-.7,1.2),PAPER)
	p["ground"]=_box(Vector3(30,.1,30),Vector3(0,-45,8),Color("9f9c82"))
	focus=_anchor(Vector3(0,-1,4))

func _show_fall(t: float) -> void:
	var drop:=c.ss(t,.08,.88)
	p["facade"].position.y=36*drop*drop
	p["rail"].position.y=-.7+drop*36
	p["ground"].position.y=-45+40*drop*drop
	_pose(t,-.16*drop,0,0,.06*drop,9*drop)

func _build_trash() -> void:
	_box(Vector3(3,.08,3),Vector3(0,-1.6,1),Color("172221"))
	for side in [-1,1]:
		_box(Vector3(.12,3.5,3),Vector3(side*1.1,.1,1),Color("33453d"))
	_box(Vector3(2.2,3.5,.12),Vector3(0,.1,2.4),Color("33453d"))
	p["lid"]=_anchor(Vector3(0,1.1,2.4))
	_box(Vector3(2.3,.1,2.8),Vector3(0,0,-1.35),Color("4d6355"),p["lid"])
	for i in 7: _box(Vector3(.06,.08,2.5),Vector3((i-3)*.3,.04,-1.35),COAL,p["lid"])
	p["sky"]=_box(Vector3(3,.04,4),Vector3(0,2,1),LIGHT)
	p["sliver"]=_box(Vector3(2,.015,.025),Vector3(0,1,.3),LIGHT)
	focus=_anchor(Vector3(0,.8,2.4))

func _show_trash(t: float) -> void:
	var close:=c.ss(t,.12,.67)
	p["lid"].rotation.x=lerpf(-1.25,0,close)
	p["sky"].visible=t<.65
	p["sliver"].scale.x=1-c.ss(t,.66,.86)
	_pose(t,.35*(1-.4*close),0,-.12*close,.02*sin(t*22)*c.ss(t,.6,.8))
	c.cue("knock",t,.72,func() -> void: c.snd("foley.door"))

func _build_door() -> void:
	_room(5,8,Color("4e615d"))
	p["left"]=_box(Vector3(1.15,3,.12),Vector3(.575,-.1,3),Color("77877d"))
	p["right"]=_box(Vector3(1.15,3,.12),Vector3(-.575,-.1,3),Color("77877d"))
	for x in [-1.27,1.27]: _box(Vector3(.2,3.3,.2),Vector3(x,-.1,3.12),INK)
	_box(Vector3(2.7,.2,.2),Vector3(0,1.45,3.12),INK)
	p["visitor"]=_person(Vector3(0,-1.6,3.5),1.1,INK)
	p["light"]=_box(Vector3(.55,.14,.05),Vector3(0,1.62,2.95),RUST)
	_text("请勿开门" if c.fx=="rules_knock" else "停 用",Vector3(0,.65,2.9),.15,INK)
	p["visitor"].hide()
	focus=_anchor(Vector3(0,.2,3))

func _show_door(t: float) -> void:
	var open:=c.ss(t,.35,.73)
	p["left"].position.x=.575+.55*open
	p["right"].position.x=-.575-.55*open
	p["visitor"].visible=t>.42
	p["visitor"].position.z=lerpf(3.5,1.1,c.ss(t,.6,.88))
	p["light"].visible=t<.8
	_pose(t,0,0,-.08*open,.015*sin(t*37)*open)
	for i in 3:
		var at:float=.12+i*.12
		c.cue("knock"+str(i),t,at,func() -> void: c.snd("foley.door",{"k":.4+i*.12}))

func _build_swarm() -> void:
	_room(6,12,Color("455d58"))
	_window(Vector3(0,.15,8),Vector2(3.7,2.6))
	p["lamp"]=_sphere(Vector3(0,.7,3.8),.12,LIGHT)
	_rod(Vector3(0,.8,3.8),Vector3(0,1.9,3.8),.02,COAL)
	var body:=BoxMesh.new()
	body.size=Vector3(.016,.016,.06)
	p["bodies"]=c.inst(body,c._mat(Color("050708"),-1,true,false,false),64)
	p["wings"]=c.inst(MothShape.wing(),c._mat(Color("090d10"),-1,true,false,false),128)
	p["bodies"].reparent(root,false)
	p["wings"].reparent(root,false)
	p["moths"]=[]
	for i in 64:
		p["moths"].append([c.rand.randf_range(0,TAU),c.rand.randf_range(.5,2),c.rand.randf_range(-1,1),c.rand.randf_range(14,26)])
	focus=p["lamp"]

func _show_swarm(t: float) -> void:
	var close:=c.ss(t,.28,.86)
	for i in 64:
		var moth:Array=p["moths"][i]
		var a:float=moth[0]+t*(4+(i%3))
		var r:float=lerpf(moth[1],.15+(i%7)*.055,close)
		var at:=Vector3(cos(a)*r,.5*(1-close)+sin(a*1.3)*r*.6,lerpf(3.8,.27,close)+sin(a)*r*.18)
		var scale:=Vector3.ONE*(1.4+close*1.2)
		p["bodies"].multimesh.set_instance_transform(i,MothShape.pose(at,a,0,scale))
		var flap:float=sin(t*c.dur*moth[3]+moth[0])*.95
		p["wings"].multimesh.set_instance_transform(i*2,MothShape.pose(at,a,flap,scale))
		p["wings"].multimesh.set_instance_transform(i*2+1,MothShape.pose(at,a,-flap,scale*Vector3(-1,1,1)))
	p["lamp"].visible=t<.66
	_pose(t,.08*(1-close),0,0,0,-3*close)
