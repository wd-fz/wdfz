class_name MazeDeath
extends RefCounted
## void-maze/maze-death.js. Times are real seconds within the original 3.6 s scenes.

const GEOMETRY := "res://assets/campus/maze_death_geometry.json"

const DOORS := [["f",0,-1,1.05,.95],["b",0,-1,-1,3.12],["r",-1.6,1.22,-1,2.2],["r",-5.3,1.4,-1,2.35],
	["r",3.3,1.3,-1,2.5],["l",-3.1,1.55,-1,2.65],["l",-6.7,1.65,-1,2.8],["l",2.4,1.75,-1,2.95]]
const PARTS := [[1.26,2.26,.06,1.13,.03],[1.12,2.16,.02,1.08,.07],[.96,2.06,.04,1.08,.10]]
const PASSES := [[.88,1.32,1.1,9.0,1.9,.25,false],[1.33,1.77,1.55,9.0,1.9,.25,false],[2.05,2.42,2.45,9.0,0,.95,true]]


## lit: the baked vertex colours take light and shade (the exported meshes carry normals); false keeps them flat.
static func original_mesh(c: DeathStage, key: String, parent: Node3D = null, lit: bool = true) -> MeshInstance3D:
	var material := c._mat_lit(Color.WHITE) if lit else c._mat(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	return c.mesh(DeathGeometry.mesh(key,GEOMETRY),material,0,0,0,parent)


static func build_lost(c: DeathStage) -> void:
	c.hide_world(Color.BLACK)
	c.d["hall"] = original_mesh(c,"hall")
	# Darkness with a cold light that walks with the camera: the corridor has near and far, its end sinks into black.
	c.stage_dark(Color.BLACK,.09,Color(.18,.18,.19),.2)
	c.d["lamp"] = c.motive_light(Vector3.ZERO,Color("cfd8dc"),1.2,7.0)
	c.d["doors"] = []
	for j in 3:
		var part: Array = PARTS[j]
		var shape := BoxMesh.new()
		shape.size = Vector3(part[0],part[1],part[2])
		var material := c._mat([Color("#4a4c4b"),Color("#8fd0ff"),Color("#111417")][j])
		c.d["doors"].append(c.inst(shape,material,DOORS.size()))
	c.veil(Color.BLACK)


static func update_lost(c: DeathStage, t: float) -> void:
	var walk := -.6*c.ss(t,0,.55)
	var narrow := 1-.16*c.ss(t,2,3.2)
	c.d["hall"].position.z = walk
	c.d["hall"].scale.x = narrow
	for i in 8:
		var d: Array = DOORS[i]
		var opened := (1-c.ss(t,d[3],d[3]+.3) if float(d[3]) > 0 else 1.0) if float(d[2]) < 0 else c.ss(t,d[2],d[2]+.3)
		var lit := opened >= .6 and t < float(d[4]) and (float(d[2]) < 0 or t >= float(d[2])+.32)
		if d[0] == "f" and ((t >= .62 and t < .68) or (t >= .8 and t < .85)):
			lit = false
		if d[0] == "b" and t >= 3.0 and t < 3.04:
			lit = false
		var a := PI if d[0] == "f" else (0.0 if d[0] == "b" else (-PI/2 if d[0] == "l" else PI/2))
		var x := 1.3*narrow if d[0] == "l" else (-1.3*narrow if d[0] == "r" else 0.0)
		var z := (9.0 if d[0] == "f" else (-9.0 if d[0] == "b" else float(d[1])))+walk
		for j in 3:
			var part: Array = PARTS[j]
			var sx := opened if opened>=.02 and (j!=1 or lit) else 0.0
			c.set_i(c.d["doors"][j],i,Vector3(x+float(part[4])*sin(a),part[3],z+float(part[4])*cos(a)),Vector3(0,a,0),Vector3(sx,1 if sx else 0,1 if sx else 0))
	var look := .25*sin(maxf(0,t-1.95)*2.4)*c.ss(t,1.95,2.3)*(1-c.ss(t,2.85,3.2))
	c.view(t,PI*c.ss(t,1.1,1.85)+look,-.04+.16*c.ss(t,2.1,2.8),-.8*c.ss(t,1.95,2.7)+.015*sin(t*3.1)*c.shk)
	c.shade(.12+.3*c.ss(t,2,3)+.55*c.ss(t,3.1,3.45))
	# The camera's light, placed after the view is set so it is a pure function of t.
	(c.d["lamp"] as Node3D).global_position = c.cam.global_position + c.cam.global_basis * Vector3(0,.2,-.6)


static func fall_distance(t: float) -> float:
	return 6*t+2.6*t*t


static func fall_pitch(t: float) -> float:
	return 1.15-1.25*DeathStage.ss(t,.7,1.15)-1.22*DeathStage.ss(t,1.95,2.4)


static func fall_yaw(t: float) -> float:
	return .6*DeathStage.ss(t,.7,1.4)-.35*DeathStage.ss(t,1.95,2.5)


static func build_fall(c: DeathStage) -> void:
	c.hide_world(Color.BLACK)
	c.d["ledge"] = original_mesh(c,"ledge")
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	c.stage_dark(Color.BLACK,.02,Color(.22,.22,.23),.25)
	c.d["rubble"] = c.inst(bm,c._mat_lit(Color("#cfcdc6")),36)
	c.d["bits"] = []
	for i in 36:
		c.d["bits"].append([c._original_random()*6.283,2+c._original_random()*5.5,.15+c._original_random()*.5,c._original_random()*36,.65+c._original_random()*.35,(c._original_random()-.5)*3,c._original_random()*6.283])
	c.d["mark"] = original_mesh(c,"mark",null,false)
	c.d["mark"].hide()
	var pad := Node3D.new()
	c.put(pad,0,0,1.2)
	var slab := c.box(4.8,.3,4.8,Color("#8f9294"),-1,0,-.15,0,false)
	slab.material_override = c._mat_lit(Color("#8f9294"),-1,false,.9,false)
	slab.reparent(pad,false)
	var hatch := original_mesh(c,"hatch",pad)
	var man := c.fig("person",Color("#0b0d10"),1,.2,.1)
	man.reparent(pad,false)
	var beam := Node3D.new()
	c.put(beam,.45,1.12,.2,pad)
	var cone := c.mesh(DeathGeometry.mesh("cone",GEOMETRY),c._mat(Color("#f4f8fa"),.22,false,false,false),0,0,0,beam)
	var lens := c.mesh(DeathGeometry.mesh("lens",GEOMETRY),c._mat(Color.WHITE,-1,false,false,false),0,0,.01,beam)
	# A cold light from above on the pad: the tile has a lit face and a dark one.
	c.motive_light(Vector3(.2,2.6,0),Color("cfd8dc"),1.6,6.0,pad)
	c.d.merge({"pad":pad,"man":man,"beam":beam,"slab":slab,"hatch":hatch,"cone":cone,"lens":lens})
	c.veil(Color.BLACK)


static func update_fall(c: DeathStage, t: float) -> void:
	var distance := fall_distance(minf(t,3.05))
	c.view(t,fall_yaw(t),fall_pitch(t)+.04*sin(t*23)*c.seg(t,.7,1.9)*c.shk,0)
	var eye := c.cam_y()
	c.d["ledge"].position.y = eye+2.2+distance
	for i in 36:
		var b: Array = c.d["bits"][i]
		var y := fposmod(float(b[3])+distance*float(b[4]),36)-18
		c.set_i(c.d["rubble"],i,Vector3(cos(b[0])*b[1],eye+y,sin(b[0])*b[1]),Vector3(b[6]+t*b[5],b[0],b[6]*.5+t*b[5]*.6),Vector3.ONE*float(b[2]))
	var mark: MeshInstance3D = c.d["mark"]
	mark.hide()
	for p: Array in PASSES:
		if t < float(p[0]) or t >= float(p[1]):
			continue
		mark.show()
		var a := fall_yaw(p[2])
		var pitch := fall_pitch(p[2])
		var u := (float(p[2])-t)*float(p[3])
		mark.position = Vector3(-sin(a)*p[4]+cos(a)*p[5],eye+(t-p[2])*p[3],cos(a)*p[4]+sin(a)*p[5]) if not p[6] else Vector3(-sin(a)*cos(pitch)*u+cos(a)*p[5],eye+sin(pitch)*u,cos(a)*cos(pitch)*u+sin(a)*p[5])
		mark.look_at(c.cam.global_position,Vector3.UP,true)
		mark.rotate_object_local(Vector3.BACK,.12*sin(t*2.1))
	c.d["pad"].position.y = eye-1.35-(fall_distance(3.05)-distance)
	c.d["man"].rotation.y = PI+.4*sin(t*.9)
	var beam: Node3D = c.d["beam"]
	var target: Vector3 = c.d["pad"].to_global(Vector3(1.1*cos(t*1.7),0,.6+1.1*sin(t*1.7)))
	beam.look_at(target,Vector3.UP,true)
	var start := beam.quaternion
	beam.look_at(c.cam.global_position,Vector3.UP,true)
	beam.quaternion = start.slerp(beam.quaternion,c.ss(t,2.45,2.95))
	if c._ui != null and t >= 2.97 and not c._flashed.has("glare"):
		c._flashed["glare"] = true
		c._ui.cut_flash(.35 if c.shk > 0.0 else .35*.55)
	elif c._ui != null and t > 3.13:
		c._ui.cut_flash(0.0)
	c.shade(.1+.85*c.ss(t,3,3.12))
