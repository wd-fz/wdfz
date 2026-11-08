extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/maze_death-reference.json.gz").decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func test_shapes() -> void:
	var comparison := preload("res://tests/suites/death_timelines.gd").new(_runner)
	for key: String in original_data()["geometryChecks"]:
		var expected: Dictionary = original_data()["geometryChecks"][key]
		var shape := DeathGeometry.mesh(key,MazeDeath.GEOMETRY)
		var box := shape.get_aabb()
		var arrays := shape.surface_get_arrays(0)
		# Godot expands a zero-thickness mesh AABB to 0.00001 m; actual vertices remain flat.
		check(comparison.near(box.position,expected["bounds"][0],.000011) and comparison.near(box.end,expected["bounds"][1],.000011),key+" original geometry bounds")
		check(arrays[Mesh.ARRAY_VERTEX].size()==expected["vertices"] and arrays[Mesh.ARRAY_INDEX].size()==expected["triangles"]*3,key+" original vertices and triangles")
		for sample: Dictionary in expected["samples"]:
			check(comparison.near(arrays[Mesh.ARRAY_VERTEX][sample["i"]],sample["p"],.000001),key+" source vertex "+str(sample["i"]))
			# The source stores signed normalized 8-bit normals; rendering normalizes their length.
			var expected_normal := Vector3(sample["n"][0],sample["n"][1],sample["n"][2]).normalized()
			check(arrays[Mesh.ARRAY_NORMAL][sample["i"]].distance_to(expected_normal)<.0002,key+" source normal direction "+str(sample["i"]))
			if sample.has("c"):
				var color: Color = arrays[Mesh.ARRAY_COLOR][sample["i"]]
				# Godot uploads vertex colors as normalized RGBA8; allow one encoded step.
				check(comparison.near(Vector3(color.r,color.g,color.b),sample["c"],.007),key+" original linear vertex color "+str(sample["i"]))

func test_frames() -> void:
	var original := original_data()
	var comparison := preload("res://tests/suites/death_timelines.gd").new(_runner)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/maze-death/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.global_position = Vector3(original["world"][0],0,original["world"][2])
	app.player.rotation.y = CampusGeometry.yaw_from_ang(0)
	app.player.camera.position.y = original["eye"]
	app.player.camera.rotation = Vector3.ZERO
	var saved := app.player.capture_pose().duplicate(true)
	var camera := app.player.camera.transform
	for sample: Dictionary in original["cases"]:
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin(sample["kind"],app.player,app._campus_world(),app.ui,3.6,sample["shake"]==0)
		for frame: Dictionary in sample["frames"]:
			cg.update(frame["t"])
			var label := "%s shake=%s t=%s" % [sample["kind"],sample["shake"],frame["t"]]
			var errors := []
			for key: String in frame["props"]: comparison.compare(cg.d.get(key),frame["props"][key],key,errors)
			check(errors.is_empty(),label+" original meshes and poses: "+str(errors.slice(0,8)))
			check(absf(cg.cam.rotation.x-float(frame["view"]["pitch"]))<.0001 and absf(cg.cam.rotation.y+float(frame["view"]["ang"]))<.0001 and absf(cg.cam.position.y-cg._base_y-float(frame["view"]["eyeLift"]))<.0001,label+" original camera")
			check(absf(cg.veil_mesh.material_override.albedo_color.a-float(frame["shade"]))<.00001,label+" original closing shade")
		cg.finish()
		check(same_json(saved,app.player.capture_pose()) and app.player.camera.transform.is_equal_approx(camera),sample["kind"]+" restores player pose and camera")
		check(app._campus_world().visible and not app.ui._cut_flash.visible,sample["kind"]+" restores world and clears flash")
		cg.queue_free()
		await _frames()
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
