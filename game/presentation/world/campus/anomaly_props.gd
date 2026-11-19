class_name AnomalyProps
extends Node3D
## World props from the original fx/anomaly-fx.js. Visual state and random draws are
## local to this instance; no player pose, anomaly rule or gameplay RNG is mutated.
const KINDS := ["exercise","hand","leak","rite","feast","lamps","chalk","roster","broad","repeat","shifting","cold","raindots","stare","necker","shadow","twin"]
var kind := ""
var time := 0.0
var seed_value: int = 42
var _random: int
var items: Array[Node3D] = []
var _tier := -1
var _writing: AnomalyWriting
var _visage: Node3D
var _shadow_yaw := 0.0


func _rand() -> float:
	_random=(_random*1664525+1013904223)&0xffffffff
	return _random/4294967296.0


static func _mat(hex: String, alpha: float = 1.0) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color=Color(hex)
	m.albedo_color.a=alpha
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if alpha<1 else BaseMaterial3D.TRANSPARENCY_DISABLED
	# Three.js anfxMat writes depth even for its transparent meshes. Opaque objects
	# must also stay in the opaque pass, or a large table sorts over its own food.
	m.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return m


func _mesh(shape: Mesh, mat: Material, p: Vector3) -> MeshInstance3D:
	var n:=MeshInstance3D.new()
	n.rotation_order=EULER_ORDER_XYZ
	n.mesh=shape
	RenderMaterials.set_override(n, mat)
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.position=p
	add_child(n)
	return n


func _box(hex: String, alpha: float, size: Vector3, p: Vector3, tracked: bool = false) -> MeshInstance3D:
	var shape:=BoxMesh.new()
	shape.size=size
	var n:=_mesh(shape,_mat(hex,alpha),p)
	if tracked: items.append(n)
	return n


func _plane(hex: String, alpha: float, size: Vector2, p: Vector3) -> MeshInstance3D:
	var mesh:=QuadMesh.new()
	mesh.size=size
	return _mesh(mesh,_mat(hex,alpha),p)


func _figure(hex: String, p: Vector3, type: String = "tall", size: float = 1.0) -> Node3D:
	var n:=Node3D.new()
	n.rotation_order=EULER_ORDER_XYZ
	var model:=FigureModel.make(type,Color(hex),true,size)
	model.rotation.y=PI # FigureModel adapts to Godot -Z; these original prop groups face +Z.
	n.add_child(model)
	n.position=p
	add_child(n)
	items.append(n)
	return n


## Where a figure's head comes off: [the height (m, the model's own scale) below which its body is kept, the
## middle of a HorrorKit head that replaces the egg-shaped one]. Measured on the exported meshes (the narrowest
## section of the neck, then the old head's centre).
const FIG_NECK := {"tall":[2.28,Vector3(0,2.41,.005)],"neck":[2.68,Vector3(0,2.84,.005)]}


## The same figure as _figure (the same node, transform and registration), but its head is a HorrorKit head:
## the model's own head is cut away (its skin drops everything above the neck) and a matte, sunken-eyed head
## sits on the neck instead. Body and head are dark and matte. opts: HorrorKit.head options; head_size.
func _figure_horror(hex: String, p: Vector3, type: String, size: float, opts: Dictionary, head_size: float = 1.0) -> Node3D:
	var n:=Node3D.new()
	n.rotation_order=EULER_ORDER_XYZ
	var model:=FigureModel.make(type,Color(hex),true,size)
	model.rotation.y=PI # FigureModel adapts to Godot -Z; these original prop groups face +Z.
	var spec: Array=FIG_NECK[type]
	HorrorKit.dress(model,HorrorKit.figure_skin(Color(hex),0.0,float(spec[0])))
	n.add_child(model)
	var tone:="wax"
	var head_opts:={"tone":tone,"mouth":"none","eyes":"hollow","quality":_tier,"socket":.7}
	head_opts.merge(opts,true)
	var head:=HorrorKit.head(head_opts)
	# Matte: the kit's shader with no gloss and only a faint cold edge, so a light picks out the brow and cheek.
	var matte:=HorrorKit.skin(tone,0.0,true).duplicate() as ShaderMaterial
	matte.set_shader_parameter("gloss",0.0)
	matte.set_shader_parameter("rim_emit",0.0)
	matte.set_shader_parameter("rim_strength",.3)
	for mi: Node in head.find_children("*","MeshInstance3D",true,false):
		if mi.name=="Face": RenderMaterials.set_override((mi as MeshInstance3D), matte)
		(mi as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.rotation.y=PI
	head.scale=Vector3.ONE*size*head_size*1.3 # the kit head is a little smaller than the model's own
	head.position=(spec[1] as Vector3)*size
	n.add_child(head)
	_visage=head
	# A white shirt collar at the neck root, so the dark body reads as a school uniform.
	var ring:=TorusMesh.new()
	ring.inner_radius=.055
	ring.outer_radius=.085
	var collar:=MeshInstance3D.new()
	collar.name="Collar"
	collar.mesh=ring
	RenderMaterials.set_override(collar, HorrorKit._cloth(Color("b9b6aa")))
	collar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collar.scale=Vector3(1,.55,1)*size
	collar.position=Vector3(0,float(spec[0])-.02,.005)*size
	if type=="neck":
		# The wrong neck: bare skin (not cloth), thicker at the shoulders and under the jaw, with a ridge for each vertebra;
		# the collar sits where the shoulders end, not under the head.
		collar.position=Vector3(0,2.205,.005)*size
		collar.scale=Vector3(1.35,.7,1.35)*size
		var tube:=MeshInstance3D.new()
		tube.name="BareNeck"
		tube.mesh=_bare_neck_mesh(2.2,float(spec[0])-.05)
		RenderMaterials.set_override(tube, matte)
		tube.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tube.position=Vector3(0,0,.005)*size
		tube.scale=Vector3.ONE*size
		n.add_child(tube)
	n.add_child(collar)
	n.position=p
	add_child(n)
	items.append(n)
	return n


## A long bare neck from y0 to y1 (model metres): a lathe, widest at the base and under the jaw, a ridge per vertebra.
static func _bare_neck_mesh(y0: float, y1: float) -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows:=36
	var seg:=16
	for i in rows:
		for j in seg:
			var pts:=[]
			for corner in [[0,0],[0,1],[1,1],[1,0]]:
				var t:=float(i+corner[0])/rows
				var a:=TAU*float(j+corner[1])/seg
				var r:=lerpf(.082,.07,smoothstep(0.0,.35,t))+.006*smoothstep(.8,1.0,t)+.007*pow(maxf(0.0,sin(t*TAU*7.0)),2.0)
				pts.append(Vector3(cos(a)*r,lerpf(y0,y1,t),sin(a)*r))
			for k in [0,1,2,0,2,3]: st.add_vertex(pts[k])
	st.generate_normals()
	return st.commit()


static func _open_wall(room: Dictionary, tile: Vector2i, dir: Vector2i) -> bool:
	var next := tile+dir
	if mini(mini(tile.x,next.x),mini(tile.y,next.y))<0 or maxi(tile.x,next.x)>=int(room.cols) or maxi(tile.y,next.y)>=int(room.rows): return false
	return String(room.grid[tile.y]).substr(tile.x,1)=="#" and String(room.grid[next.y]).substr(next.x,1)=="."


static func wall_face(room: Variant, feet: Vector3, width: float = .9, reach: float = 12.0) -> Dictionary:
	if room==null: return {}
	var best := INF
	var target := {}
	var player := Vector2(feet.x,feet.z)
	var tile_size := Vector2(room.tw,room.th)*CampusGeometry.U2M
	var furniture: Array[Rect2] = []
	for box: Dictionary in room.get("boxes",[]):
		var footprint := Rect2(box.x0,box.z0,box.x1-box.x0,box.z1-box.z0)
		if footprint.get_center().distance_squared_to(player)<144: furniture.append(footprint)
	var player_world := CampusGeometry.to_world(room,feet.x,feet.z)
	var cell := Vector2i(floori((player_world.x-room.ox)/room.tw),floori((player_world.y-room.oy)/room.th))
	var radius := Vector2i(ceili(reach/tile_size.x)+1,ceili(reach/tile_size.y)+1)
	for row in range(maxi(0,cell.y-radius.y),mini(int(room.rows),cell.y+radius.y+1)):
		for col in range(maxi(0,cell.x-radius.x),mini(int(room.cols),cell.x+radius.x+1)):
			var tile := Vector2i(col,row)
			if String(room.grid[row]).substr(col,1)!="#": continue
			var center := CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,col,row))
			for dir: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if not _open_wall(room,tile,dir): continue
				var point := center + Vector2(dir)*tile_size*.5
				var gap := player-point
				if gap.dot(Vector2(dir))<-.02 or gap.length_squared()>reach*reach or gap.length_squared()>=best: continue
				var tangent := Vector2i(dir.y,-dir.x)
				var tiles_needed := ceili((width/(tile_size.x if dir.y else tile_size.y)-1.0)*.5)
				var score := gap.length_squared()
				for offset in range(1,tiles_needed+1):
					if not _open_wall(room,tile+tangent*offset,dir) or not _open_wall(room,tile-tangent*offset,dir): score+=100.0
				if score>=best: continue
				var side := Vector2(tangent)*(width*.5+.05)
				var clear := Rect2(point-side+Vector2(dir)*.045,Vector2.ZERO).expand(point+side+Vector2(dir)*1.05).abs()
				for obstruction in furniture:
					if clear.intersects(obstruction):
						score+=140.0
						break
				if score>=best: continue
				var reading_spot := point+Vector2(dir)*.15
				if not CampusGeometry.tile_los(room,player_world,CampusGeometry.to_world(room,reading_spot.x,reading_spot.y),col,row,{}): continue
				best=score
				target={"p":Vector3(point.x,0,point.y),"n":Vector3(dir.x,0,dir.y)}
	return target


func _point(room: Variant, point: Dictionary) -> Vector3:
	var p:=CampusGeometry.to_scene(room,Vector2(point["x"],point["y"]))
	return Vector3(p.x,0,p.y)


## Find a nearby clear aisle within the specified half of the room.
static func _aisle_spot(room: Variant, origin: Vector3, direction: Vector2) -> Vector3:
	var here := Vector2(origin.x,origin.z)
	var forward := direction.normalized() if not direction.is_zero_approx() else Vector2.DOWN
	for distance: float in [1.06,1.58,.79,2.05]:
		for angle: float in [0.0,.47,-.47,.94,-.94,1.27,-1.27]:
			var point := here + forward.rotated(angle)*distance
			if room != null:
				var dest := CampusGeometry.to_world(room,point.x,point.y)
				if CampusGeometry.tile_at(room,dest) not in [".","d"]: continue
				if not CampusGeometry.tile_los(room,CampusGeometry.to_world(room,here.x,here.y),dest,-1,-1,{}): continue
				var clear := true
				for box: Dictionary in room.get("boxes",[]):
					if point.x>box.x0-.15 and point.x<box.x1+.15 and point.y>box.z0-.15 and point.y<box.z1+.15:
						clear = false
						break
				if not clear: continue
			return Vector3(point.x,origin.y,point.y)
	return Vector3.INF


func build(id: String, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2, tier: int, student: String = StudentCast.DEFAULT) -> void:
	kind=id
	_tier=tier
	_random=seed_value
	var p:=Vector3(feet.x,0,feet.z)
	if d.has("src"): p=_point(room,d["src"])
	match id:
		"exercise":
			for i in 6:
				var pupil := OtherworldFigure.make("person")
				pupil.position = p+Vector3(-5+i*2,0,.3 if i%2 else -.3)
				pupil.scale = Vector3(.98,1.39,.98)
				add_child(pupil)
				items.append(pupil)
				pupil.exercise_pose(0,i,Vector2(feet.x-pupil.position.x,feet.z-pupil.position.z))
		"hand": _hand(tier,p,feet)
		"leak":
			var pts: Array=d.get("pts",[])
			if pts.is_empty(): pts=[{"x":CampusGeometry.to_world(room,feet.x,feet.z).x,"y":CampusGeometry.to_world(room,feet.x,feet.z).y}]
			for i in 5:
				var at:=_point(room,pts[i%pts.size()])
				var radius:=.9+_rand()*.3
				var vertices:=PackedVector3Array([Vector3.ZERO])
				for j in 13: vertices.append(Vector3(cos(j*TAU/12)*radius,sin(j*TAU/12)*radius,0))
				var indices:=PackedInt32Array()
				for j in 12: indices.append_array([0,j+2,j+1])
				var arrays:=[]
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX]=vertices
				arrays[Mesh.ARRAY_INDEX]=indices
				var circle:=ArrayMesh.new()
				circle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var pool:=_mesh(circle,_mat("1b2428",.85),at+Vector3(0,.012,0))
				pool.rotation.x=-PI/2
				items.append(pool)
			for i in 15:
				var at:=_point(room,pts[i%pts.size()])
				_box("8fa6b0",.55,Vector3(.03,.28,.03),at+Vector3((_rand()-.5)*.6,_rand()*2.6,(_rand()-.5)*.6),true)
			for i in 5: _box("2a2420",.75,Vector3(.9,.01,.6),_point(room,pts[i%pts.size()])+Vector3(0,2.985,0))
		"rite":
			if d.has("c"): p=_point(room,d["c"])
			for i in 44:
				var a:=i/44.0*6.283
				_box("d8d4cc",.95,Vector3(.32,.012,.06),p+Vector3(cos(a)*2.1,.014,sin(a)*2.1),true).rotation.y=-a+PI/2
			for i in 5:
				var a:=i/5.0*6.283-PI/2
				var b:=((i+2)%5)/5.0*6.283-PI/2
				var start:=p+Vector3(cos(a)*2,0,sin(a)*2)
				var end:=p+Vector3(cos(b)*2,0,sin(b)*2)
				_box("d8d4cc",.95,Vector3(start.distance_to(end),.012,.05),(start+end)/2+Vector3(0,.016,0)).rotation.y=-atan2(end.z-start.z,end.x-start.x)
			_box("1a1210",.8,Vector3(.55,.01,1.5),p+Vector3(0,.018,0))
			for i in 4:
				var a:=i/4.0*6.283+.6
				var at:=p+Vector3(cos(a)*1.6,0,sin(a)*1.6)
				_box("f0e8d8",1,Vector3(.08,.22,.08),at+Vector3(0,.11,0))
				_box("e8dcc0",1,Vector3(.05,.10,.05),at+Vector3(0,.28,0),true)
		"feast": _feast(p,room)
		"lamps":
			for i in 16: _box("f4f8ff",1,Vector3(1.5,.06,.22),p+Vector3(-14+i*1.9,2.94,0),true).visible=false
			_box("3a444a",1,Vector3(1.3,.012,1.3),p+Vector3(0,.012,0),true).visible=false
		"chalk","roster":
			var origin := _point(room,{"x":d.rx,"y":d.ry}) if d.has("rx") and d.has("ry") else feet
			var reach := AnomalyModule.ROSTER_REACH*CampusGeometry.U2M-.35 if id=="roster" else 12.0
			var panel := wall_face(room,origin,.90 if id=="roster" else 2.92,reach)
			_writing=AnomalyWriting.new()
			_writing.build(id,d,student)
			if panel.is_empty():
				# In a large open hall the physical page must still be within reach.
				var heading := Vector2.from_angle(d.heading) if d.has("heading") else facing
				var floor_spot := _aisle_spot(room,origin,heading)
				_writing.position = (floor_spot if floor_spot.is_finite() else origin)+Vector3.UP*.045
				_writing.rotation = Vector3(-PI/2,atan2(-heading.x,-heading.y),0)
			else:
				var normal: Vector3 = panel.n
				_writing.position = (panel.p as Vector3)+normal*.16+Vector3.UP*1.55
				_writing.rotation.y = atan2(normal.x,normal.z)
			add_child(_writing)
			items.append(_writing)
		"broad":
			for i in 2:
				var at:=p+Vector3(1.9 if i else -1.9,2.55,0)
				_box("3a4046",1,Vector3(.42,.42,.30),at,true)
				_box("b8c4c8",1.15,Vector3(.26,.26,.06),at+Vector3(0,0,.17),true)
		"repeat":
			var origin := _point(room,{"x":d.rx,"y":d.ry}) if d.has("rx") and d.has("ry") else feet
			var heading := Vector2.from_angle(d.heading) if d.has("heading") else facing
			var spot := _aisle_spot(room,origin,-heading)
			if not spot.is_finite(): return
			var pupil := OtherworldFigure.make("person",null,1)
			pupil.position = spot
			pupil.rotation.y = atan2(spot.x-origin.x,spot.z-origin.z)
			add_child(pupil)
			items.append(pupil)
		"shifting":
			for i in 4: _box("9fb6c8",.75,Vector3(1.4,1.1,.04),p+Vector3(-2.4+i*1.6,1.85,0),true)
		"cold":
			var frost:=_plane("a8c0cc",.30,Vector2(6,6),p+Vector3(0,.05,0))
			frost.rotation.x=-PI/2
			items.append(frost)
		"raindots":
			var ang:=facing.angle()
			var words:=_plane("9fb6c4",0,Vector2(4.2,.95),p+Vector3(cos(ang)*3.2,.02,sin(ang)*3.2))
			words.material_override.albedo_texture=load("res://assets/campus/anomalies/rain-words.png")
			words.material_override.no_depth_test=false
			words.material_override.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
			words.rotation=Vector3(-PI/2,0,-ang-PI/2)
			items.append(words)
		"stare": _gaze(room,feet,facing,tier)
		"necker":
			var x: float=CampusData.campus()["bound_map"]["x1"]*AnomalyModule.SC+16
			var at:=CampusGeometry.to_scene(null,Vector2(x,feet.z/CampusGeometry.U2M))
			_figure_horror("121619",Vector3(at.x,0,at.y),"neck",1.4,{"mouth":"closed","skew":.6},1.15)
		"twin": _figure_horror("141a1d",_point(room,d) if d.has("x") else p,"tall",1.0,{"mouth":"closed","skew":.4})
		"shadow":
			# The painted court and track sit above the collision floor, at different heights.
			var shade := Decal.new()
			shade.texture_albedo = preload("res://assets/campus/anomalies/writing/late-shadow.png")
			shade.size = Vector3(1.08,.56,1.88)
			shade.position.y = .12
			shade.normal_fade = .75
			shade.albedo_mix = .84
			add_child(shade)
			items.append(shade)
			_shadow_yaw=atan2(-facing.x,-facing.y)
			position=feet+Vector3(facing.x,0,facing.y)*.68
			rotation.y=_shadow_yaw


## The hand from under the stall partition: back up, fingers spread and propped on their tips like a pale
## spider, the palm hanging at the old block's centre (0, .16, 0); the fingers reach towards where the player
## stood when it appeared (+z if on the spot). The forearm slopes down at a shallow angle into a deep, black
## split in the floor tiles behind the wrist (a hairline crack runs off from it towards the stall, a few
## tile chips curl up round its rim), so where it goes in is hidden by the floor itself. A little waxen
## self-light keeps it readable in a dark toilet. Its fingers tap in turn with advance(); nothing else moves.
const HAND_SCALE:=1.6
const HAND_PALM:=Vector3(0,.16,0)
const HAND_RISE:=.95      # the forearm's angle out of the floor, rad
const HAND_BEND:=1.2      # the wrist bent down so the fingertips reach the tiles

func _hand(tier: int, p: Vector3, feet: Vector3) -> void:
	var holder:=Node3D.new()
	holder.name="Hand"
	holder.position=HAND_PALM
	var toward:=Vector2(feet.x-p.x,feet.z-p.z)
	if toward.length()>.05: holder.rotation.y=atan2(toward.x,toward.y)
	holder.scale=Vector3.ONE*HAND_SCALE
	var hand:=HorrorKit.hand({"quality":tier,"long":1.32,"thin":.45,"arm":.42,"glow":.3,"tone":Color(.5,.46,.42),"fade":Vector2(.9,1.0)})
	# Back up (no roll), fingers to +z (turn), the forearm sloping down into the floor behind (pitch).
	hand.rotation=Vector3(HAND_RISE,PI,0)
	hand.position=-(hand.basis*Vector3(0,0,-.045))
	holder.add_child(hand)
	# Darker nails than the skin, so the tips read from above.
	var nail_mat:=HorrorKit.skin("nail",.0).duplicate() as ShaderMaterial
	nail_mat.set_shader_parameter("base_color",Color(.3,.26,.24))
	for nail: Node in hand.find_children("Nail","MeshInstance3D",true,false): RenderMaterials.set_override((nail as MeshInstance3D), nail_mat)
	# Where the forearm meets the floor (holder-local, unscaled): along the arm from the wrist.
	var floor_y:=-HAND_PALM.y/HAND_SCALE
	var wrist:=hand.position
	var arm_dir:=hand.basis*Vector3(0,0,1)
	var enter:=wrist+arm_dir*((floor_y-wrist.y)/arm_dir.y)
	var split:=MeshInstance3D.new()
	split.name="FloorSplit"
	split.mesh=_split_mesh()
	RenderMaterials.set_override(split, _split_material())
	split.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	split.position=Vector3(enter.x,floor_y+.004/HAND_SCALE,enter.z)
	holder.add_child(split)
	_split_chips(split)
	# Seen from standing height the arm must not lie along the tiles: it drops steeply into a hole wide enough to read as one.
	split.scale=Vector3(2.6,1,2.0)
	add_child(holder)
	items.append(holder)
	position=p
	_pose_hand()
	_fingertip_shadows(holder,hand,floor_y)


## A short length of uniform sleeve on the forearm where it goes into the floor: a ragged-edged tube a quarter wider than
## the arm (holder-local; 7 cm in the world), so the hand has a size and an owner.
func _hand_sleeve(holder: Node3D, wrist: Vector3, arm_dir: Vector3, reach: float) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n:=16
	var length:=.07/HAND_SCALE
	var w:=.0425*.89
	var h:=.033*.89
	for i in n:
		var a0:=TAU*i/n
		var a1:=TAU*(i+1)/n
		var tear:=func(a: float) -> float: return length*(1.0-.22*absf(sin(a*3.0+.6))-.12*absf(sin(a*7.0)))
		var p:=func(a: float, z: float) -> Vector3: return Vector3(cos(a)*w,sin(a)*h,z)
		var b0:=p.call(a0,0.0) as Vector3
		var b1:=p.call(a1,0.0) as Vector3
		var t0:=p.call(a0,-tear.call(a0)) as Vector3
		var t1:=p.call(a1,-tear.call(a1)) as Vector3
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)
	st.generate_normals()
	var sleeve:=MeshInstance3D.new()
	sleeve.name="Sleeve"
	sleeve.mesh=st.commit()
	var cloth:=HorrorKit._cloth(Color("2a3445")).duplicate() as ShaderMaterial
	cloth.set_shader_parameter("ambient_lift",.9)  # a little self-light, like the hand: a navy sleeve must not drop out in the dark
	RenderMaterials.set_override(sleeve, cloth)
	sleeve.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basis_z:=arm_dir.normalized()
	var x_axis:=Vector3.UP.cross(basis_z).normalized()
	sleeve.transform=Transform3D(Basis(x_axis,basis_z.cross(x_axis),basis_z),wrist+arm_dir*(minf(reach,.46)+.0))
	holder.add_child(sleeve)


## A dark wet patch on the tiles under the hand (a disc about .35 m across, about 60% of the floor's brightness), so the
## pale hand has something dark to stand on when seen from above.
func _hand_stain(holder: Node3D, floor_y: float) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius:=.175/HAND_SCALE
	var n:=24
	st.set_color(Color(.01,.008,.006,.42))
	st.add_vertex(Vector3.ZERO)
	for ring in 2:
		for i in n:
			var a:=TAU*i/n
			var rag:=1.0+.08*sin(a*5.0)+.05*sin(a*9.0+1.0)
			st.set_color(Color(.01,.008,.006,.42) if ring==0 else Color(.01,.008,.006,0))
			st.add_vertex(Vector3(cos(a),0,sin(a))*radius*rag*(.72 if ring==0 else 1.0))
	for i in n:
		var j:=(i+1)%n
		st.add_index(0); st.add_index(1+j); st.add_index(1+i)
		st.add_index(1+i); st.add_index(1+j); st.add_index(1+n+j)
		st.add_index(1+i); st.add_index(1+n+j); st.add_index(1+n+i)
	var stain:=MeshInstance3D.new()
	stain.name="WetStain"
	stain.mesh=st.commit()
	RenderMaterials.set_override(stain, _split_material())
	stain.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stain.position=Vector3(0,floor_y+.008/HAND_SCALE,.05)
	holder.add_child(stain)


## A split in the floor around the arm: an irregular, ragged black hole longer along the arm than across it,
## its rim fading into a soft stain, a thin crack running on from its far end (-z, towards the stall).
## Built once in the arm's frame (x across, z along the arm). The ragged edge and the crack's wander are
## deterministic sines, not random draws.
static func _split_mesh() -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n:=28
	var black:=Color(0,0,0,1)
	var dark:=Color(.02,.015,.01,.95)
	var rings:=[[.12,black],[.7,black],[1.0,dark],[1.4,Color(.02,.015,.01,0)]]
	var shape:=func(a: float, k: float) -> Vector3:
		var rag:=1.0+.18*sin(a*5.0+1.3)+.1*sin(a*11.0+.4)+.06*sin(a*23.0)
		return Vector3(cos(a)*.06*rag*k,0,sin(a)*.13*rag*k)
	var verts:=[]
	for r in rings.size():
		var ring:=[]
		for i in n:
			var a:=TAU*i/n
			st.set_color(rings[r][1])
			st.add_vertex(shape.call(a,float(rings[r][0])))
			ring.append(r*n+i)
		verts.append(ring)
	for i in range(1,n-1):
		st.add_index(0)
		st.add_index(i+1)
		st.add_index(i)
	for r in rings.size()-1:
		for i in n:
			var j:=(i+1)%n
			st.add_index(verts[r][i])
			st.add_index(verts[r][j])
			st.add_index(verts[r+1][j])
			st.add_index(verts[r][i])
			st.add_index(verts[r+1][j])
			st.add_index(verts[r+1][i])
	# The crack: a ribbon .006 wide, .5 long, from the far end of the hole, wandering up to .02 aside.
	var base:=n*rings.size()
	var count:=8
	var start:=-.13*.9
	var centre:=[]
	for i in count:
		var t:=float(i)/(count-1)
		centre.append(Vector3(sin(i*12.9898)*.02*t,0,start-.5*t))
	for i in count:
		var c: Vector3=centre[i]
		var w:=.003*(1.0-.6*float(i)/(count-1))
		st.set_color(Color(0,0,0,.9))
		st.add_vertex(c+Vector3(-w,0,0))
		st.set_color(Color(0,0,0,.9))
		st.add_vertex(c+Vector3(w,0,0))
	for i in count-1:
		var q:=base+i*2
		st.add_index(q)
		st.add_index(q+1)
		st.add_index(q+3)
		st.add_index(q)
		st.add_index(q+3)
		st.add_index(q+2)
	return st.commit()


## A few pieces of floor tile broken up and tilted round the split's rim (children of the split itself).
func _split_chips(split: MeshInstance3D) -> void:
	var shape:=BoxMesh.new()
	shape.size=Vector3(.03,.006,.025)
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("8a8a84")
	mat.roughness=1.0
	for i in 5:
		var a:=TAU*i/5.0+.5
		var chip:=MeshInstance3D.new()
		chip.name="Chip%d"%i
		chip.mesh=shape
		RenderMaterials.set_override(chip, mat)
		chip.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.position=Vector3(cos(a)*.05,.004,sin(a)*.1)
		chip.rotation=Vector3(.2+.1*absf(sin(i*12.9898)),a,.2+.2*absf(sin(i*78.233)))*(1 if i%2 else -1)
		split.add_child(chip)


## A soft dark spot on the tiles under each fingertip, from the pose at rest (the tips that touch barely move).
func _fingertip_shadows(holder: Node3D, hand: Node3D, floor_y: float) -> void:
	var disc:=ArrayMesh.new()
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0,0,0,.6))
	st.add_vertex(Vector3.ZERO)
	for i in 13:
		var a:=TAU*i/12.0
		st.set_color(Color(0,0,0,0))
		st.add_vertex(Vector3(cos(a),0,sin(a))*.014)
	for i in 12:
		st.add_index(0)
		st.add_index(i+2)
		st.add_index(i+1)
	disc=st.commit()
	var joints:=HorrorKit.hand_joints(hand)
	for f in joints.size():
		var tip: Node3D=joints[f][-1]
		var t:=Transform3D()
		var node:=tip
		while node!=hand:
			t=node.transform*t
			node=node.get_parent()
		var at:=(hand.transform*t).origin+(hand.transform*t).basis*Vector3(0,0,-.02)
		var spot:=MeshInstance3D.new()
		spot.name="TipShadow%d"%f
		spot.mesh=disc
		RenderMaterials.set_override(spot, _split_material())
		spot.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spot.position=Vector3(at.x,floor_y+.002/HAND_SCALE,at.z)
		holder.add_child(spot)


static func _split_material() -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo=true
	m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode=BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _pose_hand() -> void:
	var hand: Node3D=items[0].get_child(0)
	var slow:=time*.9
	# Propped on the fingertips like a spider: the knuckles lift a little, the middle joints fold down and the
	# tips point at the tiles. The fingers lift and tap in turn, index first: slow, uneven, never still.
	var wave:=func(lag: float) -> float: return maxf(0.0,sin(slow-lag))
	var claw:=func(mid: float, lag: float) -> Array: return [-.25,mid-.55*wave.call(lag),.7]
	HorrorKit.pose_hand(hand,.25,1.1,[
		[.2,.5+.05*sin(slow*.7)+.04*sin(time*2.3),.4],
		claw.call(1.05,.0),
		claw.call(.85,.45),
		claw.call(1.05,.9),
		claw.call(1.05,1.35)],
		Vector2(HAND_BEND+.06*sin(time*.6),.05*sin(time*.4)))


func _feast(p: Vector3, room: Variant) -> void:
	_box("8a7a5e",1,Vector3(5.2,.08,1.3),p+Vector3(0,.76,0))
	for i in 6: _box("6a5a42",1,Vector3(.10,.74,.10),p+Vector3(-2.4+i*.96,.37,0))
	for i in 8:
		var at:=p+Vector3(-2.1+i*.6,0,0)
		_box("d8d2c4",1.1,Vector3(.30,.05,.30),at+Vector3(0,.83,0),true)
		_box(["8a4a2a","c8a24a","5a7a42"][i%3],1.05,Vector3(.23,.09,.23),at+Vector3(0,.88,0),true)
		_box("e8e2d4",.95,Vector3(.10,.06,.10),at+Vector3(.05,.92,0),true)
	for i in 6: _box("6a5238",1,Vector3(.26,.015,.015),p+Vector3(-2.4+i*.96,.87,.18),true)
	if room==null: return
	var count:=0
	for r in range(2,int(room["rows"])-2,5):
		for c in range(2,int(room["cols"])-2,7):
			if count>=30: break
			var at:=CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,c,r))
			var lantern: Node3D=load("res://assets/campus/fx/lantern.glb").instantiate()
			for mesh: MeshInstance3D in lantern.find_children("*","MeshInstance3D",true,false):
				mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lantern.position=Vector3(at.x,0,at.y)
			add_child(lantern)
			count+=1
	for i in 4:
		var z: float=(1 if i%2 else -1)*room["rows"]*room["th"]*CampusGeometry.U2M*.22
		_box("b02a22",1,Vector3(room["cols"]*room["tw"]*CampusGeometry.U2M*.9,.02,.34),Vector3(0,2.86,z))
	count=0
	for r in range(1,int(room["rows"])-1):
		for c in range(1,int(room["cols"])-1):
			if count>=26 or String(room["grid"][r]).substr(c,1)!="R": continue
			var at:=CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,c,r))
			_box("d8d2c4",1.1,Vector3(.34,.04,.34),Vector3(at.x,.80,at.y))
			_box(["8a4a2a","c8a24a","5a7a42","d8d2c4","a8503a"][count%5],1.05,Vector3(.26,.10,.26),Vector3(at.x,.86,at.y))
			if count%3==0: _box("e8e2d4",.95,Vector3(.12,.14,.12),Vector3(at.x+.30,.86,at.y))
			count+=1


func _eye(size: float) -> MeshInstance3D:
	var color:="red" if _rand()<.4 else "gold"
	var eye := GazeEye.make(size,color)
	add_child(eye)
	items.append(eye)
	return eye


func _gaze(room: Variant, feet: Vector3, facing: Vector2, tier: int) -> void:
	var spots:=[]
	if room!=null:
		for r in int(room["rows"]):
			for c in int(room["cols"]):
				if String(room["grid"][r]).substr(c,1)!="#": continue
				for dir: Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					var n:=Vector2i(c,r)+dir
					if n.x<0 or n.y<0 or n.x>=room["cols"] or n.y>=room["rows"] or String(room["grid"][n.y]).substr(n.x,1)=="#": continue
					var at:=CampusGeometry.tile_center(room,c,r)+Vector2(dir)*Vector2(room["tw"],room["th"])*.5
					var s:=CampusGeometry.to_scene(room,at)
					var distance:=s.distance_to(Vector2(feet.x,feet.z))
					if distance<=12 and distance>=2.4: spots.append({"p":s,"n":Vector2(dir)})
	for i in range(spots.size()-1,0,-1):
		var j:=floori(_rand()*(i+1))
		var old: Dictionary=spots[i]
		spots[i]=spots[j]
		spots[j]=old
	for s: Dictionary in spots.slice(0,[14,24,24,36,44][clampi(tier,0,4)]):
		var eye:=_eye(.8+_rand()*.9)
		var side:=(_rand()-.5)*.8*CampusGeometry.TTILE*CampusGeometry.U2M
		var normal: Vector2=s["n"]
		var at: Vector2=s["p"]+normal*.12+Vector2(side if normal.y else 0,side if normal.x else 0)
		eye.position=Vector3(at.x,.9+_rand()*1.9,at.y)
		eye.set_meta("eye",{"d":.2+_rand()*1.4,"w":eye.scale.x,"ph":_rand()*6.283})
	for i in [4,8,8,12,14][clampi(tier,0,4)]:
		var a:=facing.angle()+(_rand()-.5)*1.9
		var distance:=2.6+_rand()*3.2
		var eye:=_eye(.6+_rand()*.7)
		eye.position=Vector3(feet.x+cos(a)*distance,1.7+_rand(),feet.z+sin(a)*distance)
		eye.set_meta("eye",{"d":.5+_rand()*1.5,"w":eye.scale.x,"ph":_rand()*6.283})


func advance(dt: float, d: Dictionary, room: Variant, feet: Vector3, acc: float = 0, facing: Vector2 = Vector2.ZERO, event_time: float = -1.0) -> void:
	time = event_time if event_time>=0 and kind in ["exercise","chalk","roster","shadow","repeat","necker","twin"] else time+maxf(0,dt)
	match kind:
		"exercise":
			for i in items.size():
				var pupil := items[i] as OtherworldFigure
				pupil.exercise_pose(time,i,Vector2(feet.x-pupil.position.x,feet.z-pupil.position.z))
		"leak":
			for i in range(5,items.size()):
				items[i].position.y-=dt*4.6
				if items[i].position.y<-.4: items[i].position.y+=2.6
		"lamps":
			var lit:=floori(fmod(time*2.6,20))
			for i in items.size(): items[i].visible=i<=lit
		"chalk","roster":
			if _writing != null: _writing.write_at(time)
		"shifting":
			for i in items.size(): items[i].position.x+=sin(time*.5+i)*dt*.5
		"broad":
			var pulse:=.6+.4*absf(sin(time*6))
			for i in range(1,items.size(),2): items[i].scale=Vector3.ONE*(.8+pulse*.3)
		"stare":
			var hold:=clampf(acc/1.8,0,1)
			var hit:=1.0 if d.get("hit",false) else 0.0
			for eye: MeshInstance3D in items:
				var data: Dictionary=eye.get_meta("eye")
				var aperture:=clampf((time-data["d"])/.6,0,1)
				var lid:=.30+.70*maxf(hold,hit)
				var pulse:=1+.05*sin(time*3.1+data["ph"])+.25*hit
				eye.scale=Vector3(data["w"]*pulse,data["w"]*.6875*lid*aperture*pulse,1)
				eye.material_override.albedo_color.a=aperture*(.75+.25*maxf(hold,hit))
		"shadow":
			if not facing.is_zero_approx(): _shadow_yaw=atan2(-facing.x,-facing.y)
			var dir:=Vector2(-sin(_shadow_yaw),-cos(_shadow_yaw))
			var target:=Vector2(feet.x,feet.z)+dir*lerpf(.68,.22,clampf(acc/10,0,1))
			var at:=Vector2(position.x,position.z)
			at = target if at.distance_squared_to(target)>16 else at.lerp(target,1.0-exp(-dt*3.4))
			position=Vector3(at.x,feet.y,at.y)
			var reach:=smoothstep(5.0,8.0,time)*(1.0-smoothstep(9.0,12.0,time))
			rotation.y=lerp_angle(rotation.y,_shadow_yaw+.30*reach,1.0-exp(-dt*3.0))
		"repeat":
			if items.is_empty(): return
			var pupil := items[0] as OtherworldFigure
			var away := pupil.position-feet
			var yaw := wrapf(atan2(away.x,away.z)-pupil.rotation.y,-PI,PI)
			pupil.face.rotation=Vector3(-.17*sin(time*1.7),clampf(yaw,-.95,.95)*smoothstep(.5,1.4,time),.16)
		"hand": _pose_hand()
		"twin":
			if d.has("x"):
				items[0].position=_point(room,d)
				items[0].rotation.y=atan2(feet.x-items[0].position.x,feet.z-items[0].position.z)
			_visage.rotation=Vector3(-.23,PI+.22*sin(time*.72),.12)
		"necker":
			items[0].position.z+=(feet.z-items[0].position.z)*minf(1,dt*.9)
			items[0].rotation.y=atan2(feet.x-items[0].position.x,feet.z-items[0].position.z)
			items[0].rotation.z=sin(time*1.3)*.05
			_visage.rotation.z=-.18-.12*sin(time*.75)
		"raindots": items[0].material_override.albedo_color.a=minf(.85,time*.12)
		"rite":
			for i in range(44,items.size()): items[i].scale.y=.8+.4*absf(sin(time*7+i))
