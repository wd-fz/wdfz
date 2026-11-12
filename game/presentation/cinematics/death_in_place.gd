class_name DeathInPlace
extends DeathShots
## Live death effects share the actual campus. No replacement rooms, floors,
## sky or lighting. Small effects are anchored to the captured gaze; existing
## people keep their scene positions and all borrowed visuals are restored.

const REACH := 2.4
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


func _silhouette(kind: String = "person", x: float = 0, z: float = 2) -> Node3D:
	var actor := _person(Vector3(x,-1.6,z),1.85/FigureModel.height(kind),INK,kind)
	actor.rotation.y = PI
	return actor


func _face_at(x: float = 0, z: float = 1.8) -> Node3D:
	var head := _anchor(Vector3(x,0,z))
	_sphere(Vector3.ZERO,.22,Color("a9b6a4"),head)
	for side in [-1,1]: _sphere(Vector3(side*.072,.04,-.205),.024,INK,head)
	_ring(Vector3(0,-.055,-.21),.076,.01,INK,head)
	return head


func _cracks(count: int = 12) -> Array:
	var result := []
	for i in count:
		var a := i*TAU/count
		result.append(_rod(Vector3(.03,-.02,.65),Vector3(cos(a)*(.45+i%3*.08),sin(a)*.35,.66),.003,PAPER))
	return result


func _show_cracks(t: float, start: float = .48) -> void:
	for i in p["cracks"].size(): p["cracks"][i].visible = t>start+i*.012


func _build_rollcall_here() -> void:
	_bind_attacker(false)
	if _attacker == null: p["visitor"] = _silhouette("teacher",.24,2)
	p["book"] = _anchor(Vector3(-.28,-.2,1.4))
	_box(Vector3(.38,.5,.025),Vector3.ZERO,COAL,p["book"])
	_box(Vector3(.34,.45,.012),Vector3(0,0,-.02),PAPER,p["book"])
	p["words"] = _text("巡查登记",Vector3(0,.12,-.03),.055,INK,p["book"])
	p["name"] = _text("未到",Vector3(0,-.1,-.03),.06,RUST,p["book"])
	focus = p["book"]


func _show_rollcall_here(t: float) -> void:
	var close := c.ss(t,.2,.8)
	p["book"].position = Vector3(-.28*(1-close*.5),-.2,lerpf(1.4,.5,close))
	p["name"].text = "已到" if t>.72 else "未到"
	if _attacker != null: _approach(t)
	else: p["visitor"].position.z = lerpf(2,.55,close)


func _build_garage_here() -> void:
	_bind_attacker(true)
	if _attacker == null: p["shadow"] = _silhouette("roam",0,2)
	p["eyes"] = []
	for x in [-.045,.045]: p["eyes"].append(_sphere(Vector3(x,.05,1.3),.014,Color("8b9d9b")))
	focus = _anchor(Vector3(0,.05,1))


func _show_garage_here(t: float) -> void:
	var close := c.ss(t,.25,.83)
	if _attacker != null: _approach(t)
	else: p["shadow"].position.z = lerpf(2,.48,close)
	for eye: Node3D in p["eyes"]:
		eye.visible = _attacker==null and t>.28
		eye.position.z = lerpf(1.3,.28,close)
	if _attacker==null: _pose(t,0,.015*sin(t*13)*close,0,0,-5*close)


func _build_backseat_here() -> void:
	p["mirror"] = _anchor(Vector3(.24,.14,.9))
	_box(Vector3(.46,.18,.025),Vector3.ZERO,COAL,p["mirror"])
	_box(Vector3(.41,.14,.01),Vector3(0,0,-.02),Color("667f82"),p["mirror"])
	p["passenger"] = _face_at(.24,.86)
	p["grip"] = c.fxm("hand",.35,0,0,0)
	p["grip"].reparent(root,false)
	focus = p["mirror"]


func _show_backseat_here(t: float) -> void:
	var close := c.ss(t,.3,.82)
	p["passenger"].visible = t>.22
	p["passenger"].scale = Vector3.ONE*(.18+close*.1)
	p["grip"].position = Vector3(.65-close*.32,-.22,.42)
	p["grip"].visible = t>.45
	_pose(t,0,.025*close,0,.025*close,-4*close)


func _build_crash_here() -> void:
	p["cracks"] = _cracks(15)
	p["lamps"] = []
	for x in [-.22,.22]: p["lamps"].append(_sphere(Vector3(x,-.05,2),.06,LIGHT))
	focus = _anchor(Vector3(0,0,.8))


func _show_crash_here(t: float) -> void:
	var hit := c.ss(t,.46,.63)
	for lamp: Node3D in p["lamps"]:
		lamp.position.z = lerpf(2,.7,c.ss(t,.08,.57))
		lamp.visible = t<.7
	_show_cracks(t)
	_pose(t,.035*hit,.025*hit,0,.05*sin(t*23)*hit,4*hit)


func _build_classroom_here() -> void:
	for child in c._world.get_children():
		if child is ClassmatesView:
			for entry: Dictionary in child.figures:
				_classmates.append(_remember(entry["node"]))
	p["writing"] = _text("请回到座位",Vector3(0,.05,1.1),.11)
	focus = p["writing"]


func _show_classroom_here(t: float) -> void:
	var close := c.ss(t,.2,.78)
	for i in _classmates.size():
		var state: Dictionary = _classmates[i]
		var node: Variant = state["node"]
		if not is_instance_valid(node): continue
		if c.fx in ["san","vignette","chalk"]:
			node.visible = state["visible"] and t<.4+(i%5)*.075
		else:
			var target := atan2(node.global_position.x-_eye.origin.x,node.global_position.z-_eye.origin.z)
			node.global_rotation.y += wrapf(target-node.global_rotation.y,-PI,PI)*close
	p["writing"].visible = t>.25
	p["writing"].text = "已归队" if c.fx=="assimilation" and t>.63 else ("你是谁" if c.fx in ["san","vignette","chalk"] else "请回到座位")
	p["writing"].modulate.a = close*.8
	_pose(t,0,0,0,.012*sin(t*9)*close,(-7 if c.fx=="assimilation" else 6)*close)


func _build_assembly_here() -> void:
	for x in [-.65,0,.65]: _silhouette("person",x,2)
	focus = _anchor(Vector3(0,0,1.2))


func _show_assembly_here(t: float) -> void:
	var close := c.ss(t,.23,.83)
	for i in actors.size():
		actors[i].position = Vector3((i-1)*(.65-close*.25),-1.6,2-close*1.2)
		actors[i].rotation.z = .05*sin(t*17+i)*close
	_pose(t,0,0,0,0,-5*close)


func _build_fence_here() -> void:
	p["head"] = _face_at(.65,1.6)
	p["neck"] = _rod(Vector3(.7,-.1,1.8),Vector3(.65,0,1.6),.055,Color("a9b6a4"))
	focus = p["head"]


func _show_fence_here(t: float) -> void:
	var close := c.ss(t,.15,.83)
	var a := Vector3(.7,-.1,1.8)
	var b := Vector3(.65*(1-close),.03,lerpf(1.6,.38,close))
	p["head"].position = b
	p["neck"].position = (a+b)*.5
	p["neck"].scale.y = a.distance_to(b)/.21
	p["neck"].quaternion = Quaternion(Vector3.UP,(b-a).normalized())


func _build_double_here() -> void:
	p["one"] = _silhouette("person",-.25,1.8)
	p["two"] = _silhouette("person",.25,1.8)
	focus = _anchor(Vector3(0,0,1))


func _show_double_here(t: float) -> void:
	var close := c.ss(t,.28,.82)
	p["one"].position.x = -.25*(1-close)
	p["two"].position.x = .25*(1-close)
	p["one"].rotation.z = .08*sin(t*10)
	p["two"].rotation.z = .08*sin((t-.12)*10)
	p["two"].position.z = lerpf(1.8,.45,close)
	p["one"].visible = t<.76


func _build_flood_here() -> void:
	p["water"] = _box(Vector3(2.8,2,.012),Vector3(0,-1.1,.6),Color("427b85"),null,.22)
	for i in 20: pieces.append(_sphere(Vector3.ZERO,.007+i%3*.006,Color("a6cad1")))
	focus = _anchor(Vector3(0,0,.6))


func _show_flood_here(t: float) -> void:
	p["water"].position.y = lerpf(-1.1,.25,c.ss(t,.08,.84))
	for i in pieces.size():
		pieces[i].position = Vector3(sin(i*7)*.5,-.7+fposmod(i*.17+t*1.9,1.5),.35+i%5*.14)
		pieces[i].visible = t>.35
	_pose(t,.025*sin(t*8),0,0,.018*sin(t*7)*c.ss(t,.4,.8))


func _build_frost_here() -> void:
	for i in 30:
		var angle := i*TAU/30
		pieces.append(_rod(Vector3(cos(angle)*.8,sin(angle)*.5,.5),Vector3(cos(angle)*.35,sin(angle)*.2,.5),.004,Color("b8d6d3")))
	focus = _anchor(Vector3(0,0,.5))


func _show_frost_here(t: float) -> void:
	for i in pieces.size():
		pieces[i].visible = t>.12+i*.018
		pieces[i].scale.y = .15+.85*c.ss(t,.2,.84)
	_pose(t,0,0,0,.006*sin(t*49)*c.ss(t,.4,.8),-4*c.ss(t,.3,.8))


func _build_broadcast_here() -> void:
	p["page"] = _anchor(Vector3(0,-.2,1.2))
	_box(Vector3(.6,.43,.01),Vector3.ZERO,PAPER,p["page"])
	p["words"] = _text("请停止阅读",Vector3(0,0,-.015),.065,INK,p["page"])
	p["lamp"] = _sphere(Vector3(.22,.14,-.02),.012,RUST,p["page"])
	focus = p["page"]


func _show_broadcast_here(t: float) -> void:
	p["page"].position.z = lerpf(1.2,.55,c.ss(t,.25,.8))
	p["words"].text = "你正在被记录" if t>.58 else "请停止阅读"
	p["lamp"].visible = int(t*24)%3!=0
	_pose(t,.012*sin(t*27)*c.ss(t,.3,.8))


func _build_bell_here() -> void:
	# Sound and pressure cross the existing room; no substitute bell tower.
	for i in 5: pieces.append(_ring(Vector3(0,0,2),.35+i*.08,.005,PAPER))
	focus = _anchor(Vector3(0,0,1))


func _show_bell_here(t: float) -> void:
	for i in pieces.size():
		var progress := c.ss(t,.18+i*.085,.62+i*.07)
		pieces[i].visible = progress>0 and progress<1
		pieces[i].position.z = lerpf(2,.3,progress)
		pieces[i].scale = Vector3.ONE*(1+progress*.6)
	_pose(t,.01*sin(t*38),0,0,.015*sin(t*38),3*c.ss(t,.45,.8))


func _build_banquet_here() -> void:
	p["plate"] = _ring(Vector3(0,-.22,1.2),.28,.025,PAPER)
	p["mouth"] = _ring(Vector3(0,-.18,1.19),.22,.04,INK)
	focus = p["plate"]


func _show_banquet_here(t: float) -> void:
	var close := c.ss(t,.2,.83)
	p["plate"].position.z = lerpf(1.2,.35,close)
	p["mouth"].position.z = p["plate"].position.z-.01
	p["mouth"].scale = Vector3.ONE*(1+close*.7)
	_pose(t,0,0,0,0,6*close)


func _build_cup_here() -> void:
	p["cup"] = _anchor(Vector3(0,-.3,1.2))
	var model := FallingProps.model("cup",CampusData.tier)
	model.scale = Vector3.ONE*1.4
	c.put(model,0,-.1,0,p["cup"])
	p["lid"] = FallingProps.model("lid",CampusData.tier)
	p["lid"].scale = Vector3.ONE*1.4
	c.put(p["lid"],0,.17,0,p["cup"])
	focus = p["cup"]


func _show_cup_here(t: float) -> void:
	var close := c.ss(t,.2,.84)
	p["cup"].position = Vector3(0,-.3+close*.25,lerpf(1.2,.42,close))
	p["cup"].scale = Vector3.ONE*(1+close*1.8)
	p["cup"].rotation.x = -.7*close
	p["lid"].position = Vector3(-.18*close,.17+.2*close,.1*close)
	p["lid"].rotation.z = close*2.4


func _build_ritual_here() -> void:
	p["sigil"] = _ring(Vector3(0,0,1.5),.24,.014,RUST)
	for i in 5:
		var a := i*TAU/5
		pieces.append(_rod(Vector3(cos(a)*.24,sin(a)*.24,1.5),Vector3(cos(a+TAU*.4)*.24,sin(a+TAU*.4)*.24,1.5),.006,RUST))
	focus = p["sigil"]


func _show_ritual_here(t: float) -> void:
	var close := c.ss(t,.25,.83)
	p["sigil"].position.z = lerpf(1.5,.45,close)
	p["sigil"].rotation.z = t*.4
	for line: Node3D in pieces: line.position.z = p["sigil"].position.z
	_pose(t,0,0,0,0,-4*close)


func _build_corridor_here() -> void:
	p["exit"] = _text("出口",Vector3(0,.15,1.5),.1,Color("9bb6a2"))
	p["slits"] = []
	for side in [-1,1]: p["slits"].append(_box(Vector3(.08,1.2,.025),Vector3(side*.65,0,.55),INK,null,.8))
	focus = p["exit"]


func _show_corridor_here(t: float) -> void:
	var close := c.ss(t,.15,.84)
	var narrow := c.fx in ["wall","squeeze","trap_wall"]
	p["exit"].modulate.a = 1-close
	for i in 2:
		p["slits"][i].visible = narrow
		p["slits"][i].position.x = (-1 if i==0 else 1)*(.65-close*.38)
	_pose(t,0,0,0,.012*sin(t*9)*close,(-4 if narrow else 7)*close)


func _build_face_here() -> void:
	if c.fx=="window_gaze":
		for child in c._world.get_children():
			if child is WindowGazeView and child.is_visible_in_tree(): _gaze = child
	if _gaze == null: p["head"] = _face_at(0,1.8)
	p["breath"] = _sphere(Vector3(.12,-.05,.6),.2,Color("acbcb3"))
	p["breath"].scale = Vector3(1,.6,.025)
	var material := p["breath"].material_override as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = .1
	focus = _anchor(Vector3(0,0,1))


func _show_face_here(t: float) -> void:
	var close := c.ss(t,.2,.82)
	if _gaze == null:
		p["head"].position.z = lerpf(1.8,.4,close)
		p["head"].rotation.z = .18*close
	p["breath"].visible = c.fx=="window_gaze" and t>.4
	p["breath"].scale.x = close*2
	_pose(t,0,.015*sin(t*8)*close,0,0,-3*close)


func _build_mirror_here() -> void:
	p["head"] = _face_at(0,1.6)
	p["cracks"] = _cracks()
	focus = p["head"]


func _show_mirror_here(t: float) -> void:
	p["head"].position.z = lerpf(1.6,.42,c.ss(t,.23,.82))
	p["head"].rotation.z = -.18*c.ss(t,.3,.7)
	_show_cracks(t,.4)


func _build_paper_here() -> void:
	for i in 12:
		var page := _box(Vector3(.15,.22,.003),Vector3.ZERO,PAPER)
		pieces.append(page)
	p["eye"] = _sphere(Vector3(0,0,.72),.045,INK)
	focus = p["eye"]


func _show_paper_here(t: float) -> void:
	var close := c.ss(t,.25,.85)
	for i in pieces.size():
		var a := i*TAU/pieces.size()+t*1.4
		pieces[i].position = Vector3(cos(a)*(.8-close*.4),sin(a)*(.5-close*.24),lerpf(1.8,.4,close))
		pieces[i].rotation = Vector3(.1*sin(a),a*.3,a)
	p["eye"].visible = t>.6


func _build_fall_here() -> void:
	for i in 22: pieces.append(_box(Vector3(.012,.08,.01),Vector3.ZERO,COAL))
	focus = _anchor(Vector3(0,0,.8))


func _show_fall_here(t: float) -> void:
	for i in pieces.size():
		pieces[i].position = Vector3(sin(i*7)*.9,-.7+fposmod(i*.17+t*3,1.4),.4+i%5*.2)
	_pose(t,-.05*c.ss(t,.3,.8),0,0,.035*c.ss(t,.4,.85),7*c.ss(t,.2,.8))


func _build_trash_here() -> void:
	p["lid"] = _anchor(Vector3(0,.35,1))
	_box(Vector3(1,.06,.7),Vector3(0,0,.25),Color("394d43"),p["lid"])
	focus = _anchor(Vector3(0,0,.8))


func _show_trash_here(t: float) -> void:
	var close := c.ss(t,.18,.83)
	p["lid"].rotation.x = lerpf(-1.3,-.1,close)
	p["lid"].position.y = lerpf(.35,.1,close)
	c.cue("lid",t,.72,func() -> void: c.snd("foley.door"))


func _build_door_here() -> void:
	p["visitor"] = _silhouette("person",0,2)
	p["line"] = _box(Vector3(.016,1.1,.012),Vector3(0,0,1.4),RUST)
	focus = _anchor(Vector3(0,0,1))


func _show_door_here(t: float) -> void:
	var enter := c.ss(t,.4,.84)
	p["visitor"].visible = t>.35
	p["visitor"].position.z = lerpf(2,.48,enter)
	p["line"].visible = t<.6
	for i in 3: c.cue("knock"+str(i),t,.12+i*.12,func() -> void: c.snd("foley.door",{"k":.4+i*.12}))


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
