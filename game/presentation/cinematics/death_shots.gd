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
const DARK := Color("0b0e10")       # the stage's fog and sky: distance falls into this
const KEY := Color("d8d8cf")        # the neutral key light from just behind the eye
const TUBE := Color("d6ded4")       # a fluorescent tube's pool
const WALL := Color("8b8a82")       # school plaster; the green dado below it is _room's
const FOG_TONE := Color("0d1113")   # fog and sky floor: never pure black
const GRADE_SKIP := ["flood"]       # sets whose water/dark is their own light logic
const UNIFORM := {"person":Color("181e2b"),"sit":Color("181e2b"),"teacher":Color("131416"),"roam":Color("131416")}   # dark matte clothes on the dressed figures (tools/remodel/dress.py): a dark navy school uniform, the adults near black. The plain mesh had no clothes and read as a painted mannequin when lit; the garments carry hems, collar and zip now, but stay dark
const SKIN := Color(.17,.16,.15)   # far darker than a living face: under the stage lights anything lighter reads as a white mask
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

func restore() -> void:
	pass

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
	_grade()
	_light_set()
	c.d["scene"] = root
	c.d["focus"] = focus
	c.d["layout"] = layout

## A floor under every set's ambient light and fog (never lowers a brighter value): the shots stay
## readable and neutral without each one re-tuning its own stage_dark.
func _grade() -> void:
	if layout in GRADE_SKIP: return
	var env := c.cam.environment
	if env == null: return
	env.ambient_light_energy = maxf(env.ambient_light_energy,.55)
	env.ambient_light_color = env.ambient_light_color.lerp(Color(.27,.26,.24),.7)
	if env.background_color.is_equal_approx(DARK): env.background_color = FOG_TONE
	if env.fog_light_color.is_equal_approx(DARK): env.fog_light_color = FOG_TONE
	env.fog_density = clampf(env.fog_density,.02,.05)

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
	c.key_light(Vector3(.3,.45,-.7),Vector3(0,-.85,4.5),KEY,6.5,12,52,root)

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

func _room(width: float = 7, depth: float = 16, tone: Color = WALL) -> void:
	_box(Vector3(width,.08,depth),Vector3(0,-1.6,depth*.5-1),Color("57554e"))
	_box(Vector3(width,.08,depth),Vector3(0,1.9,depth*.5-1),Color("6f6d66"))
	_box(Vector3(.08,3.5,depth),Vector3(-width*.5,.15,depth*.5-1),tone)
	_box(Vector3(.08,3.5,depth),Vector3(width*.5,.15,depth*.5-1),tone)
	_box(Vector3(width,3.5,.08),Vector3(0,.15,depth-1),tone)
	for side in [-1,1]:
		_box(Vector3(.03,1.15,depth),Vector3(side*(width*.5-.055),-1.025,depth*.5-1),Color("3f5b4d"))
		_box(Vector3(.1,.04,depth),Vector3(side*(width*.5-.04),-.45,depth*.5-1),Color("2e4438"))
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

## Drop the cached figure bodies, shaders and textures (the app and the test runner call it on exit).
static func clear_cache() -> void:
	_fig_cache.clear()
	_env_shaders.clear()
	_env_textures.clear()

## The imported figure without its egg head: triangles above the neck are dropped (cached per kind).
## The dressed variant is used when present: one surface per garment, each surface named after it
## (skin, jacket, trim, zip, trousers, shoes, shirt). Otherwise the plain body, one surface named "body".
static func _fig_body(kind: String) -> Mesh:
	if _fig_cache.has(kind): return _fig_cache[kind]
	var cut: float = _FIG_NECK[kind][0]
	var shape := ArrayMesh.new()
	var scene := FigureModel.dressed(kind)
	var source: Node3D = scene.instantiate() if scene != null else FigureModel.make(kind,Color.BLACK)
	for found: Node in source.find_children("*","MeshInstance3D",true,false):
		var mesh := (found as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var kept := PackedInt32Array()
			for i in range(0,index.size()-2,3):
				if v[index[i]].y<=cut and v[index[i+1]].y<=cut and v[index[i+2]].y<=cut:
					kept.append_array([index[i],index[i+1],index[i+2]])
			if kept.is_empty(): continue
			arrays[Mesh.ARRAY_INDEX]=kept
			shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			shape.surface_set_name(shape.get_surface_count()-1,String(found.name).get_slice("_",2) if scene != null else "body")
	source.free()
	var result: Mesh = shape if shape.get_surface_count()>0 else null
	_fig_cache[kind]=result
	return result

## Clothes: the kit's matte shader with a coarse weave instead of veins, the baked crease shade kept
## (folds, hems and the collar read from it), and only a faint edge. Garments are shades of the figure's
## tone: the jacket is the tone, trousers and shoes darker, the stripes and the zip a dull grey, a shirt a
## dirty white held well below the light, so a lit uniform never turns into a bright costume.
static func _fig_cloth(tone: Color, garment: String, rim: float) -> ShaderMaterial:
	var key := "cloth|%s|%s|%.2f" % [tone.to_html(),garment,rim]
	if _fig_cache.has(key): return _fig_cache[key]
	var col := tone
	match garment:
		"trousers": col = tone.darkened(.3)
		"shoes": col = tone.darkened(.55)
		"trim": col = tone.lerp(Color(.42,.42,.4),.45)
		"zip": col = tone.lerp(Color(.3,.31,.32),.25)
		"shirt": col = tone.lerp(Color(.42,.41,.38),.4)
	var m := HorrorKit._cloth(col).duplicate() as ShaderMaterial
	m.set_shader_parameter("noise_scale",420.0)
	m.set_shader_parameter("vein_stretch",Vector3(1.0,.35,1.0))
	m.set_shader_parameter("vein_color",col.darkened(.45))
	m.set_shader_parameter("mottle",.35)
	m.set_shader_parameter("smudge",.6)
	m.set_shader_parameter("rim_strength",minf(rim,.22))
	m.set_shader_parameter("gloss",0.0)
	_fig_cache[key]=m
	return m

## A matte skin: the kit's shader without self-glow or gloss and with only a faint rim, so a body stays
## in the dark and a light picks out an edge (a shoulder, a cheek, knuckles) instead of a plastic sheen.
static func _fig_skin(tone: Variant, rim: float = .3, shaded: bool = false) -> ShaderMaterial:
	var key := "skin|%s|%.2f|%s" % [str(tone),rim,shaded]
	if _fig_cache.has(key): return _fig_cache[key]
	var m := HorrorKit.skin(tone,0.0,shaded).duplicate() as ShaderMaterial
	m.set_shader_parameter("rim_color",Color(.55,.55,.52))
	m.set_shader_parameter("rim_strength",minf(rim,.25))
	if not shaded:
		m.set_shader_parameter("vein_amount",0.0)
		m.set_shader_parameter("mottle",.12)
		m.set_shader_parameter("pores",0.0)
	m.set_shader_parameter("rim_emit",0.0)
	m.set_shader_parameter("gloss",0.0)
	_fig_cache[key]=m
	return m

## Skin that is a Color is held at a mid grey (SKIN); named tones ("wax") are left alone.
static func _skin_tone(tone: Variant) -> Variant:
	if tone is Color and (tone as Color).get_luminance()>.42: return SKIN
	return tone

## A HorrorKit head (it faces -z, towards the eye), matte, at a point of parent.
func _fig_head(opts: Dictionary, at: Vector3, size: float = 1.0, parent: Node3D = null) -> Node3D:
	opts = opts.duplicate()
	opts["tone"]=_skin_tone(opts.get("tone","wax"))
	# Deep, empty sockets on every staged head: shallow sockets with small eyes read as a doll.
	opts["socket"]=1.0
	if not opts.has("eyes"): opts["eyes"]="hollow"
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
	var dressed: Variant = tone
	var swapped := tone is Color and (tone as Color).get_luminance()<.18
	if swapped: dressed=UNIFORM.get(kind,UNIFORM["person"])
	var body := MeshInstance3D.new()
	body.name="Body"
	body.mesh=_fig_body(kind)
	var skin_tone: Variant = SKIN if swapped else tone
	for i in (body.mesh.get_surface_count() if body.mesh != null else 0):
		var garment := (body.mesh as ArrayMesh).surface_get_name(i)
		var mat: Material
		if garment=="body": mat=_fig_skin(dressed,rim)
		elif garment=="skin": mat=_fig_skin(_skin_tone(skin_tone),rim,true)
		else: mat=_fig_cloth(dressed if dressed is Color else UNIFORM["person"],garment,rim)
		body.set_surface_override_material(i,mat)
	body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.scale=Vector3.ONE*scale
	actor.add_child(body)
	(parent if parent != null else root).add_child(actor)
	actor.position=at
	var opts := head.duplicate()
	if not opts.has("tone"): opts["tone"]=SKIN if swapped else tone
	var skull := _fig_head(opts,(_FIG_NECK[kind][1] as Vector3)*scale,scale*float(head.get("size",1.12)),actor)
	skull.name="Head"
	skull.rotation.y=PI
	actor.set_meta("head",skull)
	return actor

## A HorrorKit hand with the matte skin (nails keep theirs).
func _fig_hand(opts: Dictionary, parent: Node3D = null) -> Node3D:
	opts = opts.duplicate()
	opts["tone"]=_skin_tone(opts.get("tone","wax"))
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

## A cut made while a lamp is out: 0 before a, 1 from a on. With reduced effects nothing blinks, so it is a smooth slide.
func _a_cut(t: float, a: float) -> float:
	if c.shk>0: return 1.0 if t>=a else 0.0
	return c.ss(t,a,a+.06)

func _build_rollcall() -> void:
	c.stage_dark(DARK,.04,Color(.27,.26,.24),.6)
	_room(5,9)
	p["tube"]=c.stage_lights.back()
	p["tube"].light_color=Color("ddd8c6")
	p["tube"].omni_range=6.0
	c.motive_light(Vector3(0,1.3,7.0),Color("ddd8c6"),3.0,5.0,root)
	c.motive_light(Vector3(0,1.3,1.0),Color("ddd8c6"),2.5,4.0,root)
	_box(Vector3(3.5,1.5,.08),Vector3(0,.45,7.7),JADE)
	_text("到你了。",Vector3(0,.7,7.62),.3)
	# Classroom doors with their plates on both sides, and a notice board.
	for z in [2.4,5.6]:
		_box(Vector3(.06,2.1,.95),Vector3(-2.43,-.55,z),Color("5a4a36"))
		_text("高二(3)",Vector3(-2.4,.7,z),.14).rotation.y=PI/2
		_box(Vector3(.06,2.1,.95),Vector3(2.43,-.55,z+1.0),Color("5a4a36"))
		_text("高二(4)",Vector3(2.4,.7,z+1.0),.14).rotation.y=-PI/2
	_box(Vector3(.05,.9,1.2),Vector3(2.44,.1,3.4),Color("5a4632"))
	# The patroller: tall, in a dark grey uniform with a red armband; a grey face that is slightly wrong.
	p["man"]=_fig(Vector3(.3,-1.6,4.4),"teacher",.98,Color("2b2c30"),{"tone":SKIN,"skew":.4,"size":1.2,"hair":true,"socket":.8},.2)
	_box(Vector3(.08,.09,.08),Vector3(.19,1.8,0),Color("8a2f2a"),p["man"])
	var book := _anchor(Vector3(.1,-.55,4.2))
	_box(Vector3(.42,.56,.025),Vector3.ZERO,COAL,book)
	_box(Vector3(.36,.5,.012),Vector3(0,0,-.02),Color("8c8676"),book)
	_text("巡查登记",Vector3(0,.17,-.031),.055,INK,book)
	for i in 5:
		_box(Vector3(.26,.008,.003),Vector3(0,.07-i*.05,-.03),Color("66756c"),book)
	p["book"]=book
	p["name"]=_text("未到",Vector3(.06,-.19,-.033),.06,RUST,book)
	# The register is held out by a long hand that comes with it out of the dark.
	# Its fingers come over the top edge from behind: too long, one joint too many.
	p["hand"]=_fig_hand({"long":1.2,"thin":.6,"extra":true,"arm":.5,"tone":SKIN},book)
	p["hand"].position=Vector3(-.1,.2,.045)
	p["hand"].scale=Vector3.ONE*1.15
	focus=book

func _show_rollcall(t: float) -> void:
	var man: Node3D=p["man"]
	var head: Node3D=man.get_meta("head")
	var book: Node3D=p["book"]
	var tube: Light3D=p["tube"]
	var gone:=t>=.3
	var reach:=c.ss(t,.32,.6)
	var lean:=c.ss(t,.76,.9)
	var close:=c.ss(t,.8,.88)
	# Seen first standing still under the tube; after the light falters he is nearer, a pace from the dark.
	var z:=lerpf(lerpf(3.2,2.0,c.ss(t,.45,.8)),1.9,close)
	man.position=Vector3(.3,-1.6,4.4) if not gone else Vector3(lerpf(lerpf(.62,.3,c.ss(t,.3,.8)),.08,close),-1.6,z)
	var lean_angle:=lerpf(.05+.1*lean,.75,close) if gone else 0.0
	man.rotation=Vector3(lean_angle,PI+.1*lean*(1-close),0)
	head.rotation=Vector3(-.18+.2*lean+.6*close,PI+.3*lean*(1 if c.fx!="names" else -1)*(1-close),.18*lean*(1-close))
	HorrorKit.pose_head(head,.1+.3*c.ss(t,.8,.95))
	tube.light_energy=0.0 if _fig_blink(t,.27,.31) else 3.0
	if gone:
		book.position=Vector3(lerpf(.5,.4,reach),lerpf(-.62,-.5,reach)-.5*close,z-lerpf(.9,1.0,reach))
		book.rotation=Vector3(-.2*c.ss(t,.5,.8)-.25*lean,-.2,-.06)
	else:
		book.position=Vector3(.1,-.55,4.2)
		book.rotation=Vector3(.1,-.4,.05)
	# A finger runs down the list, then taps the line with your name.
	var mark:=c.ss(t,.62,.7)-c.ss(t,.7,.76)
	var hook:=[.05,.15,1.5,1.2]
	HorrorKit.pose_hand(p["hand"],.6,.18,[.2,[.05,.15+.5*mark,1.5-.6*mark,1.2],hook,hook,hook],Vector2(.05,0))
	p["hand"].rotation=Vector3(PI/2-.45,.1,0)
	_fig_key().light_energy=lerpf(3.0,3.4,c.ss(t,.3,.85))
	p["name"].visible=t>.61
	p["name"].text="已到" if t>.78 else ("下一位" if c.fx=="names" else "未到")
	_pose(t,0,0,0,0,-3*reach)

## A parked car from boxes (nose along +x): body 4.5 x 1.8 x .7 m, roof 2.4 x 1.6 x .5 m, four wheels, dark lamp blocks.
func _b_car(at: Vector3, yaw: float, paint: Color) -> Node3D:
	var car := _anchor(at)
	car.rotation.y = yaw
	var body := _env_lit(paint,.4,.35)
	_env_box(Vector3(4.5,.7,1.8),Vector3(0,-.97,0),body,car)
	_env_box(Vector3(2.4,.5,1.6),Vector3(-.2,-.37,0),body,car)
	_env_box(Vector3(2.2,.26,1.64),Vector3(-.2,-.38,0),_env_lit(Color("171c1f"),.15,0,.8),car)
	var tyre := _env_lit(Color("151515"),.9)
	for x in [-1.45,1.45]:
		for z in [-.8,.8]:
			var wheel := c.mesh(CylinderMesh.new(),tyre,x,-1.27,z,car)
			(wheel.mesh as CylinderMesh).top_radius = .33
			(wheel.mesh as CylinderMesh).bottom_radius = .33
			(wheel.mesh as CylinderMesh).height = .22
			wheel.rotation.x = PI*.5
	_env_box(Vector3(.06,.14,1.4),Vector3(2.25,-.85,0),_env_lit(Color("2a2a28"),.3),car)
	_env_box(Vector3(.06,.14,1.4),Vector3(-2.25,-.85,0),_env_lit(Color("4a1e1a"),.3),car)
	return car

func _build_garage() -> void:
	c.stage_dark(DARK,.035,Color(.28,.265,.24),1.35)
	# A basement garage, B1: a concrete shell, painted bays, numbered columns, six parked cars.
	var concrete := _env_textured(Color("7a7870"),"grime",.35,.95)
	_env_box(Vector3(12.4,.08,25),Vector3(0,-1.64,10.5),_env_textured(Color("5a5852"),"grime",.4,.7))
	_env_box(Vector3(12.4,.08,25),Vector3(0,1.04,10.5),_env_textured(Color("6a6862"),"grime",.35,.95))
	for side in [-1,1]: _env_box(Vector3(.1,2.7,25),Vector3(side*6.25,-.3,10.5),concrete)
	_env_box(Vector3(12.4,2.7,.1),Vector3(0,-.3,22),concrete)
	for z in [2.0,8.0,14.0,20.0]: _env_box(Vector3(12.4,.28,.5),Vector3(0,.88,z),_env_lit(Color("66645e"),.95))
	var cars := [[3.6,4.05,"4a4f55"],[-3.6,6.75,"6b3b33"],[3.6,9.45,"8a8a84"],[-3.6,12.15,"4a4f55"],[3.6,14.85,"6b3b33"],[-3.6,17.55,"8a8a84"]]
	var line := _env_lit(Color("b9b6aa"),.7)
	for entry in cars:
		_b_car(Vector3(entry[0],0,entry[1]),0.0,Color(entry[2]))
		for dz in [-1.35,1.35]: _env_box(Vector3(5.0,.012,.1),Vector3(entry[0],-1.594,entry[1]+dz),line)
	var number := 7
	for z in [2.7,8.1,13.5,18.9]:
		for side in [-1,1]:
			_env_box(Vector3(.5,2.6,.5),Vector3(side*2.3,-.3,z),concrete)
			_env_box(Vector3(.52,.5,.52),Vector3(side*2.3,-1.35,z),_env_lit(Color("a8924a"),.8))
		_text("B1-%02d"%number,Vector3(2.3,.25,z-.26),.22,Color("c9c0a4"))
		_text("B1-%02d"%(number+1),Vector3(-2.3,.25,z-.26),.22,Color("c9c0a4"))
		number += 2
	# Rows of fluorescent tubes (far to near), which go out one row at a time; the lamp over your head never does.
	p["rows"]=[]
	for z in [11.5,7.5,4.0]:
		var tubes := []
		for x in [-1.0,1.0]:
			_env_box(Vector3(.2,.07,1.9),Vector3(x,.98,z),_env_lit(Color("3a3a38"),.6))
			tubes.append(_box(Vector3(.12,.05,1.8),Vector3(x,.94,z),LIGHT))
		p["rows"].append({"tubes":tubes,"light":c.motive_light(Vector3(0,.8,z),TUBE,3.0,6.5,root)})
	p["over"]=c.motive_light(Vector3(0,.95,-.8),TUBE,3.0,5.0,root)
	# The man, in the lane, standing still between the cuts.
	p["man"]=_fig(Vector3(.3,-1.6,8),"teacher",.78,Color("2b2c30"),{"tone":SKIN,"skew":.4,"mouth":"closed","hair":true,"socket":.8,"size":1.15},.2)
	p["man"].rotation.y=PI
	# For the shadow identity his shadow arrives first: a long, pale-black slant on the floor, .1 of the shot ahead of him.
	p["shadow"]=_box(Vector3(.7,.012,1),Vector3(0,-1.594,8),Color("000000"),null,.42)
	p["shadow"].visible=false
	focus=_anchor(Vector3(.3,.25,8))

## How far the man is at t: 8 m, then 3.2 (.42), 1.4 (.62) and .6 (.80), each a cut on a row of lamps going out.
func _b_garage_at(t: float) -> Vector2:
	var d:=lerpf(lerpf(lerpf(8.0,3.2,_a_cut(t,.42)),1.4,_a_cut(t,.62)),.6,_a_cut(t,.83))
	var x:=lerpf(lerpf(lerpf(.3,-.25,_a_cut(t,.42)),.1,_a_cut(t,.62)),.04,_a_cut(t,.83))
	return Vector2(x,d)

func _show_garage(t: float) -> void:
	var man: Node3D=p["man"]
	var head: Node3D=man.get_meta("head")
	var at:=_b_garage_at(t)
	var rush:=c.ss(t,.83,.88)
	man.position=Vector3(at.x,-1.6,at.y)
	man.rotation=Vector3(.1*rush,PI-.08*rush,0)
	head.rotation=Vector3(-.15+.2*rush,PI+.2*c.ss(t,.6,.75)-.15*rush,-.25*c.ss(t,.6,.75))
	focus.position=Vector3(at.x,.25,at.y)
	# A row dies at every cut (flickering just before with full effects, a slow fade without).
	var cuts:=[.42,.62,.83]
	for i in 3:
		var row: Dictionary=p["rows"][i]
		var out:=_a_cut(t,cuts[i])
		var lit:=(1.0-out)*(0.0 if _fig_blink(t,cuts[i]-.04,cuts[i]-.02) else 1.0)
		(row["light"] as Light3D).light_energy=3.0*lit
		for tube: Node3D in row["tubes"]: tube.visible=lit>.3
	var shadow: Node3D=p["shadow"]
	shadow.visible=c.fx=="shadow"
	if shadow.visible:
		var near:=_b_garage_at(minf(t+.1,1.0)).y
		var far:=12.0
		shadow.scale.z=maxf(.01,far-near)
		shadow.position=Vector3(at.x*.9,-1.594,(near+far)*.5)
	_fig_key().light_energy=lerpf(6.5,4.2,c.ss(t,.42,.83))
	_pose(t,.25*rush,.025*sin(t*12)*rush*c.shk,0,0,-6*rush)

func _build_backseat() -> void:
	# The driver's seat at night: dashboard, wheel, pillars and roof lit by the instruments and the street lamps.
	c.stage_dark(DARK,.03,Color(.27,.26,.24),.6)
	_box(Vector3(2.8,.4,.9),Vector3(0,-.78,1.3),Color("4a4843"))
	_box(Vector3(2.8,.08,.5),Vector3(0,.66,.75),Color("55534c"))
	for x in [-1,1]:
		_rod(Vector3(x*1.05,-.58,1.55),Vector3(x*.95,.64,.95),.13,Color("4a4843"))
		_box(Vector3(.3,.45,1.4),Vector3(x*1.3,-.6,.3),Color("45443f"))
	_ring(Vector3(.36,-.5,.62),.19,.03,Color("66645d")).rotation.x=.45
	# Two dials, each with a small needle.
	for x in [.26,.48]:
		_ring(Vector3(x,-.5,1.0),.055,.006,Color("d9a066")).material_override=c._mat(Color("a8794a"))
		var tip:=Vector3(.028,.028,0) if x<.4 else Vector3(-.03,.026,0)
		_rod(Vector3(x,-.5,.99),Vector3(x,-.5,.99)+tip,.006,Color("c96a4a"))
	_box(Vector3(30,.05,60),Vector3(0,-1.45,30),Color("5a5c58"))
	# The night beyond the windscreen: a dull orange-grey glow of the town over the road.
	c.mesh(BoxMesh.new(),c._mat(Color("4a4744"),-1,false,false,false),0,6,32,root).scale=Vector3(110,40,.1)
	for i in 9: _box(Vector3(.12,.01,1.6),Vector3(-.4,-1.42,4+i*4.5),Color("9a9a88"))
	_sphere(Vector3(-2.6,2.6,9),.16,LIGHT)
	_rod(Vector3(-2.6,2.6,9),Vector3(-2.6,-1.45,9),.08,Color("3a3a36"))
	c.motive_light(Vector3(-2.4,2.2,8.6),Color("d9b98a"),3.0,8,root)
	# A street lamp sweeps down the roof of the car from front to back every .12 of the time.
	p["pass"]=c.motive_light(Vector3(-1.6,1.6,10),Color("d9a066"),2.5,7,root)
	# Light on the road ahead, a faint cabin light behind the shoulder, and the instrument glow.
	c.motive_light(Vector3(0,2.5,4),Color("b8b6ae"),4.0,9,root)
	c.motive_light(Vector3(.4,.5,-.6),Color("d8d2c0"),.8,3.0,root)
	c.motive_light(Vector3(.1,1.3,1.0),Color("d8d2c0"),3.4,3.8,root)
	p["dash"]=c.motive_light(Vector3(.3,-.5,.85),Color("d9a066"),.8,1.2,root)
	var mirror := _anchor(Vector3(0,.4,.95))
	_box(Vector3(.4,.14,.035),Vector3.ZERO,Color("22211f"),mirror)
	# The glass takes the light of the road behind the car, so the frame reads in the dark.
	_box(Vector3(.36,.105,.008),Vector3(0,0,-.02),Color("3e403f"),mirror)
	_rod(Vector3(0,.07,0),Vector3(0,.26,.08),.02,Color("22211f"),mirror)
	p["mirror"]=mirror
	# The reflection: a passenger who was not there, sitting back, then leaning between the seats.
	p["reflection"]=_fig_head({"tone":SKIN,"mouth":"closed","skew":.25,"hair":true,"socket":.8},Vector3(0,0,-.03),.3,mirror)
	focus=p["mirror"]
	# The weight on the shoulder: a long, cold hand from the back seat, over the right shoulder (set -x is screen right).
	p["hand"]=_fig_hand({"long":1.25,"thin":.4,"arm":.22,"tone":SKIN,"quality":maxi(CampusData.tier,3)})
	# At the very end the passenger itself, at your right ear: head and shoulders between the front seats.
	p["pax"]=_fig(Vector3(-.36,-1.28,.51),"sit",1.0,Color("262d3a"),{"mouth":"closed","skew":.25,"size":1.05,"hair":true,"socket":.8},.2)
	p["face"]=p["pax"].get_meta("head")
	p["pax"].rotation.y=PI

func _show_backseat(t: float) -> void:
	var lean := c.ss(t,.3,.62)
	var near := c.ss(t,.78,.88)
	var ghost: Node3D=p["reflection"]
	ghost.visible=t>.25 and t<.8
	ghost.position=Vector3(lerpf(-.1,0,lean),lerpf(-.01,-.005,lean),-.03)
	ghost.scale=Vector3.ONE*lerpf(.45,.62,lean)
	ghost.rotation=Vector3(-.1,PI-PI*0.0,.12*(1-lean))
	ghost.rotation=Vector3(-.1,0,.12*(1-lean))
	HorrorKit.pose_head(ghost,.0)
	(p["dash"] as Light3D).light_energy=0.0 if _fig_blink(t,.23,.27) else .8
	# The hand climbs up from the edge of the seat's shoulder: first only the fingertips show.
	var reach:=c.ss(t,.62,.8)
	var hand: Node3D=p["hand"]
	hand.visible=t>.62
	hand.position=Vector3(-.36,-.24,.12).lerp(Vector3(-.3,-.11,.27),reach)
	(p["pass"] as Light3D).position.z=12.0-fposmod(t/.12,1.0)*24.0
	hand.rotation=Vector3(-.05-.2*reach,PI+.75,.35)
	HorrorKit.pose_hand(hand,lerpf(.05,.45,c.ss(t,.7,.8)),.35,[.1],Vector2(.35*reach,0))
	var pax: Node3D=p["pax"]
	pax.visible=t>=.8
	pax.position=Vector3(lerpf(-.52,-.36,near),lerpf(-1.3,-1.28,near),lerpf(.3,.51,near))
	pax.rotation=Vector3(0,PI-.25*near,0)
	var face: Node3D=p["face"]
	face.rotation=Vector3(-.05,PI-.3-.1*near,.12)
	HorrorKit.pose_head(face,0.0)
	_fig_key().light_energy=1.6
	_pose(t,0,.34*c.ss(t,.76,.88),0,0,-3*near)

const ENV_WINDSHIELD := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float crack = 0.0;
uniform vec2 hit = vec2(.36, .42);
uniform float glare = 0.0;
uniform float rain = 1.0;
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
// One crack: a ragged line out of the origin along theta, ending at len.
float seg_line(vec2 q, float theta, float len, float w) {
	float r = length(q);
	float a = atan(q.y, q.x);
	float wob = .05 * (vn(vec2(r * 9.0, theta * 7.0)) - .5) + .02 * sin(r * 31.0 + theta * 5.0) * min(r, .3);
	float da = a - theta - wob;
	float d = abs(sin(da)) * r;
	return (1.0 - smoothstep(w * .5, w, d)) * step(0.0, cos(da)) * (1.0 - smoothstep(len * .85, len, r));
}
void fragment() {
	vec2 q = (UV - hit) * vec2(1.8, 1.0);
	float r = length(q);
	float a = atan(q.y, q.x);
	float lines = 0.0;
	float w = .0022;
	// Laminated glass: ten irregular spokes from the point of impact, each with one or two forks.
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float theta = (fi + .5 + (h1(fi * 1.7) - .5) * .8) / 10.0 * 6.2831853 - 3.1415927;
		float len = crack * (.55 + .9 * h1(fi + 17.0));
		vec2 dir = vec2(cos(theta), sin(theta));
		lines = max(lines, seg_line(q, theta, len, w));
		float s1 = .28 + .18 * h1(fi + 3.0);
		float s2 = .55 + .15 * h1(fi + 9.0);
		float side = h1(fi + 5.0) > .5 ? 1.0 : -1.0;
		lines = max(lines, seg_line(q - s1 * len * dir, theta + side * (.35 + .3 * h1(fi + 11.0)), max(len * (1.0 - s1) * .55, .0001), w * .9));
		if (h1(fi + 21.0) > .35) lines = max(lines, seg_line(q - s2 * len * dir, theta - side * (.3 + .3 * h1(fi + 13.0)), max(len * (1.0 - s2) * .5, .0001), w * .8));
	}
	// Short, broken arcs close round the point of impact (all within .12 m).
	float arcs = 0.0;
	for (int k = 1; k <= 3; k++) {
		float fk = float(k);
		float rr = .035 * fk + .01 * h1(fk * 3.1);
		float wob = rr * (1.0 + .04 * sin(a * 7.0 + fk * 2.0) + .1 * (vn(vec2(a * 3.0 + fk * 4.1, fk * 3.7)) - .5));
		float on = smoothstep(.15, .4, crack) * step(.45, h1(floor((a + 3.1416) * 1.6) + fk * 9.0));
		arcs = max(arcs, on * (1.0 - smoothstep(.0007, .0022, abs(r - wob))));
	}
	float crush = smoothstep(.012, .0, r) * step(.01, crack);
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
	float lit = .35 + .5 * glare;
	ALBEDO = vec3(.82, .87, .88) * min(lit, 1.0);
	ALPHA = clamp(.03 + drop * (.03 + .3 * glare) + lines * .6 + arcs * .5 + crush * .5, 0.0, .8);
}
"""

func _build_crash() -> void:
	c.stage_dark(DARK,.02,Color(.28,.265,.24),1.4)
	# Wet asphalt that takes the beams, a centre line rushing in, reflector posts, a guard rail and trees into the dark.
	_env_box(Vector3(16,.1,97),Vector3(0,-1.35,46),_env_lit(Color("575653"),.5,0,.4))
	_env_box(Vector3(.05,.01,97),Vector3(0,-1.285,46),_env_lit(Color("8f8c7c"),.55))
	_env_box(Vector3(.04,.2,97),Vector3(0,-1.3,46),_env_lit(Color("383c3c"),.35,0,.6))
	var paint := _env_lit(Color("a09d8c"),.55)
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
	# The guard rail (a long beam on posts every 4 m) and the roadside trees, both streaming past.
	var steel := _env_lit(Color("8a8d8c"),.4,.6)
	for side in [-1,1]: _env_box(Vector3(.05,.28,97),Vector3(side*4.2,-.85,46),steel)
	p["rails"]=[]
	for i in 24:
		var rail_post := _anchor(Vector3((-1 if i%2 else 1)*4.2,-1.3,0))
		_env_box(Vector3(.1,.8,.1),Vector3(0,.4,.03),_env_lit(Color("5a5d5c"),.5,.4),rail_post)
		p["rails"].append(rail_post)
	p["trees"]=[]
	var bark := _env_lit(Color("4a3d30"),.9)
	var leaves := _env_lit(Color("2c4a37"),.95)
	for i in 14:
		var tree := _anchor(Vector3((-1 if i%2 else 1)*(7.0+3.0*_env_h(i+30.0)),-1.3,0))
		_env_box(Vector3(.4,3.4,.4),Vector3(0,1.7,0),bark,tree)
		_env_ball(Vector3(0,4.0,0),1.7+.5*_env_h(i+40.0),leaves,tree,10)
		p["trees"].append(tree)
	# A faint glow of the town on the horizon.
	_env_box(Vector3(160,14,.2),Vector3(0,5,118),_env_flat(Color("4a413a"),-1,false))
	# Inside the car: dash, bonnet, pillars, roof edge, mirror, wheel and two dim gauges.
	var plastic := _env_lit(Color("403f3c"),.75,0,.3)
	_env_box(Vector3(2.3,.32,.6),Vector3(0,-.7,.98),plastic)
	var bonnet := _env_box(Vector3(2.0,.06,1.5),Vector3(0,-.8,1.95),_env_lit(Color("45433f"),.5,.1,.4))
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
		c.torus(.045,.004,_env_flat(Color("6fb08e")),x,-.5,.76,root,4,24)
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
	p["glassnode"]=glass
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
	p["beams"]=[]
	for x in [-.6,.6]: p["beams"].append(c.key_light(Vector3(x,-.7,2.3),Vector3(x*.5,-1.3,22),Color("e8dcb4"),12.0,28,38,root))
	# A thin cold moon behind the cloud: the road, rail and trees stay readable beyond the beams.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("c4c4bc")
	moon.light_energy = 1.4
	moon.shadow_enabled = false
	moon.rotation = Vector3(-.9,PI,0)
	root.add_child(moon)
	c.motive_light(Vector3(0,0,.3),Color("d8d2c0"),.7,2.5,root)
	# A dim amber glow from the instruments on the dash.
	c.motive_light(Vector3(0,-.45,.75),Color("d9a066"),.7,1.6,root)
	var truck := _anchor(Vector3(2.8,0,70))
	p["truck"]=truck
	var paint_dark := _env_lit(Color("2d2c2b"),.5,.3)
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
	focus=_anchor(Vector3(0,-.15,6))

func _show_crash(t: float) -> void:
	var hit := .58
	var after := maxf(t-hit,0)
	# Distance driven: steady until the hit, then a hard stop.
	var travelled := 120.0*minf(t,hit)+120.0*(1-exp(-after*30))/30
	for i in pieces.size(): pieces[i].position.z=fposmod(i*6.0-travelled,96)-1
	for i in p["posts"].size(): p["posts"][i].position.z=fposmod(i*7.0-travelled,98)-1
	for i in p["rails"].size(): p["rails"][i].position.z=fposmod(i*4.0-travelled,96)-1
	for i in p["trees"].size(): p["trees"][i].position.z=fposmod(i*7.0+3.0-travelled,98)-1
	var come := c.seg(t,.03,hit)
	var truck: Node3D = p["truck"]
	truck.position = Vector3(lerpf(2.8,.35,c.ss(t,.18,hit)),0,lerpf(70,2.05,come))
	var near := clampf(1-(truck.position.z-2)/68,0,1)
	# One of its lamps dies in the impact; the other stays on, dimmed, staring through the cracks.
	var dim := 1-.8*c.ss(t,hit+.02,.75)
	var lamp := [1-c.ss(t,hit+.01,hit+.03),dim]
	for i in 2:
		var halo: MeshInstance3D = p["halos"][i]
		halo.scale = Vector3.ONE*lerpf(.5,1.0,near*near*near)*maxf(lamp[i],.001)*(1 if i==0 else lerpf(.35,1,dim))
		halo.visible = lamp[i]>0
		p["heads"][i].visible = lamp[i]>0
	(p["glare_light"] as SpotLight3D).light_energy = (1.5+3.5*near*near*near)*(.5*lamp[0]+.5*lamp[1])*dim
	# Our own beams keep burning, dimmer after the hit, so the road, rail and trees stay readable behind the cracks.
	for beam: SpotLight3D in p["beams"]: beam.light_energy = lerpf(12.0,6.0,c.ss(t,hit,hit+.06))
	var glare := near*near*lerpf(.3,1,dim)
	_env_param(p["glass"],"glare",glare)
	_env_param(p["glass"],"crack",c.ss(t,hit,hit+.12))
	# The wipers beat until the hit, then stay where they stopped.
	var beat := minf(t,hit)*c.dur*2.4
	for wiper: Node3D in p["wipers"]: wiper.rotation.z = 1.3*(.5-.5*cos(beat))
	var speed := (1-c.ss(t,hit,hit+.05))
	for needle: Node3D in p["needles"]: needle.rotation.z = lerpf(1.9,-1.1,speed*(.92+.02*sin(t*31)))
	_env_key(lerpf(1.6,2.6,c.ss(t,hit,hit+.1)))
	# The glass bows in .02 m and stops (no further cracking after .70).
	(p["glassnode"] as Node3D).position = Vector3(0,-.55,1.12)+Vector3(0,0,-.02)*c.ss(t,.8,.88)
	var jolt := c.ss(t,hit,hit+.03)*(1-c.ss(t,hit+.05,.9))
	_pose(t,.07*jolt*c.shk,.004*sin(t*95)*come*c.shk,-.05*jolt*c.shk,.08*c.ss(t,hit,hit+.05),3*jolt)

const _CLASS_ROW := [1.8,4.2,6.6,9.0]    # the z of each row of desks; the classmate sits .75 behind his desk

func _build_classroom() -> void:
	c.stage_dark(DARK,.04,Color(.27,.26,.24),.6)
	_room(8,13)
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(.6,1.3,4.2)
	p["tube"].omni_range=7.0
	p["tube"].light_color=Color("ddd8c6")
	p["front"]=c.motive_light(Vector3(-.7,1.3,1.8),Color("ddd8c6"),2.8,4.5,root)
	_box(Vector3(6,1.6,.08),Vector3(0,.45,11.8),Color("294c48"))
	p["writing"]=_text("请 回 到 你 的 座 位",Vector3(0,.6,11.72),.38)
	p["students"]=[]
	for row in 4:
		for col in 3:
			var x:float=(col-1)*1.9
			var z:float=_CLASS_ROW[row]
			pieces.append(_desk(Vector3(x,0,z)))
			# Seated classmates in uniform, facing the board; their heads can turn on their own.
			var student:=_fig(Vector3(x,-1.6,z-.75),"sit",1.0,Color("262d3a"),{"tone":SKIN,"skew":.3 if (row+col)%2 else 0.0,"mouth":"none" if col==2 else "closed","hair":true,"socket":.8},.2)
			p["students"].append(student)
	for z in [3,6.5,10]:
		var window := _window(Vector3(3.92,.4,z))
		window.rotation.y=PI/2
		(window.get_node("GlassPane") as MeshInstance3D).material_override=_surface(Color("5a5e60"),.4)
	p["own"]=_desk(Vector3(0,0,.7))
	p["blank"]=_box(Vector3(5.9,1.5,.04),Vector3(0,.45,11.65),Color("bbc2b1"))
	p["blank"].hide()
	if c.fx=="chalk":
		# The one figure on the board that the eraser leaves: a chalk outline; the teacher who wrote it comes down the aisle.
		var drawn:=FigureModel.make("person",Color("b9bfae"),true,.75,Color.BLACK,true,true)
		drawn.rotation.y=PI
		c.put(drawn,1.9,-.75,11.6,root)
		p["drawn"]=drawn
		p["chalk"]=_fig(Vector3(.6,-1.6,10.8),"teacher",.98,Color("2b2c30"),{"tone":SKIN,"mouth":"closed","skew":.3,"size":1.2,"hair":true,"socket":.8},.2)
	if c.fx=="assimilation":
		# Your own two hands on the desk: your colour at first, the classmates' grey at the end.
		p["own_hands"]=[]
		for side in [-1,1]:
			var hand:=_fig_hand({"long":1.0,"thin":.3,"arm":.22,"tone":Color(.62,.52,.44),"side":side},root)
			hand.rotation=Vector3(0,PI,0)
			hand.position=Vector3(side*.24,-.57,.5)
			p["own_hands"].append(hand)
	focus=_anchor(Vector3(0,-.15,1.2))

## When a classmate's head has turned round to you (0..1), by effect; the one in front of you is last.
func _class_turn(t: float, i: int) -> float:
	if c.fx=="assimilation": return c.ss(t,.44+(i%3)*.01,.5+(i%3)*.01)
	var order:=11 if i==1 else (i*5)%11
	return c.ss(t,.14+order*.042,.24+order*.042)

## The one in front of you leans back towards you about his hips: .8 m away at the 81% frame, .55 at the end.
func _a_class_lean(t: float) -> float:
	return -.5*c.ss(t,.62,.8)-.06*c.ss(t,.8,.88)

func _show_classroom(t: float) -> void:
	var change:=c.ss(t,.22,.78)
	var assimilated:=c.fx=="assimilation"
	var staring:=c.fx=="stare"
	var chalking:=c.fx=="chalk"
	var erased:=not assimilated and not staring
	var near:=c.ss(t,.8,.88)
	var lean:=_a_class_lean(t)
	var tube: Light3D=p["tube"]
	var students: Array=p["students"]
	for i in students.size():
		var student: Node3D=students[i]
		var head: Node3D=student.get_meta("head")
		var row:=floori(i/3.0)
		student.position=Vector3((i%3-1)*1.9,-1.6,_CLASS_ROW[row]-.75)
		student.rotation=Vector3.ZERO
		head.position=(_FIG_NECK["sit"][1] as Vector3)
		head.rotation=Vector3(0,PI,0)
		HorrorKit.pose_head(head,0)
		var front:=i==1
		if erased:
			# Erased a few at a time, each time the light falters; the one in front comes back, already turned round.
			student.visible=t<.3+(i%3)*.12 or (front and t>=.62 and not chalking)
			if front and t>=.62:
				head.rotation=Vector3(-lean+.05,0,.3)
				student.rotation=Vector3(lean,0,0)
				student.position=Vector3(0,-1.1,_CLASS_ROW[0]-.75)-Basis(Vector3.RIGHT,lean)*Vector3(0,.5,0)
				HorrorKit.pose_head(head,.5*near)
			continue
		var turn:=_class_turn(t,i)
		if assimilated:
			student.position.x*=1-.16*change
			student.position.z-=.15*change
		# The bodies stay facing the board; only the heads come all the way round.
		head.rotation=Vector3(-.12*turn,PI-PI*turn,.18*turn*sin(i*2.3))
		if front:
			student.rotation=Vector3(lean,0,0)
			student.position=Vector3(student.position.x,-1.1,student.position.z)-Basis(Vector3.RIGHT,lean)*Vector3(0,.5,0)
			head.rotation.x=-lean*turn+.05
			head.rotation.z+=.15*near
			HorrorKit.pose_head(head,.4*near)
	for i in pieces.size():
		pieces[i].position.x=(i%3-1)*1.9*(1-.16*change if assimilated else 1+.35*change*float(erased))
	var falter:=_fig_blink(t,.28,.31) or _fig_blink(t,.4,.43) or _fig_blink(t,.52,.55) if erased else _fig_blink(t,.43,.46)
	tube.light_energy=0.0 if falter else 3.0
	(p["front"] as Light3D).light_energy=0.0 if falter else 2.8
	p["blank"].visible=erased and t>.5
	p["blank"].scale.x=c.ss(t,.5,.82)
	p["own"].position.z=lerpf(.7,.33,change) if assimilated else .7
	p["writing"].text="已 归 队" if assimilated and t>.6 else "请 回 到 你 的 座 位"
	if chalking:
		# The teacher who wrote the name turns from the board, and from the cut at .62 is in the aisle, leaning over you.
		var teacher: Node3D=p["chalk"]
		var thead: Node3D=teacher.get_meta("head")
		var cut:=_a_cut(t,.62)
		var turn_round:=c.ss(t,.45,.6)
		var foot:=Vector3(lerpf(.6,.95,cut),-1.6,lerpf(10.8,1.9,cut))
		foot=foot.lerp(Vector3(.45,-1.6,1.5),near)
		teacher.position=foot
		teacher.rotation=Vector3(.35*near,PI*turn_round,0)
		thead.rotation=Vector3(-.18+.5*near,PI,0)
		HorrorKit.pose_head(thead,.25*near)
		(teacher.get_node("Body") as Node3D).scale=Vector3(1,1+.006*sin(t*c.dur*1.6),1)
		p["drawn"].visible=t<.8
	if p.has("own_hands"):
		var greyed:=roundf(c.ss(t,.25,.8)*6.0)/6.0
		var tone:=Color(.62,.52,.44).lerp(SKIN,greyed)
		for hand: Node3D in p["own_hands"]:
			for mi: Node in hand.find_children("*","MeshInstance3D",true,false):
				if mi.name!="Nail": (mi as MeshInstance3D).material_override=_fig_skin(tone,.2,true)
			hand.position.z=(p["own"] as Node3D).position.z-.2
			HorrorKit.pose_hand(hand,.15,.05)
	_fig_key().light_energy=3.0+.6*near
	var pitch:=0.0
	if staring or erased and not chalking or assimilated: pitch=-.22*c.ss(t,.62,.8)-.04*near
	if chalking: pitch=.4*near
	_pose(t,pitch,0,-.25*change if assimilated else 0.0,0,-4*c.ss(t,.6,.84))

func _build_assembly() -> void:
	# An overcast morning on the playground: concrete, a rostrum, a flagpole on the left, the teaching block behind.
	c.stage_dark(Color("55585a"),.02,Color(.3,.29,.27),.7)
	p["sky"]=c.key_light(Vector3(4,6,-2),Vector3(0,-1.6,8),Color("d8d6cc"),8.0,30,60,root)
	_env_box(Vector3(24,.1,35),Vector3(0,-1.6,15),_env_textured(Color("9a9a92"),"grime",.15))
	for i in 8:
		_box(Vector3(.035,.01,28),Vector3((i-3.5)*1.8,-1.54,12),Color("c8c8bc"))
	_box(Vector3(8,.8,2),Vector3(0,-1.2,19),Color("6a6e68"))
	_text("保持队形",Vector3(0,-1.2,17.95),.4)
	# The flagpole, 8 m high, 12 m away on your left (+x is screen left); the red flag hangs still.
	_rod(Vector3(7,-1.6,12),Vector3(7,6.4,12),.1,Color("8a8a84"))
	_box(Vector3(1.4,.9,.03),Vector3(6.3,5.8,12),Color("a8322a"))
	c.mesh(BoxMesh.new(),c._mat(Color("85837d"),-1,false,false,false),0,8,36,root).scale=Vector3(140,50,.1)
	_box(Vector3(30,10,.5),Vector3(0,3,26),Color("a6a298"))
	for row in 3:
		for col in 10:
			var lit:=(row*10+col) in [3,12,17,26]
			var at:=Vector3((col-4.5)*2.6,.8+row*2.4,25.7)
			if lit: c.mesh(BoxMesh.new(),c._mat(Color("d9c79a"),-1,false,false,false),at.x,at.y,at.z,root).scale=Vector3(1.2,1,.05)
			else: _box(Vector3(1.2,1,.05),at,Color("3a3c3a"))
	# Sixteen places in the square; the one at the front, second from the right, is empty: yours, marked with a chalk X.
	for sign in [-1,1]:
		_rod(Vector3(-.65-.4,-1.53,4-.4*sign),Vector3(-.65+.4,-1.53,4+.4*sign),.05,Color("d8d8cc"))
	p["kids"]=[]
	for row in 4:
		for col in 4:
			if row==0 and col==1:
				p["kids"].append(null)
				continue
			var opts:={"tone":SKIN,"mouth":"none" if (row+col)%3==0 else "closed","skew":.3 if (row*4+col)%5==0 else 0.0,"hair":true,"socket":.8,"size":1.2 if (row==0 and col==2) else 1.12}
			var student:=_fig(Vector3((col-1.5)*1.3,-1.6,4+row*2.0),"person",.95,Color("262d3a"),opts,.2)
			# A red armband on the left upper arm.
			_box(Vector3(.07,.1,.1),Vector3(.2,1.35,0),Color("8a2f2a"),student)
			p["kids"].append(student)
	focus=_anchor(Vector3(0,0,4))

func _show_assembly(t: float) -> void:
	# The square closes up in three steps with a stop between each; then the heads turn, back rows first, and the one
	# on your left turns round, steps out of line and comes to you.
	var step:=c.ss(t,.2,.26)+c.ss(t,.29,.35)+c.ss(t,.38,.44)
	var come:=c.ss(t,.62,.8)
	var close:=c.ss(t,.8,.88)
	for i in 16:
		var student: Node3D=p["kids"][i]
		if student==null: continue
		var row:=floori(i/4.0)
		var col:=i%4
		var at:=Vector3((col-1.5)*1.3,-1.6,4+row*2.0-.6*step)
		var turn:=c.ss(t,.45+(3-row)*.05,.53+(3-row)*.05)
		var yaw:=0.0
		if row==0 and col==2:
			at.x=lerpf(at.x,.7,come)
			at.x=lerpf(at.x,.5,close)
			at.z=lerpf(at.z,1.2,come)
			at.z=lerpf(at.z,.62,close)
			yaw=PI*c.ss(t,.7,.84)
			turn=c.ss(t,.45,.53)
		elif row==0 and col==0:
			at.x=lerpf(at.x,-1.0,come)
			at.z=lerpf(at.z,2.2,come)
		student.position=at
		student.rotation=Vector3(0,yaw,0)
		# After the body has turned too, the head is already facing you: it has to be counted against the body's turn.
		(student.get_meta("head") as Node3D).rotation=Vector3(-.1*turn,PI-PI*turn-yaw,.15*turn*sin(i*2.1))
	(p["sky"] as Light3D).light_energy=lerpf(8.0,9.0,close)
	_fig_key().light_energy=lerpf(2.6,3.4,close)
	_pose(t,-.04*c.ss(t,.2,.45),0,-.1*close,0,-4*c.ss(t,.45,.88))


## A Catmull-Rom curve through points (count samples, even in the point index).
static func _a_spline(points: Array, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	for i in count:
		var u := float(i)/(count-1)*(n-1)
		var k := mini(int(u),n-2)
		var f := u-k
		var q0: Vector3 = points[maxi(k-1,0)]
		var q1: Vector3 = points[k]
		var q2: Vector3 = points[k+1]
		var q3: Vector3 = points[mini(k+2,n-1)]
		out.append(.5*(2.0*q1+(q2-q0)*f+(2.0*q0-5.0*q1+4.0*q2-q3)*f*f+(3.0*q1-q0-3.0*q2+q3)*f*f*f))
	return out

const _FENCE_RAIL := Vector3(0,.8,2.5)    # the top rail of the railing: where the neck lies over

func _build_fence() -> void:
	c.stage_dark(DARK,.05,Color(.27,.26,.24),.6)
	_box(Vector3(14,.1,12),Vector3(0,-1.6,5),Color("62674f"))
	_box(Vector3(14,.02,.5),Vector3(0,-1.54,1.6),Color("8a4a38"))
	# A faint night sky behind the trees, so their black shapes read against it.
	c.mesh(BoxMesh.new(),c._mat(Color("5e5c58"),-1,false,false,false),0,3,12.5,root).scale=Vector3(40,14,.1)
	# The playground railing: metal uprights with small spear tips, two rails and a notice.
	var metal:=_env_lit(Color("4a4f4a"),.45,.6)
	for i in 15:
		_env_box(Vector3(.04,2.8,.04),Vector3((i-7)*.27,-.2,2.5),metal)
		_env_box(Vector3(.06,.08,.06),Vector3((i-7)*.27,1.24,2.5),metal)
	for y in [-.6,.8]: _env_box(Vector3(4.1,.055,.055),Vector3(0,y,2.48),metal)
	_box(Vector3(.5,.25,.02),Vector3(1.5,.2,2.46),Color("b9b19a"))
	_text("禁止翻越",Vector3(1.5,.2,2.44),.07,INK)
	# A sodium street lamp on the far side and two black trees behind it.
	_rod(Vector3(-3.2,-1.6,8),Vector3(-3.2,2.4,8),.08,COAL)
	_box(Vector3(.5,.1,.2),Vector3(-3.0,2.4,8),LIGHT)
	_env_glow(Vector3(-3.0,2.35,7.9),3.0,Color("d9a066"),root,2.0)
	c.motive_light(Vector3(-3,2.2,7.8),Color("d9a066"),3.0,6.0,root)
	# A second sodium lamp over the railing's near side lights the neck where it hangs.
	c.motive_light(Vector3(1.6,3.0,3.8),Color("d9a066"),2.4,6.0,root)
	c.motive_light(Vector3(1,3.2,3.2),Color("c8c6bc"),9.0,10,root)
	c.motive_light(Vector3(-2.5,1.4,4.4),Color("d9a066"),1.8,2.6,root)
	for tx in [3.8,-5.5]:
		_box(Vector3(.3,2.6,.3),Vector3(tx,-.3,9),Color("0a0e0c"))
		_sphere(Vector3(tx,1.3,9),1.2,Color("0a0e0c")).scale=Vector3(1.7,.85,1)
	# A student behind the railing in the dark, facing you; his neck is the thing that comes over the rail.
	p["body"]=_fig(Vector3(-1.6,-1.6,5.4),"person",1.0,Color("262d3a"),{},.2)
	p["body"].rotation.y=PI
	(p["body"].get_meta("head") as Node3D).visible=false
	p["head"]=_fig_head({"tone":SKIN,"mouth":"closed","skew":.3,"eyes":"dull","hair":true,"socket":.75},Vector3(-1.5,.88,3.2),1.4)
	p["neck"]=MeshInstance3D.new()
	p["neck"].material_override=_fig_skin(Color(.34,.32,.29),.2,true)
	p["neck"].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p["neck"])
	focus=p["head"]

## Where the head is at t: raised behind the railing, then over the rail to hang on this side, a pause, then
## drawn towards you along the rail and finally up in front of your face.
func _a_fence_head(t: float) -> Vector3:
	var s1:=c.ss(t,.25,.45)
	var over:=.88+.08*sin(PI*clampf(s1*1.5,0,1))-1.08*c.ss(s1,.45,1.0)
	var pos:=Vector3(lerpf(-1.5,-.6,s1),over,lerpf(3.2,1.9,s1))
	var s2:=c.ss(t,.6,.8)
	pos=pos.lerp(Vector3(-.2,-.1,.95),s2)
	var s3:=c.ss(t,.8,.88)
	return pos.lerp(Vector3(0,0,.46),s3)

func _show_fence(t: float) -> void:
	var head: Node3D=p["head"]
	var pos:=_a_fence_head(t)
	head.position=pos
	# Hanging upside down at first, then it rights itself by a third, and at the end looks up into your face.
	var roll:=PI-.52*c.ss(t,.45,.6)-(PI-.52)*c.ss(t,.8,.88)
	head.rotation=Vector3(0,.5*(1.0-c.ss(t,.6,.85)),roll)
	HorrorKit.pose_head(head,.15*c.ss(t,.84,.88))
	var ends:=pos+head.basis*Vector3(0,-.1,.04)*1.4
	var body:=Vector3(-1.6,.04,5.4)
	var cx:=lerpf(body.x,ends.x,.8)
	var over:=[body,Vector3(lerpf(body.x,cx,.5),.55,lerpf(body.z,2.6,.55)),Vector3(cx,.86,2.8),Vector3(cx,.86,2.36),
		Vector3(lerpf(cx,ends.x,.5),lerpf(.8,ends.y+.2,.5),lerpf(2.36,ends.z,.45)),ends]
	var raised:=[body,Vector3(lerpf(body.x,ends.x,.5),.3,lerpf(body.z,ends.z,.5)),ends]
	var a:=_a_spline(over,36)
	var b:=_a_spline(raised,36)
	var w:=c.ss(t,.28,.4)
	var line:=PackedVector3Array()
	for i in a.size(): line.append(b[i].lerp(a[i],w))
	(p["neck"] as MeshInstance3D).mesh=_fig_tube(line,.065,.045,12)
	(p["body"].get_node("Body") as Node3D).scale=Vector3(1,1+.006*sin(t*c.dur*1.6),1)
	_fig_key().light_energy=lerpf(lerpf(1.6,2.6,c.ss(t,.25,.5)),3.4,c.ss(t,.6,.85))
	_pose(t,.04*c.ss(t,.6,.86))

func _build_double() -> void:
	c.stage_dark(DARK,.04,Color(.27,.26,.24),.6)
	_room(5,13)
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(0,1.3,7.2)
	p["tube"].omni_range=5.0
	p["tube"].light_color=Color("ddd8c6")
	p["near"]=c.motive_light(Vector3(0,1.3,3.0),Color("ddd8c6"),3.0,5.0,root)
	for z in [3,7,11]:
		var w:=_window(Vector3(2.45,.2,z))
		w.rotation.y=PI/2
		(w.get_node("GlassPane") as MeshInstance3D).material_override=_surface(Color("3b4046"),.55)
	# Sodium light from the street outside the windows.
	c.motive_light(Vector3(2.2,1.2,6.5),Color("d9a066"),2.6,4.5,root)
	# The left-hand wall: two classroom doors with their plates and a notice board.
	for z in [4.5,9.2]:
		_box(Vector3(.06,2.1,.95),Vector3(-2.43,-.55,z),Color("5a4a36"))
		_text("高二(3)",Vector3(-2.4,.7,z),.14).rotation.y=PI/2
	_box(Vector3(.05,.9,1.4),Vector3(-2.44,.1,6.8),Color("5a4632"))
	for i in 3: _box(Vector3(.02,.35,.26),Vector3(-2.41,.1+(i-1)*.08,6.25+i*.55),Color("b9b19a"))
	# Another student in your uniform, with your badge on the same side. He does what you do, half a beat late.
	p["two"]=_fig(Vector3(0,-1.6,8),"person",1.0,Color("262d3a"),{"tone":SKIN,"mouth":"closed","skew":.1,"hair":true,"socket":.75},.2)
	p["two"].rotation.y=PI
	_box(Vector3(.03,.03,.01),Vector3(.12,1.3,.135),Color("8a2f2a"),p["two"])
	focus=p["two"].get_meta("head")

## What you do with your head: a slow look around, so the one who copies it is late by .06 of the time.
func _a_look(t: float) -> float:
	return .17*sin(TAU*t*1.4)*(1.0-c.ss(t,.6,.8))

func _show_double(t: float) -> void:
	var two: Node3D=p["two"]
	var d:=_a_walk(t,.835,3.2,.5)
	var x:=lerpf(lerpf(lerpf(.2,-.15,_a_cut(t,.42)),.08,_a_cut(t,.62)),0.0,_a_cut(t,.835))
	two.position=Vector3(x,-1.6,d)
	two.rotation=Vector3(0,PI,0)
	(two.get_node("Body") as Node3D).scale=Vector3(1,1+.006*sin(t*c.dur*1.6),1)
	var head: Node3D=two.get_meta("head")
	head.rotation=Vector3(0,PI-_a_look(t-.06)*3.0,.12*c.ss(t,.62,.8))
	HorrorKit.pose_head(head,0.0)
	var out:=_fig_blink(t,.40,.43) or _fig_blink(t,.60,.63) or _fig_blink(t,.815,.845)
	(p["tube"] as Light3D).light_energy=0.0 if out else 3.0
	(p["near"] as Light3D).light_energy=0.0 if out else 3.0
	_fig_key().light_energy=0.0 if out else lerpf(2.8,3.4,c.ss(t,.6,.85))
	_pose(t,0,_a_look(t),0,0,-3*c.ss(t,.6,.84))

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

const ENV_FROST_PANE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float grow = .1;
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
float ridge(vec2 p) { return 1.0 - abs(vn(p) * 2.0 - 1.0); }
void fragment() {
	// Metres on the 1.2 x 1.4 pane; the frost grows from all four corners towards the middle.
	vec2 m = vec2(1.2, 1.4) * (UV - .5);
	float d = min(min(length(m - vec2(.6, .7)), length(m - vec2(-.6, .7))), min(length(m - vec2(.6, -.7)), length(m - vec2(-.6, -.7))));
	float front = grow * .98 + .09 * (vn(m * 8.0) - .5);
	float film = smoothstep(front, front - .14, d);
	float reach = smoothstep(front + .1, front - .05, d);
	// Fine feathered crystals: short branching ridges, a millimetre or two wide.
	float f1 = pow(ridge(m * 42.0), 11.0);
	float f2 = pow(ridge(mat2(vec2(.8, .6), vec2(-.6, .8)) * m * 77.0 + 3.0), 13.0);
	float f3 = pow(ridge(mat2(vec2(.6, -.8), vec2(.8, .6)) * m * 130.0 + 9.0), 15.0);
	float fern = max(f1, max(f2 * .85, f3 * .7));
	float a = film * (.2 + .14 * vn(m * 17.0)) + fern * reach * .5;
	ALBEDO = mix(vec3(.64, .74, .8), vec3(.93, .97, .99), fern);
	ALPHA = clamp(a, 0.0, .6) * step(.001, grow);
}
"""

## A school jacket on a hanger, hung from its hook (origin at the hook's base): a draped navy body with a
## front zip line, folded-over collar flaps round an empty neck, a rolled hem, and two sleeves that are
## separate pivots at the shoulders (meta "sleeves") so they can rise. Each sleeve carries two white stripes.
func _env_jacket() -> Node3D:
	var jacket := Node3D.new()
	var cloth := _env_lit(Color(1,1,1),.95,0,.15,-1,true)
	cloth.vertex_color_use_as_albedo = true
	cloth.vertex_color_is_srgb = true
	var navy := Color("2a3445")
	var zip_color := Color("9a9a94")
	var body := _env_grid(_env_segments(36),_env_segments(18),func(u: float, v: float) -> Vector3:
		var a := u*TAU
		var open := c.ss(v,0,.16)
		var w := lerpf(.065,.235,open)+.03*v
		var d := lerpf(.055,.085,open)+.01*v
		var fold := 1+.06*sin(a*7+v*2.5)*c.ss(v,.2,1)+.03*sin(a*13)*v
		var y := -.07*open-maxf(v-.16,0)*.78+.02*sin(a*3+1)*v*v
		return Vector3(cos(a)*w*fold,y,sin(a)*d*fold),true,func(u: float, v: float) -> Color:
		var zip := absf(fposmod(u-.75+.5,1)-.5)<.011 and v>.1
		var hem := v>.93
		var base := navy.darkened(.08*sin(u*TAU*7)*c.ss(v,.2,1))
		if hem: base = navy.lightened(.1)
		return zip_color if zip else base)
	c.mesh(body,cloth,0,0,0,jacket)
	# Rolled hem: a thin band hugging the lower edge of the body.
	_env_box(Vector3(.46,.018,.18),Vector3(0,-.07-.84*.78+.004,0),_env_lit(navy.lightened(.14),.9),jacket)
	# Folded collar flaps round the empty neck, and the pale zip pull.
	var flap := _env_lit(navy.lightened(.12),.9)
	for side in [-1,1]:
		var f := _env_box(Vector3(.1,.014,.075),Vector3(side*.062,-.032,-.05),flap,jacket)
		f.rotation = Vector3(.5,side*.35,side*.55)
	_env_box(Vector3(.014,.04,.006),Vector3(0,-.12,-.092),_env_lit(zip_color,.4,.6),jacket)
	# The collar is empty: a hollow going down into black.
	_env_ball(Vector3(0,-.06,-.004),.052,_env_flat(Color("020304")),jacket,10).scale = Vector3(1,.35,.9)
	var wire := _env_lit(Color("8a8a84"),.35,.8)
	_env_rod(Vector3(-.2,-.06,0),Vector3(0,.03,0),.008,wire,jacket)
	_env_rod(Vector3(.2,-.06,0),Vector3(0,.03,0),.008,wire,jacket)
	_env_rod(Vector3(0,.03,0),Vector3(0,.1,0),.008,wire,jacket)
	var sleeves := []
	for side in [-1,1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side*.215,-.07,0)
		jacket.add_child(pivot)
		var sleeve := _env_grid(_env_segments(14),_env_segments(12),func(u: float, v: float) -> Vector3:
			var a := u*TAU
			var r := lerpf(.062,.048,v)*(1+.06*sin(a*5+v*9)*v)
			return Vector3(side*.012*v+cos(a)*r,-v*.6,sin(a)*r),true,func(u: float, v: float) -> Color:
			# Two narrow white stripes down the outer side (about .02 m wide each).
			var du := fposmod(u-(.875 if side>0 else .625)+.5,1)-.5
			var stripe := absf(absf(du)-.045)<.026
			var cuff := v>.92
			return Color("c9c6bb") if stripe else (navy.lightened(.14) if cuff else navy.darkened(.06*sin(u*TAU*5)*v)))
		c.mesh(sleeve,cloth,0,0,0,pivot)
		sleeves.append(pivot)
	jacket.set_meta("sleeves",sleeves)
	return jacket

func _build_frost() -> void:
	c.stage_dark(DARK,.04,Color(.28,.265,.24),1.3)
	# A dormitory in winter: bed and desk, a frosting window at the upper left of the frame, and a uniform on a rail.
	_env_room(4.6,6.2,Color("8b8a82"),Color("3f5b4d"),Color("57554e"))
	var window := _window(Vector3(1.45,.8,5.15),Vector2(1.2,1.4))
	(window.get_node("GlassPane") as MeshInstance3D).material_override = _env_flat(Color("46586a"))
	var pane := MeshInstance3D.new()
	pane.mesh = QuadMesh.new()
	(pane.mesh as QuadMesh).size = Vector2(1.2,1.4)
	pane.material_override = _env_shader("frostpane",ENV_FROST_PANE,{"grow":.1},5)
	c.put(pane,0,0,-.075,window)
	p["pane"]=pane
	# Moonlight from the window (the cold side) and a warm bedside lamp low on the right: the one scene of this
	# set allowed a cold/warm contrast.
	c.motive_light(Vector3(1.45,.8,4.5),Color("8fa6c8"),1.2,8.0,root)
	var lamp := c.motive_light(Vector3(-1.5,-.55,3.0),Color("e0b98a"),1.8,6.0,root)
	p["lamp"]=lamp
	_env_box(Vector3(.2,.04,.2),Vector3(-1.5,-.82,3.0),_env_lit(Color("8a8a84"),.5,.4))
	_env_glow(Vector3(-1.5,-.62,3.0),.6,Color(1,.72,.4,.7))
	# The bed's edge (blanket, pillow, frame) and the desk under the window.
	var frame := _env_lit(Color("4b3d30"),.7)
	_env_box(Vector3(1.0,.1,2.1),Vector3(-1.65,-1.2,3.9),frame)
	_env_box(Vector3(.96,.2,2.0),Vector3(-1.65,-1.06,3.9),_env_lit(Color("5e5f6c"),.95))
	_env_box(Vector3(.6,.1,.4),Vector3(-1.7,-.9,4.7),_env_lit(Color("b9b6aa"),.95))
	for x in [-2.1,-1.2]:
		for z in [2.9,4.9]: _env_box(Vector3(.06,.45,.06),Vector3(x,-1.4,z),frame)
	var desk := _desk(Vector3(1.5,0,4.55))
	desk.rotation.y = PI
	# The rail the uniform hangs from, and the uniform itself (one coat; the sleeves are its own).
	p["rail"]=_env_rod(Vector3(-1.4,.62,3.2),Vector3(1.4,.62,3.2),.03,_env_lit(Color("8a8a84"),.4,.7))
	p["coat"]=_env_jacket()
	root.add_child(p["coat"])
	(p["coat"] as Node3D).scale = Vector3.ONE*1.25
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
	ALPHA = body * fade * .3;
}
""",{"seed":float(i)},5)
		root.add_child(puff)
		p["breaths"].append(puff)
	focus=p["coat"]

func _show_frost(t: float) -> void:
	var sway := sin(t*c.dur*1.3)
	var calm := 1-c.ss(t,.5,.62)
	var coat: Node3D = p["coat"]
	# The uniform creeps closer all along, stops for the pause (.55-.62), then comes on to 1.3 m with its sleeves rising.
	var z := lerpf(3.2,1.7,c.ss(t,.05,.55))
	z = lerpf(z,1.3,c.ss(t,.62,.8))
	coat.position = Vector3(0,.5,z)
	coat.rotation = Vector3(.04*sway*calm,.05*sway*calm,.035*sway*calm)
	var lift := deg_to_rad(lerpf(0,48,c.ss(t,.62,.8))+lerpf(0,17,c.ss(t,.8,.88)))
	var sleeves: Array = coat.get_meta("sleeves")
	for i in 2:
		var side := -1.0 if i==0 else 1.0
		var pivot: Node3D = sleeves[i]
		var hang := .06*sin(t*c.dur*1.7+i*2.0)*calm
		pivot.rotation = Vector3(lift+hang,0,side*.12*lift)
	(p["rail"] as Node3D).position.z = z-3.2+0.0
	_env_param(p["pane"],"grow",lerpf(.1,.7,c.ss(t,.1,.88)))
	# Breath: five short puffs low in the frame (each .06 of the shot), fainter every time.
	for i in 5:
		var puff: MeshInstance3D = p["breaths"][i]
		var start := [.06,.26,.45,.62,.76][i] as float
		var life := c.seg(t,start,start+.06)
		puff.visible = life>0 and life<1
		puff.position = Vector3(.02*sin(i*3.0),lerpf(-.32,-.26,life),.5)
		puff.scale = Vector3.ONE*lerpf(.1,.2,life)
		_env_param(puff,"fade",sin(life*PI)*(1-i*.17))
	var close := c.ss(t,.2,.86)
	_env_key(lerpf(5.0,3.0,close))
	var shiver := c.ss(t,.3,.7)*(1-c.ss(t,.8,.95))
	_pose(t,.03*close,.006*sin(t*c.dur*21)*shiver*c.shk,0,.012*sin(t*c.dur*17)*shiver,-4*close)

func _build_broadcast() -> void:
	c.stage_dark(DARK,.04,Color(.28,.265,.24),.8)
	_env_room(3.4,10,Color("8b8a82"),Color("3f5b4d"),Color("57554e"))
	p["tube"]=c.motive_light(Vector3(0,.9,1.6),Color("dfe6da"),2.2,7.0,root)
	# The school's wall speaker: a square wooden cabinet (.35 x .5 x .2 m) with dark grille cloth on the front,
	# held out from the wall on a bracket; the standby lamp sits beside it.
	p["speaker"]=_anchor(Vector3(-.5,.5,3.4))
	var speaker: Node3D = p["speaker"]
	speaker.scale = Vector3.ONE*1.2
	var wood := _env_textured(Color("5a4a3a"),"grime",1.2,.8)
	_env_box(Vector3(.35,.5,.2),Vector3.ZERO,wood,speaker)
	var trim := _env_lit(Color("6e5c48"),.7)
	for y in [-.255,.255]: _env_box(Vector3(.37,.02,.22),Vector3(0,y,0),trim,speaker)
	for x in [-.185,.185]: _env_box(Vector3(.02,.5,.22),Vector3(x,0,0),trim,speaker)
	p["grille"]=_env_box(Vector3(.29,.4,.012),Vector3(0,-.02,-.102),_env_lit(Color("2a2a28"),.95),speaker)
	for i in 9: _env_box(Vector3(.29,.006,.004),Vector3(0,-.19+i*.042,-.11),_env_lit(Color("3a3a36"),.9),speaker)
	_env_box(Vector3(.2,.05,.006),Vector3(0,.215,-.104),_env_lit(Color("b9b6aa"),.6),speaker)
	_text("广播",Vector3(0,.215,-.109),.035,INK,speaker)
	# The bracket: an arm from the cabinet's side to a plate on the right-hand wall, and a brace under it.
	var iron := _env_lit(Color("3a3f3c"),.6,.4)
	_env_rod(Vector3(-.18,.1,.04),Vector3(-1.2,.1,.04),.035,iron,speaker)
	_env_rod(Vector3(-.17,-.2,.04),Vector3(-1.15,.04,.04),.025,iron,speaker)
	_env_box(Vector3(.03,.28,.2),Vector3(-1.2,0,.04),iron,speaker)
	_env_box(Vector3(.1,.07,.04),Vector3(.3,.17,-.08),_env_lit(Color("2a2e2c"),.6),speaker)
	p["lamp"]=_env_ball(Vector3(.3,.17,-.105),.014,_env_flat(Color("ff3b2a")),speaker)
	p["halo"]=_env_glow(Vector3(.3,.17,-.12),.2,Color(1,.25,.15,.8),speaker)
	p["red"]=c.motive_light(Vector3(.3,.17,-.3),Color("ff4030"),.6,3.6,speaker)
	# A free-standing glass-fronted notice board on legs: cork, a paper in the middle, three small ones around it.
	p["notice"]=_anchor(Vector3(0,-.2,3.8))
	var board: Node3D = p["notice"]
	_env_box(Vector3(1.8,1.2,.05),Vector3.ZERO,_env_lit(Color("5a4632"),.7),board)
	_env_box(Vector3(1.66,1.06,.02),Vector3(0,0,-.03),_env_lit(Color("8a6a44"),.95),board)
	var old_paper := _env_lit(Color("c9c0a4"),.8)
	_env_box(Vector3(.42,.56,.006),Vector3(0,.05,-.045),old_paper,board)
	p["words"]=_text("不要念出名字" if c.fx=="voice" else "请停止阅读",Vector3(0,.12,-.052),.05,INK,board)
	p["others"]=[]
	var small := [[-.62,.2,"值日表\n周一 扫地\n周二 擦黑板"],[.64,.22,"校规第七条\n不得回头"],[.62,-.28,"失物招领\n无人认领"]]
	for entry in small:
		_env_box(Vector3(.34,.4,.006),Vector3(entry[0],entry[1],-.045),old_paper,board)
		p["others"].append(_text(entry[2],Vector3(entry[0],entry[1],-.052),.045,INK,board))
	_env_box(Vector3(1.66,1.06,.01),Vector3(0,0,-.07),_env_lit(Color("9fb6b4"),.05,0,.9,.12),board)
	for x in [-.8,.8]:
		_env_box(Vector3(.05,.84,.05),Vector3(x,-1.0,.02),_env_lit(Color("3a3f3c"),.6),board)
	_env_box(Vector3(1.6,.04,.04),Vector3(0,-1.1,.02),_env_lit(Color("3a3f3c"),.6),board)
	focus=p["speaker"]

func _show_broadcast(t: float) -> void:
	var walk:=c.ss(t,.28,.55)
	var lean:=c.ss(t,.6,.8)
	p["notice"].position.z=lerpf(3.8,2.3,walk)
	# The cabinet comes down the room to .78 m from you (it is 1.1 m at the contact beat), then holds.
	var near_z:=lerpf(lerpf(3.4,1.1,c.ss(t,.2,.55)),.78,lean)
	p["speaker"].position.z=near_z
	p["words"].text="你正在被记录" if t>.58 else ("不要念出名字" if c.fx=="voice" else "请停止阅读")
	if t>.6:
		for words: Label3D in p["others"]: words.text="你正在被记录"
	# The grille cloth breathes with the voice: at most .004 m along its normal.
	(p["grille"] as Node3D).position.z=-.102+.004*sin(t*c.dur*11)*c.ss(t,.3,.5)
	# The standby lamp breathes (it stays a standby light: no hotter than .8 this close).
	var breath:=.5+.5*sin(t*c.dur*2.2)
	(p["red"] as Light3D).light_energy=.45+.15*breath
	(p["halo"] as Node3D).scale=Vector3.ONE*(.2+.05*breath)*(1+.5*lean)
	_pose(t,.25*c.ss(t,.3,.58)+.15*lean,0,0,0,0)

func _build_bell() -> void:
	c.stage_dark(DARK,.025,Color(.29,.27,.24),3.0)
	# A belfry landing: a wide brick wall (far wider than the frame), a stone floor, and the old bell on its
	# iron bracket. The wall, bracket, bell and lamp travel together on one rig, so the shot can close in
	# on the bell without leaning on camera zoom.
	_env_box(Vector3(16,.1,16),Vector3(0,-1.64,6),_env_textured(Color("4a4741"),"tile",.5,.8))
	p["rig"]=_anchor(Vector3.ZERO)
	var rig: Node3D = p["rig"]
	_env_box(Vector3(16,8.6,.2),Vector3(0,2.7,4.6),_b_brick_material(Color("7a6656")),rig)
	# The iron bracket: a wall plate, a beam out to the bell and a diagonal brace.
	var iron := _env_lit(Color("2e3230"),.5,.5)
	_env_box(Vector3(.5,.5,.06),Vector3(0,1.45,4.47),iron,rig)
	_env_box(Vector3(.09,.09,.75),Vector3(0,1.45,4.1),iron,rig)
	_env_rod(Vector3(0,.95,4.45),Vector3(0,1.4,4.0),.05,iron,rig)
	_env_rod(Vector3(0,1.45,4.0),Vector3(0,.95,4.0),.04,iron,rig)
	p["lamp"]=c.motive_light(Vector3(0,-.5,3.4),Color("e0b98a"),2.2,3.5,rig)
	p["bell"]=_anchor(Vector3(0,.45,4))
	(p["bell"] as Node3D).reparent(rig,false)
	(p["bell"] as Node3D).position=Vector3(0,.45,4)
	var body:=c.fxm("bell",.8,0,0,0)
	body.reparent(p["bell"],false)
	# The imported mesh is authored at y=1.21..2.78, not around its pivot.
	body.position.y=-1.6
	p["bell_model"]=body
	p["clapper"]=_sphere(Vector3(0,-.15,3.8),.12,RUST,rig)
	# Dust shaken from the top of the wall at every stroke (the sound of the bell is only ever heard).
	p["dust"]=[]
	var dust_mat := _env_lit(Color("9a9484"))
	for i in 40: p["dust"].append(_env_box(Vector3(.02,.02,.02),Vector3(0,0,4.3),dust_mat,rig))
	focus=p["bell"]

func _show_bell(t: float) -> void:
	var swing:=sin(t*20)*c.ss(t,.05,.25)*(1-c.ss(t,.65,.83))
	# The camera closes in on the bell (the whole rig comes at it), held from .8.
	var near:=c.ss(t,.3,.8)
	(p["rig"] as Node3D).position.z=-1.2-1.0*near
	p["bell"].rotation.z=.25*swing
	# The clapper swings with the bell and, after the last stroke, rests against the wall of the bell.
	var rest:=c.ss(t,.8,.86)
	p["clapper"].position=Vector3(lerpf(.22*swing,.13,rest),lerpf(-.15,-.06,rest),3.8)
	_env_key(lerpf(9.0,2.0,near))
	for i in 40:
		var mote:Node3D=p["dust"][i]
		mote.visible=t>=.1
		var fall:=fposmod(t*1.7+_env_h(i+50.0),1.0)
		mote.position=Vector3((_env_h(i)-.5)*2.4,2.7-3.6*fall,4.35)
	_pose(t,.1,0,0,.025*swing*c.shk,0)

func _build_banquet() -> void:
	c.stage_dark(DARK,.04,Color(.22,.21,.19),.2)
	_env_room(8,24,Color("8a8f84"),Color("6e7b72"),Color("6a6a62"))
	var tube_mat := _env_flat(Color("dfe6da"))
	for z in [3.0,9.0,15.0,21.0]:
		_env_box(Vector3(1.2,.03,.2),Vector3(0,1.88,z),tube_mat)
		c.motive_light(Vector3(0,1.5,z),Color("dfe6da"),1.4,5.5,root)
	# The long table (it stretches); plates, stools and diners are placed by the timeline instead, so they are not squashed.
	p["table"]=_anchor(Vector3(0,0,0))
	var steel := _env_lit(Color("a7adb0"),.3,.8)
	_env_box(Vector3(1.4,.05,20),Vector3(0,-.78,11),_env_lit(Color("8d8c82"),.4),p["table"])
	for side in [-1,1]:
		_env_box(Vector3(.04,.12,20),Vector3(side*.66,-.86,11),steel,p["table"])
		for k in 7: _env_box(Vector3(.05,.78,.05),Vector3(side*.64,-1.2,1.5+k*3.0),steel,p["table"])
	p["plates"]=[]
	p["kids"]=[]
	var rice := _env_lit(Color("d9d2bd"),.9)
	var greens := _env_lit(Color("4d6a3a"),.9)
	var braise := _env_lit(Color("6b3e24"),.7)
	var chopstick := _env_lit(Color("8a7a58"),.7)
	var stool_mat := _env_lit(Color("3a3f3c"),.7)
	for i in 12:
		var side := -1 if i%2 else 1
		var plate := _anchor(Vector3(side*.38,-.745,0))
		_env_box(Vector3(.38,.02,.28),Vector3.ZERO,steel,plate)
		_env_ball(Vector3(-.09,.03,.0),.05,rice,plate,10)
		_env_ball(Vector3(.03,.03,.07),.045,greens,plate,10)
		_env_ball(Vector3(.06,.03,-.06),.04,braise,plate,10)
		_env_rod(Vector3(-.16,.015,.17),Vector3(.12,.015,.18),.008,chopstick,plate)
		_env_rod(Vector3(-.16,.015,.19),Vector3(.12,.015,.2),.008,chopstick,plate)
		p["plates"].append(plate)
		var seat := _anchor(Vector3(side*1.0,0,0))
		_env_box(Vector3(.34,.05,.34),Vector3(0,-1.17,0),stool_mat,seat)
		_env_box(Vector3(.07,.42,.07),Vector3(0,-1.4,0),stool_mat,seat)
		var kid := _fig(Vector3(0,-1.6,0),"sit",.95,Color("2c353b"),{"tone":Color(.44,.44,.4),"mouth":"closed"},.4,seat)
		kid.rotation.y = -side*PI/2
		kid.set_meta("seat",seat)
		kid.set_meta("side",side)
		(kid.get_meta("head") as Node3D).rotation.x = -.5
		p["kids"].append(kid)
	# The serving hatch at the far end: a tiled wall, a black opening, a steel counter, today's menu.
	p["mouth"]=_anchor(Vector3(0,-.1,21))
	var hatch: Node3D = p["mouth"]
	_env_box(Vector3(8,3.6,.1),Vector3(0,.2,0),_env_textured(Color("c9cdc4"),"tile",1.1),hatch)
	_env_box(Vector3(1.6,.7,.12),Vector3(0,.05,-.02),_env_lit(Color("050607"),1),hatch)
	_env_box(Vector3(1.8,.05,.4),Vector3(0,-.31,-.2),steel,hatch)
	_text("今日菜品",Vector3(0,.62,-.056),.14,INK,hatch)
	p["hatch_light"]=c.motive_light(Vector3(0,.2,-.5),Color("e0d8b0"),1.0,2,hatch)
	focus=p["mouth"]

func _show_banquet(t: float) -> void:
	var stretch:=c.ss(t,.15,.6)
	var stretch_scale:=1+1.5*stretch
	p["table"].scale.z=stretch_scale
	var eating:=1-c.ss(t,.46,.5)
	var raise:=c.ss(t,.5,.53)
	var turn:=c.ss(t,.53,.56)
	for i in 12:
		var z:float=(2+i*1.3)*stretch_scale
		(p["plates"][i] as Node3D).position.z=z
		var kid: Node3D=p["kids"][i]
		var side:int=kid.get_meta("side")
		(kid.get_meta("seat") as Node3D).position.z=z
		# Heads bob over the plates, all stop together, lift, then turn to look at you.
		var head: Node3D=kid.get_meta("head")
		var pitch:=lerpf(-.5-.06*sin(t*c.dur*2.4+i)*eating,.05,raise)
		var face:=atan2(-side*1.0,-z)
		var yaw:=lerpf(0.0,face+side*PI/2,turn)
		head.rotation=Vector3(pitch,PI+yaw,0)
	# The hatch comes down the table; its light dies a moment after the stop.
	var come:=c.ss(t,.7,.88)
	p["mouth"].position.z=lerpf(21,2.5,come)
	p["mouth"].scale=Vector3.ONE*lerpf(1.0,2.6,come)
	(p["hatch_light"] as Light3D).light_energy=0.0 if t>=.75 else 1.0
	_pose(t,-.08*stretch,0,0,0,8*stretch)

func _build_cup() -> void:
	c.stage_dark(DARK,.05,Color(.21,.21,.2),.2)
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
	# The cup holds black water, and under its surface a face looks up. The mouth's size is measured from the model.
	var top := AABB()
	var first := true
	for mi: MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		var local := (p["cup"] as Node3D).global_transform.affine_inverse()*mi.global_transform*mi.mesh.get_aabb()
		top = local if first else top.merge(local)
		first = false
	var mouth := maxf(top.size.x,top.size.z)*.5
	var surface_y := top.end.y-.02
	var water := c.disc(mouth*.9,Color("0d1513"),.8,0,0,0)
	water.reparent(p["cup"],false)
	water.position = Vector3(0,surface_y,0)
	water.rotation.x = -PI/2
	p["water"] = water
	p["drown_face"]=_fig_head({"tone":Color(.55,.56,.52),"mouth":"closed","eyes":"dull"},Vector3(0,surface_y-.012,0),mouth*1.7,p["cup"])
	p["drown_face"].rotation.x = PI/2
	p["drown_face"].visible = false
	p["rim"]=c.torus(.5,.05,_env_lit(Color("d8d4c8"),.4),0,.02,3.4,root,6,_env_segments(40))
	p["inside"]=_env_box(Vector3(9,7,.03),Vector3(0,0,6),_env_lit(Color("0d1513"),.05,0,.9))
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
	p["drown_face"].visible=t>=.55
	_env_key(lerpf(5.0,2.6,grow))
	_pose(t,.15*grow,0,0,0,-5*grow)

func _build_ritual() -> void:
	c.stage_dark(DARK,.05,Color(.2,.2,.19),.18)
	_room(8,14,Color("3e4742"))
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(0,1.5,5)
	p["tube"].omni_range=7.0
	# After school: the desks pushed to the walls, the board still has the duty roster on it.
	for side in [-1,1]:
		for i in 3: _desk(Vector3(side*3.2,0,3+i*2.5)).rotation.y=side*PI/2
	_box(Vector3(5,1.5,.08),Vector3(0,.45,12.8),Color("294c48"))
	_text("值日：",Vector3(0,.6,12.7),.3)
	# The chalk circle, and seven people standing on it, heads bowed, round the eighth place: the one at your feet.
	var chalk:=Color("c9c5b5")
	p["circle"]=_ring(Vector3(0,-1.54,4.4),2.0,.02,chalk)
	p["circle"].rotation.x=PI/2
	p["circle"].material_override=_surface(chalk,.7,true)
	p["ring"]=[]
	for i in 7:
		var a:float=-PI/2+(i+1)*TAU/8
		var opts:={"tone":Color(.45,.45,.41),"mouth":"closed" if i%2 else "none","eyes":"hollow" if i==3 else "dull"}
		var person:=_fig(Vector3(cos(a)*2.0,-1.6,4.4+sin(a)*2.0),"person",.95,Color("1a2026"),opts,.35)
		person.rotation.y=atan2(-cos(a),-sin(a))
		(person.get_meta("head") as Node3D).rotation.x=-.55
		p["ring"].append(person)
	_rod(Vector3(-.15,-1.54,2.25),Vector3(.15,-1.54,2.55),.02,chalk)
	_rod(Vector3(.15,-1.54,2.25),Vector3(-.15,-1.54,2.55),.02,chalk)
	focus=(p["ring"][3] as Node3D).get_meta("head")

func _show_ritual(t: float) -> void:
	var ring: Array=p["ring"]
	var look:=c.ss(t,.5,.66)
	var slot:=_a_cut(t,.72)
	var press:=c.ss(t,.8,1)
	for i in 7:
		var person: Node3D=ring[i]
		var a:float=-PI/2+(i+1)*TAU/8
		var at:=Vector3(cos(a)*2.0,-1.6,4.4+sin(a)*2.0)
		# The two nearest step in beside you while the lamp is out, then close on you.
		if i==0 or i==6:
			var side:=1.0 if i==0 else -1.0
			at=at.lerp(Vector3(side*.7,-1.6,1.6),slot)
			at=at.lerp(Vector3(side*.45,-1.6,1.0),press)
		person.position=at
		var head: Node3D=person.get_meta("head")
		# Heads come up one after another to look at the middle, then all turn to face you; bodies never move.
		var up:=c.ss(t,.25+i*.03,.31+i*.03)
		var to_eye:=atan2(at.x,at.z)-person.rotation.y
		head.rotation=Vector3(-.55*(1-up),lerp_angle(PI,to_eye,look),0)
	(p["tube"] as Light3D).light_energy=0.0 if _fig_blink(t,.72,.75) else 9.0
	_fig_key().light_energy=lerpf(4.0,6.0,press)
	_pose(t,-.05*c.ss(t,.5,.8),0,-.12*press,0,-4*c.ss(t,.5,.95))

func _build_corridor() -> void:
	# loop and trap_out keep their accepted look; the other four take the neutral school plaster and a real ambient.
	var neutral := c.fx in ["lamps","wall","squeeze","trap_wall"]
	var plaster := WALL if neutral else Color("9aa196")
	if neutral: c.stage_dark(DARK,.035,Color(.28,.265,.24),1.2 if c.fx=="lamps" else .75)
	else: c.stage_dark(DARK,.035,Color(.21,.21,.2),.2)
	_env_room(4.2,30,plaster,Color("3d5a50"),Color("6a6d66") if not neutral else Color("57554e"))
	p["left"]=_anchor(Vector3(2.1,0,0))
	p["right"]=_anchor(Vector3(-2.1,0,0))
	# A wall skin on each moving group: it carries the doors and notice boards when the walls close in.
	var skin := _env_textured(plaster,"grime",.35)
	for side in [1,-1]:
		var group: Node3D = p["left"] if side==1 else p["right"]
		_env_box(Vector3(.06,3.6,26),Vector3(-side*.05,.15,12),skin,group)
	p["bays"]=[]
	p["again"]=null
	var same := c.fx in ["loop","trap_out"]
	var door_mat := _env_lit(Color("5a4837"),.6)
	var glass_mat := _env_lit(Color("141c1e"),.2,0,.8)
	var board_mat := _env_lit(Color("6b5536"))
	var paper_mat := _env_lit(Color("c9c0a4"),1.0,0,0)
	for side in [1,-1]:
		var group: Node3D = p["left"] if side==1 else p["right"]
		for i in 7:
			var bay := Node3D.new()
			c.put(bay,0,0,3+i*3.6,group)
			_env_box(Vector3(.06,2.1,.95),Vector3(-side*.1,-.55,0),door_mat,bay)
			_env_box(Vector3(.07,.45,.3),Vector3(-side*.11,0,.2),glass_mat,bay)
			var plate := _text("高二(3)班" if same else "高二(%d)班" % (i+1),Vector3(-side*.1,.75,0),.14,INK,bay)
			plate.rotation.y = -PI/2 if side==1 else PI/2
			_env_box(Vector3(.04,.8,1.1),Vector3(-side*.07,.1,1.8),board_mat,bay)
			for k in 3:
				var sheet := _env_box(Vector3(.012,.26,.19),Vector3(-side*.1,.1+(_env_h(i*6+k+side)-.5)*.18,1.8+(k-1)*.32),paper_mat,bay)
				sheet.rotation.x = (_env_h(i*3+k)-.5)*.2
				if side==1 and i==1 and k==1 and same:
					var line := _text("你又回来了",Vector3(-side*.108,sheet.position.y,sheet.position.z),.07,INK,bay)
					line.rotation.y = -PI/2
					line.visible = false
					p["again"] = line
			p["bays"].append(bay)
	p["lamps"]=[]
	p["lamp_lights"]=[]
	# A fill between the walls: the cold key grazes whichever wall it sits beside once they close in.
	p["fill"]=c.motive_light(Vector3(0,.4,-.8),Color("dfe6da"),0.0,5.0,root)
	var tube_mat := _env_flat(Color("e8ecdf"))
	for i in 7:
		var z: float = 3+i*3.6
		p["lamps"].append(_env_box(Vector3(1,.03,.18),Vector3(0,1.88,z),tube_mat))
	for z in [3.0,10.2,17.4,24.6]:
		p["lamp_lights"].append(c.motive_light(Vector3(0,1.5,z),Color("dfe6da"),1.6,4.5,root))
	# The lamp over your head (lamps): a pool that ends in a clear edge about 2 m ahead; it dims but never goes out.
	p["over"]=null
	if c.fx=="lamps":
		p["over"]=c.motive_light(Vector3(0,1.0,.6),Color("dfe6da"),3.0,3.6,root)
		(p["over"] as OmniLight3D).omni_attenuation=.5
	p["exit"]=_anchor(Vector3(0,0,26))
	_box(Vector3(1.8,2.8,.08),Vector3(0,-.2,0),INK,p["exit"])
	_box(Vector3(1.55,2.6,.1),Vector3(0,-.2,-.02),Color("9aa790"),p["exit"])
	_env_box(Vector3(.6,.2,.05),Vector3(0,1.25,-.1),_env_flat(Color("3fae6a")),p["exit"])
	_env_glow(Vector3(0,1.25,-.15),.9,Color(.3,1,.5,.6),p["exit"])
	_text("安全出口",Vector3(0,1.25,-.14),.09,Color("eaffef"),p["exit"])
	c.motive_light(Vector3(0,1.1,-.6),Color("7fdca0"),1.5,4.0,p["exit"])
	focus=p["exit"]

func _show_corridor(t: float) -> void:
	var narrow:bool=c.fx in ["wall","squeeze","trap_wall"]
	var same:bool=c.fx in ["loop","trap_out"]
	# Held beats: the loop stops dead for a moment; the walls stop before they close the last of the way.
	var u:float=t-(clampf(t-.45,0,.1) if same else (clampf(t-.6,0,.08) if narrow else 0.0))
	var close:=c.ss(u,.15,.84 if not narrow else .76)
	var gap:=1.75*close
	p["left"].position.x=2.1-(gap if narrow else 0)
	p["right"].position.x=-2.1+(gap if narrow else 0)
	p["left"].rotation.z=.06*close if narrow else 0.0
	p["right"].rotation.z=-.06*close if narrow else 0.0
	p["exit"].position.z=26+close*20 if same else 26
	(p["fill"] as Light3D).light_energy=.5*close if narrow else 0.0
	for i in p["bays"].size():
		p["bays"][i].position.z=-1.2+fposmod((i%7)*3.6+4.2-u*5,25.2)
	if p["again"]!=null: p["again"].visible=t>=.45 and t<.55
	for i in p["lamps"].size():
		p["lamps"][i].visible=t<.2+(6-i)*.09 if c.fx=="lamps" else true
	for k in p["lamp_lights"].size():
		var light: Light3D = p["lamp_lights"][k]
		if c.fx=="lamps": light.light_energy=0.0 if t>=.2+(6-k*2)*.09 else 1.6
		elif narrow: light.light_energy=lerpf(3.0,1.2,close)
	if narrow:
		# The nearer a wall, the harder the key grazes it: fade it with the wall's distance (never to a white board).
		_fig_key().light_energy=6.5*clampf((2.1-gap)/2.1,.3,1.0)
	elif c.fx=="lamps":
		# Darkness creeps in from the far end and stops 2 m ahead: the key's reach shrinks to that edge, the lamp overhead stays.
		_fig_key().light_energy=lerpf(6.5,12.5,c.ss(t,.2,.8))
		(_fig_key() as SpotLight3D).spot_range=lerpf(12.0,4.0,c.ss(t,.2,.8))
		var over: Light3D = p["over"]
		var dim := 3.0-1.8*c.ss(t,.2,.88)
		if c.shk>0 and _fig_blink(t,.855,.88): dim *= .3
		over.light_energy=dim
	# In the dark the eye drops to the lit floor, so the pool and its edge are what the frame holds.
	_pose(t,-.25*c.ss(t,.3,.7) if c.fx=="lamps" else 0.0,0,0,.035*sin(u*7)*close,8*close if not narrow else -5*close)

func _build_face() -> void:
	c.stage_dark(DARK,.04,Color(.27,.26,.24),.6)
	_room(4.4,14)
	p["tube"]=c.stage_lights.back()
	p["tube"].position=Vector3(0,1.3,7.2)
	p["tube"].omni_range=5.0
	p["tube"].light_color=Color("ddd8c6")
	# A second tube nearer to you keeps the doors and the notice board readable.
	p["near"]=c.motive_light(Vector3(0,1.3,3.0),Color("ddd8c6"),3.0,5.0,root)
	var fx:=c.fx
	var through_glass:=fx=="window_gaze"
	# A school corridor at night: a notice board, two classroom doors with their plates, a fire extinguisher.
	_box(Vector3(.05,.9,1.4),Vector3(2.12,.1,4.5),Color("5a4632"))
	for i in 3: _box(Vector3(.02,.35,.26),Vector3(2.09,.1+(i-1)*.08,3.95+i*.5),Color("b9b19a"))
	for z in [3.2,6.4]:
		_box(Vector3(.06,2.1,.95),Vector3(-2.12,-.55,z),Color("5a4a36"))
		_text("高二(3)",Vector3(-2.1,.7,z),.14).rotation.y=PI/2
	_box(Vector3(.3,.5,.18),Vector3(2.05,-1.3,6.0),RUST)
	# One wrong thing each: the head is too big (face), the mouth too wide (laugh), the turned head (gaze),
	# the pointing arm with a joint too many (trap_beg), the hands on the glass (window_gaze).
	var opts:={"tone":SKIN,"mouth":"closed","skew":.2,"size":1.26,"hair":true,"socket":.75}
	if fx=="laugh": opts={"tone":SKIN,"mouth":"closed","skew":.45,"size":1.12,"hair":true,"socket":.75}
	elif fx=="gaze": opts={"tone":SKIN,"mouth":"closed","skew":.3,"eyes":"dull","size":1.12,"hair":true,"socket":.75}
	elif fx=="trap_beg": opts={"tone":SKIN,"mouth":"none","eyes":"hollow","skew":0.0,"size":1.12,"hair":true}
	elif fx=="window_gaze": opts={"tone":SKIN,"mouth":"closed","skew":.25,"size":1.12,"hair":true,"socket":.75}
	p["man"]=_fig(Vector3(0,-1.6,8),"person",1.0,Color("262d3a"),opts,.2)
	p["head"]=p["man"].get_meta("head")
	if fx=="trap_beg":
		# The right arm straight out towards the far end of the corridor; the hand has a finger joint too many.
		p["beg"]=_fig_hand({"long":1.15,"thin":.5,"arm":.55,"extra":true,"tone":SKIN},p["man"])
		p["beg"].position=Vector3(-.2-sin(.8)*.6,1.4,.02+cos(.8)*.6)
		p["beg"].rotation=Vector3(0,PI-.8,0)
		HorrorKit.pose_hand(p["beg"],.1,.1)
	if through_glass:
		# A partition with a window in it, close in front of you; the man stands behind the glass. A rail and
		# the two uprights give the pane its edges; no bar crosses where his face comes.
		p["window"]=_anchor(Vector3(0,0,.8))
		var pane:=_box(Vector3(2.1,3.4,.02),Vector3(0,0,-.02),Color("9a9a92"),p["window"])
		pane.material_override=_surface(Color("9a9a92"),.1)
		for x in [-1.08,1.08]: _box(Vector3(.1,3.6,.08),Vector3(x,0,0),Color("5a5546"),p["window"])
		_box(Vector3(2.3,.07,.08),Vector3(0,-.62,0),Color("5a5546"),p["window"])
		_box(Vector3(3.4,3.6,.06),Vector3(-2.8,0,.06),WALL)
		_box(Vector3(3.4,3.6,.06),Vector3(2.8,0,.06),WALL)
		p["palms"]=[]
		for side in [-1,1]:
			var palm:=_fig_hand({"long":1.15,"thin":.4,"arm":.2,"tone":SKIN})
			palm.rotation=Vector3(PI/2,0,0)
			HorrorKit.pose_hand(palm,.05,.45)
			p["palms"].append(palm)
		p["breath"]=_sphere(Vector3.ZERO,.125,Color("4a4d4c"))
		p["breath"].scale=Vector3(1,1,.03)
		var condensation:=p["breath"].material_override as StandardMaterial3D
		condensation.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		condensation.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
		condensation.albedo_color.a=.35
	focus=p["head"]

## The stalker's distance to you: 8 m under the far tube, then it is nearer each time the light blinks (3.2, 1.4,
## close). Between the cuts it only creeps. A pure function of t (a smooth step without flicker when shk is 0).
func _a_walk(t: float, c3: float, mid: float, close: float) -> float:
	var far:=lerpf(8.0,6.0,c.ss(t,.25,.42))
	var near:=lerpf(1.4,1.2,c.ss(t,.62,.8))
	return lerpf(lerpf(lerpf(far,mid,_a_cut(t,.42)),near,_a_cut(t,.62)),close,_a_cut(t,c3))

func _show_face(t: float) -> void:
	var fx:=c.fx
	var man: Node3D=p["man"]
	var head: Node3D=p["head"]
	var glass:=fx=="window_gaze"
	var back:=fx in ["gaze","trap_beg"]
	var c3:=.78 if glass else .835
	var d:=_a_walk(t,c3,3.2,.92 if glass else .5)
	var x:=lerpf(lerpf(lerpf(.12,-.12,_a_cut(t,.42)),.06,_a_cut(t,.62)),0.0,_a_cut(t,c3))
	man.position=Vector3(x,-1.6,d)
	man.rotation=Vector3(0,0.0 if back else PI,0)
	(man.get_node("Body") as Node3D).scale=Vector3(1,1+.006*sin(t*c.dur*1.6),1)
	# Between the cuts he stands still and only the head moves: it turns to you, faster and faster.
	var turn:=pow(c.ss(t,.62,.8),2.0)
	if back: head.rotation=Vector3(0,PI-PI*c.ss(t,.58,.8),0)
	else: head.rotation=Vector3(.15*(1.0-turn),PI-.9*(1.0-turn),(.18*c.ss(t,.62,.8)) if fx=="laugh" else 0.0)
	HorrorKit.pose_head(head,.5*c.ss(t,.62,.8) if fx=="laugh" else 0.0)
	var out:=_fig_blink(t,.40,.43) or _fig_blink(t,.60,.63) or _fig_blink(t,c3-.02,c3+.01)
	(p["tube"] as Light3D).light_energy=0.0 if out else 3.0
	(p["near"] as Light3D).light_energy=0.0 if out else 3.0
	_fig_key().light_energy=0.0 if out else lerpf(2.8,3.4,c.ss(t,.6,.85))
	if glass:
		var on:=t>=.78
		for i in 2:
			var palm: Node3D=p["palms"][i]
			palm.visible=on
			palm.position=Vector3(x+(.34 if i==0 else -.34),-.22,.84)
		p["breath"].visible=t>=.85
		p["breath"].position=Vector3(x,.02,.82)
	_pose(t,0,0,0,0,-3*c.ss(t,.6,.84))

const _MZ := .42    # the glass plane at the end of the push-in, in the rig's own coordinates

## The washroom mirror: you at the basins, a small tiled room on the far side of the glass with a stall door in
## its back wall. Everything is in one rig that is pushed towards you (the push-in), so the lamps move with it.
func _build_mirror() -> void:
	c.stage_dark(DARK,.04,Color(.27,.26,.24),.6)
	var rig:=_anchor(Vector3.ZERO)
	p["rig"]=rig
	var dado:=Color("4c5a4a")
	var tile:=WALL
	# Our side of the glass: a tiled washroom with the basins in front of the mirror.
	_box(Vector3(5,.08,5.02),Vector3(0,-1.6,-1.79),Color("57554e"),rig)
	_box(Vector3(5,.08,5.02),Vector3(0,1.9,-1.79),Color("6f6d66"),rig)
	for side in [-1,1]:
		_box(Vector3(.08,3.5,5.02),Vector3(side*2.5,.15,-1.79),tile,rig)
		_box(Vector3(.03,1.15,5.02),Vector3(side*2.46,-1.025,-1.79),dado,rig)
	for z in [-.2,.5]: _box(Vector3(1.1,.03,.2),Vector3(0,1.82,z),LIGHT,rig)
	c.motive_light(Vector3(0,1.3,-.2),Color("ddd8c6"),1.5,5.0,rig)
	_box(Vector3(2.6,.1,.55),Vector3(0,-.75,_MZ-.3),Color("bfc2b8"),rig)
	_box(Vector3(2.5,.8,.5),Vector3(0,-1.2,_MZ-.3),Color("5b605a"),rig)
	for x in [-.6,.6]:
		_box(Vector3(.45,.08,.35),Vector3(x,-.69,_MZ-.32),Color("9da39b"),rig)
		_rod(Vector3(x,-.69,_MZ-.1),Vector3(x,-.5,_MZ-.1),.025,Color("8a8f8c"),rig)
	# The wall with the mirror set in it.
	_box(Vector3(5,1.0,.08),Vector3(0,1.4,_MZ+.04),tile,rig)
	_box(Vector3(5,.9,.08),Vector3(0,-1.15,_MZ+.04),Color("a5aaa1"),rig)
	for side in [-1,1]: _box(Vector3(1.3,1.6,.08),Vector3(side*1.85,.1,_MZ+.04),tile,rig)
	var rim:=Color("8a8f8c")
	_box(Vector3(2.5,.1,.1),Vector3(0,.95,_MZ),rim,rig)
	_box(Vector3(2.5,.1,.1),Vector3(0,-.75,_MZ),rim,rig)
	for side in [-1,1]: _box(Vector3(.1,1.7,.1),Vector3(side*1.25,.1,_MZ),rim,rig)
	# A thin cool-grey glass over the opening: what is in it is a little darker and colder than this side.
	p["glass"]=_box(Vector3(2.4,1.6,.01),Vector3(0,.1,_MZ),Color("62676c"),rig,.15)
	# The mirrored washroom: shallow, tiled, a stall door in its back wall (the one place that is cold).
	var depth:=2.8
	var wz:=_MZ+.05
	_box(Vector3(4,.08,depth),Vector3(0,-1.6,wz+depth*.5),Color("57554e"),rig)
	_box(Vector3(4,.08,depth),Vector3(0,1.9,wz+depth*.5),Color("6f6d66"),rig)
	for side in [-1,1]:
		_box(Vector3(.08,3.5,depth),Vector3(side*2.0,.15,wz+depth*.5),tile,rig)
		_box(Vector3(.03,1.15,depth),Vector3(side*1.96,-1.025,wz+depth*.5),dado,rig)
		_box(Vector3(.05,2.1,.8),Vector3(side*1.92,-.55,wz+1.0+(.9 if side>0 else 0.0)),Color("8a7f6a"),rig)
	var back:=wz+depth
	for side in [-1,1]: _box(Vector3(1.5,3.5,.08),Vector3(side*1.25,.15,back),tile,rig)
	_box(Vector3(1,1.4,.08),Vector3(0,1.2,back),tile,rig)
	_box(Vector3(1,2.1,.4),Vector3(0,-.55,back+.25),Color("0d0d0d"),rig)
	p["door"]=_anchor(Vector3(-.5,-.55,back-.03))
	p["door"].reparent(rig,false)
	_box(Vector3(1.0,2.1,.05),Vector3(.5,0,0),Color("8a7f6a"),p["door"])
	_box(Vector3(1.1,.03,.2),Vector3(0,1.82,wz+1.4),LIGHT,rig)
	c.motive_light(Vector3(0,1.2,wz+1.4),Color("d2d4d0"),1.4,4.2,rig)
	# The one who stands in there: in your uniform, in the dark doorway, then close behind the glass.
	p["refl"]=_fig(Vector3(.4,-1.6,_MZ+2.2),"person",1.0,Color("262d3a"),{"tone":SKIN,"mouth":"closed","skew":.2,"size":1.2,"hair":true,"socket":.8},.2,rig)
	p["refl"].rotation.y=PI
	p["head"]=p["refl"].get_meta("head")
	p["hands"]=[]
	for i in 2:
		var h:=_fig_hand({"long":1.1,"thin":.4,"arm":.28,"tone":SKIN},rig)
		h.rotation=Vector3(PI/2,0,0)
		p["hands"].append(h)
	# Cracks leave the two palms, five and four of them, each its own length.
	p["fractures"]=[]
	var crack:=_surface(PAPER,.55)
	for i in 9:
		var left:=i<5
		var from:=Vector3(.3 if left else -.3,-.15,_MZ-.012)
		var ang:=(TAU*(i if left else i-5)/(5.0 if left else 4.0))+.4*_env_h(i)+(0.0 if left else .5)
		var len:=.15+.25*_env_h(i+3.0)
		var to:=Vector3(clampf(from.x+cos(ang)*len,-1.1,1.1),clampf(from.y+sin(ang)*len,-.65,.85),_MZ-.012)
		var rod:=_rod(from,to,.003,PAPER,rig)
		rod.material_override=crack
		p["fractures"].append(rod)
	focus=p["head"]

func _show_mirror(t: float) -> void:
	var rig: Node3D=p["rig"]
	var refl: Node3D=p["refl"]
	var head: Node3D=p["head"]
	# The push-in: you lean over the basins to the glass, finished by .55.
	rig.position=Vector3(0,0,1.9*(1.0-c.ss(t,0,.55)))
	p["door"].rotation.y=1.0*c.ss(t,.22,.5)
	refl.visible=t>=.3
	var walk:=c.ss(t,.62,.8)
	var close:=c.ss(t,.8,.88)
	var z:=lerpf(lerpf(_MZ+2.2,_MZ+.3,walk),_MZ+.17,close)
	var x:=lerpf(lerpf(.4,0.0,c.ss(t,.55,.8)),0.0,close)+.04*sin(t*c.dur*1.3)*(1.0-walk)
	refl.position=Vector3(x,-1.6,z)
	refl.rotation=Vector3(0,PI,0)
	(refl.get_node("Body") as Node3D).scale=Vector3(1,1+.006*sin(t*c.dur*1.6),1)
	head.rotation=Vector3(0,PI,.22*c.ss(t,.3,.5)*(1.0-walk))
	HorrorKit.pose_head(head,0.0)
	for i in 2:
		var s:=1.0 if i==0 else -1.0
		var hand: Node3D=p["hands"][i]
		hand.visible=t>=.66
		hand.position=Vector3(x+s*.3,-.15,maxf(_MZ+.025,z-.22))
		HorrorKit.pose_hand(hand,lerpf(.1,.05,walk),.45)
	for i in 9: p["fractures"][i].visible=t>.74+i*.01
	_fig_key().light_energy=lerpf(1.6,2.6,c.ss(t,.6,.85))
	_pose(t,0,0,0,0,-3*c.ss(t,.6,.85))

func _build_paper() -> void:
	c.stage_dark(DARK,.05,Color(.19,.2,.22),.18)
	_env_room(6,12,Color("7d8780"),Color("3d5a50"),Color("5c5e57"))
	var window := _window(Vector3(0,.3,6),Vector2(3,2.5))
	(window.get_node("GlassPane") as MeshInstance3D).material_override = _env_flat(Color("2a3a48"))
	c.motive_light(Vector3(0,.6,5.2),Color("8fa6c8"),2.2,8,root)
	c.motive_light(Vector3(0,1.3,2.4),Color("9fb2cc"),1.3,6,root)
	_desk(Vector3(-1.2,0,2.6))
	_desk(Vector3(1.2,0,2.6))
	_desk(Vector3(0,0,4.6))
	_desk(Vector3(0,0,1.0))
	p["plane"]=_anchor(Vector3(1.6,.9,6.5))
	var plane_mat := _env_lit(Color("d8d0b8"),.8,0,.3,-1,true)
	plane_mat.emission_enabled = true
	plane_mat.emission = Color("d8d0b8")
	plane_mat.emission_energy_multiplier = .3
	c.mesh(_b_plane_mesh(),plane_mat,0,0,0,p["plane"]).scale=Vector3.ONE*.8
	# Sixteen test papers, each with four printed lines, lying on the three desks behind yours.
	p["sheets"]=[]
	var old_paper := _env_lit(Color("bdb598"),.85,0,.4,-1,true)
	var print_line := _env_lit(Color("7a7464"),.9)
	var desks := [Vector2(-1.2,2.6),Vector2(1.2,2.6),Vector2(0,4.6)]
	for i in 16:
		var page := _env_box(Vector3(.42,.6,.004),Vector3.ZERO,old_paper)
		for k in 4: _env_box(Vector3(.3,.008,.001),Vector3(0,.2-k*.1,-.003),print_line,page)
		var d: Vector2 = desks[i%3]
		page.position = Vector3(d.x+(_env_h(i+1.0)-.5)*.6,-.6+.004*(i/3),d.y+(_env_h(i+30.0)-.5)*.4)
		page.rotation = Vector3(PI/2,(_env_h(i+60.0)-.5)*1.6,0)
		page.set_meta("home",page.position)
		page.set_meta("home_yaw",page.rotation.y)
		p["sheets"].append(page)
	# The eye behind the slit: a head too large for a person, only its brow and one eye ever seen.
	p["eye"]=_fig_head({"tone":Color(.34,.34,.31),"eyes":"dull","mouth":"none","rim":.3},Vector3(-.07,.02,1.15),2.2)
	p["eye"].visible=false
	p["eye_light"]=c.motive_light(Vector3(-.04,.1,.9),Color("b8c4cc"),0.0,1.4,root)
	focus=p["plane"]

func _show_paper(t: float) -> void:
	# The plane glides in along an arc and settles on your desk; it rests there while the papers rise.
	var flight:=c.ss(t,0,.35)
	var a0:=Vector3(1.6,.9,6.5)
	var a1:=Vector3(1.0,1.3,4.6)
	var a2:=Vector3(.2,.0,2.6)
	var a3:=Vector3(0,-.55,1.0)
	var heading:=_b_bez(a0,a1,a2,a3,minf(flight+.02,1.0))-_b_bez(a0,a1,a2,a3,minf(flight,.98))
	heading=heading.normalized().lerp(Vector3(0,-.04,-1),c.ss(flight,.75,1)).normalized()
	p["plane"].position=_b_bez(a0,a1,a2,a3,flight)
	p["plane"].basis=Basis.looking_at(heading,Vector3.UP)*Basis(Vector3.BACK,.25*sin(t*7)*(1-flight))
	p["plane"].visible=t<.72
	# Papers lift off the desks, then close into four walls around a slit; the slit narrows and shuts.
	var slit:=c.ss(t,.72,.79)
	var half:=lerpf(.4,.03,slit)-.03*c.ss(t,.92,1)
	var desks:=[Vector2(-1.2,2.6),Vector2(1.2,2.6),Vector2(0,4.6)]
	for i in 16:
		var page:MeshInstance3D=p["sheets"][i]
		var rise:=c.ss(t,.5+i*.008,.6+i*.008)
		var d:Vector2=desks[i%3]
		var aloft:=Vector3(d.x+(_env_h(i+20.0)-.5)*1.6,-.2+.6*_env_h(i+11.0)+.03*sin(t*c.dur*1.5+i)*rise,2.0+(d.y-2.0)*.5+(_env_h(i+40.0)-.5)*1.2)
		var home:Vector3=page.get_meta("home")
		var pos:=home.lerp(aloft,rise)
		var yaw:float=page.get_meta("home_yaw")
		var rot:=Vector3(lerpf(PI/2,.3*sin(i*1.7),rise)+.35*rise*sin(t*3+i),yaw+rise*(i*.6)*.5,.5*rise*sin(t*2.2+i))
		var side:=i/4
		var j:=i%4
		var wall:=Vector3(0,0,.55+.2*_env_h(i+80.0))
		if side<2:
			wall.x=(half+.21+(j%2)*.38)*(1 if side==0 else -1)
			wall.y=((j/2)-.5)*.56
		else:
			wall.x=(j-1.5)*.3
			wall.y=.55 if side==2 else -.55
		var fold:=c.ss(t,.72+.002*i,.79)
		page.position=pos.lerp(wall,fold)
		page.rotation=rot.lerp(Vector3(0,0,(_env_h(i+90.0)-.5)*.2),fold)
	p["eye"].visible=t>=.8
	(p["eye_light"] as Light3D).light_energy=.45 if t>=.8 else 0.0
	_env_key(lerpf(2.8,.8,c.ss(t,.68,.8)))
	_pose(t,.03,0,0,-.025*c.ss(t,.5,.8))

func _build_fall() -> void:
	c.stage_dark(DARK,.012,Color(.2,.2,.21),.22)
	p["facade"]=_anchor(Vector3(0,0,0))
	_box(Vector3(18,55,.2),Vector3(0,-18,4),Color("526e69"),p["facade"])
	# A quarter of the windows are lit, a figure standing in each; the rest are dark glass.
	var lit_glass := _env_flat(Color("cdbb8a"))
	var dark_glass := _env_lit(Color("22343a"),.15,0,.7)
	var figure := _env_flat(Color("15191b"))
	for row in 12:
		for col in 5:
			var window:=_window(Vector3((col-2)*3.2,-row*3.6,3.85),Vector2(1.9,1.8))
			window.reparent(p["facade"],true)
			var face_window := row==5 and col==2
			var lit := face_window or _env_h(row*5+col)<.25
			(window.get_node("GlassPane") as MeshInstance3D).material_override = lit_glass if lit else dark_glass
			if lit and not face_window: _env_box(Vector3(.4,.9,.02),Vector3(0,-.25,-.07),figure,window)
	# Pressed against the glass of the fifth row's middle window: it passes the centre of the frame around mid-fall.
	p["window_face"]=_fig_head({"tone":Color(.46,.46,.42),"mouth":"closed","skew":.4},Vector3(0,-18,3.72),6.0,p["facade"])
	p["rail"]=_box(Vector3(7,.08,.08),Vector3(0,-.7,1.2),PAPER)
	p["ground"]=_env_box(Vector3(30,.1,30),Vector3(0,-45,8),_env_textured(Color("6a6a5e"),"tile",.3))
	var lane := _env_lit(Color("c9c5b5"),.7)
	for k in 7: _env_box(Vector3(30,.012,.12),Vector3(0,.056,(k-3)*3.5),lane,p["ground"])
	focus=_anchor(Vector3(0,-1,4))

func _show_fall(t: float) -> void:
	var drop:=c.ss(t,.08,.88)
	p["facade"].position.y=36*drop*drop
	p["rail"].position.y=-.7+drop*36
	p["ground"].position.y=-45+40*drop*drop
	_pose(t,-.16*drop,0,0,.06*drop,9*drop)

func _build_trash() -> void:
	c.stage_dark(DARK,.03,Color(.27,.26,.24),.6)
	# Inside a school's galvanised bin (1.2 x 1.0 x 1.1 m), looking up through the mouth at a lamp post, the
	# eave of the teaching block and the night sky. The lid hangs on a hinge behind the eye and swings shut.
	var steel := _env_textured(Color("4a4842"),"grime",.9,.65)
	steel.metallic = .35
	var lid_steel := _env_textured(Color("6a675f"),"grime",.9,.6)
	var rib := _env_lit(Color("3a3833"),.6,.4)
	_env_box(Vector3(1.2,.04,1.0),Vector3(0,-.35,0),_env_lit(Color("2c2b28"),.8))
	_env_box(Vector3(1.2,1.1,.04),Vector3(0,.2,.4),steel)
	_env_box(Vector3(1.2,1.1,.04),Vector3(0,.2,-.6),steel)
	for side in [-1,1]:
		_env_box(Vector3(.04,1.1,1.0),Vector3(side*.6,.2,-.1),steel)
		for y in [-.1,.2,.5]: _env_box(Vector3(.06,.05,1.0),Vector3(side*.58,y,-.1),rib)
	for y in [-.1,.2,.5]: _env_box(Vector3(1.2,.05,.06),Vector3(0,y,.37),rib)
	# The rim: a folded lip all round the mouth.
	_env_box(Vector3(1.28,.05,.07),Vector3(0,.76,.4),rib)
	_env_box(Vector3(1.28,.05,.07),Vector3(0,.76,-.6),rib)
	for side in [-1,1]: _env_box(Vector3(.07,.05,1.0),Vector3(side*.6,.76,-.1),rib)
	var spray := _text("可回收",Vector3(0,.35,.36),.15,Color(.79,.75,.64,.6))
	spray.shaded = true
	# Rubbish heaped against the back wall: bin bags, balled paper, the milk carton and a test paper.
	var bag_a := _env_lit(Color("1d2530"),.45,0,.25)
	var bag_b := _env_lit(Color("26303b"),.45,0,.25)
	var heap := [[Vector3(-.45,-.1,.22),.26,bag_a],[Vector3(.3,-.08,.26),.3,bag_b],[Vector3(0,-.2,.3),.26,bag_a],[Vector3(.4,-.25,-.05),.22,bag_b],[Vector3(-.42,-.25,-.05),.22,bag_b],[Vector3(0,-.27,-.12),.18,bag_a]]
	for entry in heap:
		var sack := _env_ball(entry[0],entry[1],entry[2],null,12)
		sack.scale = Vector3(1.15,.8,.55)
	var wad := _env_lit(Color("6f6955"),1.0,0,0)
	for i in 2: _env_ball(Vector3(-.1+i*.3,.12-i*.1,.3-i*.04),.06,wad,null,8)
	var carton := _env_box(Vector3(.09,.16,.09),Vector3(.28,.2,.3),_env_lit(Color("6c7072"),.9,0,0))
	carton.rotation = Vector3(.3,.6,.4)
	var test_paper := _env_box(Vector3(.26,.32,.004),Vector3(.38,.12,.355),_env_lit(Color("6f6955"),1.0,0,0,-1,true))
	test_paper.rotation = Vector3(-.1,.08,.12)
	p["scrap"]=_env_box(Vector3(.13,.004,.17),Vector3(.1,.6,.2),_env_lit(Color("6f6955"),1.0,0,0,-1,true))
	# The lid: the same steel, hinged along the front edge behind the eye; angle 90 is open, 0 is shut.
	p["lid"]=_anchor(Vector3(0,.8,-.6))
	_env_box(Vector3(1.32,.04,1.34),Vector3(0,0,.67),lid_steel,p["lid"])
	for x in [-.4,0,.4]: _env_box(Vector3(.06,.05,1.3),Vector3(x,-.04,.67),rib,p["lid"])
	_env_box(Vector3(1.32,.07,.05),Vector3(0,-.03,1.31),rib,p["lid"])
	for x in [-.45,.45]: _env_box(Vector3(.1,.08,.1),Vector3(x,0,.0),rib,p["lid"])
	# The hand over the free edge of the lid, fingers curled round it; it arrives as the lid starts to come down.
	p["lidhand"]=_fig_hand({"long":1.15,"thin":.6,"arm":.25,"tone":Color(.36,.33,.3)},p["lid"])
	p["lidhand"].position=Vector3(.05,.05,1.2)
	p["lidhand"].scale=Vector3.ONE*2.8   # any larger and the fingers read as sausages
	p["lidhand"].rotation=Vector3(0,0,0)
	HorrorKit.pose_hand(p["lidhand"],.9,.15)
	p["lidhand"].visible=false
	# The night outside: a sky with a faint glow behind the block, the block's eave and windows, a lamp post.
	var sky_mat := _env_flat(Color("34445a"),-1,false)
	_env_box(Vector3(30,.04,30),Vector3(0,7,3),sky_mat)
	var wall_mat := _env_lit(Color("55575a"),.9)
	_env_box(Vector3(16,3.2,.3),Vector3(0,3.4,4.6),wall_mat)
	_env_box(Vector3(16,.22,1.0),Vector3(0,5.1,4.2),_env_lit(Color("6d6e6c"),.8))
	for i in 7:
		_env_box(Vector3(.8,.9,.04),Vector3(-4.5+i*1.5,3.4,4.42),_env_flat(Color(.45,.4,.27) if i%3!=1 else Color(.1,.12,.15),-1,false))
	_env_rod(Vector3(1.8,-1.6,1.6),Vector3(1.8,3.3,1.6),.1,_env_lit(Color("3b3e41"),.6))
	_env_rod(Vector3(1.8,3.3,1.6),Vector3(.25,3.1,1.0),.07,_env_lit(Color("3b3e41"),.6))
	_env_box(Vector3(.5,.07,.22),Vector3(.2,3.05,1.0),_env_flat(Color("d9a066"),-1,false))
	p["lampglow"]=_env_glow(Vector3(.2,3.0,1.0),2.2,Color(.85,.6,.32,.85))
	p["lamp"]=c.key_light(Vector3(.0,2.8,.3),Vector3(0,-.2,.0),Color("d9a066"),3.0,6.0,70,root)
	p["lamp"].spot_attenuation = .6
	p["spill"]=c.motive_light(Vector3(0,.25,-.1),Color("d9a066"),2.0,3.0,root)
	p["sliver"]=_box(Vector3(1.2,.015,.02),Vector3(0,.85,.4),LIGHT)
	focus=_anchor(Vector3(0,.78,.35))

func _show_trash(t: float) -> void:
	# 90 open to 50 (.25-.5), held (.5-.6), 20 (.8), 6 (.88).
	var open := 90.0
	open = lerpf(open,50.0,c.ss(t,.25,.5))
	open = lerpf(open,20.0,c.ss(t,.6,.8))
	open = lerpf(open,6.0,c.ss(t,.8,.88))
	p["lid"].rotation.x=-deg_to_rad(open)
	var arrive:=c.ss(t,.6,.68)
	p["lidhand"].visible=false   # a hand hooked over the lid floats in the middle of the frame; the closing lid tells this death
	p["lidhand"].position=Vector3(.05,.05+.5*(1-arrive),1.2)
	var lamp: SpotLight3D = p["lamp"]
	lamp.light_energy=lerpf(3.0,1.6,c.ss(t,.25,.88))
	lamp.spot_angle=lerpf(70,25,c.ss(t,.25,.88))
	p["spill"].light_energy=lerpf(2.0,1.6,c.ss(t,.25,.88))
	p["lampglow"].visible=open>25
	p["scrap"].visible=t>.48 and t<.64
	var fall:=c.ss(t,.5,.62)
	p["scrap"].position=Vector3(.1+.12*sin(fall*5),lerpf(.7,.3,fall),.4)
	p["scrap"].rotation=Vector3(fall*4,fall*3,fall*2)
	p["sliver"].visible=false
	_pose(t,1.05+.25*c.ss(t,.25,.58)-.05*c.ss(t,.6,.88),0,0,.02*sin(t*22)*c.ss(t,.6,.8))
	c.cue("knock",t,.72,func() -> void: c.snd("foley.door"))

func _build_door() -> void:
	c.stage_dark(DARK,.05,Color(.22,.2,.18),.2)
	_room(5,8,Color("4e615d"))
	var dorm:=c.fx=="rules_knock"
	p["left"]=_box(Vector3(1.15,3,.12),Vector3(.575,-.1,3),Color("77877d"))
	p["right"]=_box(Vector3(1.15,3,.12),Vector3(-.575,-.1,3),Color("77877d"))
	# A lift is brushed steel with a cold lamp behind it; a dorm room is wood with a warm bulb and a peephole.
	var leaf:=_env_lit(Color("6b5a44"),.7) if dorm else _env_lit(Color("8d9390"),.5,.6,.3)
	p["left"].material_override=leaf
	p["right"].material_override=leaf
	for x in [-1.27,1.27]: _box(Vector3(.2,3.3,.2),Vector3(x,-.1,3.12),INK)
	_box(Vector3(2.7,.2,.2),Vector3(0,1.45,3.12),INK)
	p["inner"]=c.motive_light(Vector3(0,1.2,4.2),Color("e0b98a") if dorm else Color("cfe0e6"),1.6,3,root)
	# Door plate and peephole ride on the leaf (left leaf centre x .575, right -.575; its face is at local z -.06).
	if dorm:
		_text("304",Vector3(-.175,1.0,-.08),.12,INK,p["left"])
		_sphere(Vector3(-.5,.35,-.08),.02,COAL,p["left"])
	# The visitor is too tall for the door: it comes in bent over, face first.
	p["visitor"]=_fig(Vector3(0,-1.6,3.7),"roam",.95,Color("0b0f11"),{"tone":Color(.45,.45,.41),"mouth":"none","eyes":"hollow","size":1.1},.3)
	p["visitor"].rotation.y=PI
	p["head"]=p["visitor"].get_meta("head")
	p["grip"]=_fig_hand({"long":1.35,"thin":.6,"extra":true,"arm":.3,"tone":Color(.43,.43,.4)})
	p["grip"].rotation=Vector3(0,0,PI/2)
	p["light"]=_box(Vector3(.55,.14,.05),Vector3(0,1.62,2.95),RUST)
	_text("请勿开门" if dorm else "停 用",Vector3(0,.65,-.08),.15,INK,p["right"])
	p["visitor"].hide()
	p["grip"].hide()
	focus=p["head"]

func _show_door(t: float) -> void:
	# Open a crack after the knocks, wait; then a hand takes the edge and the rest swings aside.
	var open:=.22*c.ss(t,.36,.46)+.78*c.ss(t,.7,.8)
	var knock:=0.0
	for at in [.12,.24,.36]: knock+=c.ss(t,at,at+.02)-c.ss(t,at+.02,at+.06)
	var zoff:=.01*knock*c.shk
	p["left"].position=Vector3(.575+.55*open,-.1,3+zoff)
	p["right"].position=Vector3(-.575-.55*open,-.1,3+zoff)
	var visitor: Node3D=p["visitor"]
	var head: Node3D=p["head"]
	# It stoops as the leaves part, then comes through bent double, head down (the head stops short of 0.6 m).
	var stoop:=c.ss(t,.7,.82)
	var come:=c.ss(t,.82,.95)
	visitor.visible=t>.36
	visitor.position=Vector3(lerpf(.12,0,stoop),-1.6,lerpf(lerpf(3.45,2.9,stoop),1.8,come))
	visitor.rotation=Vector3(.18+.32*stoop,PI,0)
	head.rotation=Vector3(.3*stoop,PI,.2*stoop)
	HorrorKit.pose_head(head,.15*c.ss(t,.5,.66))
	var grip: Node3D=p["grip"]
	grip.scale=Vector3.ONE*1.6
	grip.visible=t>=.68
	grip.position=Vector3(.55*open-.035,.25,3.12)
	HorrorKit.pose_hand(grip,.75,.15)
	(p["inner"] as Light3D).light_energy=0.0 if _fig_blink(t,.58,.6) else 1.6
	p["light"].visible=t<.8
	_pose(t,0,0,-.08*open,.015*sin(t*37)*open*c.shk)
	for i in 3:
		var at:float=.12+i*.12
		c.cue("knock"+str(i),t,at,func() -> void: c.snd("foley.door",{"k":.4+i*.12}))

func _build_swarm() -> void:
	c.stage_dark(DARK,.05,Color(.2,.19,.17),.18)
	_room(6,12,Color("455d58"))
	_window(Vector3(0,.15,8),Vector2(3.7,2.6))
	# A classroom hanging lamp: a flat fixture with its glow, and the one real light the moths gather around.
	p["lamp"]=_anchor(Vector3(0,.7,3.8))
	_env_box(Vector3(.9,.06,.18),Vector3.ZERO,_env_flat(Color("ece4c8")),p["lamp"])
	_env_glow(Vector3(0,0,-.05),1.6,Color(1,.92,.7,.7),p["lamp"])
	p["lamp_light"]=c.motive_light(Vector3(0,.55,3.8),Color("e8d8a8"),2.2,5,root)
	_rod(Vector3(0,.73,3.8),Vector3(0,1.9,3.8),.02,COAL)
	var body:=BoxMesh.new()
	body.size=Vector3(.016,.016,.06)
	# Dusty, pale moths: lit by the key as they come close, after the lamp has gone.
	p["bodies"]=c.inst(body,c._mat_lit(Color("3a352c"),-1,true),64)
	p["wings"]=c.inst(MothShape.wing(),c._mat_lit(Color("4f483c"),-1,true,.95),128)
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
		var at:=Vector3(cos(a)*r,.5*(1-close)+sin(a*1.3)*r*.6,lerpf(3.8,.45,close)+sin(a)*r*.18)
		var scale:=Vector3.ONE*(1.0+close*.55)
		p["bodies"].multimesh.set_instance_transform(i,MothShape.pose(at,a,0,scale))
		var flap:float=sin(t*c.dur*moth[3]+moth[0])*.95
		p["wings"].multimesh.set_instance_transform(i*2,MothShape.pose(at,a,flap,scale))
		p["wings"].multimesh.set_instance_transform(i*2+1,MothShape.pose(at,a,-flap,scale*Vector3(-1,1,1)))
	p["lamp"].visible=t<.66
	(p["lamp_light"] as Light3D).light_energy=2.2 if t<.66 else 0.0
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

# ---- Environment-shot helpers of the environment tickets (_b_ prefix) ----

## A brick-bond mortar texture (cached): rows .25 m high, bricks .5 m long, one tile = 1 m.
static func _b_h(i: float) -> float:
	return fposmod(sin(i*12.9898)*43758.5453,1.0)

static func _b_brick_texture() -> ImageTexture:
	if _env_textures.has("brick"): return _env_textures["brick"]
	var size := 128
	var image := Image.create(size,size,false,Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var row := y/32
			var shifted := (x+(row%2)*32)%64
			var mortar := y%32<3 or shifted<3
			var v := .42 if mortar else .72+.28*_b_h(float(row)*5.0+float((x+(row%2)*32)/64)*11.0)
			if not mortar: v *= .88+.12*_b_h(x*31.0+y*17.0)
			image.set_pixel(x,y,Color(v,v,v))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_env_textures["brick"]=texture
	return texture

func _b_brick_material(color: Color) -> StandardMaterial3D:
	var m := _env_lit(color,.9,0,.1)
	m.albedo_texture = _b_brick_texture()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE
	return m

## A point on a cubic Bezier at u (0..1).
func _b_bez(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, u: float) -> Vector3:
	var w := 1.0-u
	return a*w*w*w+b*3*w*w*u+cc*3*w*u*u+d*u*u*u

## A paper plane folded from four triangles (two wings, a keel and a nose flap), nose towards -z.
func _b_plane_mesh() -> ArrayMesh:
	var nose := Vector3(0,0,-.35)
	var tail := Vector3(0,0,.28)
	var left := Vector3(.3,.07,.3)
	var right := Vector3(-.3,.07,.3)
	var keel := Vector3(0,-.1,.22)
	var tris := [[nose,left,tail],[nose,tail,right],[nose,keel,tail],[Vector3(0,0,-.1),Vector3(.12,.03,.16),Vector3(0,-.04,.14)]]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for tri: Array in tris:
		var n := ((tri[1]-tri[0]) as Vector3).cross(tri[2]-tri[0]).normalized()
		for v: Vector3 in tri:
			verts.append(v)
			normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return shape
