extends "res://tests/support/test_suite.gd"

func test_original_layout() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/cyber-reference.json.gz")
	var original: Dictionary = JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var font_size := RegEx.new()
	font_size.compile("([0-9]+)px")
	for sample: Dictionary in original["samples"]:
		var monitor := EndingCut.cy_monitor(sample["aspect"])
		check(monitor["portrait"] == sample["portrait"] and absf(monitor["w"]-sample["screen"]["w"])<.00001 and absf(monitor["h"]-sample["screen"]["h"])<.00001 and absf(monitor["y"]-sample["screen"]["y"])<.00001,"original monitor orientation, size and height")
		var shot := EndingCut.cy_archive_camera(sample["t"],sample["aspect"],sample["fov"],monitor)
		var v: Array = sample["view"]
		check(shot["eye"].distance_to(Vector3(v[0],v[1],v[2]))<.00001 and shot["target"].distance_to(Vector3(v[3],v[4],v[5]))<.00001,"original camera fitting at aspect %s / FOV %s / time %s" % [sample["aspect"],sample["fov"],sample["t"]])
		var widths := {}
		for op: Dictionary in sample["ops"]:
			if op["kind"] == "text": widths[op["text"]] = op["width"]
		var measure := func(text: String,_fs: int) -> float: return widths.get(text,0)
		var ops := CutScreen.archive_ops(Vector2i(sample["size"][0],sample["size"][1]),sample["portrait"],CutScreen.arch_state(sample["t"]),measure)
		check(ops.size()==sample["ops"].size(),"all original archive text and red boxes appear at the right time")
		for i in mini(ops.size(),sample["ops"].size()):
			var actual: Dictionary = ops[i]
			var expected: Dictionary = sample["ops"][i]
			check(actual["kind"]==expected["kind"] and actual["color"].is_equal_approx(Color(expected["color"])),"original operation order and colour")
			if actual["kind"]!=expected["kind"]: continue
			if actual["kind"]=="text":
				check(actual["text"]==expected["text"] and actual["pos"].distance_to(Vector2(expected["x"],expected["y"]))<.0001 and actual["size"]==int(font_size.search(expected["font"]).get_string(1)) and actual["bold"]==String(expected["font"]).contains("bold"),"original archive typography and layout: "+String(expected["text"]))
			else:
				var r: Array = expected["rect"]
				var rect: Rect2 = actual["rect"]
				check(rect.position.distance_to(Vector2(r[0],r[1]))<.0001 and rect.size.distance_to(Vector2(r[2],r[3]))<.0001 and absf(actual["line"]-expected["line"])<.0001,"original contradiction outline geometry")

func test_stage() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/cyber-screen/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	var before := app.session.capture(app.player.capture_pose()).duplicate(true)
	# The maintained display target is landscape, including laptop and wide-phone ratios.
	for extent: Vector2i in [Vector2i(960,540),Vector2i(960,600),Vector2i(1200,540)]:
		root.size = extent
		await _frames(4)
		var cut := EndingCut.new()
		app.add_child(cut)
		cut.begin("cyber",app._campus_world(),CampusData.campus(),app.player,app.ui)
		cut.set_process(false)
		cut._apply(10.8/16)
		await _frames(3)
		var vertical := extent.x<float(extent.y)*.8
		check(not vertical and not cut._arch.portrait and cut._arch.size==Vector2i(1280,768),"real landscape stage uses the original archive canvas")
		var monitor: Dictionary = cut._cy_monitor
		var centre := Vector3(80,monitor["y"],-.75+.019)
		var p0 := cut.cam.unproject_position(centre+Vector3(-monitor["w"]*.5,monitor["h"]*.5,0))
		var p1 := cut.cam.unproject_position(centre+Vector3(monitor["w"]*.5,-monitor["h"]*.5,0))
		var screen := cut.cam.get_viewport().get_visible_rect().size
		var fraction := maxf(absf(p1.x-p0.x)/screen.x,absf(p1.y-p0.y)/screen.y)
		check(fraction>.70 and fraction<.80,"camera makes the archive readable while retaining its frame at each maintained landscape ratio")
		cut.cancel()
		cut.queue_free()
		await _frames(3)
		check(same_json(before,app.session.capture(app.player.capture_pose())) and app._campus_world().visible,"cut exit restores the formal camera/world and leaves the run unchanged")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	root.size = old_size
	root.content_scale_size = old_scale
