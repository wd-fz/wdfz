extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/atmos_props-reference.json.gz").decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func near(actual: Vector3, expected: Array) -> bool:
	return actual.distance_to(Vector3(expected[0],expected[1],expected[2]))<.0001

func compare(node: Node3D, sample: Dictionary, label: String) -> void:
	var q: Array = sample["q"]
	var rotation := Basis.from_euler(node.rotation,node.rotation_order).get_rotation_quaternion()
	check(near(node.position,sample["p"]) and near(node.scale,sample["s"]) and absf(rotation.dot(Quaternion(q[0],q[1],q[2],q[3])))>.99999,label+" original transform")
	check(node.get_child_count()==sample["children"].size(),label+" original child count")
	if sample.has("material"):
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as BaseMaterial3D
		var m: Dictionary = sample["material"]
		check(mat.albedo_color.to_html(false)==m["color"] and absf(mat.albedo_color.a-m["alpha"])<.00001,label+" colour and opacity")
		check((mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED)==m["unlit"] and mat.disable_fog!=m["fog"] and (mat.depth_draw_mode!=BaseMaterial3D.DEPTH_DRAW_DISABLED)==m["depthWrite"],label+" lighting, fog and depth writing")
		check((mat.albedo_texture!=null)==m["texture"] and (mat.blend_mode==BaseMaterial3D.BLEND_MODE_ADD)==m["add"],label+" texture and blend")
		var g: Dictionary = sample["geometry"]
		if g.has("cylinder"):
			var cylinder := mesh.mesh as CylinderMesh
			var values: Array = g["cylinder"]
			check(cylinder!=null and absf(cylinder.top_radius-values[0])<.00001 and absf(cylinder.bottom_radius-values[1])<.00001 and absf(cylinder.height-values[2])<.00001 and cylinder.radial_segments==values[3],label+" cylinder dimensions and segments")
		else:
			var quad := mesh.mesh as QuadMesh
			check(quad!=null and quad.size.distance_to(Vector2(g["plane"][0],g["plane"][1]))<.00001,label+" plane dimensions")
	for i in mini(node.get_child_count(),sample["children"].size()): compare(node.get_child(i),sample["children"][i],label+"/"+str(i))

func test_original_props() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var fx := AtmosFx.new()
	root.add_child(fx)
	for sample: Dictionary in original_data()["floors"]:
		fx.setup(CampusData.layout(sample["room"]))
		check(fx.get_child_count()==sample["props"].size(),sample["room"]+" original floor decoration count")
		for i in mini(fx.get_child_count(),sample["props"].size()): compare(fx.get_child(i),sample["props"][i],sample["room"]+"/"+str(i))
		for shift: Dictionary in sample["shifts"]:
			var p: Array = shift["camera"]
			camera.position = Vector3(p[0],p[1],p[2])
			fx.apply_shift(shift["kind"],shift["pose"] if shift["pose"] is Dictionary else {})
			fx.face_camera(camera)
			compare(fx.props,shift["props"],sample["room"]+" "+shift["kind"])
			var pose := fx.props.transform
			camera.position.x += 3
			fx.face_camera(camera)
			check(fx.props.transform==pose,"a shifted prop faces the observer once, not continuously")
	fx.free()
	camera.free()

func test_window() -> void:
	var data := original_data()
	var camera := Camera3D.new()
	root.add_child(camera)
	var fx := AtmosFx.new()
	root.add_child(fx)
	var last: Dictionary = {}
	for sample: Dictionary in data["windows"]:
		var record: Dictionary = sample["record"]
		if fx.room.get("id")!=record["room"]: fx.setup(CampusData.layout(record["room"]))
		var p: Array = sample["camera"]
		camera.position = Vector3(p[0],p[1],p[2])
		camera.rotation.y = sample["yaw"]
		var looking := fx.show_window(record,camera)
		check(near(fx._fig.position,sample["position"]) and near(fx._fig.scale,sample["scale"]),record["cls"]+" original projected window position and scale")
		check(looking==sample["looking"],record["cls"]+" original observation cone")
		var bounds := AABB()
		var first := true
		var parts := fx._fig.find_children("*","MeshInstance3D",true,false)
		for part: MeshInstance3D in parts:
			var b: AABB = part.global_transform*part.mesh.get_aabb()
			bounds = b if first else bounds.merge(b)
			first = false
			var m := part.material_override as BaseMaterial3D
			check(m.albedo_color.to_html(false)=="101315" and absf(m.albedo_color.a-.82)<.00001 and not m.vertex_color_use_as_albedo and m.disable_fog and m.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED,"window person uses the original transparent silhouette material")
		check(not parts.is_empty() and near(bounds.position,sample["bounds"][0]) and near(bounds.end,sample["bounds"][1]),"original standing-person silhouette geometry, flattened on the window")
		last = record
	camera.position.x += 3
	last["seen"] = .5
	fx.show_window(last,camera)
	check(near(fx._fig.position,data["stable"]) and same_json(data["stable"],data["before"]),"observing and moving the camera keeps the same window record anchored")
	last["gone"] = true
	check(not fx.show_window(last,camera) and not fx._fig.visible,"a disappeared silhouette is hidden and no longer observed")
	fx.clear()
	check(fx._fig==null and fx.props==null and fx.signs.is_empty() and fx.get_child_count()==0 and data["cleared"],"clearing removes the original atmospheric scene and record")
	fx.free()
	camera.free()

func test_app() -> void:
	var data := original_data()
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/atmos-props/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	var mood := app.atmos()
	check(same_json(mood._window_anchor,data["anchor"]),"formal session injects the original laboratory world anchor")
	var room := CampusData.layout("teach1")
	var position := CampusGeometry.tile_center(room,12,13)
	for day in range(1,60):
		mood.reset()
		mood.set_context({"scene":"teach1","x":position.x,"y":position.y,"day":day,"tsec":620,"age":100,"dread":DreadModule.new(CampusData.rooms())})
		mood._window_tick()
		if not mood.window.is_empty(): break
	check(not mood.window.is_empty() and same_json(mood.window.get("anchor",{}),data["anchor"]),"a naturally eligible window record carries its anchor")
	var fx := app._campus_world().atmos_fx
	var sign := fx.signs[0]
	app.kill("atmosphere boundary test","vignette","vignette")
	await _frames(2)
	check(app.story().dead and fx.get_child_count()==0 and not is_instance_valid(sign),"real death releases the atmosphere props before its cinematic")
	app.debug_flow.revive()
	app._atmos_step(0)
	check(not app.story().dead and not fx.signs.is_empty() and fx.props!=null,"revival rebuilds the original floor decorations")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
