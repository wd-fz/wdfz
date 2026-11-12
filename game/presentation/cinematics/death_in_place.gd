class_name DeathInPlace
extends DeathShots
## Live death effects share the actual campus. No replacement rooms, floors,
## sky or lighting. Small effects are anchored to the captured gaze; existing
## people keep their scene positions and all borrowed visuals are restored.

const REACH := 2.4
## The staged props and figures are drawn on their own render layer as well as the default one: the campus
## lights still reach them, and a faint presence light reaches only them (never the real room).
const PROP_LAYER := 1 << 18
const PAGE := Color("5a5750")      # paper under a room light: lit, never the brightest thing in the shot
const INK_DARK := Color("1e2023")
const CHALK := Color("bdbbb1")
const STEEL := Color("5d6264")
var clearance := REACH
var _eye := Transform3D.IDENTITY
var _borrowed: Array[Dictionary] = []
var _classmates: Array[Dictionary] = []
var _attacker: Node3D
var _attacker_start := Vector3.ZERO
var _attacker_goal := Vector3.ZERO
var _gaze: WindowGazeView


func build() -> void:
	layout = DeathSceneCatalog.layout(c.fx)
	_eye = c.cam.global_transform
	clearance = _clearance()
	root = Node3D.new()
	root.name = "OnSiteDeathEffects"
	c.F.add_child(root)
	root.global_transform = _eye * Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
	root.scale *= clearance / REACH
	base_camera = c.F.to_local(_eye.origin)
	c.cam.near = minf(c._camera_near,.008)
	c.veil(Color("03070a"))
	call("_build_"+layout+"_here")
	_presence_light()
	c.d["scene"] = root
	c.d["focus"] = focus
	c.d["layout"] = layout
	c.d["in_place"] = true


func _clearance() -> float:
	var result := REACH
	var space := c._player.get_world_3d().direct_space_state
	# Sample the small effect cone, including its sides. Props have no physics;
	# only the real scene can constrain their depth, even beside a desk or wall.
	for offset: Vector2 in [Vector2.ZERO,Vector2(-.65,0),Vector2(.65,0),Vector2(0,.5),Vector2(0,-.5)]:
		var direction := _eye.basis * Vector3(offset.x,offset.y,-1).normalized()
		var query := PhysicsRayQueryParameters3D.create(_eye.origin,_eye.origin+direction*REACH,1,[c._player.get_rid()])
		var hit := space.intersect_ray(query)
		if not hit.is_empty(): result = minf(result,maxf(.12,_eye.origin.distance_to(hit["position"])-.12))
	return result


func present(t: float) -> void:
	_reset_borrowed()
	_pose(t)
	call("_show_"+layout+"_here",t)
	# The campus remains visible through the contact beat; darkness only closes
	# the shot at its end, rather than concealing a replacement set at the start.
	c.shade(.94*c.ss(t,.82,1))
	c.cue("establish",t,.04,func() -> void: c.snd("scene.hum",{"k":.3}))
	c.cue("contact",t,.56,func() -> void: c.snd("event.bigBell" if layout=="bell" else "threat.sting",{"k":.7}))
	c.cue("close",t,.88,func() -> void: c.snd("foley.vanish"))


func _pose(_t: float, pitch: float = 0, yaw: float = 0, _lift: float = 0, roll: float = 0, zoom: float = 0) -> void:
	c.cam.transform = c._camera_transform
	c.cam.rotate_object_local(Vector3.RIGHT,pitch*c.shk)
	c.cam.rotate_object_local(Vector3.UP,yaw*c.shk)
	c.cam.rotate_object_local(Vector3.BACK,roll*c.shk)
	c.cam.fov = c._camera_fov + zoom*c.shk


func _remember(node: Node3D) -> Dictionary:
	var state := {"node":node,"transform":node.transform,"visible":node.visible}
	_borrowed.append(state)
	return state


func _reset_borrowed() -> void:
	for state in _borrowed:
		var node: Variant = state["node"]
		if is_instance_valid(node):
			node.transform = state["transform"]
			node.visible = state["visible"]


func restore() -> void:
	_reset_borrowed()
	_borrowed.clear()
	_classmates.clear()
	_attacker = null
	_gaze = null


func _bind_attacker(garage: bool) -> void:
	var world := c._world as CampusWorld
	if world == null: return
	var node := world._garage_shadow if garage else world._patrol_figure
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return
	_attacker = node
	_attacker_start = node.global_position
	var offset := _attacker_start-c._player.global_position
	offset.y = 0
	_attacker_goal = c._player.global_position+offset.normalized()*.38 if offset.length_squared()>.0001 else _attacker_start
	_attacker_goal.y = _attacker_start.y
	if _attacker_start.distance_squared_to(_attacker_goal)>.001:
		var lift := Vector3.UP*1.4
		var query := PhysicsRayQueryParameters3D.create(_attacker_start+lift,_attacker_goal+lift,1,[c._player.get_rid()])
		var hit := c._player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var fraction := maxf(0,_attacker_start.distance_to(hit["position"]-lift)-.3)/_attacker_start.distance_to(_attacker_goal)
			_attacker_goal = _attacker_start.lerp(_attacker_goal,clampf(fraction,0,1))
	_remember(node)


func _approach(t: float) -> void:
	if not is_instance_valid(_attacker): return
	_attacker.global_position = _attacker_start.lerp(_attacker_goal,c.ss(t,.15,.78))
	# Turn only the presentation camera toward the actual attacker, never the
	# player's saved yaw/pitch. The attacker does not jump to another doorway.
	var target := _attacker.global_position+Vector3.UP*1.65
	if target.distance_squared_to(_eye.origin)>.01:
		var wanted := _eye.looking_at(target,Vector3.UP)
		var basis := Basis(_eye.basis.get_rotation_quaternion().slerp(wanted.basis.get_rotation_quaternion(),c.ss(t,.12,.55)*c.shk))
		c.cam.global_basis = basis




# ---- shared pieces ----
# Root coordinates: +z runs away from the eye, +y up, +x is the viewer's LEFT (the root is turned PI).

## A faint key from just behind the eye, on the props' own layer: what is staged reads in a dark corridor
## as in a lit classroom, while the campus keeps exactly the lighting it had.
func _presence_light() -> void:
	var key := c.key_light(Vector3(-.35,.45,-.4),Vector3(0,-.25,1.8),Color(.8,.82,.84),.65,4.5,62,root)
	key.light_cull_mask = PROP_LAYER
	key.light_specular = .15
	var fill := c.motive_light(Vector3(.6,-.4,.3),Color(.55,.6,.66),.12,3.0,root)
	fill.light_cull_mask = PROP_LAYER
	for node: Node in root.find_children("*","VisualInstance3D",true,false):
		(node as VisualInstance3D).layers |= PROP_LAYER


## The staged figure: dressed, matte, near-black clothes; dark skin; deep hollow sockets (see DeathShots._fig).
## It faces the eye unless away is set.
func _silhouette(kind: String = "person", x: float = 0, z: float = 2, away: bool = false, head: Dictionary = {}) -> Node3D:
	var opts := {"tone":SKIN,"mouth":"closed","skew":.2,"hair":true}
	opts.merge(head,true)
	var actor := _fig(Vector3(x,-1.6,z),kind,1.85/FigureModel.height(kind) if kind != "sit" else 1.0,Color("11141a"),opts,.3)
	actor.rotation.y = 0.0 if away else PI
	actors.append(actor)
	return actor


## Turn a figure's head towards the eye: 0 as built (with the body), 1 fully round (an owl turn when the
## body faces away). Pure: sets the rotation from scratch.
func _turn_head(actor: Node3D, amount: float, tilt: float = 0.0) -> void:
	var skull: Node3D = actor.get_meta("head")
	skull.rotation = Vector3(0,PI-PI*amount if actor.rotation.y==0.0 else PI,tilt)


func _face_at(x: float = 0, z: float = 1.8, opts: Dictionary = {}) -> Node3D:
	# Head, neck and shoulders of the jump scare: hollow sockets and a shut, too-wide mouth. The anchor keeps
	# the old ball's size (.22 m radius, twice a real head) so the callers' scales and distances still hold.
	var head := _anchor(Vector3(x,0,z))
	var look := {"mouth":"wide","open":0.0,"skew":.2,"eyes":"hollow","tone":Color(.16,.15,.14),"glow":.0,"body":.5,"cloth":Color("14161a")}
	look.merge(opts,true)
	var bust := HorrorKit.bust(look)
	HorrorKit.dress(bust.get_meta("horror_bust")["torso"],_fig_cloth(Color("161a24"),"jacket",.25))
	bust.scale = Vector3.ONE*1.9
	head.add_child(bust)
	head.set_meta("bust",bust)
	return head


## Ink or chalk on a surface: lit by the room (and the presence light), not glowing in the air.
func _ink(words: String, at: Vector3, height: float, color: Color = INK_DARK, parent: Node3D = null) -> Label3D:
	var label := _text(words,at,height,color,parent)
	label.shaded = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	return label


## Lay a label flat on a page that faces +y, its lines running to the viewer's right, read from the eye.
static func _flat(label: Label3D) -> Label3D:
	label.basis = Basis(Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,1,0))
	return label


static var _soft_textures := {}

## A soft-edged quad: "disc" (a glow, a breath, a halo) or "ring" (a pressure ripple); unshaded and
## transparent, so it reads as light or haze rather than a solid plate.
func _soft(kind: String, size: Vector2, color: Color, at: Vector3, parent: Node3D = null, billboard: bool = false) -> MeshInstance3D:
	if not _soft_textures.has(kind):
		var gradient := Gradient.new()
		if kind == "ring":
			gradient.offsets = PackedFloat32Array([0.0,.62,.8,1.0])
			gradient.colors = PackedColorArray([Color(1,1,1,0),Color(1,1,1,0),Color(1,1,1,1),Color(1,1,1,0)])
		else:
			gradient.offsets = PackedFloat32Array([0.0,.35,1.0])
			gradient.colors = PackedColorArray([Color(1,1,1,1),Color(1,1,1,.45),Color(1,1,1,0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5,.5)
		texture.fill_to = Vector2(1,.5)
		texture.width = 128
		texture.height = 128
		_soft_textures[kind] = texture
	var quad := QuadMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.albedo_texture = _soft_textures[kind]
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard: material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return c.mesh(quad,material,at.x,at.y,at.z,parent if parent != null else root)


## A network of thin cracks from a point on a pane (in the plane z = origin.z): jagged runs that branch,
## and a few short concentric breaks round the impact. Each piece carries its own reveal order in [0, 1].
func _crack_net(origin: Vector3, runs: int, seed_value: int, color: Color = Color("a9b3b5"), width: float = .0016, reach: float = 1.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for b in runs:
		var angle := b*TAU/runs+rng.randf_range(-.3,.3)
		var at := origin
		var steps := rng.randi_range(5,8)
		for s in steps:
			angle += rng.randf_range(-.5,.5)
			var length := rng.randf_range(.035,.1)*reach*(1.0+s*.12)
			var next := at+Vector3(cos(angle)*length,sin(angle)*length*.85,0)
			var rod := _rod(at,next,width*(1.0-s*.07),color)
			rod.set_meta("order",(s+.5)/steps)
			out.append(rod)
			if rng.randf()<.35:
				var twig := angle+rng.randf_range(.6,1.1)*(1 if rng.randf()<.5 else -1)
				var end := next+Vector3(cos(twig),sin(twig)*.85,0)*length*.6
				var branch := _rod(next,end,width*.7,color)
				branch.set_meta("order",minf(1.0,(s+1.2)/steps))
				out.append(branch)
			at = next
	for ring in 2:
		var radius := (.045+ring*.05)*reach
		for i in 9:
			var a0 := i*TAU/9+rng.randf_range(-.1,.1)
			var a1 := a0+TAU/9*rng.randf_range(.55,.9)
			var rod := _rod(origin+Vector3(cos(a0),sin(a0)*.85,0)*radius,origin+Vector3(cos(a1),sin(a1)*.85,0)*radius,width*.8,color)
			rod.set_meta("order",.25+ring*.25)
			out.append(rod)
	return out


func _show_net(net: Array, t: float, start: float, span: float = .22) -> void:
	for rod: Node3D in net: rod.visible = t>start+float(rod.get_meta("order"))*span


# ---- people ----

func _build_rollcall_here() -> void:
	_bind_attacker(false)
	if _attacker == null: p["visitor"] = _silhouette("teacher",.32,2.1)
	# The register comes up by itself: a hardback held open low in the view, lines of names in ink, the last
	# line yours. Paper is lit by the room, so it stays darker than the people.
	var book := _anchor(Vector3(-.1,-.5,1.3))
	book.rotation_order = EULER_ORDER_YXZ
	p["book"] = book
	_box(Vector3(.47,.014,.33),Vector3(0,-.01,0),Color("2c2421"),book)
	for side in [-1,1]:
		var page := _box(Vector3(.215,.012,.31),Vector3(side*.113,0,0),PAGE,book)
		page.rotation.z = side*.05
		for row in 9:
			_box(Vector3(.19,.0015,.0016),Vector3(side*.113,.007,-.12+row*.03),Color("5f6a72"),book)
	_box(Vector3(.006,.016,.31),Vector3(0,.004,0),Color("1a1614"),book)
	var names := ["王 磊","陈晓雨","刘 洋","张 婷","李 浩","赵 敏","周 林"]
	for row in names.size():
		var line := _flat(_ink(names[row],Vector3(.06 if row<4 else -.17,.009,.105-(row%4)*.06),.022,INK_DARK,book))
		line.modulate.a = .85
	p["name"] = _flat(_ink("未到",Vector3(-.06,.009,-.075),.026,Color("6e2a20"),book))
	p["strike"] = _box(Vector3(.09,.002,.003),Vector3(-.06,.01,-.075),Color("6e2a20"),book)
	p["new"] = _flat(_ink("你",Vector3(-.17,.009,-.135),.03,INK_DARK,book))
	focus = book


func _show_rollcall_here(t: float) -> void:
	var close := c.ss(t,.18,.8)
	var book: Node3D = p["book"]
	book.position = Vector3(-.1+.04*close,lerpf(-.5,-.36,close),lerpf(1.3,.62,close))
	book.rotation = Vector3(-.95+.25*close,.12*sin(t*3.0)*(1-close),.04*sin(t*5.0))
	# patrol: ticked present; grip: the name is struck through; names: the next line writes itself.
	p["name"].text = "已到" if c.fx=="patrol" and t>.72 else "未到"
	p["strike"].visible = c.fx=="grip" and t>.6
	p["strike"].scale.x = clampf((t-.6)/.12,0,1)
	p["new"].visible = c.fx=="names" and t>.55
	p["new"].modulate.a = clampf((t-.55)/.15,0,1)
	if _attacker != null:
		_approach(t)
		return
	var visitor: Node3D = p["visitor"]
	visitor.position = Vector3(lerpf(.32,.12,close),-1.6,lerpf(2.1,.62,c.ss(t,.3,.86)))
	_turn_head(visitor,0.0,.25*c.ss(t,.55,.8))
	_pose(t,.04*close,0,0,0,-4*close)


func _build_garage_here() -> void:
	_bind_attacker(true)
	if _attacker == null:
		p["shadow"] = _silhouette("roam",-.1,2.2,false,{"mouth":"none","skew":.35})
		# Two dull glints deep in the sockets: the only thing that catches light on it.
		var skull: Node3D = (p["shadow"] as Node3D).get_meta("head")
		p["eyes"] = []
		for side in [-1,1]:
			var glint := MeshInstance3D.new()
			var dot := SphereMesh.new()
			dot.radius = .0042
			dot.height = .0084
			glint.mesh = dot
			glint.material_override = c._mat(Color(.52,.56,.52))
			skull.add_child(glint)
			glint.position = Vector3(side*.033,.012,-.07)
			p["eyes"].append(glint)
	focus = _anchor(Vector3(0,.05,1))


func _show_garage_here(t: float) -> void:
	var close := c.ss(t,.25,.83)
	if _attacker != null:
		_approach(t)
		return
	var shadow: Node3D = p["shadow"]
	# It stands still for a long moment, then comes in a few uneven steps and leans over you at the end.
	var walk := c.ss(t,.32,.5)*.45+c.ss(t,.58,.84)*.55
	shadow.position = Vector3(lerpf(-.1,.05,walk),-1.6,lerpf(2.2,.46,walk))
	shadow.rotation = Vector3(.12*c.ss(t,.76,.88),PI,.04*sin(t*7.0)*walk)
	_turn_head(shadow,0.0,.35*c.ss(t,.4,.6)-.2*c.ss(t,.75,.88))
	for eye: Node3D in p["eyes"]: eye.visible = t>.28 and not (t>.62 and t<.65)
	_pose(t,0,.015*sin(t*13)*close,0,0,-5*close)


func _build_backseat_here() -> void:
	# The rear-view mirror: a dark plastic housing on a stem, the glass a dull dark grey. In it, small, the
	# passenger who should not be there; later the same face beside you, and a hand on your shoulder.
	var mirror := _anchor(Vector3(-.16,.24,.78))
	p["mirror"] = mirror
	_rod(Vector3(0,.06,.02),Vector3(0,.2,.05),.014,Color("1b1d1f"),mirror)
	_box(Vector3(.32,.105,.012),Vector3(0,0,.026),Color("17191b"),mirror)
	for side in [-1,1]:
		_box(Vector3(.012,.105,.04),Vector3(side*.154,0,.008),Color("1b1d1f"),mirror)
		_box(Vector3(.32,.01,.04),Vector3(0,side*.048,.008),Color("1b1d1f"),mirror)
	var glass := _box(Vector3(.296,.086,.002),Vector3(0,0,-.006),Color("39464a"),mirror,.42)
	(glass.material_override as StandardMaterial3D).roughness = .12
	p["reflection"] = HorrorKit.head({"tone":SKIN,"mouth":"closed","skew":.3,"socket":1.0,"eyes":"hollow","hair":true})
	mirror.add_child(p["reflection"])
	(p["reflection"] as Node3D).position = Vector3(.07,-.006,.012)
	(p["reflection"] as Node3D).scale = Vector3.ONE*.24
	p["passenger"] = _face_at(.5,.9,{"mouth":"closed","skew":.35})
	# The hand comes over your shoulder from behind: back of the hand to the eye, fingers hanging down over
	# the collarbone, low in the corner of the view.
	p["grip"] = _anchor(Vector3.ZERO)
	var hand := _fig_hand({"long":1.25,"thin":.45,"arm":.3,"tone":Color(.23,.215,.2),"rim":.45},p["grip"])
	hand.basis = Basis.looking_at(Vector3(.3,-1,.25),Vector3(0,.25,-1))
	hand.scale = Vector3.ONE*1.25
	HorrorKit.pose_hand(hand,.45,.25)
	p["hand"] = hand
	focus = mirror


func _show_backseat_here(t: float) -> void:
	var lean := c.ss(t,.2,.55)
	var reflection: Node3D = p["reflection"]
	reflection.visible = t>.12
	reflection.position = Vector3(lerpf(.07,.0,lean),-.006-.006*lean,.012)
	reflection.scale = Vector3.ONE*lerpf(.2,.3,lean)
	reflection.rotation.z = .3*c.ss(t,.4,.55)
	var passenger: Node3D = p["passenger"]
	passenger.visible = t>.56
	var near := c.ss(t,.56,.86)
	passenger.position = Vector3(lerpf(.62,.34,near),-.04,lerpf(.9,.5,near))
	passenger.scale = Vector3.ONE*(.2+near*.06)
	passenger.rotation = Vector3(0,-.5+.3*near,.3)
	var grip := c.ss(t,.4,.62)
	p["grip"].visible = t>.4
	p["grip"].position = Vector3(lerpf(-.55,-.24,grip),lerpf(-.08,-.2,grip),lerpf(.32,.38,grip))
	HorrorKit.pose_hand(p["hand"],.45+.35*c.ss(t,.62,.8),.25)
	_pose(t,0,.025*near,0,.025*grip,-4*near)


func _build_classroom_here() -> void:
	for child in c._world.get_children():
		if child is ClassmatesView:
			for entry: Dictionary in child.figures:
				_classmates.append(_remember(entry["node"]))
	# With nobody in the room, a few staged classmates stand in for them (behind the desks, backs to you).
	p["stand_ins"] = []
	var seen := false
	for state: Dictionary in _classmates:
		var node: Node3D = state["node"]
		if is_instance_valid(node) and node.is_visible_in_tree() and not c.cam.is_position_behind(node.global_position+Vector3.UP):
			seen = seen or (c.cam.unproject_position(node.global_position+Vector3.UP) as Vector2).distance_to(c.cam.get_viewport().get_visible_rect().get_center())<c.cam.get_viewport().get_visible_rect().size.x*.6
	if not seen:
		for spot: Vector2 in [Vector2(.75,1.7),Vector2(-.55,2.0),Vector2(.1,2.25)]:
			p["stand_ins"].append(_silhouette("person",spot.x,spot.y,true,{"skew":.25}))
	if c.fx=="chalk":
		# A chalk outline of a person, drawn on nothing, that will not rub out.
		p["outline"] = _anchor(Vector3(-.15,-.1,1.3))
		var pts := [Vector2(0,.62),Vector2(.09,.55),Vector2(.1,.42),Vector2(.06,.35),Vector2(.2,.28),Vector2(.24,0),Vector2(.2,-.32),
			Vector2(.12,-.1),Vector2(.1,-.65),Vector2(0,-.62),Vector2(-.1,-.65),Vector2(-.12,-.1),Vector2(-.2,-.32),Vector2(-.24,0),
			Vector2(-.2,.28),Vector2(-.06,.35),Vector2(-.1,.42),Vector2(-.09,.55),Vector2(0,.62)]
		p["strokes"] = []
		for i in pts.size()-1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i+1]
			var stroke := _rod(Vector3(a.x,a.y,0),Vector3(b.x,b.y,0),.0045,CHALK,p["outline"])
			stroke.material_override = _surface(Color("9d9b93"),.45)
			p["strokes"].append(stroke)
	p["writing"] = _ink("请回到座位",Vector3(0,-.02,1.15),.085,CHALK)
	focus = p["writing"]


func _show_classroom_here(t: float) -> void:
	var close := c.ss(t,.2,.78)
	var erase := c.fx in ["san","vignette","chalk"]
	for i in _classmates.size():
		var state: Dictionary = _classmates[i]
		var node: Variant = state["node"]
		if not is_instance_valid(node): continue
		if erase:
			node.visible = state["visible"] and t<.4+(i%5)*.075
		else:
			var target := atan2(node.global_position.x-_eye.origin.x,node.global_position.z-_eye.origin.z)
			node.global_rotation.y += wrapf(target-node.global_rotation.y,-PI,PI)*close
	for i in p["stand_ins"].size():
		var actor: Node3D = p["stand_ins"][i]
		if erase:
			actor.visible = t<.42+i*.1
		else:
			# One after another the heads come round, the bodies still facing the front.
			_turn_head(actor,c.ss(t,.22+i*.12,.42+i*.12),.15*sin(i*2.0)*close)
			if c.fx=="assimilation": actor.position.z = lerpf([1.7,2.0,2.25][i],[1.1,1.3,1.5][i],c.ss(t,.55,.85))
	if p.has("outline"):
		p["outline"].visible = t>.3
		for i in p["strokes"].size(): p["strokes"][i].visible = t>.3+i*.012
		p["outline"].position.z = lerpf(1.3,.8,c.ss(t,.5,.86))
	p["writing"].visible = t>.25
	p["writing"].text = "已归队" if c.fx=="assimilation" and t>.63 else ("你是谁" if erase else "请回到座位")
	p["writing"].modulate.a = close*.85
	_pose(t,0,0,0,.012*sin(t*9)*close,(-7 if c.fx=="assimilation" else 6)*close)


func _build_assembly_here() -> void:
	# A queue of students, backs to you, with a gap at the end where you are. The line closes up.
	for i in 4: _silhouette("person",.06*sin(i*2.3),1.0+i*.62,true,{"skew":.15+.1*i})
	focus = _anchor(Vector3(0,0,1.2))


func _show_assembly_here(t: float) -> void:
	var step := c.ss(t,.3,.42)*.4+c.ss(t,.6,.8)*.6
	for i in actors.size():
		var actor := actors[i]
		actor.position = Vector3(.06*sin(i*2.3),-1.6,1.0+i*.62-step*.5)
		actor.rotation.z = .02*sin(t*6+i)
		# The nearest turns its head all the way round; the next one only halfway.
		if i==0: _turn_head(actor,c.ss(t,.45,.72),.2*c.ss(t,.72,.85))
		elif i==1: _turn_head(actor,.5*c.ss(t,.62,.8))
	_pose(t,0,0,0,0,-5*c.ss(t,.23,.83))


func _build_fence_here() -> void:
	# A railing across the view, rusted paint over steel; the neck lies over its top rail.
	var rail := _anchor(Vector3(0,-.42,1.5))
	p["rail"] = rail
	_rod(Vector3(-1.3,0,0),Vector3(1.3,0,0),.04,Color("5c3a2c"),rail)
	_rod(Vector3(-1.3,-.6,0),Vector3(1.3,-.6,0),.032,Color("54372a"),rail)
	for i in 11: _rod(Vector3(-1.25+i*.25,-1.2,0),Vector3(-1.25+i*.25,.06,0),.022,Color("4b3127"),rail)
	p["head"] = _fig_head({"tone":SKIN,"mouth":"closed","skew":.35,"eyes":"hollow","hair":true,"socket":1.0},Vector3(.7,-.3,1.8),1.15)
	p["neck"] = MeshInstance3D.new()
	p["neck"].material_override = _fig_skin(Color(.3,.29,.27),.25,true)
	root.add_child(p["neck"])
	focus = p["head"]


func _show_fence_here(t: float) -> void:
	var head: Node3D = p["head"]
	# Over the rail from the far side, a pause hanging there, then along the rail and up into your face.
	var over := c.ss(t,.15,.38)
	var come := c.ss(t,.55,.84)
	var pos := Vector3(lerpf(1.0,.5,over),lerpf(-.62,-.22,over),lerpf(2.1,1.45,over))
	pos = pos.lerp(Vector3(.04,.0,.4),come)
	head.position = pos
	head.rotation = Vector3(.2-.2*come,.5*(1.0-come),PI*.55*(1.0-c.ss(t,.4,.62))+.25*come)
	HorrorKit.pose_head(head,.12*c.ss(t,.8,.88))
	var base := Vector3(1.6,-.9,2.6)
	var top := Vector3(lerpf(.9,pos.x+.15,.5),-.38,1.5)
	var neck := head.position+head.basis*Vector3(0,-.12,.03)*1.15
	(p["neck"] as MeshInstance3D).mesh = _fig_tube(_fig_curve(base,top,(top+neck)*.5+Vector3(0,.04,0),neck,22),.05,.042)


func _build_double_here() -> void:
	# Two of the same person walking in step; one is half a beat late, and when they meet only one is left.
	p["one"] = _silhouette("person",-.28,1.9,false,{"skew":.25})
	p["two"] = _silhouette("person",.28,1.9,false,{"skew":.25})
	focus = _anchor(Vector3(0,0,1))


func _show_double_here(t: float) -> void:
	var close := c.ss(t,.28,.82)
	for i in 2:
		var actor: Node3D = p["one" if i==0 else "two"]
		var late := .1*i
		var gait := sin((t-late)*c.dur*5.0)
		actor.position = Vector3((-.28 if i==0 else .28)*(1-close),-1.6+.012*absf(gait),lerpf(1.9,.5,c.ss(t-late,.28,.82)))
		actor.rotation = Vector3(0,PI,.03*gait)
		_turn_head(actor,0.0,.3*c.ss(t-late,.4,.55)-.3*c.ss(t-late,.6,.7))
	p["one"].visible = t<.76


func _build_door_here() -> void:
	# Three knocks, then something looks round the edge of the view at eye height, half a face, and comes in.
	p["peek"] = _face_at(.95,1.3,{"mouth":"none","skew":.3})
	p["visitor"] = _silhouette("person",.3,2.0,false,{"mouth":"none","skew":.3})
	focus = _anchor(Vector3(0,0,1))


func _show_door_here(t: float) -> void:
	var peek := c.ss(t,.4,.52)
	p["peek"].visible = t>.38 and t<.66
	p["peek"].position = Vector3(lerpf(.85,.55,peek),.02,1.0)
	p["peek"].rotation = Vector3(0,-.35,.5*peek)
	p["peek"].scale = Vector3.ONE*.3
	var enter := c.ss(t,.62,.86)
	p["visitor"].visible = t>.62
	p["visitor"].position = Vector3(lerpf(.5,.05,enter),-1.6,lerpf(1.5,.46,enter))
	_turn_head(p["visitor"],0.0,.45*(1.0-enter))
	for i in 3: c.cue("knock"+str(i),t,.12+i*.12,func() -> void: c.snd("foley.door",{"k":.4+i*.12}))


func _build_face_here() -> void:
	if c.fx=="window_gaze":
		for child in c._world.get_children():
			if child is WindowGazeView and child.is_visible_in_tree(): _gaze = child
	if _gaze == null:
		match c.fx:
			"gaze":
				# Someone stands with their back to you, close; the head comes round before the body does.
				p["back"] = _silhouette("person",.12,1.35,true,{"skew":.3,"mouth":"wide"})
			"trap_beg":
				# The stranger who asked the way: no face at all, the head tilting as if listening.
				p["head"] = _face_at(0,1.8,{"mouth":"none","eyes":"none","socket":.3,"skew":.1})
			"laugh":
				p["head"] = _face_at(0,1.8,{"mouth":"wide","skew":.25})
			"face":
				p["head"] = _face_at(0,1.8,{"mouth":"wide","skew":.2})
				# The extra smile: a second face looking over its shoulder.
				p["second"] = _face_at(-.3,2.0,{"mouth":"wide","skew":.5})
			_:
				p["head"] = _face_at(0,1.8)
	p["breath"] = _soft("disc",Vector2(.5,.3),Color(.75,.8,.8,.0),Vector3(.12,-.05,.6))
	focus = _anchor(Vector3(0,0,1))


func _show_face_here(t: float) -> void:
	var close := c.ss(t,.2,.82)
	if p.has("head"):
		var head: Node3D = p["head"]
		head.position.z = lerpf(1.8,.4,close)
		head.rotation.z = .18*close if c.fx!="trap_beg" else .35*sin(t*2.2)*(1.0-close)+.3*close
		var bust: Node3D = head.get_meta("bust")
		var skull: Node3D = bust.get_meta("horror_bust")["head"]
		# The laugh opens; the others stay shut until the very end.
		HorrorKit.pose_head(skull,(c.ss(t,.35,.7)*.9 if c.fx=="laugh" else .3*c.ss(t,.8,.88)))
	if p.has("second"):
		var second: Node3D = p["second"]
		second.visible = t>.45
		second.position = Vector3(lerpf(-.3,-.2,close),lerpf(-.1,.05,close),lerpf(2.0,.62,close))
		second.rotation.z = -.4
		second.scale = Vector3.ONE*.8
	if p.has("back"):
		var back: Node3D = p["back"]
		var turn := c.ss(t,.25,.55)
		_turn_head(back,turn,.25*turn)
		back.position = Vector3(.12-.1*close,-1.6,lerpf(1.35,.42,c.ss(t,.6,.84)))
		back.rotation.y = 0.0
	var breath: MeshInstance3D = p["breath"]
	breath.visible = c.fx=="window_gaze" and t>.4
	breath.scale = Vector3(.4+close*1.6,.4+close*1.2,1)
	(breath.material_override as StandardMaterial3D).albedo_color.a = .22*c.ss(t,.4,.6)*(1.0-.4*c.ss(t,.8,.9))
	_pose(t,0,.015*sin(t*8)*close,0,0,-3*close)


func _build_mirror_here() -> void:
	p["head"] = _face_at(0,1.6,{"skew":.3})
	p["cracks"] = _crack_net(Vector3(.04,.03,.66),13,7,Color("8e9799"),.0012,.8)
	focus = p["head"]


func _show_mirror_here(t: float) -> void:
	# The reflection moves first: its head tilts a beat before the camera rolls the same way.
	var head: Node3D = p["head"]
	head.position.z = lerpf(1.6,.66,c.ss(t,.23,.62))
	head.rotation.z = -.22*c.ss(t,.25,.45)
	_show_net(p["cracks"],t,.62)
	_pose(t,0,0,0,-.03*c.ss(t,.4,.6),-3*c.ss(t,.6,.85))


# ---- surroundings and things ----

func _build_crash_here() -> void:
	p["cracks"] = _crack_net(Vector3(-.08,.06,.5),12,3,Color("8e9799"),.0012,.7)
	p["car"] = _anchor(Vector3(0,-.35,2.4))
	if c.fx!="shatter":
		# Oncoming: a dark car front, two lamps with soft halos.
		_box(Vector3(1.7,.42,.5),Vector3(0,-.1,.25),Color("15181a"),p["car"])
		_box(Vector3(1.5,.3,.6),Vector3(0,.25,.55),Color("101214"),p["car"])
		_box(Vector3(.9,.08,.02),Vector3(0,-.08,-.01),Color("2a2e30"),p["car"])
		for x in [-.62,.62]:
			_box(Vector3(.26,.1,.02),Vector3(x,.02,-.012),LIGHT,p["car"])
			_soft("disc",Vector2(.9,.6),Color(1,.95,.82,.55),Vector3(x,.02,-.03),p["car"])
	focus = _anchor(Vector3(0,0,.8))


func _show_crash_here(t: float) -> void:
	var hit := c.ss(t,.46,.63)
	var car: Node3D = p["car"]
	car.position = Vector3(.1*sin(t*3.0),-.35,lerpf(2.4,.9,c.ss(t,.08,.57)))
	car.visible = t<.62
	_show_net(p["cracks"],t,.46 if c.fx!="shatter" else .3)
	_pose(t,.035*hit,.025*hit,0,.05*sin(t*23)*hit,4*hit)


func _build_flood_here() -> void:
	# The water: a tinted volume rising from the floor with a bright line where the surface meets the eye.
	p["water"] = _box(Vector3(2.8,2,.8),Vector3(0,-1.1,.9),Color("1f3a40"),null,.4)
	p["surface"] = _box(Vector3(2.8,.006,.8),Vector3(0,-.1,.9),Color("8fb3b6"),null,.35)
	for i in 26: pieces.append(_sphere(Vector3.ZERO,.003+i%3*.0025,Color("b3cfd2")))
	for bubble in pieces: (bubble.material_override as StandardMaterial3D).roughness = .1
	focus = _anchor(Vector3(0,0,.6))


func _show_flood_here(t: float) -> void:
	var level := lerpf(-1.1,.32,c.ss(t,.08,.84))
	p["water"].position.y = level-1.0
	p["surface"].position.y = level
	for i in pieces.size():
		pieces[i].position = Vector3(sin(i*7)*.45,level-1.0+fposmod(i*.13+t*1.6,1.0),.35+i%5*.12)
		pieces[i].visible = t>.35 and pieces[i].position.y<level
	_pose(t,.025*sin(t*8),0,0,.018*sin(t*7)*c.ss(t,.4,.8))


const _FROST := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float grow = 0.0;
varying vec2 uv;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void vertex() { uv = UV; }
void fragment() {
	vec2 q = uv - .5;
	float edge = max(abs(q.x) * 1.15, abs(q.y)) * 2.0;
	float n = noise(uv * 14.0) * .45 + noise(uv * 37.0) * .35 + noise(uv * 90.0) * .2;
	// Feathery crystals: thin ridges of a stretched noise, growing in from the edges.
	// Fine grain and a few needles pointing inwards, no large shapes: a frosted pane, not a pattern.
	float grain = noise(uv * 180.0) * .6 + noise(uv * 420.0) * .4;
	float needle = smoothstep(.86, .97, noise(vec2(atan(q.y, q.x) * 60.0, length(q) * 6.0)));
	float reach = 1.0 - grow * .8;
	float cover = smoothstep(reach, reach + .35, edge + (n - .5) * .25);
	ALBEDO = vec3(.55, .62, .65) + vec3(.18) * (grain + needle * .3);
	ALPHA = cover * clamp(.24 + .3 * grain + .12 * needle, 0.0, .8);
}
"""

func _build_frost_here() -> void:
	# Frost closes in from the edges of the view; in front, an empty school jacket hangs, turning slowly.
	var pane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6,1.0)
	pane.mesh = quad
	var shader := Shader.new()
	shader.code = _FROST
	var material := ShaderMaterial.new()
	material.shader = shader
	pane.material_override = material
	c.put(pane,0,0,.42,root)
	p["frost"] = pane
	p["jacket"] = _anchor(Vector3(.1,.35,1.5))
	var body := _fig_body("person")
	if body != null:
		var shell := MeshInstance3D.new()
		shell.mesh = body
		for i in body.get_surface_count():
			var garment := (body as ArrayMesh).surface_get_name(i)
			if garment in ["jacket","trim"]: shell.set_surface_override_material(i,_fig_cloth(Color("1d2433"),garment,.3))
			else: shell.set_surface_override_material(i,_hidden())
		p["jacket"].add_child(shell)
		shell.position = Vector3(0,-1.6,0)
		shell.rotation.y = PI
	_rod(Vector3(0,.0,0),Vector3(0,.5,0),.006,STEEL,p["jacket"])
	focus = p["jacket"]


static var _hidden_material: Material

## A material that draws nothing (keeps a garment's surface on the mesh but out of the picture).
static func _hidden() -> Material:
	if _hidden_material == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0,0,0,0)
		_hidden_material = m
	return _hidden_material


func _show_frost_here(t: float) -> void:
	(p["frost"].material_override as ShaderMaterial).set_shader_parameter("grow",c.ss(t,.12,.86))
	var jacket: Node3D = p["jacket"]
	jacket.visible = t>.15
	jacket.rotation = Vector3(0,.5*sin(t*2.5)+PI*c.ss(t,.55,.8),.03*sin(t*3.1))
	jacket.position.z = lerpf(1.5,1.0,c.ss(t,.4,.85))
	_pose(t,0,0,0,.006*sin(t*49)*c.ss(t,.4,.8),-4*c.ss(t,.3,.8))


func _build_broadcast_here() -> void:
	if c.fx=="voice":
		# The classroom speaker: a wooden box with a cloth grille, high in the corner, its red lamp on.
		var box := _anchor(Vector3(.5,.5,1.5))
		p["page"] = box
		_box(Vector3(.36,.26,.14),Vector3.ZERO,Color("4a3526"),box)
		p["grille"] = _box(Vector3(.3,.18,.01),Vector3(0,-.01,-.072),Color("26231f"),box)
		for i in 7: _box(Vector3(.3,.004,.004),Vector3(0,-.09+i*.027,-.078),Color("3b2c20"),box)
		p["lamp"] = _sphere(Vector3(.14,.105,-.07),.008,RUST,box)
		p["words"] = _ink("",Vector3.ZERO,.01,INK_DARK,box)
	else:
		# The notice: a sheet of typed lines; the last line is not the one that was there.
		var page := _anchor(Vector3(0,-.25,1.2))
		p["page"] = page
		_box(Vector3(.42,.56,.004),Vector3.ZERO,PAGE,page)
		_ink("通 知",Vector3(0,.22,-.004),.035,INK_DARK,page)
		for row in 9: _box(Vector3(.3+.04*sin(row*3.1),.006,.002),Vector3(.0,.15-row*.034,-.004),Color("3a3c3f"),page)
		p["words"] = _ink("请停止阅读",Vector3(0,-.19,-.004),.03,INK_DARK,page)
		p["lamp"] = _box(Vector3(.06,.06,.002),Vector3(-.14,-.235,-.005),Color("7b2a1e"),page)
	focus = p["page"]


func _show_broadcast_here(t: float) -> void:
	var close := c.ss(t,.25,.8)
	var page: Node3D = p["page"]
	if c.fx=="voice":
		page.position = Vector3(lerpf(.5,.22,close),lerpf(.5,.25,close),lerpf(1.5,.6,close))
		page.rotation = Vector3(.25*close,-.35*(1-close),0)
		p["grille"].scale = Vector3.ONE*(1.0+.04*sin(t*90.0)*c.ss(t,.3,.5)*c.shk)
		p["lamp"].visible = int(t*24)%3!=0
	else:
		page.position = Vector3(0,-.25+.1*close,lerpf(1.2,.5,close))
		page.rotation = Vector3(-.2*(1-close),0,.03*sin(t*4))
		p["words"].text = "你正在被记录" if t>.58 else "请停止阅读"
		p["lamp"].visible = t>.6
	_pose(t,.012*sin(t*27)*c.ss(t,.3,.8))


func _build_bell_here() -> void:
	# Sound and pressure cross the existing room: faint ripples in the air and dust shaken from above.
	for i in 5: pieces.append(_soft("ring",Vector2(1,1),Color(.8,.82,.8,.0),Vector3(0,.05,2)))
	p["dust"] = []
	for i in 40: p["dust"].append(_box(Vector3(.004,.004,.004),Vector3.ZERO,Color("8d8b84")))
	focus = _anchor(Vector3(0,0,1))


func _show_bell_here(t: float) -> void:
	for i in pieces.size():
		var progress := c.ss(t,.18+i*.085,.62+i*.07)
		var ring: MeshInstance3D = pieces[i]
		ring.visible = progress>0 and progress<1
		ring.position.z = lerpf(2,.4,progress)
		ring.scale = Vector3.ONE*(.4+progress*1.4)
		(ring.material_override as StandardMaterial3D).albedo_color.a = .16*sin(PI*progress)
	for i in p["dust"].size():
		var fall := fposmod(t*1.3+i*.137,1.0)
		var mote: Node3D = p["dust"][i]
		mote.position = Vector3(sin(i*5.3)*.9,.9-fall*1.8,.5+fmod(i*.37,1.5))
		mote.visible = t>.2
	_pose(t,.01*sin(t*38),0,0,.015*sin(t*38),3*c.ss(t,.45,.8))


func _build_banquet_here() -> void:
	# A canteen tray at table height: steel, compartments, rice and greens going grey. It keeps the same size
	# in the view while everything behind it stretches away (a dolly zoom): you never reach the table.
	var tray := _anchor(Vector3(0,-.36,.95))
	p["tray"] = tray
	_box(Vector3(.42,.012,.3),Vector3.ZERO,STEEL,tray).material_override = _surface_steel()
	for side in [-1,1]:
		_box(Vector3(.42,.03,.008),Vector3(0,.014,side*.146),STEEL,tray).material_override = _surface_steel()
		_box(Vector3(.008,.03,.3),Vector3(side*.206,.014,0),STEEL,tray).material_override = _surface_steel()
	_box(Vector3(.008,.022,.3),Vector3(.02,.012,0),STEEL,tray).material_override = _surface_steel()
	var rice := _sphere(Vector3(-.1,.012,0),.08,Color("5d5b53"),tray)
	rice.scale = Vector3(1.1,.35,1.4)
	for i in 5:
		var leaf := _sphere(Vector3(.12+.03*sin(i*2.0),.016,-.08+i*.04),.03,Color("2d3a25"),tray)
		leaf.scale = Vector3(1.2,.3,.8)
	_rod(Vector3(.05,.02,.17),Vector3(.2,.03,-.12),.006,Color("6b5a43"),tray)
	_rod(Vector3(.07,.02,.18),Vector3(.21,.03,-.1),.006,Color("6b5a43"),tray)
	focus = tray


func _surface_steel() -> StandardMaterial3D:
	var m := _surface(STEEL)
	m.metallic = .6
	m.roughness = .35
	return m


func _show_banquet_here(t: float) -> void:
	var pull := c.ss(t,.2,.83)
	var tray: Node3D = p["tray"]
	# The tray comes closer while the lens widens, so it stays the same size and the room runs away.
	var z := lerpf(.95,.45,pull)
	tray.position = Vector3(0,lerpf(-.36,-.18,pull),z)
	tray.rotation.x = -.5*pull
	var fov := rad_to_deg(2.0*atan(tan(deg_to_rad(c._camera_fov)*.5)*.95/z))
	_pose(t,0,0,0,0,minf(fov,140.0)-c._camera_fov)


func _build_cup_here() -> void:
	p["cup"] = _anchor(Vector3(0,-.3,1.2))
	var model := FallingProps.model("cup",CampusData.tier)
	model.scale = Vector3.ONE*1.4
	c.put(model,0,-.1,0,p["cup"])
	p["lid"] = FallingProps.model("lid",CampusData.tier)
	p["lid"].scale = Vector3.ONE*1.4
	c.put(p["lid"],0,.17,0,p["cup"])
	# Inside, the dark water; looking down into it the rim becomes the edge of the sky.
	p["inside"] = _sphere(Vector3(0,.1,0),.05,Color("0d1416"),p["cup"])
	p["inside"].scale = Vector3(1.3,.05,1.3)
	focus = p["cup"]


func _show_cup_here(t: float) -> void:
	var close := c.ss(t,.2,.84)
	var cup: Node3D = p["cup"]
	cup.position = Vector3(0,-.3+close*.18,lerpf(1.2,.42,close))
	cup.scale = Vector3.ONE*(1+close*1.8)
	# The mouth turns to face you.
	cup.rotation.x = -.9*c.ss(t,.3,.8)
	p["lid"].position = Vector3(-.18*close,.17+.2*close,.1*close)
	p["lid"].rotation.z = close*2.4
	p["lid"].visible = t<.7


func _build_ritual_here() -> void:
	# A chalk circle on the floor and figures standing round its far side, facing in, heads bowed; the one
	# gap in the ring is where you stand. They close it.
	p["circle"] = _anchor(Vector3(0,-1.58,1.4))
	for i in 48:
		var a := i*TAU/48
		var b := (i+.8)*TAU/48
		_rod(Vector3(cos(a),0,sin(a))*.9,Vector3(cos(b),0,sin(b))*.9,.012,CHALK,p["circle"])
	for i in 5: _silhouette("person",0,0,true,{"skew":.2+.1*i})
	focus = _anchor(Vector3(0,-.2,1.2))


func _show_ritual_here(t: float) -> void:
	var close := c.ss(t,.25,.83)
	for i in actors.size():
		var a := (i-2)*.62
		var radius := lerpf(1.05,.75,close)
		var actor := actors[i]
		actor.position = Vector3(sin(a)*radius,-1.6,1.4-.45*close+cos(a)*radius)
		actor.rotation = Vector3(0,a+PI,0)
		var skull: Node3D = actor.get_meta("head")
		skull.rotation = Vector3(.5*(1.0-c.ss(t,.55+i*.04,.7+i*.04)),PI,0)
	_pose(t,-.08*c.ss(t,.2,.5)+.08*close,0,0,0,-4*close)


func _build_corridor_here() -> void:
	match c.fx:
		"lamps":
			# A row of ceiling tubes ahead going out one by one, from the far end towards you.
			p["tubes"] = []
			for i in 4:
				var tube := _anchor(Vector3(0,.72,.9+i*.45))
				_box(Vector3(.6,.03,.1),Vector3(0,.02,0),Color("8a8c86"),tube)
				_box(Vector3(.56,.012,.05),Vector3.ZERO,LIGHT,tube)
				_soft("disc",Vector2(.9,.35),Color(.9,.95,.9,.35),Vector3(0,-.01,0),tube).rotation.x = PI*.5
				p["tubes"].append(tube)
			focus = _anchor(Vector3(0,0,1))
		"squeeze","trap_wall":
			# Plaster walls with the green dado sliding in from both sides; for "wall" a door in front fades.
			p["walls"] = []
			for side in [-1,1]:
				var wall := _anchor(Vector3(side*1.1,0,.75))
				_box(Vector3(.9,2.4,.04),Vector3(0,.0,0),Color("4d4c46"),wall)
				for k in 3: _soft("disc",Vector2(.35,.6),Color(.05,.05,.04,.35),Vector3(sin(k*2.1)*.25,.2-k*.3,-.025),wall)
				_box(Vector3(.9,1.0,.045),Vector3(0,-1.1,-.002),Color("3f5b4d"),wall)
				_box(Vector3(.9,.03,.05),Vector3(0,-.6,-.004),Color("2e4438"),wall)
				p["walls"].append(wall)
			focus = _anchor(Vector3(0,0,1))
		"wall":
			# The door in front of you is plastered over while you look at it.
			p["door"] = _anchor(Vector3(0,-.55,1.6))
			_box(Vector3(.9,2.1,.03),Vector3.ZERO,Color("4a3a2e"),p["door"])
			_box(Vector3(.98,.05,.05),Vector3(0,1.07,-.01),Color("2f2620"),p["door"])
			for side in [-1,1]: _box(Vector3(.05,2.15,.05),Vector3(side*.47,.02,-.01),Color("2f2620"),p["door"])
			_box(Vector3(.04,.04,.06),Vector3(-.35,0,-.04),STEEL,p["door"])
			_box(Vector3(.3,.2,.004),Vector3(0,.55,-.02),Color("2c2f30"),p["door"])
			p["plaster"] = _box(Vector3(1.1,2.25,.03),Vector3(0,-.55,1.585),Color("55544e"),null,0.0)
			focus = p["door"]
		_:
			# The green exit sign: lit, and every time you look it is a little further, or there are more.
			p["signs"] = []
			for i in (3 if c.fx=="trap_out" else 1):
				var sign := _anchor(Vector3([0.0,.45,-.4][i],.5-i*.06,1.4+i*.55))
				_box(Vector3(.34,.13,.04),Vector3.ZERO,Color("1f6b45"),sign).material_override = c._mat(Color("2f8f5c"))
				_ink("安全出口",Vector3(.03,0,-.022),.045,Color("e6f2ea"),sign).shaded = false
				_box(Vector3(.05,.06,.002),Vector3(.12,0,-.022),Color("e6f2ea"),sign).material_override = c._mat(Color("e6f2ea"))
				_soft("disc",Vector2(.7,.35),Color(.3,.9,.55,.25),Vector3(0,0,-.03),sign)
				p["signs"].append(sign)
			focus = p["signs"][0]


func _show_corridor_here(t: float) -> void:
	var close := c.ss(t,.15,.84)
	var narrow := c.fx in ["wall","squeeze","trap_wall"]
	if p.has("tubes"):
		for i in p["tubes"].size():
			p["tubes"][i].visible = t<.75-i*.13
	if p.has("walls"):
		for i in 2:
			var breathe := .03*sin(t*9.0)*c.shk if c.fx=="squeeze" else 0.0
			# They stop a hand's width apart: the room is still there through the slit.
			p["walls"][i].position.x = (-1 if i==0 else 1)*(1.1-close*.6+breathe)
	if p.has("door"):
		(p["plaster"].material_override as StandardMaterial3D).albedo_color.a = c.ss(t,.35,.72)
		p["door"].visible = t<.74
		p["door"].position.z = lerpf(1.6,1.05,close)
		p["plaster"].position.z = p["door"].position.z-.015
	if p.has("signs"):
		for i in p["signs"].size():
			var sign: Node3D = p["signs"][i]
			sign.position.z = 1.4+i*.55+(1.2 if c.fx=="loop" else .4)*close
			sign.rotation.y = [0.0,.5,-.5][i] if c.fx=="trap_out" else 0.0
			sign.visible = c.fx!="trap_out" or t>.2+i*.15
	_pose(t,0,0,0,.012*sin(t*9)*close,(-4 if narrow else 7)*close)


func _build_paper_here() -> void:
	if c.fx=="slit":
		# A sheet right in front of you tears along a line; through the gap, an eye.
		for side in [-1,1]:
			var half := _anchor(Vector3(0,0,.55))
			_box(Vector3(.5,.7,.003),Vector3(side*.25,0,0),PAGE,half)
			pieces.append(half)
		p["eye"] = _anchor(Vector3(0,0,.62))
		var white := _sphere(Vector3.ZERO,.03,Color("8e8b80"),p["eye"])
		white.scale = Vector3(1.4,.8,.6)
		_sphere(Vector3(0,0,-.012),.012,Color("1b1612"),p["eye"])
		_box(Vector3(.12,.08,.01),Vector3(0,0,.025),Color("050506"),p["eye"])
		focus = p["eye"]
	else:
		# Paper planes fly back in from the dark, one after another; the last unfolds into the letter.
		for i in 7:
			var plane := _anchor(Vector3.ZERO)
			var wing := ArrayMesh.new()
			var verts := PackedVector3Array([Vector3(0,0,-.12),Vector3(.07,.0,.06),Vector3(0,-.02,.06),
				Vector3(0,0,-.12),Vector3(0,-.02,.06),Vector3(-.07,0,.06)])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
			wing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			c.mesh(wing,_surface(PAGE,-1,true),0,0,0,plane).scale = Vector3.ONE*1.7
			pieces.append(plane)
		p["letter"] = _anchor(Vector3(0,-.1,.62))
		_box(Vector3(.34,.46,.003),Vector3.ZERO,PAGE,p["letter"])
		for row in 6: _box(Vector3(.24,.004,.002),Vector3(0,.1-row*.04,-.003),Color("3a3c3f"),p["letter"])
		_ink("你回来了",Vector3(0,.17,-.003),.03,INK_DARK,p["letter"])
		focus = p["letter"]


func _show_paper_here(t: float) -> void:
	if c.fx=="slit":
		var tear := c.ss(t,.35,.75)
		for i in pieces.size():
			var half: Node3D = pieces[i]
			half.position = Vector3((-1 if i==0 else 1)*.05*tear,0,lerpf(.8,.55,c.ss(t,.1,.35)))
			half.rotation.y = (-1 if i==0 else 1)*.4*tear
		p["eye"].visible = t>.45
		p["eye"].position.z = lerpf(.7,.6,c.ss(t,.6,.86))
		return
	for i in pieces.size():
		var plane: Node3D = pieces[i]
		var flight := c.ss(t,.08+i*.07,.38+i*.07)
		var a := i*2.4
		plane.position = Vector3(cos(a)*.7*(1-flight)+.1*sin(t*3+i),sin(a)*.4*(1-flight)-.05,lerpf(2.2,.35,flight))
		plane.rotation = Vector3(.2*sin(t*4+i),PI+.6*cos(a)*(1-flight),.4*sin(t*5+i))
		plane.visible = flight>0 and flight<1
	p["letter"].visible = t>.7
	p["letter"].position.z = lerpf(.9,.55,c.ss(t,.7,.86))


func _build_fall_here() -> void:
	# You go down past the front of the building: windows stream upward, faster and faster.
	var facade := _anchor(Vector3(0,0,1.3))
	p["facade"] = facade
	for i in 8:
		var y := i*.9
		_box(Vector3(2.4,.9,.04),Vector3(0,y,0),Color("44433e"),facade)
		for x in [-.7,0,.7]:
			_box(Vector3(.46,.5,.02),Vector3(x,y+.05,-.025),Color("111619") if (i+int(x*10))%3 else Color("5c5944"),facade)
			_box(Vector3(.5,.03,.04),Vector3(x,y-.21,-.04),Color("6a6962"),facade)
	focus = _anchor(Vector3(0,0,.8))


func _show_fall_here(t: float) -> void:
	var fall := t*.6+1.6*c.ss(t,.15,.9)*t
	p["facade"].position.y = -5.6+fmod(fall*4.0,3.6)
	p["facade"].position.z = lerpf(1.6,1.0,c.ss(t,.3,.8))
	_pose(t,-.05*c.ss(t,.3,.8),0,0,.035*c.ss(t,.4,.85),7*c.ss(t,.2,.8))


func _build_trash_here() -> void:
	# Inside the bin: its dark rim round the view, rubbish at the bottom, and the lid coming down.
	var rim := _anchor(Vector3(0,0,.42))
	p["rim"] = rim
	var plastic := Color("23352c")
	_box(Vector3(1.0,.12,.4),Vector3(0,-.42,.2),plastic,rim)
	for side in [-1,1]: _box(Vector3(.12,1.0,.4),Vector3(side*.56,0,.2),plastic,rim)
	for i in 6:
		var bag := _sphere(Vector3(sin(i*1.7)*.4,-.38,.25+i%3*.08),.12,Color("101213"),rim)
		bag.scale = Vector3(1.2,.6,1)
	p["lid"] = _anchor(Vector3(0,.42,.62))
	_box(Vector3(1.1,.04,.75),Vector3(0,0,-.37),Color("2d4436"),p["lid"])
	_box(Vector3(1.1,.06,.02),Vector3(0,-.02,-.74),Color("22332a"),p["lid"])
	p["gap"] = _soft("disc",Vector2(1.4,.25),Color(.85,.88,.82,.3),Vector3(0,.4,.7))
	focus = _anchor(Vector3(0,0,.8))


func _show_trash_here(t: float) -> void:
	var close := c.ss(t,.18,.8)
	p["lid"].rotation.x = lerpf(1.35,0.0,close)
	p["gap"].scale = Vector3(1,1.0-close,1)
	p["gap"].visible = close<.98
	c.cue("lid",t,.72,func() -> void: c.snd("foley.door"))


func _build_swarm_here() -> void:
	var shape := BoxMesh.new()
	shape.size = Vector3(.012,.012,.04)
	p["bodies"] = c.inst(shape,c._mat(Color("050708"),-1,true,false,false),64)
	p["wings"] = c.inst(MothShape.wing(),c._mat(Color("090d10"),-1,true,false,false),128)
	p["bodies"].reparent(root,false)
	p["wings"].reparent(root,false)
	focus = _anchor(Vector3(0,0,.8))


func _show_swarm_here(t: float) -> void:
	var close := c.ss(t,.2,.86)
	for i in 64:
		var angle := i*2.399+t*(3+i%3)
		var radius := lerpf(.5+(i%7)*.055,.05+(i%5)*.03,close)
		var at := Vector3(cos(angle)*radius,sin(angle*1.3)*radius*.6,lerpf(1.8,.28,close))
		p["bodies"].multimesh.set_instance_transform(i,MothShape.pose(at,angle,0,Vector3.ONE))
		var flap := sin(t*c.dur*(17+i%9)+i)*.95
		p["wings"].multimesh.set_instance_transform(i*2,MothShape.pose(at,angle,flap,Vector3.ONE))
		p["wings"].multimesh.set_instance_transform(i*2+1,MothShape.pose(at,angle,-flap,Vector3(-1,1,1)))
