class_name CrowdDeath
extends RefCounted
## Original lift-crowd/crowd-death.js: 4.2 seconds, in DeathStage's view frame.
const D := 1.05
const DIGITS := {6:"afedcg",7:"abc",8:"abcdefg",9:"abcdfg"}
const SPOTS := [[.27,-.26,.06],[-.27,-.24,.04],[.32,-.12,.14],[-.33,-.1,.16],[.2,-.34,.2],[-.18,-.36,.22]]
## The HorrorKit hand inside each old hand frame: fingers to the frame's +z, sized like the old fx hand.
const HAND_FIT := 1.75


static func build(c: DeathStage) -> void:
	c.hide_world()
	var floor_shape := QuadMesh.new()
	floor_shape.size = Vector2(1.6,1.6)
	c.d["floor"] = c.mesh(floor_shape,c._mat(Color("#15191a")),0,.002,D-.8)
	c.d["floor"].rotation.x = -PI/2
	c.d["walls"]=[
		c.box(.04,2.3,1.6,Color("#5e6766"),-1,-.8,1.15,D-.8),c.box(.04,2.3,1.6,Color("#5e6766"),-1,.8,1.15,D-.8),
		c.box(1.6,2.3,.04,Color("#545c5b"),-1,0,1.15,D-1.6),c.box(1.6,.04,1.6,Color("#2c3231"),-1,0,2.32,D-.8),
		c.box(.35,2.3,.05,Color("#5e6766"),-1,-.625,1.15,D+.02),c.box(.35,2.3,.05,Color("#5e6766"),-1,.625,1.15,D+.02),
		c.box(.9,.2,.05,Color("#5e6766"),-1,0,2.2,D+.02)]
	for wall: MeshInstance3D in c.d["walls"]:
		# Lit, so the lift's four walls and ceiling take the strip light's fall-off instead of one flat grey.
		wall.material_override=c._mat_lit(wall.material_override.albedo_color)
		wall.set_meta("base_color",wall.material_override.albedo_color.srgb_to_linear())
	c.d["lamp"]=c.box(.6,.012,.4,Color("#d8ddd6"),-1,0,2.29,D-.8,false)
	c.stage_dark(Color(.01,.012,.014),.04,Color(.2,.2,.19),.18)
	c.motive_light(Vector3(0,2.15,D-.8),Color("dfe6da"),1.4,2.6)
	c.box(.04,.82,.19,Color("#262c2e"),-1,-.77,1.42,D-.4)
	c.box(.2,.12,.008,Color("#070808"),-1,0,2.2,D-.008)
	var text := LiftCrowdFx.display_face(.19,.07)
	text.rotation.y=PI
	c.put(text,0,2.2,D-.013)
	c.d["full"]=text
	c.d["segs"]={}
	for key: String in DeathStage.LIFT_SEG:
		var q: Array=DeathStage.LIFT_SEG[key]
		c.d["segs"][key]=c.box(q[2],q[3],.004,Color("#ff4a2a"),-1,-q[0],2.2+q[1],D-.013,false)
	c.d["leaf_l"]=c.box(.45,2.1,.03,Color("#737b7a"),-1,.225,1.05,D)
	c.d["leaf_r"]=c.box(.45,2.1,.03,Color("#737b7a"),-1,-.225,1.05,D)
	c.d["out"]=c.box(1.6,2.3,.01,Color("#b9b6a8"),-1,0,1.15,D+.9,false)
	c.d["out"].material_override=c._mat_lit(Color("8a877c"),-1,false,.9,false)
	c.d["card"]=c.box(.12,.004,.078,Color("#e9e4d6"),-1,.04,.004,D-.42)
	c.d["photo"]=c.box(.03,.005,.04,Color("#47515a"),-1,.058,.005,D-.43)
	c.d["card"].rotation.y=.5
	c.d["photo"].rotation.y=.5
	c.d["hands"]=[]
	for i in SPOTS.size():
		# Same frame (transform, scale .8, timing) as the old fx hand; inside it a jointed, rim-lit shadow hand.
		var h := Node3D.new()
		h.rotation_order = EULER_ORDER_YXZ
		h.scale = Vector3.ONE*.8
		c.put(h,0,-5,0)
		var hand := HorrorKit.hand({"tone":"shadow","arm":.34,"long":1.2,"thin":.3,"side":1 if i%2 else -1})
		hand.rotation = Vector3(0,PI,PI*.5*(1 if i%2 else -1))
		hand.scale = Vector3.ONE*HAND_FIT
		h.add_child(hand)
		h.hide()
		c.d["hands"].append(h)
	c.d["edges"]=[]
	for i in 4:
		var plane := QuadMesh.new()
		plane.size=Vector2.ONE
		c.d["edges"].append(c.mesh(plane,c._mat(Color.BLACK,-1,false,false,false),0,-5,0))
	c.veil(Color.BLACK)


## Pure timeline for fixtures and scrubbing; no camera or gameplay mutation.
static func frame(t: float, shake: float = 1.0) -> Dictionary:
	var end := t>=3.25
	var press := DeathStage.ss(t,.9,2.2)
	var look := DeathStage.ss(t,2.2,2.7)
	var yaw := 0.0 if end else .22*press
	var pitch := -1.02 if end else .16*(1-press)+.62*look+.025*sin(t*31)*shake*press
	var lift := .6 if end else -.28*press
	var shade := .9-.6*DeathStage.ss(t,3.3,3.6)+.5*DeathStage.ss(t,3.95,4.2) if end else .12+.5*DeathStage.ss(t,1.6,2.2)-.35*look+.7*DeathStage.ss(t,3.05,3.25)
	var gap := .9*DeathStage.ss(t,3.35,3.75) if end else 0.0
	var lit := .15 if end else 1-.8*DeathStage.ss(t,.8,2)
	var n := 6+mini(3,floori((t-2.2)/.24))
	var segments: String=DIGITS[n] if t>=2.2 and t<3.1 else ("abcdefg" if t>=3.1 and t<3.15 else "")
	return {"yaw":yaw,"pitch":pitch,"lift":lift,"shade":minf(.94,shade),"gap":gap,"lit":lit,"segments":segments,"full":t<2.2,"end":end}


static func update(c: DeathStage, t: float) -> void:
	var f := frame(t,c.shk)
	c.view(t,f["yaw"],f["pitch"],f["lift"])
	c.shade(f["shade"])
	c.d["leaf_l"].position.x=.225+float(f["gap"])/2
	c.d["leaf_r"].position.x=-.225-float(f["gap"])/2
	c.d["out"].visible=bool(f["end"]) and float(f["gap"])>.02
	c.d["lamp"].visible=not bool(f["end"]) and float(f["lit"])>.25
	for wall: MeshInstance3D in c.d["walls"]:
		var color: Color = wall.get_meta("base_color")
		var level := .25+.75*float(f["lit"])
		wall.material_override.albedo_color=Color(color.r*level,color.g*level,color.b*level).linear_to_srgb()
	c.d["full"].visible=f["full"]
	for key: String in c.d["segs"]:
		c.d["segs"][key].visible=String(f["segments"]).contains(key)
	c.d["card"].visible=f["end"]
	c.d["photo"].visible=f["end"]
	var base := c.F.to_local(c.cam.global_position)
	var basis := c.F.global_basis.inverse()*c.cam.global_basis
	var lf := -basis.z
	var lu := basis.y
	var lr := basis.x
	var dist := .3
	var hh := tan(deg_to_rad(c.cam.fov)*.5)*dist
	var size := c.cam.get_viewport().get_visible_rect().size
	var hw := hh*size.x/maxf(1,size.y)
	var sq := 0.0 if f["end"] else c.ss(t,.9,2.9)
	var ix := .42*hw*sq
	var iy := .3*hh*sq
	var positions := [[2*hw-ix,0,2*hw,2.6*hh],[-(2*hw-ix),0,2*hw,2.6*hh],[0,2*hh-iy,2.6*hw,2*hh],[0,-(2*hh-iy),2.6*hw,2*hh]]
	for i in 4:
		var edge: MeshInstance3D=c.d["edges"][i]
		var q: Array=positions[i]
		edge.visible=not f["end"] and sq>.01
		edge.position=base+lf*dist+lr*float(q[0])+lu*float(q[1])
		edge.basis=basis.scaled_local(Vector3(q[2],q[3],1))
	for i in SPOTS.size():
		var h: Node3D=c.d["hands"][i]
		var s: Array=SPOTS[i]
		var at := .9+i*.2
		h.visible=not f["end"] and t>at
		if not h.visible: continue
		var g := c.ss(t,at,at+.35)
		h.position=base+lf*(.24+float(s[2])*.5)+lr*(-float(s[0])*(1.3-.3*g))+lu*(float(s[1])*(1.25-.25*g))
		h.look_at(c.F.to_global(base+lf*1.2+lu*float(s[1])),Vector3.UP,true)
		# Fingers open as the hand arrives, then close on what they reach (pure function of t).
		var grab := c.ss(t,at+.45,at+1.3)
		HorrorKit.pose_hand(h.get_child(0),lerpf(-.1,.75,grab)+.06*sin(t*3.1+i),lerpf(.9,.25,grab))
