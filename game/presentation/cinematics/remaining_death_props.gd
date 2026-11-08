class_name RemainingDeathProps
extends AnomalyProps
## The nine original anfx death branches outside DeathCG. Absolute stage positions,
## elapsed-time animation, and presentation-only camera output; never writes rule state.
const CAUSES:=["vignette","hand","names","chalk","mirror","face","squeeze","slit","wall"]
var origin:=Vector3.ZERO
var forward:=Vector3.FORWARD
var right:=Vector3.RIGHT
var heading:=0.0
var camera_pitch: Variant=null
var origins: Array[Vector3]=[]
var _hole: Node3D

func _group(p: Vector3 = Vector3.ZERO, angle: float = 0) -> Node3D:
	var group:=Node3D.new()
	group.rotation_order=EULER_ORDER_XYZ
	group.position=p
	group.rotation.y=angle
	add_child(group)
	return group

func _in_box(parent: Node3D, hex: String, size: Vector3, p: Vector3) -> MeshInstance3D:
	var box:=_box(hex,1,size,p)
	box.reparent(parent,false)
	return box

func _fx(type: String, p: Vector3, size: float = 1) -> Node3D:
	var n:=_group(p)
	var model: Node3D=(load("res://assets/campus/fx/%s.glb" % type) as PackedScene).instantiate()
	var mat:=_mat("ffffff")
	mat.vertex_color_use_as_albedo=true
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		(child as MeshInstance3D).material_override=mat
		(child as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(model)
	n.scale=Vector3.ONE*size
	return n

func stage(cause: String, feet: Vector3, ang: float) -> void:
	kind=cause
	origin=Vector3(feet.x,0,feet.z)
	heading=ang
	forward=Vector3(cos(ang),0,sin(ang))
	right=Vector3(-sin(ang),0,cos(ang))
	_random=seed_value
	var rot:=PI/2-ang
	match kind:
		"vignette":
			var plane:=_plane("020304",.92,Vector2(14,14),origin+Vector3.DOWN)
			plane.rotation.x=-PI/2
			items.append(plane)
			for i in 10:
				var angle:=i/10.0*6.283+(i%2)*.18
				_figure("030405",origin+Vector3(cos(angle)*4.2,0,sin(angle)*4.2))
		"hand":
			var p:=origin+forward
			var gap:=_plane("020304",.95,Vector2(1.5,.55),p+Vector3.UP*.015)
			gap.rotation=Vector3(-PI/2,0,-ang)
			var hand:=_fx("hand",p+Vector3.DOWN*.35,1.4)
			hand.rotation=Vector3(-.8,-PI/2-ang,0)
			items.append(hand)
		"names":
			var group:=_group(origin,rot)
			# The original Kit combines 42 plates / top lines / bottom lines into 3 meshes.
			for k in 3:
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				for row in 6:
					for col in 7:
						var shape:=BoxMesh.new()
						shape.size=[Vector3(.78,.40,.05),Vector3(.58,.05,.02),Vector3(.40,.04,.02)][k]
						var at:=Vector3(-2.6+col*.86,.55+row*.46+[0,.08,-.06][k],[2.6,2.57,2.57][k])
						st.append_from(shape,0,Transform3D(Basis.IDENTITY,at))
				var mesh:=_mesh(st.commit(),_mat(["07090a","8f8a80","5e5a52"][k]),Vector3.ZERO)
				mesh.reparent(group,false)
				items.append(mesh)
		"chalk":
			var group:=_group(origin,rot)
			for spec: Array in [["141a1e",Vector3(6.4,2.4,.1),Vector3(0,1.55,2.6)],["2a3338",Vector3(6.5,.08,.16),Vector3(0,.34,2.58)]]:
				items.append(_in_box(group,spec[0],spec[1],spec[2]))
			for i in 7:
				var width:=1.4+_rand()*3
				var n:=_box("d8d2c4",.95,Vector3(width,.09,.02),Vector3(-3+width/2+_rand()*(6-width),2.35-i*.29,2.54),true)
				n.reparent(group,false)
		"mirror":
			var p:=origin+forward*(1.55/9)
			var frame:=_box("161d22",.96,Vector3(1.3,2.3,.1),p+Vector3.UP*1.16,true)
			frame.rotation.y=-PI/2-ang
			var glass:=_plane("26343c",.62,Vector2(1.14,2.14),p+forward*.06+Vector3.UP*1.16)
			glass.rotation.y=-PI/2-ang
			items.append(glass)
			var person:=_figure("0a1013",p,"tall",1.02)
			person.rotation.y=-PI/2-ang
		"face":
			var person:=_figure("0a0c0e",Vector3.ZERO,"person")
			_hole=_fx("smile",Vector3(0,1.72-1.72*.2,.06),.2)
			_hole.reparent(person,false)
			_hole.hide()
		"squeeze":
			for i in 4:
				var group:=_group(origin+forward*(1.1+i*1.8),rot)
				_in_box(group,"3a2f2c",Vector3(9,2.8,.36),Vector3(0,1.4,0))
				_in_box(group,"6c675f",Vector3(9.2,.12,.5),Vector3(0,2.86,0))
				items.append(group)
			for i in 2:
				var wall:=_box("2b3036",1,Vector3(.3,3.4,8),origin+Vector3.UP*1.7,true)
				wall.rotation.y=rot
		"slit":
			for i in 4:
				var leaf:=_box("101316",1,Vector3(1.25,2.7,.1),origin+Vector3.UP*1.35,true)
				leaf.rotation.y=rot
			var light:=_plane("d6e2dd",.9,Vector2(1,2.6),Vector3.ZERO)
			(light.material_override as BaseMaterial3D).disable_fog=true
			light.rotation.y=rot+PI
			items.append(light)
			var gate:=_group(Vector3.ZERO,rot)
			for box: Array in [[-2.4,1.6,.35,3.2],[2.4,1.6,.35,3.2],[0,3.3,5.2,.3]]:
				_in_box(gate,"07090b",Vector3(box[2],box[3],.35),Vector3(box[0],box[1],0))
			items.append(gate)
		"wall":
			for i in 2: _box("9a958c",1,Vector3(.6,3,4),origin+Vector3(1.2 if i else -1.2,1.5,0),true)
	for item in items: origins.append(item.position)

func present(elapsed: float, feet: Vector3, ang: float) -> void:
	time=elapsed
	camera_pitch=null
	match kind:
		"vignette":
			for i in 10:
				var delay:=((i*7)%10)*.11
				var angle:=i/10.0*6.283+(i%2)*.18
				var radius:=maxf(.75,4.2-maxf(0,time-.35-delay)*1.7)
				var node:=items[i+1]
				node.position=origin+Vector3(cos(angle)*radius,0,sin(angle)*radius)
				node.rotation=Vector3(.18*clampf((2.4-radius)/1.6,0,1),atan2(origin.x-node.position.x,origin.z-node.position.z),0)
				node.visible=time>delay*.6
		"hand":
			var progress:=clampf(time/2,0,1)
			var rise:=clampf((progress-.12)/.34,0,1)
			var reach:=clampf((progress-.48)/.32,0,1)
			items[0].position=origins[0].lerp(Vector3(feet.x,origins[0].y,feet.z),reach*.68)
			items[0].position.y=-.35+rise*1.45
			items[0].rotation.x=-.8+rise*.8+reach*.35
		"names":
			for i in items.size(): items[i].visible=(i%3)<=floori(time*6)%3
		"chalk":
			for i in items.size():
				if origins[i].y>.4 and origins[i].y<2.5: items[i].position.y=origins[i].y-minf(.9,time*.55)
		"mirror":
			items[2].position=origins[2]+Vector3(cos(ang),0,sin(ang))*minf(1.55,time*.85)
			items[0].scale=Vector3(1+time*.22,1+time*.16,1)
		"face":
			var turn:=clampf((time-.5)/.9,0,1)
			var ease:=turn*turn*(3-2*turn)
			var walk:=clampf((time-1.4)/1.2,0,1)
			items[0].position=origin+forward*(4.6-walk*3.9)+Vector3.DOWN*.04*absf(sin(time*5))*walk
			items[0].rotation.y=-PI/2-heading+PI*(1-ease)
			_hole.visible=turn>.45
			var scale_value:=.2+walk*walk*.35
			_hole.scale=Vector3.ONE*scale_value
			_hole.position.y=1.72-.12*walk-1.72*scale_value
		"squeeze":
			var climb:=minf(time,2.4)/.6
			for i in 4:
				var over:=clampf(climb-i,0,1)
				items[i].position=origin+forward*(1.1+i*1.8-over*1.8)+Vector3.DOWN*2.9*over
				items[i].visible=over<1
			for i in 2:
				var gap:=maxf(.3,2.2-maxf(0,time-2.4)*1.6)
				items[i+4].position=origin+right*(1 if i else -1)*gap+Vector3.UP*1.7
				items[i+4].visible=time>2.2
			camera_pitch=.55*absf(sin(minf(climb,4)*PI*.5))*(1 if time<2.4 else 0)-(.08 if time>2.4 else 0)
		"slit":
			var pass_t:=clampf((time-.7)/.9,0,1)
			var distance:=1.8-pass_t*2.6
			var gap:=.08+.67*clampf((time-.7)/.5,0,1)
			var shut_gap:=1.4*(1-clampf((time-3)/.5,0,1))
			for i in 4:
				items[i].position=origin+forward*(distance if i<2 else 1.3)+right*(1 if i%2 else -1)*(.625+(gap if i<2 else shut_gap)/2)+Vector3.UP*1.35
				items[i].visible=distance>-.4 if i<2 else time>2.9
			items[4].position=origin+forward*(distance+.25)
			items[4].visible=distance>-.2
			(items[4].material_override as BaseMaterial3D).albedo_color.a=.9*(.55+.45*absf(sin(time*9)) if time<.7 else 1-pass_t*.6)
			items[5].position=origin+forward*(30-clampf((time-1.6)/1.4,0,1)*26)
			items[5].visible=time>1.5
		"wall":
			for item in items: item.position.y=minf(1.6,time*.9)
