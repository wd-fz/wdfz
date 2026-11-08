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
	n.material_override=mat
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


static func wall_face(room: Variant, feet: Vector3) -> Dictionary:
	if room==null: return {}
	var world:=CampusGeometry.to_world(room,feet.x,feet.z)
	var c0:=floori((world.x-room["ox"])/room["tw"])
	var r0:=floori((world.y-room["oy"])/room["th"])
	var best:=Vector2i(-1,-1)
	var distance:=2147483647
	for r in int(room["rows"]):
		for c in int(room["cols"]):
			if String(room["grid"][r]).substr(c,1)!="#": continue
			var d:=absi(r-r0)+absi(c-c0)
			if d<distance:
				distance=d
				best=Vector2i(c,r)
	if best.x<0: return {}
	var normal:=Vector2.ZERO
	if best.y!=r0: normal.y=1 if r0>best.y else -1
	elif best.x!=c0: normal.x=1 if c0>best.x else -1
	else: normal.y=1
	var at:=CampusGeometry.tile_center(room,best.x,best.y)+normal*Vector2(room["tw"],room["th"])*.5
	var point:=CampusGeometry.to_scene(room,at)
	return {"p":Vector3(point.x,0,point.y),"n":Vector3(normal.x,0,normal.y)}


func _point(room: Variant, point: Dictionary) -> Vector3:
	var p:=CampusGeometry.to_scene(room,Vector2(point["x"],point["y"]))
	return Vector3(p.x,0,p.y)


func build(id: String, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2, tier: int) -> void:
	kind=id
	_random=seed_value
	var p:=Vector3(feet.x,0,feet.z)
	if d.has("src"): p=_point(room,d["src"])
	match id:
		"exercise":
			for i in 6:
				var f:=_figure("1b2226",p+Vector3(-5+i*2,0,.3 if i%2 else -.3))
				f.rotation=Vector3(-.25,PI,0)
		"hand":
			_box("6a5a52",1,Vector3(.34,.05,.26),Vector3(0,.16,0))
			for i in 4: _box("6a5a52",1,Vector3(.055,.05,.22),Vector3(-.12+i*.08,.16,.22))
			position=p
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
			var face:=wall_face(room,feet)
			var at: Vector3=face.get("p",p)
			var normal: Vector3=face.get("n",Vector3.ZERO)
			var side:=normal.x!=0
			if id=="chalk":
				_box("171c20",1,Vector3(.035 if side else 4.2,1.02,4.2 if side else .035),at+normal*.19+Vector3(0,1.58,0),true)
				for i in 5:
					var width:=1.4+i*.42
					_box("e6e8e2",.92,Vector3(.03 if side else width,.055,width if side else .03),at+normal*.22+Vector3(0,2-i*.13,0),true)
			else:
				_box("d6d2c8",1,Vector3(.045 if side else 1.1,1.5,1.1 if side else .045),at+Vector3(0,1.55,0),true)
				for i in 9: _box("4a4a46",1,Vector3(.02 if side else .82,.035,.82 if side else .02),at+normal*.035+Vector3(0,1.95-i*.15,0),true)
		"broad":
			for i in 2:
				var at:=p+Vector3(1.9 if i else -1.9,2.55,0)
				_box("3a4046",1,Vector3(.42,.42,.30),at,true)
				_box("b8c4c8",1.15,Vector3(.26,.26,.06),at+Vector3(0,0,.17),true)
		"repeat": _figure("1a2024",p)
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
			_figure("121619",Vector3(at.x,0,at.y),"neck",1.4)
		"twin": _figure("141a1d",_point(room,d) if d.has("x") else p)
		"shadow":
			var shade:=_plane("05070a",.72,Vector2(.9,1.6),p+Vector3(0,.02,0))
			shade.rotation.x=-PI/2
			items.append(shade)


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
	var eye:=_plane("ffffff",0,Vector2.ONE,Vector3.ZERO)
	var color:="red" if _rand()<.4 else "gold"
	eye.material_override.albedo_texture=load("res://assets/campus/anomalies/eye-"+color+".png")
	eye.material_override.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	eye.material_override.no_depth_test=true
	eye.material_override.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	eye.material_override.disable_fog=true
	eye.material_override.render_priority=5
	eye.scale=Vector3(size,size*.6875,1)
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


func advance(dt: float, d: Dictionary, room: Variant, feet: Vector3, acc: float = 0) -> void:
	time+=maxf(0,dt)
	match kind:
		"exercise":
			for i in items.size(): items[i].rotation.x=-.25+sin(time*2.2+i)*.35
		"leak":
			for i in range(5,items.size()):
				items[i].position.y-=dt*4.6
				if items[i].position.y<-.4: items[i].position.y+=2.6
		"lamps":
			var lit:=floori(fmod(time*2.6,20))
			for i in items.size(): items[i].visible=i<=lit
		"chalk":
			for i in range(1,items.size()):
				items[i].position.y-=dt*.08
				if items[i].position.y<.9: items[i].position.y=2.05
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
		"shadow": position=Vector3(feet.x+.35,0,feet.z+.5)
		"twin":
			if d.has("x"):
				items[0].position=_point(room,d)
				items[0].rotation.y=atan2(feet.x-items[0].position.x,feet.z-items[0].position.z)
		"necker":
			items[0].position.z+=(feet.z-items[0].position.z)*minf(1,dt*.9)
			items[0].rotation.y=atan2(feet.x-items[0].position.x,feet.z-items[0].position.z)
			items[0].rotation.z=sin(time*1.3)*.05
		"raindots": items[0].material_override.albedo_color.a=minf(.85,time*.12)
		"rite":
			for i in range(44,items.size()): items[i].scale.y=.8+.4*absf(sin(time*7+i))
