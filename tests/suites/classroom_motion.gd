extends "res://tests/support/test_suite.gd"


func test_material_lifecycle() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.current = true
	for cycle in 12:
		var view := ClassmatesView.new()
		root.add_child(view)
		view.build(CampusData.layout("teach1"), [Vector2i(8, 8), Vector2i(9, 8)])
		var shared := view._material
		for data: Dictionary in view.figures:
			(data["node"] as Node3D).position = Vector3.ZERO
		view.set_normal(true)
		for data: Dictionary in view.figures: view._pose(data, "person")
		await _frames(1)
		var meshes := view.find_children("*", "MeshInstance3D", true, false)
		check(shared != null and meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.material_override == shared)
			and shared.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "rebuilt classroom poses retain the live shared material %d" % cycle)
		view.set_normal(false)
		for data: Dictionary in view.figures: view._pose(data, "sit")
		await _frames(1)
		check(shared.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and shared.albedo_color == Color("080b0d"), "new poses preserve the dark classroom tint %d" % cycle)
		view.queue_free()
		await _frames(2)
	camera.queue_free()
	await _frames(2)

func fixture() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/classmates-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func compare(view: ClassmatesView, sample: Array, label: String) -> void:
	check(view.figures.size()==sample.size(),label+" figure count including teacher")
	var mismatch := ""
	for i in mini(view.figures.size(),sample.size()):
		var d: Dictionary = view.figures[i]
		var figure: Node3D = d["node"]
		var ref: Dictionary = sample[i]
		var expected := Vector3(ref["p"][0],ref["p"][1],ref["p"][2])
		if figure.position.distance_to(expected)>.0003 or absf(wrapf(figure.rotation.y-float(ref["yaw"]),-PI,PI))>.0003 or d["kind"]!=ref["kind"] or figure.visible!=ref["visible"] or absf(float(d["standing"])-float(ref["standing"]))>.00001:
			mismatch = "%s figure %d: %s / %s, yaw %f / %f, pose %s / %s" % [label,i,figure.position,expected,figure.rotation.y,ref["yaw"],d["kind"],ref["kind"]]
			break
	check(mismatch.is_empty(),mismatch)

func test_original_motion() -> void:
	var source := fixture()
	var mates := ClassmatesModule.new(CampusData.rooms())
	mates.set_seed(source["seed"])
	var room: Dictionary = CampusData.rules().room("teach1")
	var player := Vector2(source["player"][0],source["player"][1])
	for scenario: Dictionary in source["frames"]:
		var view := ClassmatesView.new()
		root.add_child(view)
		view.build(room,mates.layout("teach1")["seats"])
		compare(view,scenario["initial"],"initial original chairs")
		# Navigation tie-breaking is engine-specific. Feed the original path here to
		# isolate the frame integrator; actual native navigation is exercised below.
		if scenario["context"].get("bell",false):
			for i in view.figures.size():
				view.figures[i]["path"] = scenario["frames"][0]["figures"][i]["path"]
		mates.reset()
		var frame := 0
		for sample: Dictionary in scenario["frames"]:
			while frame<int(sample["frame"]):
				var context: Dictionary = scenario["context"]
				if frame>=90 and context.has("after"): context = context["after"]
				mates.tick("teach1",player,context["viol"],false)
				view.advance(1.0/60,player,context["viol"],mates.state.get("door"),context.get("stare",false),context.get("bell",false),null)
				frame += 1
			compare(view,sample["figures"],"original %s frame %d" % [scenario["context"],frame])
		view.queue_free()
		await _frames(2)

func test_departure_navigation() -> void:
	var nav := CampusData.patrol_nav()
	var mates := ClassmatesModule.new(CampusData.rooms())
	mates.set_seed("classroom-reference")
	for floor_i in range(1,6):
		var id := "teach%d" % floor_i
		var room: Dictionary = CampusData.rules().room(id)
		var view := ClassmatesView.new()
		root.add_child(view)
		view.build(room,mates.layout(id)["seats"])
		var snapshot := mates.capture().duplicate(true)
		for _i in 3600: view.advance(1.0/60,Vector2.ZERO,0,null,false,true,nav)
		var arrived := true
		for d: Dictionary in view.figures:
			if d["teacher"]: continue
			arrived = arrived and not (d["node"] as Node3D).visible and d["path"] != null and not (d["path"] as Array).is_empty()
		check(arrived,"all students follow native paths to the stairs on "+id)
		view.advance(0,Vector2.ZERO,0,null,false,false,nav)
		var restored := true
		for d: Dictionary in view.figures:
			var f: Node3D = d["node"]
			restored = restored and f.visible and Vector2(f.position.x,f.position.z).is_equal_approx(d["home"]) and d["kind"]==("teacher" if d["teacher"] else "sit")
		check(restored and same_json(snapshot,mates.capture()),"bell cancellation restores chairs without changing saved occupancy")
		view.queue_free()
		await _frames(2)

func test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/classroom/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/classroom-settings.json")
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none","xu")
	app.set_physics_process(false)
	app.set_process(false)
	app.player.set_physics_process(false)
	if DisplayServer.get_name() != "headless":
		app._play_opening()
		check(is_instance_valid(app._mates_nodes) and app._opening_cut._mates.size()==app.classmates().layout("teach1")["seats"].size(),"real new-game opening builds its classmates before taking camera ownership")
		check(app._opening_cut._me.character=="xu" and app._opening_cut._teacher.character=="teacher","opening uses the selected student and a separate faculty model")
		app._opening_cut.end(true)
		await _frames(2)
		app.player.set_physics_process(false)
	app._classmates_step(0)
	check(is_instance_valid(app._mates_nodes.teacher),"own classroom keeps the original teacher")
	var view := app._mates_nodes
	app.school().viol = 75
	for _i in 90: app._classmates_step(1.0/60)
	check(view.figures[0]["kind"]=="person","real rule state drives standing figures")
	var before := app.session.capture(app.player.capture_pose()).duplicate(true)
	var cut := OpeningCut.new()
	app.add_child(cut)
	cut.begin(app._campus_world(),CampusData.rules().room("teach1"),app.player,app.ui,false,app.session.character_id)
	cut.set_process(false)
	var material: StandardMaterial3D = (view.figures[0]["node"] as Node3D).find_children("*","MeshInstance3D",true,false)[0].material_override
	check(material.albedo_color == Color("5d6873") and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,"opening figures use the original lit normal material")
	check(view.normal and not view.teacher.visible,"full opening uses normal classmates and only one teacher")
	check(cut._me.character=="xu" and cut._me.clip=="sit" and cut._teacher.animation.has_animation("read"),"opening actors are dressed and posed for this run")
	cut._apply(.75)
	check(not cut._me.visible,"the cinematic body is gone before first-person handover")
	check(material.albedo_color == Color("080b0d") and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,"the flip changes actual figure materials")
	check(not view.normal,"opening flips classmates to the original dark silhouette")
	cut.cancel()
	check(view.teacher.visible and not view.normal and same_json(before,app.session.capture(app.player.capture_pose())),"opening cancellation restores figures without changing the run")
	cut.queue_free()
	app.return_to_menu()
	check(not is_instance_valid(app._mates_nodes),"menu releases classroom presentation")
	# The outdoor crowd uses the real outdoor physics for the old side-line fallback.
	app.start_new_game("hard","none")
	app.travel("out",{"position":[158,0,180],"yaw":0,"pitch":0},false)
	await _frames(3)
	var crowd := DepartingCrowd.new()
	app._campus_world().add_child(crowd)
	for sample: Dictionary in fixture()["crowd"]:
		crowd.update(sample["p"])
		var equal := true
		for i in crowd.people.size():
			var ref: Dictionary = sample["figures"][i]
			var p := Vector3(ref["p"][0],ref["p"][1],ref["p"][2])
			equal = equal and crowd.people[i].position.distance_to(p)<.0001 and absf(wrapf(crowd.people[i].rotation.y-float(ref["yaw"]),-PI,PI))<.0001
		check(equal,"original sixteen students, spacing, collision fallback, bob and facing at "+str(sample["p"]["left"]))
	app.queue_free()
	await _frames(3)
