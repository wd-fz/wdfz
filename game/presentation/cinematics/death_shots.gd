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
const DARK := Color("06090b")       # the stage's fog and sky: distance falls into this
const KEY := Color("b4c6d0")        # the cold key light from just behind the eye
const TUBE := Color("d6ded4")       # a fluorescent tube's pool
## Fog density of the stage dark; long or open sets keep their far subject (an exit, a road, a facade) readable.
const FOG := {"corridor":.035,"crash":.02,"flood":.05,"fall":.012,"assembly":.04,"banquet":.04,"garage":.035,"fence":.06,"classroom":.05}
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
	c.hide_world(DARK)
	c.veil(Color("03070a"))
	c.stage_dark(DARK,float(FOG.get(layout,.085)))
	call("_build_"+layout)
	_light_set()
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

## The default rig: a cold key from just above and behind the eye that lights what comes close, the
## distance left to the stage dark. Sets may add motivated lights (tubes, headlights) of their own.
func _light_set() -> void:
	c.key_light(Vector3(.3,.45,-.7),Vector3(0,-.85,4.5),KEY,8.0,12,52,root)

## Light fixtures glow (unshaded); everything else takes the stage lights and its fog.
func _surface(color: Color, alpha: float = -1, double: bool = false) -> StandardMaterial3D:
	if color==LIGHT: return c._mat(color,alpha,double,false,true)
	return c._mat_lit(color,alpha,double)

func _box(size: Vector3, at: Vector3, color: Color, parent: Node3D = null, alpha: float = -1) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return c.mesh(shape,_surface(color,alpha),at.x,at.y,at.z,parent if parent != null else root)

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
	return c.mesh(shape,_surface(color),at.x,at.y,at.z,parent if parent != null else root)

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
	return c.torus(radius,width,_surface(color,-1,true),at.x,at.y,at.z,parent if parent != null else root,6,40)

func _person(at: Vector3, scale: float = 1, color: Color = INK, kind: String = "person") -> Node3D:
	var actor := c.fig(kind,color,scale,0,0,false,true)
	actor.reparent(root,false)
	actor.position=at
	actors.append(actor)
	return actor

func _anchor(at: Vector3) -> Node3D:
	var node := Node3D.new()
	c.put(node,at.x,at.y,at.z,root)
	return node

func _room(width: float = 7, depth: float = 16, tone: Color = COAL) -> void:
	_box(Vector3(width,.08,depth),Vector3(0,-1.6,depth*.5-1),Color("3d5253"))
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
	# One tube actually lights its stretch of floor: a pool to cross on the way in, darkness beyond it.
	c.motive_light(Vector3(0,.7,clampf(depth*.42,3,7)),TUBE,2.6,4.6,root)

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

# ---- people: matte figures with HorrorKit heads and hands (rollcall .. door) ----
## Neck cut height and skull centre of each imported figure kind (figure-local metres at scale 1).
const _FIG_NECK := {"person":[1.645,Vector3(0,1.75,.005)],"teacher":[2.245,Vector3(0,2.37,.005)],"roam":[2.32,Vector3(0,2.47,.005)],"sit":[1.205,Vector3(0,1.3,.13)]}
static var _fig_cache := {}

## The imported figure without its egg head: triangles above the neck are dropped (cached per kind).
static func _fig_body(kind: String) -> Mesh:
	if _fig_cache.has(kind): return _fig_cache[kind]
	var source := FigureModel.make(kind,Color.BLACK)
	var found := source.find_children("*","MeshInstance3D",true,false)
	var result: Mesh = null
	if not found.is_empty():
		var arrays := (found[0] as MeshInstance3D).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var cut: float = _FIG_NECK[kind][0]
		var kept := PackedInt32Array()
		for i in range(0,index.size()-2,3):
			if v[index[i]].y<=cut and v[index[i+1]].y<=cut and v[index[i+2]].y<=cut:
				kept.append_array([index[i],index[i+1],index[i+2]])
		if not kept.is_empty(): arrays[Mesh.ARRAY_INDEX]=kept
		var shape := ArrayMesh.new()
		shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result=shape
	source.free()
	_fig_cache[kind]=result
	return result

## A matte skin: the kit's shader without self-glow or gloss and with only a faint rim, so a body stays
## in the dark and a light picks out an edge (a shoulder, a cheek, knuckles) instead of a plastic sheen.
static func _fig_skin(tone: Variant, rim: float = .3, shaded: bool = false) -> ShaderMaterial:
	var key := "skin|%s|%.2f|%s" % [str(tone),rim,shaded]
	if _fig_cache.has(key): return _fig_cache[key]
	var m := HorrorKit.skin(tone,0.0,shaded).duplicate() as ShaderMaterial
	m.set_shader_parameter("rim_strength",rim)
	m.set_shader_parameter("rim_emit",0.0)
	m.set_shader_parameter("gloss",0.0)
	_fig_cache[key]=m
	return m

## A HorrorKit head (it faces -z, towards the eye), matte, at a point of parent.
func _fig_head(opts: Dictionary, at: Vector3, size: float = 1.0, parent: Node3D = null) -> Node3D:
	var head := HorrorKit.head(opts)
	var face := head.get_node_or_null("Skull/Face") as MeshInstance3D
	if face != null: face.material_override=_fig_skin(opts.get("tone","wax"),float(opts.get("rim",.25)),true)
	var neck := head.get_node_or_null("Skull/Neck") as MeshInstance3D
	if neck != null: neck.material_override=_fig_skin(opts.get("tone","wax"),float(opts.get("rim",.25)),true)
	head.rotation_order=EULER_ORDER_YXZ
	head.scale=Vector3.ONE*size
	(parent if parent != null else root).add_child(head)
	head.position=at
	return head

## A person of the old build with a HorrorKit head on its neck. Like _person it faces +z (away from the
## eye; turn it PI to face the eye); its head (meta "head") is turned to match and can turn on its own.
func _fig(at: Vector3, kind: String, scale: float, tone: Variant, head: Dictionary = {}, rim: float = .3, parent: Node3D = null) -> Node3D:
	var actor := Node3D.new()
	actor.rotation_order=EULER_ORDER_YXZ
	var body := MeshInstance3D.new()
	body.name="Body"
	body.mesh=_fig_body(kind)
	body.material_override=_fig_skin(tone,rim)
	body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.scale=Vector3.ONE*scale
	actor.add_child(body)
	(parent if parent != null else root).add_child(actor)
	actor.position=at
	var opts := head.duplicate()
	if not opts.has("tone"): opts["tone"]=tone
	var skull := _fig_head(opts,(_FIG_NECK[kind][1] as Vector3)*scale,scale*float(head.get("size",1.12)),actor)
	skull.name="Head"
	skull.rotation.y=PI
	actor.set_meta("head",skull)
	return actor

## A HorrorKit hand with the matte skin (nails keep theirs).
func _fig_hand(opts: Dictionary, parent: Node3D = null) -> Node3D:
	var hand := HorrorKit.hand(opts)
	var mat := _fig_skin(opts.get("tone","wax"),float(opts.get("rim",.3)),true)
	for mi: Node in hand.find_children("*","MeshInstance3D",true,false):
		if mi.name!="Nail" or HorrorKit.is_dark(opts.get("tone","wax")): (mi as MeshInstance3D).material_override=mat
	hand.rotation_order=EULER_ORDER_YXZ
	(parent if parent != null else root).add_child(hand)
	return hand

## The stage key light (_light_set adds it last, after the set is built).
func _fig_key() -> Light3D:
	return c.stage_lights.back()

## One lamp blink, off between a and b; none with reduced effects (no flashing).
func _fig_blink(t: float, a: float, b: float) -> bool:
	return c.shk>0 and t>=a and t<b

## A smooth tube through points, radius r0 at the first point to r1 at the last (a neck), built anew
## from the points on every call, so it follows the timeline without keeping state.
static func _fig_tube(points: PackedVector3Array, r0: float, r1: float, seg: int = 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var normal := Vector3.ZERO
	for i in n:
		var tangent := (points[mini(i+1,n-1)]-points[maxi(i-1,0)]).normalized()
		if i==0:
			var ref := Vector3.RIGHT if absf(tangent.x)<.9 else Vector3.UP
			normal=(ref-tangent*ref.dot(tangent)).normalized()
		else:
			normal=(normal-tangent*normal.dot(tangent)).normalized()
		var binormal := tangent.cross(normal)
		var u := float(i)/maxf(1,n-1)
		var r := lerpf(r0,r1,u)*(1.0+.12*sin(u*PI*3.0)*(1.0-u))
		for j in seg+1:
			var a := TAU*j/seg
			st.set_uv(Vector2(float(j)/seg,u))
			st.add_vertex(points[i]+(normal*cos(a)+binormal*sin(a))*r)
	for i in n-1:
		for j in seg:
			var a := i*(seg+1)+j
			var b := a+seg+1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a+1)
			st.add_index(a+1)
			st.add_index(b)
			st.add_index(b+1)
	st.generate_normals()
	return st.commit()

## Cubic Bezier samples.
static func _fig_curve(a: Vector3, b: Vector3, c2: Vector3, d: Vector3, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		var u := float(i)/(count-1)
		var w := 1.0-u
		out.append(a*w*w*w+b*3*w*w*u+c2*3*w*u*u+d*u*u*u)
	return out

func _build_rollcall() -> void:
	_room(5,9)
	p["tube"]=c.stage_lights.back()
	_box(Vector3(3.5,1.5,.08),Vector3(0,.45,7.7),JADE)
	_text("到你了。",Vector3(0,.7,7.62),.3)
	# The patroller: tall and dark, a pale face that is slightly wrong, standing in the one pool of light.
	p["man"]=_fig(Vector3(.3,-1.6,4.4),"teacher",.86,Color("0a0e10"),{"tone":Color(.46,.46,.42),"skew":.4,"size":1.2},.5)
	var book := _anchor(Vector3(.1,-.55,4.2))
	_box(Vector3(.5,.66,.025),Vector3.ZERO,COAL,book)
	_box(Vector3(.44,.6,.012),Vector3(0,0,-.02),Color("a8a290"),book)
	_text("巡查登记",Vector3(0,.2,-.031),.065,INK,book)
	for i in 5:
		_box(Vector3(.32,.009,.003),Vector3(0,.08-i*.06,-.03),Color("66756c"),book)
	p["book"]=book
	p["name"]=_text("未到",Vector3(.07,-.22,-.033),.07,RUST,book)
	# The register is held out by a long hand that comes with it out of the dark.
	# Its fingers come over the top edge from behind: too long, one joint too many.
	p["hand"]=_fig_hand({"long":1.35,"thin":.75,"extra":true,"arm":.5,"tone":Color(.44,.44,.41)},book)
	p["hand"].position=Vector3(-.1,.2,.045)
	focus=book

func _show_rollcall(t: float) -> void:
	var man: Node3D=p["man"]
	var head: Node3D=man.get_meta("head")
	var book: Node3D=p["book"]
	var tube: Light3D=p["tube"]
	var gone:=t>=.3
	var reach:=c.ss(t,.32,.6)
	var lean:=c.ss(t,.76,.9)
	# Seen first standing still under the far tube; after the light falters he is somewhere in the dark.
	man.position=Vector3(.3,-1.6,4.4) if not gone else Vector3(lerpf(.62,.42,lean),-1.6,lerpf(2.5,1.55,lean))
	man.rotation=Vector3(.45*lean,PI+.15*lean,0)
	head.rotation=Vector3(-.18+.5*lean,PI+.35*lean*(1 if c.fx!="names" else -1),.22*lean)
	HorrorKit.pose_head(head,.1+.45*c.ss(t,.8,.95))
	tube.light_energy=0.0 if _fig_blink(t,.27,.31) else (2.6 if not gone else lerpf(1.4,.5,c.ss(t,.6,.9)))
	if gone:
		book.position=Vector3(lerpf(.5,.3,reach),lerpf(-.62,-.32,reach)-.1*lean,lerpf(3.0,1.0,reach)+.3*lean)
		book.rotation=Vector3(-.2*c.ss(t,.5,.8)-.25*lean,-.2,-.06)
	else:
		book.position=Vector3(.1,-.55,4.2)
		book.rotation=Vector3(.1,-.4,.05)
	# A finger runs down the list, then taps the line with your name.
	var mark:=c.ss(t,.62,.7)-c.ss(t,.7,.76)
	var hook:=[.05,.15,1.5,1.2]
	HorrorKit.pose_hand(p["hand"],.6,.18,[.2,[.05,.15+.5*mark,1.5-.6*mark,1.2],hook,hook,hook],Vector2(.05,0))
	p["hand"].rotation=Vector3(PI/2-.45,.1,0)
	_fig_key().light_energy=3.2
	p["name"].visible=t>.61
	p["name"].text="已到" if t>.78 else ("下一位" if c.fx=="names" else "未到")
	_pose(t,-.07*reach+.12*lean,0,-.06*reach,0,-4*reach)

func _build_garage() -> void:
	_room(10,22,Color("233034"))
	for x in [-3.4,3.4]:
		for z in [4,9,14,19]:
			_box(Vector3(.45,3.5,.45),Vector3(x,.15,z),Color("49514a"))
			_box(Vector3(.46,.22,.46),Vector3(x,-.4,z),RUST)
			_box(Vector3(2,.01,.06),Vector3(x*.6,-1.54,z),PAPER)
	# The far tube of the bay stands behind him: his shadow reaches down the lane towards you.
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(.6,1.2,13.2)
	p["tube"].omni_range=6.0
	# A pale roller shutter under that tube: the one bright thing his outline stands against.
	var shutter:=_anchor(Vector3(0,-.2,14.4))
	_box(Vector3(5.5,2.9,.08),Vector3.ZERO,Color("6d7770"),shutter)
	for i in 14: _box(Vector3(5.5,.025,.04),Vector3(0,-1.35+i*.2,-.05),Color("3b4440"),shutter)
	# Your own car: the hood edge low in the view, its two lamps throwing one beam down the bay.
	_box(Vector3(2.2,.12,1.1),Vector3(0,-1.02,.75),Color("0d1316"))
	p["lights"]=[]
	for x in [-.8,.8]:
		# The lamps themselves sit under the hood edge, out of view; only their throw is seen.
		p["lights"].append(_box(Vector3(.4,.06,.03),Vector3(x,-1.1,1.31),LIGHT))
		for i in 3:
			_box(Vector3(.7+i*.5,.006,2),Vector3(x,-1.53,2+i*1.8),Color("69736b"))
	p["beam"]=c.key_light(Vector3(0,-.85,1.4),Vector3(0,-.4,11),Color("e6dcc0"),40.0,24,18,root)
	p["man"]=_fig(Vector3(.3,-1.6,11),"roam",.8,Color("14191c"),{"tone":Color(.27,.28,.27),"skew":.7,"mouth":"none","eyes":"hollow","size":1.25},.45)
	p["man"].rotation.y=PI
	p["shadow"]=_box(Vector3(.55,.012,1),Vector3(0,-1.535,8),Color("030506"))
	focus=_anchor(Vector3(0,0,11))

func _show_garage(t: float) -> void:
	var man: Node3D=p["man"]
	var head: Node3D=man.get_meta("head")
	# Each time a lamp dies he is nearer; between the cuts he does not move at all.
	var lamps:=2 if t<.35 else (1 if t<.55 else 0)
	var rush:=c.ss(t,.76,.9)
	var z:float=11.0 if lamps==2 else (7.0 if lamps==1 else lerpf(4.2,1.6,rush))
	var x:float=.3 if lamps==2 else (-.25 if lamps==1 else lerpf(.35,.12,rush))
	man.position=Vector3(x,-1.6,z)
	man.rotation=Vector3(.5*rush,PI-.1*rush,0)
	head.rotation=Vector3(-.15+.4*rush,PI+.25*c.ss(t,.6,.75)-.2*rush,-.35*c.ss(t,.6,.75)-.2*rush)
	focus.position=Vector3(x,.1,z)
	var shadow: Node3D=p["shadow"]
	var long:float=(13.5-z)*.9+1.5
	shadow.scale.z=maxf(.01,long)
	shadow.position=Vector3(x*.8,-1.535,z-long*.5)
	shadow.visible=lamps>0 or rush<.5
	for i in 2: p["lights"][i].visible=i<lamps and not _fig_blink(t,.31+i*.2,.34+i*.2)
	var beam: Light3D=p["beam"]
	beam.light_energy=0.0 if _fig_blink(t,.31,.34) or _fig_blink(t,.51,.54) else 15.0*lamps
	var tube: Light3D=p["tube"]
	tube.light_energy=0.0 if _fig_blink(t,.66,.69) else 2.6*(1-c.ss(t,.8,.86))
	_fig_key().light_energy=lerpf(1.5,2.6,rush)
	_pose(t,.12*rush,.025*sin(t*12)*rush*c.shk,0,0,-6*rush)

func _build_backseat() -> void:
	# The driver's seat at night: dashboard, wheel, pillars and roof in the dark; the road outside.
	_box(Vector3(2.8,.4,.9),Vector3(0,-.78,1.3),Color("0e1417"))
	_box(Vector3(2.8,.08,.5),Vector3(0,.66,.75),Color("0b1013"))
	for x in [-1,1]: _rod(Vector3(x*1.05,-.58,1.55),Vector3(x*.95,.64,.95),.13,Color("0d1215"))
	_ring(Vector3(.36,-.5,.62),.19,.022,Color("161d20")).rotation.x=.45
	for x in [.26,.48]: _ring(Vector3(x,-.5,1.0),.055,.006,Color("6fa89b")).material_override=c._mat(Color("4f7d73"))
	_box(Vector3(30,.05,60),Vector3(0,-1.45,30),Color("1c2428"))
	for i in 9: _box(Vector3(.12,.01,1.6),Vector3(-.4,-1.42,4+i*4.5),Color("8a8a78"))
	_sphere(Vector3(-2.6,2.6,9),.16,LIGHT)
	_rod(Vector3(-2.6,2.6,9),Vector3(-2.6,-1.45,9),.08,Color("1b2226"))
	c.motive_light(Vector3(-2.4,2.2,8.6),Color("d9b98a"),4.0,8,root)
	# The instrument glow from below: the only light on what leans in from the back seat.
	p["dash"]=c.motive_light(Vector3(.3,-.5,.85),Color("7fb3a8"),.9,1.6,root)
	var mirror := _anchor(Vector3(0,.4,.95))
	_box(Vector3(.44,.15,.035),Vector3.ZERO,Color("101517"),mirror)
	# The glass holds the faint glow of the rear window, so the frame reads in the dark.
	_box(Vector3(.4,.115,.008),Vector3(0,0,-.02),Color("1f292c"),mirror).material_override=c._mat(Color("26312f"))
	_rod(Vector3(0,.07,0),Vector3(0,.26,.08),.02,Color("101517"),mirror)
	p["mirror"]=mirror
	# The reflection: a passenger who was not there, sitting back, then leaning between the seats.
	p["reflection"]=_fig_head({"tone":Color(.4,.41,.38),"mouth":"closed","skew":.25},Vector3(0,0,-.03),.3,mirror)
	focus=p["mirror"]
	# The weight on the shoulder: a long, cold hand from the back seat, over the right shoulder (set -x is screen right).
	p["hand"]=_fig_hand({"long":1.25,"thin":.4,"arm":.22,"tone":Color(.33,.34,.32),"quality":maxi(CampusData.tier,3)})
	# At the very end the passenger itself, at your right ear.
	p["face"]=_fig_head({"tone":Color(.36,.37,.34),"mouth":"closed","skew":.25},Vector3(-.36,.02,.34),1.0)

func _show_backseat(t: float) -> void:
	var lean := c.ss(t,.3,.62)
	var near := c.ss(t,.78,.9)
	var ghost: Node3D=p["reflection"]
	ghost.visible=t>.25 and t<.8
	ghost.position=Vector3(lerpf(-.1,0,lean),lerpf(-.01,-.005,lean),-.03)
	ghost.scale=Vector3.ONE*lerpf(.3,.5,lean)
	ghost.rotation=Vector3(-.1,0,.12*(1-lean))
	HorrorKit.pose_head(ghost,.0)
	(p["dash"] as Light3D).light_energy=0.0 if _fig_blink(t,.23,.27) else .9
	var reach:=c.ss(t,.45,.62)
	var hand: Node3D=p["hand"]
	hand.visible=t>.45
	hand.position=Vector3(lerpf(-.42,-.3,reach),lerpf(-.2,-.11,reach),lerpf(.05,.27,reach))
	hand.rotation=Vector3(-.05-.2*reach,PI+.75,.35)
	HorrorKit.pose_hand(hand,lerpf(.05,.45,c.ss(t,.58,.75)),.35,[.1],Vector2(.35*reach,0))
	var face: Node3D=p["face"]
	face.visible=t>=.8
	face.position=Vector3(lerpf(-.5,-.3,near),lerpf(-.02,.02,near),lerpf(.25,.36,near))
	face.rotation=Vector3(-.1,-.95+.25*near,.2)
	HorrorKit.pose_head(face,.5*c.ss(t,.84,.95))
	_fig_key().light_energy=1.1
	_pose(t,0,.34*c.ss(t,.76,.88),0,-.03*near,-3*near)

const ENV_WINDSHIELD := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float crack = 0.0;
uniform vec2 hit = vec2(.36, .42);
uniform float glare = 0.0;
uniform float rain = 1.0;
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 q = (UV - hit) * vec2(1.8, 1.0);
	float r = length(q);
	float a = atan(q.y, q.x);
	float lines = 0.0;
	float n = 17.0;
	float sec = floor((a / 6.2831853 + .5) * n);
	for (int k = -1; k <= 1; k++) {
		float s = sec + float(k);
		float ang = (s + .5 + (h1(s) - .5) * .7) / n * 6.2831853 - 3.1415927;
		float dang = a - ang - (h1(s * 3.7 + floor(r * 22.0)) - .5) * .07;
		float d = abs(sin(dang)) * r;
		float len = crack * (.3 + .9 * h1(s + 17.0));
		float w = .0016 + .0012 * r;
		lines = max(lines, (1.0 - smoothstep(w * .4, w, d)) * step(0.0, cos(dang)) * (1.0 - smoothstep(len * .8, len, r)));
	}
	for (int k = 1; k <= 4; k++) {
		float fk = float(k);
		float rr = fk * .05 * (1.0 + .4 * h1(fk * 3.1));
		float wob = rr * (1.0 + .06 * sin(a * 5.0 + fk * 2.0) + .03 * sin(a * 13.0 + fk));
		float on = smoothstep(rr * 1.2, rr * 1.8, crack) * step(.38, h1(floor((a + 3.1416) * 2.4) + fk * 9.0));
		lines = max(lines, on * (1.0 - smoothstep(.001, .0032, abs(r - wob))));
	}
	float crush = smoothstep(.02, .0, r) * step(.01, crack);
	float drop = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		vec2 g = UV * vec2(34.0, 21.0) * (1.0 + float(layer) * .73) + float(layer) * 5.3;
		vec2 cell = floor(g);
		float rh = h2(cell + float(layer) * 17.0);
		vec2 off = vec2(h2(cell + 3.1), h2(cell + 7.7)) - .5;
		vec2 f = fract(g) - .5 - off * .5;
		f.y *= 1.0 - .5 * step(.9, rh);
		drop = max(drop, (1.0 - smoothstep(.02 + .05 * rh, .04 + .07 * rh, length(f))) * step(.78, rh));
	}
	// Beads only glitter around the oncoming light; elsewhere they are barely there.
	drop *= rain * (.15 + exp(-length((UV - hit) * vec2(1.8, 1.0)) * 4.0));
	float lit = .2 + glare;
	ALBEDO = vec3(.82, .87, .88) * min(lit, 1.2);
	ALPHA = clamp(.03 + drop * (.03 + .5 * glare) + lines * (.45 + .45 * glare) + crush * .7, 0.0, 1.0);
}
"""

func _build_crash() -> void:
	# Wet asphalt that takes the beams, a centre line rushing in, reflector posts into the dark.
	_env_box(Vector3(16,.1,97),Vector3(0,-1.35,46),_env_lit(Color("1a1f22"),.3,0,.7))
	var paint := _env_lit(Color("8f8c7c"),.55)
	for side in [-1,1]: _env_box(Vector3(.12,.01,97),Vector3(side*3.4,-1.29,46),paint)
	for i in 16: pieces.append(_env_box(Vector3(.12,.012,2.2),Vector3(0,-1.288,0),paint))
	p["posts"]=[]
	var post_mat := _env_lit(Color("50574f"),.7)
	var reflector := _env_flat(Color("9a6a2c"))
	for i in 14:
		var post := _anchor(Vector3((-1 if i%2 else 1)*4.8,-1.3,0))
		_env_box(Vector3(.09,.95,.09),Vector3(0,.47,0),post_mat,post)
		_env_box(Vector3(.06,.12,.02),Vector3(0,.82,-.05),reflector,post)
		p["posts"].append(post)
	# Inside the car: dash, bonnet, pillars, roof edge, mirror, wheel and two dim gauges.
	var plastic := _env_lit(Color("0c0f11"),.75,0,.3)
	_env_box(Vector3(2.3,.32,.6),Vector3(0,-.7,.98),plastic)
	var bonnet := _env_box(Vector3(2.0,.06,1.5),Vector3(0,-.8,1.95),_env_lit(Color("1b252b"),.22,.55,.6))
	bonnet.rotation.x = -.07
	for side in [-1,1]:
		_env_rod(Vector3(side*.84,-.55,1.12),Vector3(side*.64,.47,.6),.1,plastic)
	_env_box(Vector3(1.5,.13,.14),Vector3(0,.5,.6),plastic)
	_env_box(Vector3(1.8,.03,.9),Vector3(0,.56,.15),_env_lit(Color("1e2224"),.95))
	_env_rod(Vector3(0,.5,.6),Vector3(0,.4,.6),.015,plastic)
	_env_box(Vector3(.26,.075,.03),Vector3(0,.37,.59),_env_lit(Color("20292d"),.3,.4))
	var wheel := _anchor(Vector3(.36,-.62,.5))
	wheel.rotation.x = .45
	c.torus(.19,.022,_env_lit(Color("101315"),.6),0,0,0,wheel,8,_env_segments(40))
	for a in [PI*.5+.35,PI*1.5,PI*.5-.35+PI]:
		_env_rod(Vector3.ZERO,Vector3(cos(a),sin(a),0)*.18,.03,plastic,wheel)
	_env_ball(Vector3.ZERO,.05,plastic,wheel)
	p["needles"]=[]
	for x in [.27,.45]:
		c.torus(.045,.004,_env_flat(Color("3b6e5c")),x,-.5,.76,root,4,24)
		var needle := _anchor(Vector3(x,-.5,.755))
		_env_box(Vector3(.004,.04,.002),Vector3(0,.02,0),_env_flat(Color("b06a3a")),needle)
		p["needles"].append(needle)
	# The windshield as one plane: its frame carries the wipers; the glass carries rain and the cracks.
	var low := Vector3(0,-.55,1.12)
	var up := (Vector3(0,.47,.6)-low)
	var glass := Node3D.new()
	glass.basis = Basis(Vector3.RIGHT,up.normalized(),Vector3.RIGHT.cross(up.normalized()))
	glass.position = low
	root.add_child(glass)
	p["glass"]=c.mesh(_env_quad(Vector3(.84,0,0),Vector3(-.84,0,0),Vector3(-.64,up.length(),0),Vector3(.64,up.length(),0)),_env_shader("windshield",ENV_WINDSHIELD,{"rain":1.0 if c.fx=="car_chase" else .55},2),0,0,-.01,glass)
	p["wipers"]=[]
	for x in [-.62,.06]:
		var wiper := _anchor(Vector3.ZERO)
		wiper.reparent(glass,false)
		wiper.position = Vector3(x,.05,-.03)
		_env_box(Vector3(.5,.012,.01),Vector3(.25,0,0),plastic,wiper)
		_env_box(Vector3(.52,.022,.02),Vector3(.3,.012,-.01),plastic,wiper)
		p["wipers"].append(wiper)
	# Our own headlights down the lane, and the oncoming truck: two points far off, then all light.
	p["beam"]=c.key_light(Vector3(0,-.85,2.6),Vector3(0,-1.3,14),Color("d9cfae"),16.0,45,34,root)
	var truck := _anchor(Vector3(2.8,0,70))
	p["truck"]=truck
	var paint_dark := _env_lit(Color("1e2528"),.5,.3)
	_env_box(Vector3(2.5,2.9,.4),Vector3(0,.15,.2),paint_dark,truck)
	_env_box(Vector3(2.2,.95,.05),Vector3(0,.95,-.03),_env_lit(Color("050708"),.15,.2,.8),truck)
	_env_box(Vector3(2.6,.28,.4),Vector3(0,-1.05,-.08),_env_lit(Color("2b3133"),.4,.6),truck)
	for i in 4: _env_box(Vector3(1.3,.05,.05),Vector3(0,-.32-i*.12,-.03),plastic,truck)
	p["heads"]=[]
	p["halos"]=[]
	for x in [-.92,.92]:
		p["heads"].append(_env_ball(Vector3(x,-.62,-.05),.13,_env_flat(Color("f2ead2"),-1,false),truck,12))
		p["halos"].append(_env_glow(Vector3(x,-.62,-.25),1,Color(1,.94,.78,1),truck,2.6))
	p["glare_light"]=c.key_light(Vector3(0,-.6,-.4),Vector3(0,-.3,-10),Color("f0e6c8"),0.0,90,32,truck)
	p["wash"]=_env_screen("wash","""
uniform vec4 tint : source_color = vec4(1.0, .96, .86, 0.0);
uniform vec2 center = vec2(0.0);
void fragment() {
	float asp = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float d = length((sp - center) * vec2(asp, 1.0));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * clamp(1.15 - d * .6, 0.0, 1.0);
}
""")
	focus=_anchor(Vector3(0,-.15,6))

func _show_crash(t: float) -> void:
	var hit := .58
	var after := maxf(t-hit,0)
	# Distance driven: steady until the hit, then a hard stop.
	var travelled := 120.0*minf(t,hit)+120.0*(1-exp(-after*30))/30
	for i in pieces.size(): pieces[i].position.z=fposmod(i*6.0-travelled,96)-1
	for i in p["posts"].size(): p["posts"][i].position.z=fposmod(i*7.0-travelled,98)-1
	var come := c.seg(t,.03,hit)
	var truck: Node3D = p["truck"]
	truck.position = Vector3(lerpf(2.8,.35,c.ss(t,.18,hit)),0,lerpf(70,2.05,come))
	var near := clampf(1-(truck.position.z-2)/68,0,1)
	# One of its lamps dies in the impact; the other stays on, dimmed, staring through the cracks.
	var dim := 1-.8*c.ss(t,hit+.02,.75)
	var lamp := [1-c.ss(t,hit+.01,hit+.03),dim]
	for i in 2:
		var halo: MeshInstance3D = p["halos"][i]
		halo.scale = Vector3.ONE*lerpf(.9,7.0,near*near*near)*maxf(lamp[i],.001)*(1 if i==0 else lerpf(.35,1,dim))
		halo.visible = lamp[i]>0
		p["heads"][i].visible = lamp[i]>0
	(p["glare_light"] as SpotLight3D).light_energy = (1.5+40*near*near*near)*(.5*lamp[0]+.5*lamp[1])*dim
	(p["beam"] as SpotLight3D).light_energy = 16.0*(1-c.ss(t,hit,hit+.01))
	var glare := near*near*lerpf(.3,1,dim)
	_env_param(p["glass"],"glare",glare)
	_env_param(p["glass"],"crack",c.ss(t,hit,hit+.12))
	# The wipers beat until the hit, then stay where they stopped.
	var beat := minf(t,hit)*c.dur*2.4
	for wiper: Node3D in p["wipers"]: wiper.rotation.z = 1.3*(.5-.5*cos(beat))
	var speed := (1-c.ss(t,hit,hit+.05))
	for needle: Node3D in p["needles"]: needle.rotation.z = lerpf(1.9,-1.1,speed*(.92+.02*sin(t*31)))
	# The glare swells over the last half second; with reduced effects it never washes the frame white.
	var peak := .85 if c.shk>0 else .28
	_env_param(p["wash"],"tint",Color(1,.95,.84,peak*c.ss(t,.47,.585)*(1-c.ss(t,.6,.7))))
	_env_key(lerpf(1.2,4.0,c.ss(t,hit,hit+.1)))
	var jolt := c.ss(t,hit,hit+.03)*(1-c.ss(t,hit+.05,.9))
	_pose(t,.07*jolt*c.shk,.004*sin(t*95)*come*c.shk,-.05*jolt*c.shk,.08*c.ss(t,hit,hit+.05),3*jolt)

func _build_classroom() -> void:
	_room(8,18,Color("64736d"))
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(.6,1.3,5.2)
	p["tube"].omni_range=7.5
	_box(Vector3(6,1.6,.08),Vector3(0,.45,16.8),Color("294c48"))
	p["writing"]=_text("请 回 到 你 的 座 位",Vector3(0,.6,16.72),.38)
	p["students"]=[]
	for row in 4:
		for col in 3:
			var x:float=(col-1)*1.9
			var z:float=3+row*2.6
			pieces.append(_desk(Vector3(x,0,z)))
			# Seated classmates, dark, facing the board; their pale heads can turn on their own.
			var student:=_fig(Vector3(x,-1.6,z-.75),"sit",1.0,Color("101719"),{"tone":Color(.37,.38,.35),"skew":.3 if (row+col)%2 else 0.0,"mouth":"none" if col==2 else "closed"},.35)
			p["students"].append(student)
	for z in [3,8,13]:
		var window := _window(Vector3(3.92,.4,z))
		window.rotation.y=PI/2
	p["own"]=_desk(Vector3(0,0,.7))
	p["blank"]=_box(Vector3(5.9,1.5,.04),Vector3(0,.45,16.65),Color("bbc2b1"))
	p["blank"].hide()
	if c.fx=="chalk":
		# The one figure on the board that the eraser leaves: a chalk outline, later standing in the room.
		var drawn:=FigureModel.make("person",Color("b9bfae"),true,.75,Color.BLACK,true,true)
		drawn.rotation.y=PI
		c.put(drawn,.9,-.75,16.6,root)
		p["drawn"]=drawn
		p["chalk"]=_fig(Vector3(.75,-1.6,1.7),"person",.95,Color(.5,.52,.48),{"tone":Color(.55,.56,.52),"mouth":"none","eyes":"hollow"},.2)
		p["chalk"].rotation.y=PI
	if c.fx=="assimilation":
		# The hand that seats you: from behind, on the left shoulder (set +x is screen left).
		p["hand"]=_fig_hand({"long":1.2,"thin":.5,"arm":.25,"tone":Color(.33,.34,.32)})
	focus=_anchor(Vector3(0,-.15,5.6))

## When a classmate's head has turned round to you (0..1), by effect; the one in front of you is last.
func _class_turn(t: float, i: int) -> float:
	if c.fx=="assimilation": return c.ss(t,.44+(i%3)*.01,.5+(i%3)*.01)
	var order:=11 if i==1 else (i*5)%11
	return c.ss(t,.14+order*.042,.24+order*.042)

func _show_classroom(t: float) -> void:
	var change:=c.ss(t,.22,.78)
	var assimilated:=c.fx=="assimilation"
	var staring:=c.fx=="stare"
	var erased:=not assimilated and not staring
	var near:=c.ss(t,.8,.92)
	var tube: Light3D=p["tube"]
	var students: Array=p["students"]
	for i in students.size():
		var student: Node3D=students[i]
		var head: Node3D=student.get_meta("head")
		var row:=floori(i/3.0)
		student.position=Vector3((i%3-1)*1.9,-1.6,3+row*2.6-.75)
		student.rotation=Vector3.ZERO
		head.position=(_FIG_NECK["sit"][1] as Vector3)
		head.rotation=Vector3(0,PI,0)
		HorrorKit.pose_head(head,0)
		if erased:
			# Erased a few at a time, each time the light falters; one comes back, already turned round.
			student.visible=t<.3+(i%3)*.12 or (i==1 and t>=.78)
			if i==1 and t>=.78:
				head.rotation=Vector3(-.15,0,.3)
				head.position+=Vector3(0,.04*near,-.35*near)
				HorrorKit.pose_head(head,.6*near)
			continue
		var turn:=_class_turn(t,i)
		if assimilated:
			student.position.x*=1-.16*change
			student.position.z-=.15*change
		# The bodies stay facing the board; only the heads come all the way round.
		head.rotation=Vector3(-.12*turn,PI-PI*turn,.18*turn*sin(i*2.3))
		if staring and i==1:
			head.position+=Vector3(0,.12*near,-1.0*near)
			head.rotation.z+=.35*near
			HorrorKit.pose_head(head,.55*near)
	for i in pieces.size():
		pieces[i].position.x=(i%3-1)*1.9*(1-.16*change if assimilated else 1+.35*change*float(erased))
	var falter:=_fig_blink(t,.28,.31) or _fig_blink(t,.4,.43) or _fig_blink(t,.52,.55) if erased else _fig_blink(t,.43,.46)
	tube.light_energy=0.0 if falter else lerpf(3.4,1.6,c.ss(t,.6,.9))
	p["blank"].visible=erased and t>.5
	p["blank"].scale.x=c.ss(t,.5,.82)
	p["own"].position.z=lerpf(.7,.33,change) if assimilated else .7
	p["writing"].text="已 归 队" if assimilated and t>.6 else "请 回 到 你 的 座 位"
	if p.has("chalk"):
		p["chalk"].visible=t>=.8
		p["chalk"].position=Vector3(lerpf(.85,.55,near),-1.6,lerpf(2.2,1.35,near))
		(p["chalk"].get_meta("head") as Node3D).rotation=Vector3(-.1,PI,.3*near)
		p["drawn"].visible=t<.8
	if p.has("hand"):
		var press:=c.ss(t,.55,.72)
		var hand: Node3D=p["hand"]
		hand.visible=t>.55
		hand.position=Vector3(lerpf(.45,.3,press),lerpf(-.12,-.2,press),lerpf(.02,.25,press))
		hand.rotation=Vector3(-.25-.15*press,PI-.75,-.35)
		HorrorKit.pose_hand(hand,lerpf(.1,.5,press),.3,[.1],Vector2(.3*press,0))
	_fig_key().light_energy=5.0
	if assimilated: _pose(t,-.1*change,0,-.25*change,0,-6*change)
	elif staring: _pose(t,-.06*near,0,0,.02*sin(t*9)*near,-5*near)
	else: _pose(t,.07*change,0,0,.025*sin(t*9)*change,7*change-9*near)

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

const ENV_WATER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float time = 0.0;
uniform float rain = 0.0;
uniform vec3 deep : source_color = vec3(.03, .09, .1);
uniform vec3 sky : source_color = vec3(.36, .5, .55);
uniform vec3 win_o = vec3(0.0);
uniform vec3 win_x = vec3(1.0, 0.0, 0.0);
uniform vec3 win_y = vec3(0.0, 1.0, 0.0);
uniform vec3 win_n = vec3(0.0, 0.0, 1.0);
uniform float stranger = 0.0;
uniform float reflect_k = 1.0;
uniform float below_k = 1.0;
uniform float ring_k = 1.0;
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
varying vec3 local;
void vertex() {
	float a = VERTEX.x * 2.3 + time * 1.7;
	float b = VERTEX.z * 3.1 - time * 1.3;
	float c = (VERTEX.x + VERTEX.z) * 5.7 + time * 2.9;
	VERTEX.y += sin(a) * .02 + sin(b) * .015 + sin(c) * .007;
	float dx = cos(a) * .02 * 2.3 + cos(c) * .007 * 5.7;
	float dz = cos(b) * .015 * 3.1 + cos(c) * .007 * 5.7;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
	local = VERTEX;
}
void fragment() {
	// Rain rings: one expanding ring per cell, each on its own beat.
	vec2 g = local.xz * 1.6;
	vec2 cell = floor(g);
	float rh = h2(cell);
	float age = fract(time * .9 + rh * 7.0);
	vec2 at = cell + .2 + .6 * vec2(h2(cell + 1.7), h2(cell + 4.1));
	float ring = (1.0 - smoothstep(0.0, .025, abs(length(g - at) - age * .45))) * (1.0 - age) * rain * ring_k;
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	// The window, reflected analytically: trace the mirrored view ray to the window's plane.
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 ray = reflect(normalize(world - INV_VIEW_MATRIX[3].xyz), wn);
	float facing = dot(ray, win_n);
	float pane = 0.0;
	float figure = 0.0;
	if (abs(facing) > .001) {
		vec3 hit = world + ray * (dot(win_o - world, win_n) / facing);
		float u = dot(hit - win_o, win_x) / dot(win_x, win_x);
		float v = dot(hit - win_o, win_y) / dot(win_y, win_y);
		float inside = step(abs(u), .97) * step(abs(v), .96) * step(.04, abs(u)) * step(.05, abs(v)) * step(0.0, dot(hit - world, ray));
		pane = inside * (.55 + .45 * (v * .5 + .5));
		// Someone standing in the reflected room, where the real room is empty.
		vec2 f = vec2(u - .2, v + .15);
		figure = stranger * inside * max(1.0 - smoothstep(.09, .11, length(f * vec2(1.0, .8) - vec2(0.0, .55))),
			1.0 - smoothstep(.0, .02, max(abs(f.x) - .13 + f.y * .03, abs(f.y + .1) - .55)));
	}
	if (FRONT_FACING) {
		vec3 mirrored = mix(sky * (.55 + .45 * pane) * pane, deep * .2, figure);
		ALBEDO = mix(deep, sky * .5, fres * .6) + vec3(ring * .25);
		EMISSION = mirrored * (.35 + .65 * fres) * reflect_k;
		ALPHA = mix(.7, .95, fres);
	} else {
		// From below: the bright, crawling underside, brightest where the window still is.
		float crawl = sin(local.x * 9.0 + time * 2.0) * sin(local.z * 7.0 - time * 1.6) * .5 + .5;
		ALBEDO = deep;
		EMISSION = sky * (.25 + .35 * crawl) * below_k + sky * 1.6 * pane * below_k;
		ALPHA = .92;
	}
	ROUGHNESS = .06;
	SPECULAR = .9;
}
"""

func _build_flood() -> void:
	_env_room(7,12,Color("4a5752"),Color("2f4a47"),Color("394240"))
	# The window at the far end: night outside, the only light in the room.
	var window := _window(Vector3(0,.35,10.9),Vector2(3,2.3))
	(window.get_node("GlassPane") as MeshInstance3D).material_override = _env_shader("rainpane","""
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float time = 0.0;
uniform float rain = 0.0;
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
void fragment() {
	vec3 night = mix(vec3(.16, .23, .27), vec3(.3, .4, .44), UV.y);
	float col = floor(UV.x * 70.0);
	float y = fract(UV.y * 1.5 + time * (.35 + h1(col) * .5) + h1(col + 3.0));
	float streak = smoothstep(.0, .05, y) * (1.0 - smoothstep(.05, .35, y)) * step(.55, h1(col * 1.3)) * rain;
	ALBEDO = night + vec3(.22, .27, .28) * streak;
}
""",{"rain":1.0 if c.fx=="drown" else .2})
	p["pane"]=window.get_node("GlassPane")
	p["window"]=window
	p["window_light"]=c.motive_light(Vector3(0,.3,9.4),Color("8fb2c4"),10.0,14,root)
	for x in [-1.9,1.9]:
		for z in [3.2,6.4]: _desk(Vector3(x,0,z))
	var surface := PlaneMesh.new()
	surface.size = Vector2(7,12)
	surface.subdivide_width = _env_segments(44)
	surface.subdivide_depth = _env_segments(70)
	# The water mirrors the window; the standing water mirrors someone in it whom the room does not hold.
	p["water"]=c.mesh(surface,_env_shader("water",ENV_WATER,{"rain":1.0 if c.fx=="drown" else .25,"stranger":1.0 if c.fx=="water" else 0.0},1),0,-1.5,5,root)
	# Exercise books and a pencil case afloat: silhouettes against the surface once you are under it.
	p["floats"]=[]
	var sheet := _env_lit(Color("b9b29a"),.9,0,.2,-1,true)
	for i in 5:
		var page := _env_box(Vector3(.3,.008,.42),Vector3.ZERO,sheet)
		p["floats"].append(page)
	var bead := SphereMesh.new()
	bead.radius = .5
	bead.height = 1
	bead.radial_segments = 10
	bead.rings = 6
	p["bubbles"]=c.inst(bead,_env_lit(Color(.7,.85,.86),.05,0,1.0,.32),44)
	p["bubbles"].reparent(root,false)
	p["under"]=_env_screen("underwater","""
uniform float under = 0.0;
uniform float edge = 0.0;
uniform float line = 0.0;
uniform float time = 0.0;
uniform float deep = 0.0;
void fragment() {
	float wav = .025 * sin(sp.x * 7.0 + time * 3.0) + .012 * sin(sp.x * 19.0 - time * 5.0);
	float below = smoothstep(line + wav + .015, line + wav - .015, sp.y);
	float mask = max(under, below * edge);
	vec3 col = mix(vec3(.03, .12, .13), vec3(.0, .015, .02), clamp((1.0 - sp.y) * .5 + deep * .6, 0.0, 1.0));
	float shaft = vn(vec2(sp.x * 2.6 + sp.y * .7, time * .25)) * smoothstep(-.8, 1.0, sp.y);
	col += vec3(.06, .14, .15) * shaft * (1.0 - deep * .8) * under;
	float meniscus = (1.0 - smoothstep(0.0, .008, abs(sp.y - line - wav))) * edge * (1.0 - under);
	ALBEDO = col + vec3(.3, .38, .38) * meniscus;
	ALPHA = clamp(mask * (.35 + .5 * deep) + meniscus * .3, 0.0, 1.0);
}
""")
	focus=_anchor(Vector3(0,0,3))

func _show_flood(t: float) -> void:
	var time := t*c.dur
	var level := lerpf(-1.4,.55,c.ss(t,.05,.86))
	var sink := -.35*c.ss(t,.66,1)
	var water: MeshInstance3D = p["water"]
	water.position.y = level
	_env_param(water,"time",time)
	_env_param(p["pane"],"time",time)
	# Above water the window stays where it is; under it, the light drifts away and dims.
	var gone := c.ss(t,.6,.95)
	p["window"].position.z = 10.9+9*gone
	(p["window_light"] as OmniLight3D).light_energy = 10.0*(1-.7*gone)
	var frame: Transform3D = (p["pane"] as Node3D).global_transform
	_env_param(water,"win_o",frame.origin)
	_env_param(water,"win_x",frame.basis.x.normalized()*1.5)
	_env_param(water,"win_y",frame.basis.y.normalized()*1.15)
	_env_param(water,"win_n",frame.basis.z.normalized())
	_env_param(water,"below_k",1.0-.6*c.ss(t,.75,1))
	_env_param(water,"ring_k",1.0-c.ss(level-c.ss(t,.66,1)*-.35,-.5,-.1))
	for i: int in p["floats"].size():
		var page: MeshInstance3D = p["floats"][i]
		var x := sin(i*2.7+time*.15)*1.6
		var z := 1.6+i*1.1+cos(i*1.9+time*.11)*.4
		page.position = Vector3(x,level+.012+.02*sin(x*2.3+time*1.7),z)
		page.rotation = Vector3(.06*sin(time*1.3+i),i*1.3+time*.05,.05*cos(time*1.1+i))
	# Bubbles: drifting up from the floor once the room is flooded, then the last breath, large and close.
	var under := c.ss(level-sink,-.01,.06)
	var bubbles: MultiMeshInstance3D = p["bubbles"]
	for i in 44:
		var at: Vector3
		var size: float
		if i<34:
			size = .008+.03*pow(_env_h(i+.5),3)
			var depth := level+1.6
			at = Vector3(sin(i*7.3)*1.5,-1.6+fposmod(_env_h(i+3.1)*depth+time*(.25+size*14),maxf(depth,.01)),.5+_env_h(i+9.2)*3.2)
			at.x += .03*sin(time*6+i)
			if t<.3: size = 0
		else:
			var k := i-34
			var rise := c.seg(t,.64+k*.012,.8+k*.012)
			size = (.02+.035*_env_h(k+20.0))*(1 if rise>0 and rise<1 else 0)
			at = Vector3(.12*sin(k*2.1)+.05*sin(time*9+k),lerpf(-.35,.5,rise*rise)+sink,.35+.08*k)
		if at.y>level: size = 0
		bubbles.multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3(1,.85,1)*size*2),at))
	var look := c.ss(t,.6,.86)
	_pose(t,.5*look,0,sink,.02*sin(t*8)*look)
	# The water line on the lens, then the underwater colour and a short, dense, green-black fog.
	var forward := -c.cam.global_transform.basis.z
	var horizon := -tan(asin(clampf(forward.y,-.99,.99)))/tan(deg_to_rad(c.cam.fov*.5))
	var rel := level-sink
	var screen: MeshInstance3D = p["under"]
	_env_param(screen,"under",under)
	_env_param(screen,"edge",1.0-c.ss(absf(rel),.03,.09) if rel<.09 else 0.0)
	_env_param(screen,"line",horizon+rel*8)
	_env_param(screen,"time",time)
	_env_param(screen,"deep",c.ss(t,.7,1))
	var env := c.cam.environment
	if env != null:
		env.fog_light_color = DARK.lerp(Color(.012,.05,.055),under)
		env.fog_density = lerpf(float(FOG["flood"]),.12+.25*c.ss(t,.8,1),under)

## A school tracksuit jacket on a hanger: a draped body with folds that deepen towards an uneven hem,
## hanging sleeves with the white stripe, and an empty collar. Origin at the hanger hook's base.
func _env_jacket() -> Node3D:
	var jacket := Node3D.new()
	var cloth := _env_lit(Color(1,1,1),.95,0,.15,-1,true)
	cloth.vertex_color_use_as_albedo = true
	var navy := Color("223349")
	var body := _env_grid(_env_segments(36),_env_segments(18),func(u: float, v: float) -> Vector3:
		var a := u*TAU
		var open := c.ss(v,0,.16)
		var w := lerpf(.065,.235,open)+.03*v
		var d := lerpf(.055,.085,open)+.01*v
		var fold := 1+.07*sin(a*7+v*2.5)*c.ss(v,.2,1)+.03*sin(a*13)*v
		var y := -.07*open-maxf(v-.16,0)*.78+.025*sin(a*3+1)*v*v
		return Vector3(cos(a)*w*fold,y,sin(a)*d*fold),true,func(u: float, v: float) -> Color:
		var zip := absf(fposmod(u-.75+.5,1)-.5)<.012 and v>.1
		return navy.lightened(.12) if zip else navy.darkened(.08*sin(u*TAU*7)*c.ss(v,.2,1)))
	c.mesh(body,cloth,0,0,0,jacket)
	for side in [-1,1]:
		var sleeve := _env_grid(_env_segments(14),_env_segments(12),func(u: float, v: float) -> Vector3:
			var a := u*TAU
			var r := lerpf(.06,.048,v)*(1+.08*sin(a*5+v*9)*v)
			var center := Vector3(side*lerpf(.215,.25,v),-.07-v*.6,lerpf(0,.025,v))
			return center+Vector3(cos(a)*r,0,sin(a)*r),true,func(u: float, _v: float) -> Color:
			return Color("d9dad2") if absf(fposmod(u-(.0 if side>0 else .5)+.5,1)-.5)<.07 else navy)
		c.mesh(sleeve,cloth,0,0,0,jacket)
	# The collar is empty: a hollow going down into black.
	_env_ball(Vector3(0,-.055,0),.058,_env_flat(Color("020304")),jacket,10).scale = Vector3(1,.35,.9)
	var wire := _env_lit(Color("8d9190"),.35,.8)
	_env_rod(Vector3(-.2,-.06,0),Vector3(0,.03,0),.008,wire,jacket)
	_env_rod(Vector3(.2,-.06,0),Vector3(0,.03,0),.008,wire,jacket)
	_env_rod(Vector3(0,.03,0),Vector3(0,.1,0),.008,wire,jacket)
	return jacket

func _build_frost() -> void:
	_env_room(5,10,Color("56656a"),Color("2c4148"),Color("3c4547"))
	var window := _window(Vector3(0,.4,8.9),Vector2(2.6,2.2))
	(window.get_node("GlassPane") as MeshInstance3D).material_override = _env_flat(Color("4a6a7c"))
	c.motive_light(Vector3(0,.3,8.0),Color("9cc0d6"),7.0,10,root)
	_env_rod(Vector3(-2.2,.62,4.5),Vector3(2.2,.62,4.5),.03,_env_lit(Color("6c716f"),.4,.7))
	for i in 7:
		var coat := _env_jacket()
		root.add_child(coat)
		pieces.append(coat)
	p["frost"]=_env_screen("frost","""
uniform float grow = 0.0;
uniform float time = 0.0;
float ridge(vec2 p) { return 1.0 - abs(vn(p) * 2.0 - 1.0); }
void fragment() {
	float asp = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 p = sp * vec2(asp, 1.0);
	// 0 at the frame's edge, 1 at its centre; the front creeps in unevenly.
	float e = min((1.0 - abs(sp.x)) * asp, 1.0 - abs(sp.y));
	float front = grow * .9 + .18 * (vn(p * 2.3) - .5) + .08 * (vn(p * 7.0) - .5);
	// Feathered crystals: sharpened ridges at three scales, each domain turned.
	mat2 r1 = mat2(vec2(.8, .6), vec2(-.6, .8));
	float f1 = pow(ridge(p * 5.0), 14.0);
	float f2 = pow(ridge(r1 * p * 11.0 + 3.0), 18.0);
	float f3 = pow(ridge(r1 * r1 * p * 23.0 + 7.0), 22.0);
	float fern = max(f1, max(f2 * .9, f3 * .75));
	float solid = smoothstep(front - .02, front - .25, e);
	float reach = smoothstep(front + .16, front - .02, e);
	float grain = step(.93, h2(floor(gl_FragCoord.xy * .5))) * solid;
	float a = clamp(solid * (.38 + .25 * vn(p * 9.0)) + fern * reach * .85 + grain * .3, 0.0, .92);
	ALBEDO = mix(vec3(.62, .72, .78), vec3(.9, .95, .97), fern);
	ALPHA = a * step(.001, grow);
}
""")
	p["breaths"]=[]
	for i in 5:
		var puff := MeshInstance3D.new()
		puff.mesh = QuadMesh.new()
		puff.material_override = _env_shader("breath","""
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float fade = 0.0;
uniform float seed = 0.0;
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 q = UV - .5;
	float n = vn(UV * 5.0 + seed * 7.0) * .6 + vn(UV * 11.0 - seed * 3.0) * .4;
	float body = smoothstep(.5, .1, length(q) + (n - .5) * .35);
	ALBEDO = vec3(.78, .84, .86);
	ALPHA = body * fade * .5;
}
""",{"seed":float(i)},5)
		root.add_child(puff)
		p["breaths"].append(puff)
	focus=_anchor(Vector3(0,0,4.5))

func _show_frost(t: float) -> void:
	var close := c.ss(t,.2,.86)
	# The rack's coats sway, then drift towards you; the middle one comes until its empty collar is at your eyes.
	for i in pieces.size():
		var coat: Node3D = pieces[i]
		var sway := sin(t*c.dur*1.3+i*1.7)
		if i==3:
			var come := c.ss(t,.3,.9)
			coat.position = Vector3(.03*sway*(1-come),lerpf(.62,.14,come),lerpf(4.5,.62,come))
			coat.rotation = Vector3(.05*sway*(1-come),PI+.12*(1-come),.03*sway)
		else:
			coat.position = Vector3((i-3)*.58,.62,4.5-close*(.9+_env_h(i+1.0)*.6))
			coat.rotation = Vector3(.04*sway,PI+(_env_h(i+4.0)-.5)*.5,.025*sway)
	# Five breaths, each fainter and later than the one before; then none.
	for i in 5:
		var puff: MeshInstance3D = p["breaths"][i]
		var start := [.06,.26,.45,.62,.76][i] as float
		var life := c.seg(t,start,start+.16)
		puff.visible = life>0 and life<1
		puff.position = Vector3(.02*sin(i*3.0),lerpf(-.2,-.06,life),lerpf(.22,.75,life))
		puff.scale = Vector3.ONE*lerpf(.12,.6,life)
		_env_param(puff,"fade",sin(life*PI)*(1-i*.17))
	_env_param(p["frost"],"grow",c.ss(t,.12,.92))
	_env_key(lerpf(4,2,close))
	var shiver := c.ss(t,.3,.7)*(1-c.ss(t,.8,.95))
	_pose(t,.03*close,.006*sin(t*c.dur*21)*shiver*c.shk,0,.012*sin(t*c.dur*17)*shiver,-4*close)

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
	c.motive_light(Vector3(0,1.1,-.6),TUBE,3.0,4.0,p["exit"])
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
	# Dusty, pale moths: lit by the key as they come close, after the lamp has gone.
	p["bodies"]=c.inst(body,c._mat_lit(Color("3a352c"),-1,true),64)
	p["wings"]=c.inst(MothShape.wing(),c._mat_lit(Color("7a7262"),-1,true),128)
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

# ---- Environment-shot helpers (crash, flood, frost, broadcast, bell, banquet, cup, corridor, paper,
# fall, trash, swarm). Pure: no random draws, every pose recomputed from t. Shaders use only what
# Forward+, Mobile and Compatibility share (no screen reads, no derivatives-dependent features). ----

static var _env_shaders := {}

## Screen-space overlays draw on a 2x2 quad written straight to clip space, above the set, under the veil.
const ENV_SCREEN_HEAD := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled;
varying vec2 sp;
void vertex() { sp = VERTEX.xy; POSITION = vec4(VERTEX.xy, .5, 1.0); }
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
"""

## A soft additive glow that always faces the camera (a lamp's halo, a headlight's bloom).
const ENV_GLOW := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, .95, .8, 1.0);
uniform float power = 2.2;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV - .5) * 2.0;
	ALBEDO = tint.rgb;
	ALPHA = tint.a * pow(clamp(1.0 - d, 0.0, 1.0), power);
}
"""

## Deterministic 0..1 hash of an index (no random state).
func _env_h(i: float) -> float:
	return fposmod(sin(i*12.9898)*43758.5453,1.0)

func _env_shader(key: String, code: String, params: Dictionary = {}, priority: int = 0) -> ShaderMaterial:
	if not _env_shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		_env_shaders[key] = shader
	var m := ShaderMaterial.new()
	m.shader = _env_shaders[key]
	m.render_priority = priority
	for name: String in params: m.set_shader_parameter(name,params[name])
	return m

func _env_lit(color: Color, rough: float = .85, metal: float = 0, spec: float = .4, alpha: float = -1, double: bool = false) -> StandardMaterial3D:
	var m := c._mat_lit(color,alpha,double,rough)
	m.metallic = metal
	m.metallic_specular = spec
	return m

func _env_flat(color: Color, alpha: float = -1, fog: bool = true) -> StandardMaterial3D:
	return c._mat(color,alpha,true,false,fog)

func _env_box(size: Vector3, at: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return c.mesh(shape,mat,at.x,at.y,at.z,parent if parent != null else root)

func _env_rod(a: Vector3, b: Vector3, width: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var result := _env_box(Vector3(width,a.distance_to(b),width),(a+b)*.5,mat,parent)
	result.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return result

func _env_ball(at: Vector3, radius: float, mat: Material, parent: Node3D = null, segments: int = 16) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius*2
	shape.radial_segments = segments
	shape.rings = segments/2
	return c.mesh(shape,mat,at.x,at.y,at.z,parent if parent != null else root)

func _env_glow(at: Vector3, size: float, tint: Color, parent: Node3D = null, power: float = 2.2) -> MeshInstance3D:
	var quad := QuadMesh.new()
	var glow := c.mesh(quad,_env_shader("glow",ENV_GLOW,{"tint":tint,"power":power},4),at.x,at.y,at.z,parent if parent != null else root)
	glow.scale = Vector3.ONE*size
	return glow

## A full-screen overlay with its own fragment code (ENV_SCREEN_HEAD supplies sp: -1..1 screen, h1, h2, vn).
func _env_screen(key: String, fragment: String, params: Dictionary = {}, priority: int = 90) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	var overlay := c.mesh(quad,_env_shader("screen_"+key,ENV_SCREEN_HEAD+fragment,params,priority),0,0,0,root)
	overlay.custom_aabb = AABB(Vector3(-500,-500,-500),Vector3(1000,1000,1000))
	overlay.name = "Screen_"+key
	return overlay

func _env_param(node: GeometryInstance3D, name: String, value: Variant) -> void:
	(node.material_override as ShaderMaterial).set_shader_parameter(name,value)

## A flat quad from four corners (bottom-left, bottom-right, top-right, top-left); UV y runs top to bottom.
func _env_quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var normal := (b-a).cross(d-a).normalized()
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a,b,cc,d])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([normal,normal,normal,normal])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2])
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return shape

## A smooth grid surface: f(u, v) -> point, u around (0..1, closed when wrap), v along (0..1). UV = (u, v).
func _env_grid(cols: int, rows: int, f: Callable, wrap: bool = false, tint: Callable = Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := cols if wrap else cols+1
	for j in rows+1:
		for i in width:
			var u := float(i)/cols
			var v := float(j)/rows
			st.set_uv(Vector2(u,v))
			if tint.is_valid(): st.set_color(tint.call(u,v))
			st.add_vertex(f.call(u,v))
	for j in rows:
		for i in cols:
			var a := j*width+i
			var b := j*width+(i+1)%width if wrap else j*width+i+1
			var d := a+width
			var e := b+width
			st.add_index(a)
			st.add_index(b)
			st.add_index(e)
			st.add_index(a)
			st.add_index(e)
			st.add_index(d)
	st.generate_normals()
	return st.commit()

## A surface of revolution about +Y: profile points (radius, y) from one end to the other.
func _env_lathe(profile: PackedVector2Array, segments: int) -> ArrayMesh:
	return _env_grid(segments,profile.size()-1,func(u: float, v: float) -> Vector3:
		var k := v*(profile.size()-1)
		var i := mini(int(k),profile.size()-2)
		var at := profile[i].lerp(profile[i+1],k-i)
		return Vector3(cos(u*TAU)*at.x,at.y,sin(u*TAU)*at.x),true)

func _env_segments(base: int) -> int:
	return maxi(8,int(base*(.5+.125*clampi(CampusData.tier,0,4))))

## The default cold key of _light_set (added after the build): sets may dim it per frame.
func _env_key(energy: float) -> void:
	for light: Light3D in c.stage_lights:
		if is_instance_valid(light) and light.get_parent()==root and light is SpotLight3D and light.position.is_equal_approx(Vector3(.3,.45,-.7)):
			light.light_energy = energy

static var _env_textures := {}

## Small procedural greyscale textures (cached): "tile" floor grout, "grime" mottled stains.
func _env_texture(kind: String) -> ImageTexture:
	if _env_textures.has(kind): return _env_textures[kind]
	var size := 64
	var image := Image.create(size,size,false,Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := 1.0
			if kind=="tile":
				v = .93+.07*_env_h(floori(x/32.0)*7.0+floori(y/32.0)*13.0)
				if x%32<2 or y%32<2: v = .55
			else:
				v = .7+.3*(.5+.25*sin(x*.31+sin(y*.17)*2.0)+.25*sin(y*.23+cos(x*.13)*3.0))*(.8+.2*_env_h(x*64.0+y))
			image.set_pixel(x,y,Color(v,v,v))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_env_textures[kind] = texture
	return texture

func _env_textured(color: Color, kind: String, scale: float, rough: float = .8) -> StandardMaterial3D:
	var m := _env_lit(color,rough)
	m.albedo_texture = _env_texture(kind)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE*scale
	return m

## A plain school room around the eye: tiled floor, a painted dado below a pale upper wall, no lights.
func _env_room(width: float, depth: float, upper: Color, lower: Color, floor_color: Color, ceiling: bool = true, back: bool = true) -> void:
	var z := depth*.5-1
	_env_box(Vector3(width,.08,depth),Vector3(0,-1.64,z),_env_textured(floor_color,"tile",.55,.55))
	if ceiling: _env_box(Vector3(width,.08,depth),Vector3(0,1.94,z),_env_lit(upper.darkened(.35),.95,0,.1))
	var top := _env_textured(upper,"grime",.35,.95)
	var dado := _env_textured(lower,"grime",.5,.55)
	var trim := _env_lit(lower.darkened(.5),.5)
	for side in [-1,1]:
		_env_box(Vector3(.08,2.3,depth),Vector3(side*width*.5,.75,z),top)
		_env_box(Vector3(.09,1.3,depth),Vector3(side*width*.5,-.95,z),dado)
		_env_box(Vector3(.11,.035,depth),Vector3(side*width*.5,-.3,z),trim)
	if back:
		_env_box(Vector3(width,2.3,.08),Vector3(0,.75,depth-1),top)
		_env_box(Vector3(width,1.3,.09),Vector3(0,-.95,depth-1),dado)

## Pin a node to the camera (call after the last _pose of the frame): offset is camera-local.
func _env_on_camera(node: Node3D, offset: Transform3D) -> void:
	node.global_transform = c.cam.global_transform*offset
