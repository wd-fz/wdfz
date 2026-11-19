extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/anomaly_fx-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _v(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])


func _differences(props: AnomalyProps, state: Dictionary) -> Array:
	var errors:=[]
	if props.position.distance_to(_v(state["p"]))>.0001: errors.append("root")
	var expected: Array=state["children"]
	if props.get_child_count()!=expected.size(): return ["count %d != %d" % [props.get_child_count(),expected.size()]]
	for i in expected.size():
		var spec: Dictionary=expected[i]
		var n: Node3D=props.get_child(i)
		if n.position.distance_to(_v(spec["p"]))>.0001: errors.append("position %d %s != %s" % [i,n.position,spec["p"]])
		if n.scale.distance_to(_v(spec["s"]))>.0001: errors.append("scale %d" % i)
		for axis in 3:
			if absf(wrapf(n.rotation[axis]-spec["r"][axis],-PI,PI))>.0001: errors.append("rotation %d.%d" % [i,axis])
		var q: Array=spec["q"]
		var actual:=Basis.from_euler(n.rotation,n.rotation_order).get_rotation_quaternion()
		if absf(actual.dot(Quaternion(q[0],q[1],q[2],q[3])))<.99999: errors.append("rotation order %d" % i)
		if n.visible!=spec["v"]: errors.append("visible %d" % i)
		if n is MeshInstance3D:
			var mat: StandardMaterial3D=n.material_override
			if absf(mat.albedo_color.a-float(spec.get("alpha",1)))>.00001: errors.append("alpha %d" % i)
			if mat.albedo_color.to_html(false)!=String(spec.get("color","ffffff")): errors.append("color %d" % i)
			if spec.get("depthWrite",false) and mat.depth_draw_mode!=BaseMaterial3D.DEPTH_DRAW_ALWAYS: errors.append("depth write %d" % i)
			var geo: Variant=spec["geo"]
			if geo is Dictionary and geo.has("depth") and n.mesh is BoxMesh:
				if n.mesh.size.distance_to(Vector3(geo["width"],geo["height"],geo["depth"]))>.0001: errors.append("box %d" % i)
			if geo is Dictionary and geo.has("width") and n.mesh is QuadMesh:
				if n.mesh.size.distance_to(Vector2(geo["width"],geo["height"]))>.0001: errors.append("plane %d" % i)
	return errors


## The stall hand keeps the old prop's root and palm centre (the old 0.34 x 0.26 palm block at
## (0, .16, 0), fingers beyond it) and its timing; the five boxes became one jointed HorrorKit hand.
func _hand_differences(props: AnomalyProps, state: Dictionary, feet: Vector3) -> Array:
	var errors:=[]
	if props.position.distance_to(_v(state["p"]))>.0001: errors.append("root")
	var palm: Dictionary=state["children"][0]
	if props.get_child_count()!=1 or props.items.size()!=1: return errors+["one hand node, %d" % props.get_child_count()]
	var holder: Node3D=props.get_child(0)
	if holder.position.distance_to(_v(palm["p"]))>.0001: errors.append("palm centre %s" % holder.position)
	if holder.visible!=palm["v"]: errors.append("visible")
	var hand: Node3D=holder.get_child(0)
	if not hand.has_meta("horror_hand"): return errors+["not a HorrorKit hand"]
	# The palm centre of the kit hand sits on the holder origin; the fingers reach out of the old block's span.
	var centre:=holder.global_transform*hand.transform*Vector3(0,0,-.045)
	if centre.distance_to(holder.global_position)>.001: errors.append("palm offset %s" % centre)
	var tip: Node3D=HorrorKit.hand_joints(hand)[2][-1]
	var reach:=Vector2(tip.global_position.x-props.global_position.x,tip.global_position.z-props.global_position.z).length()
	if reach<.15 or reach>.6: errors.append("finger reach %.3f" % reach)
	var toward:=Vector2(feet.x-props.position.x,feet.z-props.position.z)
	var fingers:=Vector2(tip.global_position.x-holder.global_position.x,tip.global_position.z-holder.global_position.z)
	if toward.length()>.05 and fingers.normalized().dot(toward.normalized())<.8: errors.append("fingers do not reach towards the player")
	return errors


func _school_anomaly(props: AnomalyProps, spec: Dictionary, data: Dictionary, room: Variant, feet: Vector3) -> void:
	var original:=data.duplicate(true)
	match props.kind:
		"exercise":
			check(props.items.size()==6,"the playground still has six pupils")
			for i in props.items.size():
				check(props.items[i].position.distance_to(_v(spec.before.children[i].p))<.001,"drill feet stay on their original marks")
			var lead:=props.items[0] as OtherworldFigure
			var late:=props.items[4] as OtherworldFigure
			var a:=lead.find_child("Skeleton3D",true,false) as Skeleton3D
			var b:=late.find_child("Skeleton3D",true,false) as Skeleton3D
			var arm:=a.find_bone("ArmL")
			props.advance(0,data,room,feet,0,Vector2.RIGHT,.2)
			var rest:=a.get_bone_pose_rotation(arm)
			props.advance(0,data,room,feet,0,Vector2.RIGHT,1.60)
			check(a.get_bone_pose_rotation(arm).angle_to(rest)>.8 and a.get_bone_pose_rotation(arm).angle_to(b.get_bone_pose_rotation(arm))>.4,"arms articulate, with one student finishing half a count late")
			props.advance(0,data,room,feet+Vector3.RIGHT*6,0,Vector2.RIGHT,2.0)
			check(absf(lead.face.rotation.y)>.1 and lead.rotation==Vector3.ZERO,"the head turns independently while the feet hold position")
		"chalk","roster":
			check(props.items.size()==1 and props.items[0] is AnomalyWriting,"one legible world-space notice replaces placeholder bars")
			var face:=props._writing.global_basis.z
			check(face.dot(feet-props._writing.position)>-.05 and face.y==0,"the notice faces the walkable reading side of the wall")
			props.advance(0,data,room,feet,0,Vector2.RIGHT,5)
			check(is_equal_approx(props._writing.surface.get_shader_parameter("written"),1.0),"loading into the event restores the written marks")
			if props.kind=="chalk":
				props.advance(0,data,room,feet,0,Vector2.RIGHT,13)
				check(not props._writing.forecast and is_equal_approx(props._writing.surface.get_shader_parameter("erased"),1.0),"an unconfirmed forecast erases without inventing a time")
		"shadow":
			var at:=props.items[0].global_position
			check(at.distance_to(feet)<1.1,"late shadow begins at the actual player, including far from the origin")
			props.advance(.05,data,room,feet+Vector3.RIGHT*1.5,0,Vector2.RIGHT,6)
			var behind:=props.items[0].global_position
			check(behind.x>at.x and behind.x<at.x+1.4,"the shadow lags a step behind actual movement")
			props.advance(.016,data,room,feet+Vector3.RIGHT*20,0,Vector2.RIGHT,7)
			check(props.position.distance_to(feet+Vector3.RIGHT*20)<1,"an authoritative displacement cannot stretch the shadow across the grounds")
		"repeat":
			var headmate := props.items[0] as OtherworldFigure
			var offset := Vector2(headmate.position.x-feet.x,headmate.position.z-feet.z)
			check(offset.dot(Vector2.from_angle(spec.ang))<0 and offset.length()>.65,"the voice has a classmate behind the player, clear of the camera")
			var anchor := headmate.position
			props.advance(0,data,room,feet+Vector3.RIGHT*2,0,Vector2.RIGHT,2.0)
			check(headmate.position==anchor and absf(headmate.face.rotation.y)>.1,"the classmate follows with the head while staying in the original aisle")
	check(same_json(original,data),"school horror staging is read-only for "+props.kind)


func test_reference() -> void:
	var scenarios: Array=_reference()["scenarios"]
	check(scenarios.size()==21,"reference covers 17 original effects and all five gaze qualities")
	for spec: Dictionary in scenarios:
		var room: Variant=null if spec["scene"]=="out" else CampusData.layout(spec["scene"])
		var world: Dictionary=spec["me"]
		var p:=CampusGeometry.to_scene(room,Vector2(world["x"],world["y"]))
		var data: Dictionary=spec["data"].duplicate(true)
		if spec["kind"]=="hand": data["src"]=spec["source"]
		var props:=AnomalyProps.new()
		root.add_child(props)
		props.build(spec["kind"],data,room,Vector3(p.x,0,p.y),Vector2.from_angle(spec["ang"]),int(spec["tier"]))
		if spec["kind"] in ["exercise","chalk","roster","shadow","repeat"]:
			_school_anomaly(props,spec,data,room,Vector3(p.x,0,p.y))
			props.free()
			continue
		if spec["kind"]=="hand":
			var feet:=Vector3(p.x,0,p.y)
			check(_hand_differences(props,spec["before"],feet).is_empty(),"stall hand keeps the original spot: %s" % [_hand_differences(props,spec["before"],feet)])
			var poses:=[]
			for frame: Dictionary in spec["frames"]:
				props.advance(frame["dt"],data,room,_v(frame["feet"]),frame["acc"])
				var wrong_hand:=_hand_differences(props,frame["state"],feet)
				check(wrong_hand.is_empty(),"stall hand stays put while its fingers move t%.3f: %s" % [props.time,wrong_hand])
				poses.append((HorrorKit.hand_joints(props.items[0].get_child(0))[0][1] as Node3D).rotation)
			check(poses.size()>1 and not poses[0].is_equal_approx(poses[-1]),"the stall hand's fingers move over time")
			var again:=AnomalyProps.new()
			root.add_child(again)
			again.build("hand",data,room,feet,Vector2.from_angle(spec["ang"]),int(spec["tier"]))
			again.advance(props.time,data,room,feet)
			check((HorrorKit.hand_joints(again.items[0].get_child(0))[0][1] as Node3D).rotation.is_equal_approx(poses[-1]),"finger pose is a function of elapsed time only")
			again.free()
			props.free()
			continue
		var wrong:=_differences(props,spec["before"])
		check(wrong.is_empty(),"original model layout %s q%s: %s" % [spec["kind"],spec["tier"],wrong.slice(0,3)])
		for frame: Dictionary in spec["frames"]:
			data["hit"]=frame["hit"]
			props.advance(frame["dt"],data,room,_v(frame["feet"]),frame["acc"])
			wrong=_differences(props,frame["state"])
			check(wrong.is_empty(),"original animation %s q%s t%.3f: %s" % [spec["kind"],spec["tier"],props.time,wrong.slice(0,3)])
		props.free()
	CampusData.clear_caches()


func test_adapter() -> void:
	var fx:=AnomalyFx.new()
	root.add_child(fx)
	var room:=CampusData.layout("teach1")
	var p:=CampusGeometry.to_scene(room,CampusGeometry.tile_center(room,30,17))
	var feet:=Vector3(p.x,0,p.y)
	var an: Dictionary={"id":"chalk","active":true,"t":0.0,"acc":0.0,"data":{"scene":"teach1","until":800.0}}
	var state:=an.duplicate(true)
	fx.update(.016,an,room,"teach1",feet,Vector2.RIGHT)
	var props: AnomalyProps=fx._extra["original"]
	check(props._writing.surface.get_shader_parameter("clock_digits")==Vector4(1,3,2,0),"chalk records the real 13:20 forecast")
	var at:=props.items[0].position
	an["t"]=.016
	fx.update(.016,an,room,"teach1",feet+Vector3(2,0,3),Vector2.LEFT)
	check(props.items[0].position==at,"the board stays on its original wall when the player moves or turns")
	an["t"]=0.0
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	check(fx._extra["original"]!=props and not props.is_visible_in_tree(),"a restarted same-id anomaly replaces its old props without a one-frame overlap")
	an={"id":"roster","active":true,"t":5.0,"data":{"scene":"teach1"}}
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT,Vector3.INF,false,"lin")
	var first: AnomalyProps=fx._extra.original
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT,Vector3.INF,false,"xu")
	check(fx._extra.original!=first and not first.is_visible_in_tree() and is_equal_approx(fx._extra.original._writing.surface.get_shader_parameter("student_row"),3.0),"spectating another student changes the crossed-out name even during the same event")
	var origin := CampusGeometry.to_world(room,feet.x,feet.z)
	an={"id":"repeat","active":true,"t":4.0,"data":{"scene":"teach1","rx":origin.x,"ry":origin.y,"heading":0.0}}
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	var witness: Vector3 = fx._extra.original.items[0].position
	fx.update(0,{},room,"teach1",feet,Vector2.RIGHT)
	fx.update(0,an,room,"teach1",feet+Vector3.RIGHT*4,Vector2.LEFT)
	check(fx._extra.original.items[0].position==witness,"loading while facing a different way leaves the witness in the original aisle")
	var sealed_room:=room.duplicate()
	sealed_room["grid"]=room.grid.map(func(line: String) -> String: return "#".repeat(line.length()))
	var boxed:=AnomalyProps.new()
	boxed.build("repeat",{},sealed_room,feet,Vector2.RIGHT,2)
	boxed.advance(.1,{},sealed_room,feet)
	check(boxed.items.is_empty(),"when there is no clear aisle only the question is heard")
	boxed.free()
	var hall := room.duplicate()
	hall["grid"] = room.grid.map(func(line: String) -> String: return ".".repeat(line.length()))
	hall["boxes"] = []
	var paper := AnomalyProps.new()
	root.add_child(paper)
	paper.build("roster",{"rx":origin.x,"ry":origin.y,"heading":0.0},hall,feet+Vector3.RIGHT*20,Vector2.LEFT,2)
	check(paper._writing.position.distance_to(feet)<2.0 and paper._writing.global_basis.z.y>.99,"an open hall leaves the physical register flat within its original interaction radius")
	paper.free()
	an=state.duplicate(true)
	an["id"]="raindots"
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	check(not fx._extra.has("rain") and (fx._extra["original"] as AnomalyProps).items[0].material_override.albedo_texture!=null,"rain-writing displays the original text texture instead of spawning ordinary rainfall")
	var words: MeshInstance3D=fx._extra["original"].items[0]
	check(words.material_override.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED,"fading text preserves the original no-depth-write material")
	an["id"]="feast"
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	var feast: AnomalyProps=fx._extra["original"]
	check(feast.get_child(0).material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED and feast.items[0].material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"the table and full-opacity plates render in the opaque pass, avoiding transparent self-occlusion")
	an["id"]="stare"
	fx.update(.5,an,room,"teach1",feet,Vector2.RIGHT)
	var eyes: AnomalyProps=fx._extra["original"]
	check(eyes.items.size()==[18,32,32,48,58][CampusData.tier],"gaze uses the original quality-dependent eye count")
	var eye: MeshInstance3D=eyes.items[0]
	check(eye.material_override.no_depth_test and eye.material_override.disable_fog and eye.material_override.billboard_mode==BaseMaterial3D.BILLBOARD_ENABLED,"the original eyes face the camera and remain visible through walls")
	var untouched:=an.duplicate(true)
	fx.update(.4,an,room,"teach1",feet,Vector2.LEFT)
	check(same_json(an,untouched),"animation never changes rule data or the caller's input")
	an["active"]=false
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	check(fx.shown_count()==0,"ending removes every owned prop")
	fx.free()
	await _frames()
	CampusData.clear_caches()


func test_rendering() -> void:
	if DisplayServer.get_name()=="headless": return
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera3D.new()
	viewport.add_child(camera)
	camera.position=Vector3(0,1.65,4)
	camera.look_at(Vector3(0,.8,0))
	var props:=AnomalyProps.new()
	viewport.add_child(props)
	props.build("feast",{},null,Vector3.ZERO,Vector2.RIGHT,2)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var with_table:=viewport.get_texture().get_image()
	(props.get_child(0) as Node3D).hide()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var without_table:=viewport.get_texture().get_image()
	for i in 8:
		var food:=props.items[i*3+1]
		var pixel:=Vector2i(camera.unproject_position(food.global_position))
		var a:=with_table.get_pixelv(pixel)
		var b:=without_table.get_pixelv(pixel)
		var error:=Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))
		check(error<.02 and b.get_luminance()>.1,"food %d remains visible above the large table in the native depth buffer" % i)
	props.free()
	props=AnomalyProps.new()
	viewport.add_child(props)
	props.build("raindots",{},null,Vector3(-3.2,0,0),Vector2.RIGHT,2)
	props.advance(8,{},null,Vector3.ZERO)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var with_text:=viewport.get_texture().get_image()
	props.hide()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var blank:=viewport.get_texture().get_image()
	var changed:=0
	for y in viewport.size.y:
		for x in viewport.size.x:
			if absf(with_text.get_pixel(x,y).get_luminance()-blank.get_pixel(x,y).get_luminance())>.05: changed+=1
	check(changed>100,"original rain lettering is visible from above after its authored fade-in")
	props.free()
	var court := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(10,.18,10)
	court.mesh = slab
	viewport.add_child(court)
	var sun := DirectionalLight3D.new()
	viewport.add_child(sun)
	sun.rotation.x = -PI*.45
	props = AnomalyProps.new()
	viewport.add_child(props)
	props.build("shadow",{},null,Vector3.ZERO,Vector2.RIGHT,2)
	camera.position = props.position+Vector3(0,3.0,1.3)
	camera.look_at(props.position)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var with_shadow := viewport.get_texture().get_image()
	props.hide()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var bare := viewport.get_texture().get_image()
	var dark_samples := 0
	for y in range(0,bare.get_height(),4):
		for x in range(0,bare.get_width(),4):
			if bare.get_pixel(x,y).get_luminance()-with_shadow.get_pixel(x,y).get_luminance()>.08:
				dark_samples+=1
	check(dark_samples>32,"the detached shadow projects onto a raised playing surface above the collision floor")
	viewport.queue_free()
	await _frames()
