extends "res://tests/support/test_suite.gd"

func original_frames() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/paper-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
func v3(p: Array) -> Vector3: return Vector3(p[0],p[1],p[2])

func test_original_frames() -> void:
	var old := original_frames()
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var view := PaperPlaneView.new()
	view.build()
	world.add_child(view)
	var geometry: Dictionary = old["geometry"]
	var arrays := view.plane.mesh.surface_get_arrays(0)
	for i in 6:
		check(arrays[Mesh.ARRAY_VERTEX][i].distance_to(v3(geometry["points"].slice(i*3,i*3+3)))<.00001 and arrays[Mesh.ARRAY_NORMAL][i].distance_to(v3(geometry["normals"].slice(i*3,i*3+3)))<.0001,"original folded triangle vertices and normals")
	for i in geometry["hand"].size():
		var part := view.hand.get_child(i) as MeshInstance3D
		var spec: Dictionary = geometry["hand"][i]
		check(part.position.distance_to(v3(spec["p"]))<.00001 and part.mesh.size.distance_to(v3(spec["size"]))<.00001 and part.material_override.albedo_color.is_equal_approx(Color(spec["color"])) and part.material_override.emission.is_equal_approx(Color(spec["emission"])),"original palm/finger geometry and material")
	var room: Dictionary = CampusData.rules().room(old["room"])
	var window := {"p":Vector2(old["window"]["x"],old["window"]["y"]),"nz":old["window"]["nz"]}
	for frame: Dictionary in old["frames"]:
		view.show_event(frame["e"],room,window,camera)
		var spec: Dictionary = frame["snapshot"]
		check(view.plane.visible==spec["plane"]["visible"] and view.hand.visible==spec["hand"]["visible"],"original visibility by phase")
		check(view.plane.position.distance_to(v3(spec["plane"]["p"]))<.00001 and view.plane.rotation.distance_to(v3(spec["plane"]["rotation"]))<.00001,"original arrival arc, roll, landing and flight attitude")
		check(view.hand.position.distance_to(v3(spec["hand"]["p"]))<.00001,"original hand stays at the window")
		if frame["e"]["phase"]=="flight":
			check(view.camera.position.distance_to(v3(spec["camera"]["p"]))<.00001 and (-view.camera.basis.z).distance_to(v3(spec["camera"]["direction"]))<.00001,"independent follow camera matches the original camera path")
	view.cancel_camera()
	check(camera.is_current(),"ending a flight restores the formal camera")
	world.queue_free()
	await _frames(2)
	for sample: Dictionary in old["solid"]:
		var r := room.duplicate(true)
		var rows: Array = r["grid"]
		rows[3] = String(rows[3]).substr(0,3)+String(sample["ch"])+String(rows[3]).substr(4)
		var plane := PaperPlaneModule.new({old["room"]:r})
		plane.reset()
		var event: Dictionary = old["frames"].back()["e"].duplicate(true)
		event["limit"] = 10
		event["f"] = {"x":r["ox"]+3.5*r["tw"],"y":r["oy"]+3.5*r["th"],"h":sample["height"],"yaw":0.0,"pitch":0.0,"clean":true}
		plane.s["ev"] = event
		plane.set_context({"scene":old["room"]})
		plane.tick(.000001)
		check((plane.phase()=="hunt")==sample["blocked"],"original low-flight tile collision: %s / %s" % [sample["ch"],sample["height"]])

func touch(control: Control, finger: int, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.pressed = down
	event.position = root.get_final_transform()*control.get_global_rect().get_center()
	Input.parse_input_event(event)
	await _frames(2)

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await _frames(2)

func seed_event(app: GameApp, spot: Dictionary, phase: String) -> void:
	var room: Dictionary = CampusData.rules().room(spot["room"])
	app.travel(spot["room"],_campus_pose(room,spot["stand"],spot["look"]),false)
	app.player.enabled = true
	var win: Dictionary = spot["w"]
	app.paper().s["ev"] = {"kind":"danger","room":spot["room"],"c":win["c"],"r":win["r"],"phase":phase,"t":0.0,"text":"原路送回。","lx":spot["stand"].x,"ly":spot["stand"].y,"limit":10.0,
		"f":{"x":spot["stand"].x,"y":spot["stand"].y,"h":1.45,"yaw":spot["look"],"pitch":0.0,"clean":true}}
	app.paper().set_context(app._paper_context())

func test_input_and_boundaries() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(960,540)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/paper/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(3)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.ui.set_touch_enabled(true)
	var spot := _paper_spot("danger")
	seed_event(app,spot,"wait")
	check(app.paper().use_here(),"actual paper pickup opens the reading event")
	app._apply_paper_events()
	app._show_plane(app.paper())
	await _frames(4)
	check(app.ui.choice_open() and app.ui._paper_progress.visible and is_equal_approx(app.ui._paper_progress.value,8) and not app.player.enabled,"paper reading shows its eight-second bar and locks movement")
	app._paper_step(2)
	check(is_equal_approx(app.ui._paper_progress.value,6),"reading deadline advances in real simulation seconds")
	await key(KEY_E,true)
	await key(KEY_E,false)
	check(app.paper().phase()=="aim" and not app.ui.choice_open() and app.player.enabled,"physical E folds once and releases reading controls")
	app.paper().set_context(app._paper_context())
	check(app.paper().use_here() and app.paper().phase()=="flight","formal throw starts the flight")
	var before := app.player.capture_pose().duplicate(true)
	app._show_plane(app.paper())
	await _frames(5)
	check(not app.player.enabled and app._plane_nodes.camera.is_current() and same_json(before,app.player.capture_pose()),"follow camera takes over without moving the saved player")
	check(root.get_visible_rect().encloses(app.ui._paper_pad.get_global_rect()) and app.ui._paper_pad.visible and not app.ui.touch_controls.visible,"landscape touch flight has four reachable buttons without movement overlays")
	await touch(app.ui._paper_pad.buttons["r"],8,true)
	await touch(app.ui._paper_pad.buttons["u"],9,true)
	var steer: Dictionary = app._paper_context()["steer"]
	check(steer["r"]==1 and steer["u"]==1 and steer["l"]==0,"two independent fingers steer and climb together")
	var f: Dictionary = app.paper().s["ev"]["f"]
	var old_yaw := float(f["yaw"])
	app._paper_step(.05)
	check(float(f["yaw"])>old_yaw and float(f["pitch"])>0 and same_json(before,app.player.capture_pose()),"actual flight responds while the physical body and save pose stay put")
	await touch(app.ui._paper_pad.buttons["r"],8,false)
	check(app._paper_context()["steer"]["r"]==0 and app._paper_context()["steer"]["u"]==1,"one release preserves the other finger")
	app.pause_game()
	check(not app.ui._paper_pad.visible and app.ui._paper_pad.fingers.is_empty(),"pausing clears held flight fingers")
	await touch(app.ui._paper_pad.buttons["u"],9,false)
	app.resume_game()
	check(not app.player.enabled and app.ui._paper_pad.visible,"resume retains plane input ownership")
	await touch(app.ui._paper_pad.buttons["l"],10,true)
	root.size = Vector2i(1200,540)
	await _frames(4)
	check(app.ui._paper_pad.fingers.is_empty() and root.get_visible_rect().encloses(app.ui._paper_pad.get_global_rect()),"wide landscape resize releases touch and keeps controls reachable")
	await touch(app.ui._paper_pad.buttons["l"],10,false)
	app.paper().fail("wall")
	app._apply_paper_events()
	app._show_plane(app.paper())
	await _frames(2)
	check(app.player.camera.is_current() and app.player.enabled and not app.ui._paper_pad.visible and same_json(before,app.player.capture_pose()),"failed flight restores camera and control without teleporting the body")
	seed_event(app,spot,"wait")
	app.paper().use_here()
	app._apply_paper_events()
	app._show_plane(app.paper())
	app._paper_step(8)
	check(app.paper().phase()=="hunt" and not app.ui.choice_open() and app.player.enabled,"reading timeout closes the paper and releases movement for the hunt")
	for boundary: String in ["travel","load","new","death","menu"]:
		seed_event(app,spot,"flight")
		app._show_plane(app.paper())
		match boundary:
			"travel": app.travel("teach1",CampusData.rules().default_spawn("teach1"),false)
			"load":
				app.save_game()
				app.load_game()
			"new": app.start_new_game("hard","none")
			"death": app.kill("reference","vignette","san")
			"menu": app.return_to_menu()
		await _frames(3)
		check(app._plane_nodes==null and not app.ui._paper_flying and not app._plane_input_owned,"boundary clears plane camera, fingers and ownership: "+boundary)
		if boundary in ["new","load"]: check(app.player.camera.is_current(),"replacement run owns the formal camera")
		if boundary=="death": app.return_to_menu();app.start_new_game("hard","none")
	app.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale
