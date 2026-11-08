extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/death_timelines-reference.json.gz").decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func near(value: Vector3, expected: Array, tolerance: float = .0002) -> bool:
	return value.distance_to(Vector3(expected[0],expected[1],expected[2]))<tolerance

func compare(actual: Variant, expected: Variant, label: String, errors: Array) -> void:
	if expected is Array:
		if not actual is Array or actual.size()!=expected.size():
			errors.append(label+" count")
			return
		for i in expected.size(): compare(actual[i],expected[i],label+"/"+str(i),errors)
		return
	if not actual is Node3D:
		errors.append(label+" missing node")
		return
	var q: Array = expected["q"]
	var scale: Array = expected["s"]
	var basis := Basis(Quaternion(q[0],q[1],q[2],q[3]))*Basis.from_scale(Vector3(scale[0],scale[1],scale[2]))
	if not near(actual.position,expected["p"]): errors.append(label+" position")
	if actual.basis.x.distance_to(basis.x)>.0002 or actual.basis.y.distance_to(basis.y)>.0002 or actual.basis.z.distance_to(basis.z)>.0002: errors.append(label+" rotation/scale")
	if actual.visible!=expected["visible"]: errors.append(label+" visibility")
	var figure_colors := []
	for figure: Node in actual.find_children("Figure_*","Node3D",true,false):
		for part: MeshInstance3D in figure.find_children("*","MeshInstance3D",true,false):
			figure_colors.append(part.material_override.vertex_color_use_as_albedo)
	if not same_json(figure_colors,expected["figureColors"]): errors.append(label+" figure vertex tint")
	if expected.has("alpha"):
		var material := actual.material_override as BaseMaterial3D
		if material==null or absf(material.albedo_color.a-float(expected["alpha"]))>.00001: errors.append(label+" alpha")
		if material!=null and (material.disable_fog==expected["fog"] or material.no_depth_test==expected["depthTest"]): errors.append(label+" fog/depth")
		if material!=null and expected.has("color"):
			var color := material.albedo_color.srgb_to_linear()
			if not near(Vector3(color.r,color.g,color.b),expected["color"],.00001): errors.append(label+" color")
	if expected.has("instances") and DisplayServer.get_name()!="headless":
		var mesh: MultiMesh = actual.multimesh
		if mesh.instance_count!=expected["instances"].size(): errors.append(label+" instance count")
		for i in mini(mesh.instance_count,expected["instances"].size()):
			var t := mesh.get_instance_transform(i)
			var e: Array = expected["instances"][i]
			if not near(t.basis.x,e.slice(0,3)) or not near(t.basis.y,e.slice(4,7)) or not near(t.basis.z,e.slice(8,11)) or not near(t.origin,e.slice(12,15)):
				errors.append(label+" instance "+str(i))
				break
	if expected.has("lamp"): compare(actual.get_meta("lamp"),expected["lamp"],label+"/lamp",errors)

func test_shapes() -> void:
	for key: String in original_data()["geometryChecks"]:
		var expected: Dictionary = original_data()["geometryChecks"][key]
		var shape := DeathGeometry.mesh(key)
		var box := shape.get_aabb()
		var arrays := shape.surface_get_arrays(0)
		check(near(box.position,expected["bounds"][0],.000001) and near(box.end,expected["bounds"][1],.000001),key+" retains the original partial geometry bounds")
		check(arrays[Mesh.ARRAY_VERTEX].size()==expected["vertices"] and arrays[Mesh.ARRAY_INDEX].size()==expected["triangles"]*3,key+" retains original vertices and triangles")

func test_frames() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/death-timelines/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.camera.position.y = original_data()["eye"]
	app.player.camera.rotation = Vector3.ZERO
	var saved := app.player.capture_pose().duplicate(true)
	var camera := app.player.camera.transform
	for sample: Dictionary in original_data()["cases"]:
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin(sample["kind"],app.player,app._campus_world(),app.ui,4.5,sample["shake"]==0)
		for frame: Dictionary in sample["frames"]:
			cg.update(frame["t"])
			var label := "%s shake=%s t=%s" % [sample["kind"],sample["shake"],frame["t"]]
			var errors := []
			for key: String in frame["props"]: compare(cg.d.get(key),frame["props"][key],key,errors)
			check(errors.is_empty(),label+" original props: "+str(errors.slice(0,6)))
			check(absf(cg.cam.rotation.x-float(frame["view"]["pitch"]))<.0001 and absf(cg.cam.rotation.y+float(frame["view"]["ang"]))<.0001 and absf(cg.cam.position.y-cg._base_y-float(frame["view"]["eyeLift"]))<.0001,label+" original camera")
			check(absf(cg.veil_mesh.material_override.albedo_color.a-float(frame["shade"]))<.00001,label+" original closing shade")
			var cued := cg._cued.keys()
			var original: Array = frame["cues"]
			cued.sort()
			original.sort()
			check(same_json(cued,original),label+" original one-shot cue timing")
		cg.finish()
		check(same_json(saved,app.player.capture_pose()) and app.player.camera.transform.is_equal_approx(camera),sample["kind"]+" leaves the saved player and camera unchanged")
		cg.queue_free()
		await _frames()
	for sample: Dictionary in original_data()["floors"]:
		var room := CampusData.layout("teach%d" % int(sample["floor"]))
		app.travel(room["id"],_campus_pose(room,CampusGeometry.tile_center(room,45,9),0),false)
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin("liftdoor",app.player,app._campus_world(),app.ui,4.5)
		var segments := []
		for child: Node in cg.F.get_children():
			if child is MeshInstance3D and child.material_override.albedo_color.to_html(false)=="ffb257": segments.append(child)
		var errors := []
		compare(segments,sample["segments"],"floor "+str(sample["floor"]),errors)
		check(errors.is_empty(),"lift floor display uses the actual scene: "+str(errors))
		cg.finish()
		cg.queue_free()
		await _frames()
	# Both normal and reduced-flash exits must restore their presentation ownership.
	app._campus_world().hide()
	var stopped := DeathCG.new()
	app.add_child(stopped)
	stopped.begin("shatter",app.player,app._campus_world(),app.ui,3.5)
	stopped.update(1.0)
	check(app.ui._cut_flash.visible,"fixture reaches the real impact flash before interruption")
	stopped.finish()
	check(not app.ui._cut_flash.visible and not app._campus_world().visible,"interrupting death removes its flash and preserves a previously hidden world")
	stopped.queue_free()
	await _frames()
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
