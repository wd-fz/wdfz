class_name FallingProps
extends Node3D
## Original fx/cup.js and fx/cola.js animation. Owns only presentation state;
## AN.data remains the sole source of the warning/fall/impact phases and times.
var kind:=""
var body: Node3D
var attached_lid: Node3D
var lid_wrap: Node3D
var lid: Node3D
var ring: MeshInstance3D
var core: MeshInstance3D
var pool: MeshInstance3D
var particles: Array[MeshInstance3D]=[]
var ground_height: Callable
var _random: int=42
var _sill:=Vector3.ZERO
var _ground:=NAN
var _landed:=false
var _angle:=0.0
var _spin:=0.0


func _rand() -> float:
	_random=(_random*1664525+1013904223)&0xffffffff
	return _random/4294967296.0


func _node(parent: Node3D) -> Node3D:
	var n:=Node3D.new()
	n.rotation_order=EULER_ORDER_XYZ
	parent.add_child(n)
	return n


static func model(id: String, tier: int) -> Node3D:
	var object: Node3D=(load("res://assets/campus/anomalies/falling/q%d/%s.glb" % [clampi(tier,0,4),id]) as PackedScene).instantiate()
	for mesh: MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return object


func _mat(hex: String, alpha: float) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color=Color(hex)
	m.albedo_color.a=alpha
	if alpha<1:
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _mesh(shape: Mesh, mat: Material) -> MeshInstance3D:
	var n:=MeshInstance3D.new()
	n.mesh=shape
	n.material_override=mat
	n.rotation_order=EULER_ORDER_XYZ
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.hide()
	add_child(n)
	return n


func _circle(hex: String, inner: float = 0.0, segments: int = 24) -> MeshInstance3D:
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	if inner==0:
		vertices.append(Vector3.ZERO)
		for i in segments+1: vertices.append(Vector3(cos(i*TAU/segments),0,sin(i*TAU/segments)))
		for i in segments: indices.append_array([0,i+1,i+2])
	else:
		for i in segments+1:
			var v:=Vector3(cos(i*TAU/segments),0,sin(i*TAU/segments))
			vertices.append(v)
			vertices.append(v*inner)
		for i in segments: indices.append_array([i*2,i*2+2,i*2+1,i*2+1,i*2+2,i*2+3])
	var normals:=PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var shape:=ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var m:=_mat(hex,0)
	m.render_priority=2
	return _mesh(shape,m)


func _point(room: Variant, x: float, y: float) -> Vector3:
	var p:=CampusGeometry.to_scene(room,Vector2(x,y))
	return Vector3(p.x,0,p.y)


func _height(p: Vector3) -> float:
	return float(ground_height.call(p.x,p.z)) if ground_height.is_valid() else 0.0


func build(id: String, d: Dictionary, room: Variant, feet: Vector3, t: float, tier: int, seed_value: int = 42) -> void:
	kind=id
	_random=seed_value
	if kind=="cup" and (d.get("wall",{}) as Dictionary).is_empty(): return
	body=_node(self)
	body.add_child(model(kind,tier))
	if kind=="cup":
		var wall: Dictionary=d["wall"]
		var wall_point:=_point(room,float(wall["x"])*AnomalyModule.SC,float(wall["y"])*AnomalyModule.SC)
		var normal:=Vector3(float(wall.get("nx",0)),0,float(wall.get("ny",0)))
		if not wall.has("nx") or not wall.has("ny"):
			# Early Godot saves omitted the outward normal. Recover it from the
			# locked landing point (or the warning position), without editing the save.
			var from:=_point(room,float(d["lx"]),float(d["ly"])) if d.has("lx") and d.has("ly") else feet
			normal=Vector3(from.x-wall_point.x,0,from.z-wall_point.z).normalized()
		_sill=wall_point+normal*.2
		body.scale=Vector3.ONE*2.2
		body.position=_sill+Vector3(0,AnomalyModule.CUP_H+.02,0)
		attached_lid=model("lid",tier)
		attached_lid.position.y=.166
		body.add_child(attached_lid)
		ring=_circle("000000")
		core=_circle("000000")
		ring.scale=Vector3(AnomalyModule.CUP_R,1,AnomalyModule.CUP_R)
		lid_wrap=_node(self)
		lid=_node(lid_wrap)
		lid.add_child(model("lid",tier))
		lid.scale=Vector3.ONE*2.2
		lid.rotation.z=PI/2
		lid_wrap.hide()
		var chip:=BoxMesh.new()
		chip.size=Vector3(.03,.006,.02)
		for i in 7:
			var n:=_mesh(chip,_mat("d6d4cf" if i%2==0 else "8d90cf",1))
			var angle:=i/7.0*TAU+_rand()*.6
			n.set_meta("velocity",{"vx":cos(angle)*(1.2+_rand()*1.6),"vz":sin(angle)*(1.2+_rand()*1.6),"vy":1.2+_rand()*1.6})
			particles.append(n)
	else:
		body.scale=Vector3.ONE*2.4
		ring=_circle("e6d8bf",.9,32)
		core=_circle("000000")
		pool=_circle("2a1206")
		ring.scale=Vector3(AnomalyModule.COLA_R,1,AnomalyModule.COLA_R)
		var source:=model("foam",tier)
		var foam: Mesh=(source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D).mesh
		source.free()
		var mat:=_mat("e8dcc6",.9)
		for i in 10:
			var n:=_mesh(foam,mat)
			var angle:=i/10.0*TAU+_rand()*.5
			var speed:=.8+_rand()*1.4
			n.set_meta("velocity",{"vx":cos(angle)*speed,"vz":sin(angle)*speed,"vy":1.4+_rand()*1.8,"s":.6+_rand()*.8})
			particles.append(n)
		_spin=_rand()*TAU
		advance(0,t,d,room,feet) # The original cola spawn updates immediately, including on load.


func advance(dt: float, t: float, d: Dictionary, room: Variant, feet: Vector3) -> void:
	if body==null: return
	var phase:=int(d.get("phase",0))
	if phase==0:
		if kind=="cup":
			var wob:=float(d.get("wob",1))
			var k:=clampf(t/(wob if wob!=0 else 1),0,1)
			body.rotation.z=sin(t*26)*.18*k
			body.rotation.x=sin(t*19)*.1*k
			body.position=_sill+Vector3(0,AnomalyModule.CUP_H+.02+absf(sin(t*26))*.02*k,0)
		else:
			var warn:=float(d.get("warn",AnomalyModule.COLA_WARN))
			var k:=clampf(t/(warn if warn!=0 else AnomalyModule.COLA_WARN),0,1)
			ring.show()
			ring.position=Vector3(feet.x,_height(feet)+.035,feet.z)
			ring.material_override.albedo_color.a=.08+.22*k
			_spin+=dt*3
			body.position=Vector3(feet.x+cos(_spin)*.6,AnomalyModule.COLA_H+.6,feet.z+sin(_spin)*.6)
			body.rotation=Vector3(sin(t*7)*.6,_spin,PI/2)
		return
	var land:=_point(room,float(d.get("lx",0)),float(d.get("ly",0)))
	if is_nan(_ground): _ground=_height(land)
	ring.position=land+Vector3(0,_ground+(.012 if kind=="cup" else .035),0)
	core.position=land+Vector3(0,_ground+(.013 if kind=="cup" else .03),0)
	if phase==1:
		var height:=AnomalyModule.CUP_H if kind=="cup" else AnomalyModule.COLA_H
		var u:=clampf((t-float(d.get("tf",t)))/sqrt(2*height/9.8),0,1)
		body.position=(_sill.lerp(land,u) if kind=="cup" else land)+Vector3(0,_ground+(height-_ground)*(1-u*u)+(.02 if kind=="cup" else .05),0)
		body.rotation.x+=dt*(9 if kind=="cup" else 11)
		body.rotation.z+=dt*(5 if kind=="cup" else 4)
		ring.show()
		core.show()
		ring.material_override.albedo_color.a=.30+.30*u if kind=="cup" else .35+.4*u
		var radius:=AnomalyModule.CUP_R*(.25+.6*u) if kind=="cup" else AnomalyModule.COLA_R*(.2+.65*u)
		core.scale=Vector3(radius,1,radius)
		core.material_override.albedo_color.a=.40+.50*u*u if kind=="cup" else .35+.55*u*u
		return
	var tl:=float(d.get("tl",t))
	var elapsed:=t-(tl if kind=="cup" or tl!=0 else t)
	if not _landed:
		_landed=true
		var turn:=_rand()*TAU
		body.rotation=Vector3(0,turn,PI/2)
		body.scale=Vector3(2.2,2.2,1.7) if kind=="cup" else Vector3(2.4*.62,2.4*1.05,2.4)
		_angle=_rand()*TAU if kind=="cup" else turn
		if kind=="cup":
			attached_lid.hide()
			lid_wrap.show()
			lid_wrap.rotation.y=atan2(cos(_angle),sin(_angle))
		else:
			pool.show()
			pool.position=land+Vector3(0,_ground+.011,0)
		for n in particles:
			n.show()
			n.position=land+Vector3(0,_ground+(.05 if kind=="cup" else .08),0)
			if kind=="cola": n.scale=Vector3.ONE*float(n.get_meta("velocity")["s"])
	if kind=="cup":
		var bounce:=maxf(0,sin(minf(elapsed,.35)/.35*PI))*.18*(1-minf(1,elapsed/.35))
		body.position=land+Vector3(0,_ground+.07+bounce,0)
		var roll:=minf(elapsed,1.2)*.9
		lid_wrap.position=land+Vector3(cos(_angle)*roll,_ground+.0462*2.2,sin(_angle)*roll)
		lid.rotation.x+=dt*(8 if elapsed<1.2 else 0)
	else:
		var roll:=minf(elapsed,1.4)*.75*(1-minf(elapsed,1.4)/2.8)
		body.position=land+Vector3(cos(_angle)*roll,_ground+.06,sin(_angle)*roll)
		body.rotation.x+=dt*(6 if elapsed<1.4 else 0)
		var radius:=.4+minf(elapsed,1.2)*.9
		pool.scale=Vector3(radius,1,radius*.8)
		pool.material_override.albedo_color.a=minf(.7,elapsed*1.4)
	for n in particles:
		var v: Dictionary=n.get_meta("velocity")
		var floor_y:=_ground+(.012 if kind=="cup" else .02)
		if n.position.y>floor_y or v["vy"]>0:
			v["vy"]-=9.8*dt
			n.position+=Vector3(v["vx"]*dt,0,v["vz"]*dt)
			var next_y: float=n.position.y+v["vy"]*dt
			n.position.y=maxf(floor_y,next_y)
			# Compare before Vector3's float32 rounding, or a settled fragment can
			# remain a fraction above the floor and keep sliding on every update.
			if next_y<=floor_y:
				v["vx"]=0.0
				v["vz"]=0.0
				v["vy"]=0.0
		if kind=="cola": n.scale=Vector3.ONE*v["s"]*maxf(.15,1-elapsed/2.6)
	ring.material_override.albedo_color.a=maxf(0,.4-elapsed*.5) if kind=="cup" else maxf(0,.45-elapsed*.6)
	core.material_override.albedo_color.a=maxf(0,.75-elapsed*.8) if kind=="cup" else maxf(0,.8-elapsed*.9)
