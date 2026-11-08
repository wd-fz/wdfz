extends "res://tests/support/test_suite.gd"

func fixture() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/archive-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func ids(entries: Array) -> Array: return entries.map(func(e: Dictionary) -> String: return e["id"])

func test_reference() -> void:
	var original := fixture()
	var rules := ArchiveRules.new(CampusData.archive())
	for sample: Dictionary in original["migrations"]:
		rules.restore(null)
		rules.migrate(sample["log"])
		check(same_json(rules.state,sample["state"]),"original once-only archive migration")
		check(same_json(ids(rules.visible("deaths")),sample["visible"]),"original secret death visibility")
		var snapshot := rules.state.duplicate(true)
		rules.migrate({"sources":{"san":100},"counts":{"san":100}})
		check(same_json(rules.state,snapshot),"later debug logs never reimport")
	for sample: Dictionary in original["deaths"]:
		rules.restore(null)
		rules.migrate({})
		var first := rules.record(sample["source"],sample["fx"],sample["debug"],sample["replay"],sample["ctx"],123456)
		var second := rules.record(sample["source"],sample["fx"],sample["debug"],sample["replay"],sample["ctx"],123456)
		check(first == str(sample["first"] if sample["first"] != null else "") and second == str(sample["second"] if sample["second"] != null else "") and same_json(rules.state,sample["state"]),"original real/developer/replay archive record "+str(sample["source"]))
	rules.restore(null)
	rules.migrate({})
	check(same_json(ids(rules.visible("deaths")),original["before"]["deaths"]) and same_json(ids(rules.visible("cuts")),original["before"]["cuts"]),"original unopened archive list")
	check(not rules.mark_seen("cut:void_in",true) and rules.mark_seen("cut:void_in") and not rules.mark_seen("cut:void_in"),"maze cut marks once only outside replay")
	check(same_json(rules.state,original["seen"]) and same_json(rules.locked(original["ends"],original["opening"]),original["locked"]),"original seen and locked sets")
	rules.grant(rules.locked())
	check(rules.state["unlocked"].is_empty() and rules.state["count"].is_empty() and rules.locked().is_empty(),"direct unlock never fabricates a death, first timestamp or ending")
	var raw := rules.state.duplicate(true)
	raw["unlocked"]["unknown"] = true
	raw["granted"]["x.bad key"] = 1
	raw["granted"]["x.valid-rule"] = 1
	raw["seen"]["end:car"] = 1
	rules.restore(raw)
	check(not rules.state["unlocked"].has("unknown") and not rules.state["granted"].has("x.bad key") and rules.state["granted"].has("x.valid-rule") and not rules.state["seen"].has("end:car"),"unknown record IDs are discarded without remapping")

func files(dir: String) -> Dictionary:
	var out := {}
	for file: String in DirAccess.get_files_at(dir): out[file] = FileAccess.get_file_as_bytes(dir.path_join(file))
	for child: String in DirAccess.get_directories_at(dir): out[child] = files(dir.path_join(child))
	return out

func test_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/archive/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/archive-settings.json")
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	var flow := app.archive_flow
	app.items().add("elixir")
	app.kill("protected","grip","patrol")
	check(not app.story().dead and flow.rules.state["unlocked"].is_empty(),"protection runs before archive record")
	app.kill("real","grip","patrol")
	check(flow.rules.state["count"].get("patrol",0) == 1,"real death records its source, not generic grip effect")
	app.debug_flow.revive()
	app._toggle_debug()
	app.kill("debug","vignette","san")
	check(not flow.rules.state["unlocked"].has("san"),"visible developer panel blocks actual death archive")
	app.debug_flow.revive()
	app.debug_panel.dismiss()
	app.kill("real after panel","vignette","san")
	check(flow.rules.state["count"].get("san",0) == 1 and not app.runscore().trusted,"archive experiences follow original current-context rule separately from sticky achievement trust")
	app.debug_flow.revive()
	app.save_game()
	app.return_to_menu()
	flow.open()
	await _frames(4)
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(app.ui.ach_panel.get_global_rect()),"first archive opening is inside the viewport after layout")
	check(not flow.play("cut:opening") and not flow.play("end:face"),"unseen opening and ending cannot be replayed")
	var real: Dictionary = flow.rules.state["unlocked"].duplicate(true)
	flow.unlock_all()
	check(same_json(real,flow.rules.state["unlocked"]) and app._read_side("ends.json") == null,"unlock-all cannot invent played deaths or completed endings")
	var original_files := files(app.saves.path.get_base_dir())
	var original_pose := app.player.capture_pose().duplicate(true)
	var original_audio := app.audio._rng.state
	var list := flow.rules.entries.values()
	list.append(ArchiveFlow.KNOCK)
	for entry: Dictionary in list:
		print("ARCHIVE: ",entry["id"])
		check(flow.play(entry["id"]),"unlocked entry starts: "+String(entry["id"]))
		if not flow.active(): continue
		var stage := flow.stage
		stage.set_process(false)
		if is_instance_valid(stage.cut): stage.cut.set_process(false)
		check(app.session == null and app.router.world_instance() == null and stage.player != app.player,"isolated archive world and player: "+String(entry["id"]))
		if stage.death != null:
			for t: float in [.2,.55,.85]: stage.death.update(stage.duration*t)
		elif stage.cut is MazeCut:
			for k: float in [.2,.5,.85]: stage.cut.apply_frame(k)
		else:
			for _i in 3: stage.cut.tick(1.0)
		await _frames(2)
		flow.stop(true)
		await _frames(2)
		check(not flow.active() and app.ui.menu.visible and app.ui.ach_panel.visible and same_json(app.player.capture_pose(),original_pose),"every replay exit restores menu without touching live camera: "+String(entry["id"]))
		check(files(app.saves.path.get_base_dir()) == original_files and app.audio._rng.state == original_audio,"replay leaves every side file, slot and gameplay audio RNG unchanged: "+String(entry["id"]))
	flow.open("结算")
	for grade: Dictionary in ScoreRules.GRADES:
		var id := "x.grade."+String(grade["g"])
		check(flow.play(id),"directly granted grade preview opens "+id)
		check(app.ui.results_panel.current["source"]=="archive" and app.ui.results_panel.current["grade"]==grade["g"],"unearned grade uses isolated sample "+id)
		app.ui.results_panel.back_pressed.emit()
		check(not flow.active() and app.ui.ach_panel.visible,"grade back button restores archive")
		check(not app.ui.results_panel.hero.is_processing(),"closing a grade cancels its delayed reveal sound")
	check(files(app.saves.path.get_base_dir())==original_files,"grade previews never add a clear, grade or replay record")
	var earned := ScoreRules.sample_meta("A","face")
	earned["source"]="play"
	var real_id := app.runs().add(earned)
	check(flow.play("x.grade.A") and app.ui.results_panel.current["id"]==real_id,"earned grade opens the real best clear rather than a sample")
	app.ui.results_panel.back_pressed.emit()
	flow.open("死亡")
	check(flow.play("patrol"),"replay starts for skip lifecycle")
	flow.stage.elapsed = .5
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	key.pressed = false
	Input.parse_input_event(key)
	check(not flow.active() and app.ui.ach_panel.visible,"actual Escape stops replay and reopens archive")
	flow.play("cut:void_out")
	var stage := flow.stage
	app.start_new_game("hard","none")
	await _frames(2)
	check(not flow.active() and not is_instance_valid(stage) and app.session != null and app.session.world_id == "teach1","new game cancels an unfinished exit without applying its transfer")
	flow.open()
	check(not flow.play("patrol"),"live run cannot be replaced by archive replay")
	app.return_to_menu()
	flow.open("结算")
	flow.play("x.grade.SSS")
	app.return_to_menu()
	check(not flow.active() and not app.ui.results_panel.visible,"menu/new-session boundary clears archive grade page")
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
