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
	var at:=props.items[0].position
	an["t"]=.016
	fx.update(.016,an,room,"teach1",feet+Vector3(2,0,3),Vector2.LEFT)
	check(props.items[0].position==at,"the board stays on its original wall when the player moves or turns")
	an["t"]=0.0
	fx.update(0,an,room,"teach1",feet,Vector2.RIGHT)
	check(fx._extra["original"]!=props and not props.is_visible_in_tree(),"a restarted same-id anomaly replaces its old props without a one-frame overlap")
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
	viewport.queue_free()
	await _frames()
