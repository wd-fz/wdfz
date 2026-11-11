extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/secret_items-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _knife_state(d: Dictionary) -> Dictionary:
	var out:=d.duplicate(true)
	for key in ["took","held","done"]: out[key]=bool(out[key])
	if out["cap"]==null: out["cap"]={}
	return out


func test_reference() -> void:
	var reference:=_reference()
	for spec: Dictionary in reference["near"]:
		var knife:=KnifeModule.new()
		knife.took=spec["took"]
		var r:=CampusData.layout(spec["scene"])
		var p:=CampusGeometry.tile_center(r,6,1)+Vector2(spec["offset"][0]*r["tw"],spec["offset"][1]*r["th"])
		check(knife.near(spec["scene"],r,p)==spec["near"],"knife pickup radius and one-per-run match the original: %s" % spec)
	for spec: Dictionary in reference["knife"]:
		var knife:=KnifeModule.new()
		knife.took=true
		knife.held=spec.get("held",false)
		knife.done=spec.get("done",false)
		var has_knife: bool=not spec.get("missing",false)
		var caught:=knife.catch_player(has_knife,"caught")
		check(caught==spec["caught"],"original catch interception: "+spec["id"])
		var dead:=not caught
		var deaths:=[] if caught else [{"text":"caught","fx":"grip","source":"patrol"}]
		var ends:=[]
		for s: Dictionary in spec["steps"]:
			var action: Array=s["action"]
			if action[0]=="tick": knife.tick(action[1],dead)
			elif action[0] in ["bag","hot"] and not dead: knife.use(has_knife,action[0])
			for event: Dictionary in knife.take_events():
				match event["kind"]:
					"remove": has_knife=false
					"ending": ends.append(event["id"])
					"kill":
						dead=true
						deaths.append({"text":event["text"],"fx":event["fx"],"source":event["source"]})
			check(same_json(knife.capture(),_knife_state(s["state"])) and has_knife==s["has"] and dead==s["dead"] and same_json(deaths,s["deaths"]) and same_json(ends,s["ends"]),"original one-second window %s: %s" % [spec["id"],action])
	for spec: Dictionary in reference["gifts"]:
		var gift:=WudaKidModule.new()
		check(gift.start(spec["armed"],spec["roll"],spec["speedrun"])==spec["picked"],"gift chance / armed / speedrun match original: %s" % spec)
		check(gift.tick(5.9)=="" and gift.on==spec["before"]["on"] and gift.told==spec["before"]["told"],"no announcement during the first 5.9 seconds")
		var line:=gift.tick(.11)
		check((line==WudaKidModule.LINE)==(spec["lines"].size()==1) and gift.tick(9)=="","gift notice occurs once after six effective seconds")
	var taps:=[]
	var armed:=false
	for s: Dictionary in reference["taps"]:
		var changed:=WudaKidModule.tap(taps,s["ms"])
		if changed: armed=not armed
		check(changed==(s["result"]!=null) and armed==s["armed"],"three taps use the original strict 1600 ms boundary at %s" % s["ms"])
	for s: Dictionary in reference["frames"]:
		var f:=KnifeScene.frame(s["k"])
		var look: Array=s["view"]
		var same: bool=f["stage"]==s["stage"] and absf(f["fade"]-s["fade"])<.00001
		same=same and f["from"].distance_to(Vector3(look[0],look[1],look[2]))<.00001 and f["to"].distance_to(Vector3(look[3],look[4],look[5]))<.00001
		for key in ["blade_y","hand_y","form_x","stamp_y"]:
			if f.has(key): same=same and absf(f[key]-s[key])<.00001
		check(same,"original knife cinematic stage, camera, prop and fade at %.4f" % s["k"])
	var ach:=AchievementsModule.new()
	ach.reset()
	var pts:=ach.points()
	check(ach.fact({"kind":"ending","id":"knife","fake":true}).has("h.knife") and ach.points()==pts,"fake ending reveals its archive achievement without awarding clear points")
	check(RoutesModule.card("knife")["fake"] and not Speedrun.ROUTES.has("knife"),"fake ending is not a successful speedrun route")
	CampusData.clear_caches()


func test_save() -> void:
	var converter:=preload("res://tests/suites/legacy.gd").new(_runner)
	for spec: Dictionary in _reference()["saves"]:
		var session:=SessionFactory.create()
		var result: Dictionary=converter._convert(spec["save"],session)
		check(result["error"]=="","old hidden-item save converts: "+String(result["error"]))
		if result["error"]!="": continue
		check(session.validate(result["snapshot"],PackedStringArray(CampusData.rooms().keys()+["out"])).is_empty(),"converted capture / starting gift validates atomically")
		session.restore(result["snapshot"])
		var knife: KnifeModule=session.modules.get_module(&"story.knife")
		var kid: WudaKidModule=session.modules.get_module(&"story.wuda_kid")
		if spec["kind"]=="capture":
			check(same_json(knife.capture(),_knife_state(spec["save"]["rt"]["knife"])) and knife.captured(),"old capture preserves equip order and remaining fraction of one second")
		else:
			check(kid.on and kid.told and kid.via=="menu","old gift uses saved acquisition instead of rerolling")
		var store:=SaveStore.new(_test_path.get_base_dir()+"/secret-items/slot.json")
		check(store.write(session.capture(result["snapshot"]["player"])).is_empty(),"hidden item state writes to native save")
		var restored:=SessionFactory.create()
		restored.restore(store.read()["data"])
		check(same_json(restored.modules.get_module(&"story.knife").capture(),knife.capture()) and same_json(restored.modules.get_module(&"story.wuda_kid").capture(),kid.capture()),"native JSON preserves both hidden modules")
	var knife:=KnifeModule.new()
	knife.catch_player(true,"caught")
	var broken:=knife.capture()
	broken["cap"]["equip"]=.5
	check(not knife.validate(broken).is_empty(),"future equip time cannot enter a loaded run")
	broken["cap"]["t"]=NAN
	check(not knife.validate(broken).is_empty(),"non-finite capture timer rejected")
	CampusData.clear_caches()


func _quiet(app: GameApp) -> void:
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.school().tsec=900
	app.patrol().pat["next"]=10000.0
	app.anomaly().an["next"]=10000.0


func _use_button(app: GameApp) -> void:
	app.ui.select_bag_item("small_knife")
	var button: Button=app.ui.bag_panel.find_child("Item_small_knife_-1",true,false)
	check(button!=null,"captured player has a real bag-use button")
	if button!=null: button.pressed.emit()


func _school_touch(app: GameApp) -> void:
	var label: Control=app.ui.get_node("%SchoolName")
	var p:=root.get_final_transform()*label.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=0
		event.position=p
		event.pressed=down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/secret-items-app/save.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/secret-items-app/settings.json")
	app.wuda_roll=func() -> float: return .99
	root.add_child(app)
	await _frames(2)
	# Real touch dispatch, including the emulated-mouse guard: two taps are insufficient.
	_school_touch(app)
	_school_touch(app)
	check(not app.settings.wuda_armed,"two menu touches do not unlock the additive gift")
	_school_touch(app)
	check(app.settings.wuda_armed,"three menu touches toggle the hidden setting")
	var disk:=GameSettings.new(app.settings.path)
	disk.load_file()
	check(disk.wuda_armed,"the menu switch persists in the actual settings file")
	app.start_new_game("hard","night")
	_quiet(app)
	check(app.talent().id=="night" and app.wuda_kid().on and app.items().has("torch") and app.items().hot[0]=="torch","starting gift adds a flashlight without replacing the selected talent")
	check(app.wuda_kid().tick(6)==WudaKidModule.LINE and app.wuda_kid().tick(6)=="","notice belongs to this run and is not repeated")
	app.save_game()
	app.settings.wuda_armed=false
	app.load_game()
	_quiet(app)
	check(app.wuda_kid().on and app.wuda_kid().told and app.items().bag.count("torch")==1,"loading retains the gift with no second flashlight or notice")
	app._stand_up()
	var room:=CampusData.layout("gear1")
	app.travel("gear1",_campus_pose(room,CampusGeometry.tile_center(room,6,1),0),false)
	check(app.knife_flow.hint()=="旧工具抽屉","real room interaction finds the fixed drawer")
	app._campus_interact()
	check(app.items().has("small_knife") and app.knife().took and app.knife_flow.hint()=="","pickup yields exactly one knife")
	app.items().add("coin")
	app.school().day=2
	check(app.knife_flow.catch_player("caught") and not app.player.enabled,"capture blocks body input instead of immediately killing")
	app._open_manual()
	check(app.ui.bag_open() and not paused,"mobile manual opens the usable bag while the world keeps running")
	app.knife_flow.step(.3)
	_use_button(app)
	check(app.knife().held and app.knife().cap["equip"]==.3 and app.ui.bag_open(),"first bag press equips without closing the window")
	app.save_game()
	app.load_game()
	_quiet(app)
	check(app.knife_flow.captured() and not app.player.enabled and app.knife().cap["equip"]==.3,"loading an active capture restores its body-input lock")
	app._open_bag()
	app.knife_flow.step(.3)
	var pose:=app.player.capture_pose()
	_use_button(app)
	await _frames(2)
	check(app.story().ended=="knife" and app.knife().done and not app.items().has("small_knife") and app.saves.exists(),"second bag press reaches the fake ending while retaining the save slot")
	if DisplayServer.get_name()!="headless":
		check(is_instance_valid(app._ending_cut) and app._ending_cut.kind=="knife","native fake ending plays its sixteen-second cinematic")
		var props: KnifeScene=app._ending_cut._knife
		for mesh: Node in props.stages[1].find_children("*","MeshInstance3D",true,false):
			check((mesh as MeshInstance3D).material_override.disable_fog,"staged knife props do not inherit the campus fog")
		for k in [.1,.3,.55,.85]:
			app._ending_cut._apply(k)
			await _frames(1)
		check(same_json(pose,app.player.capture_pose()),"four cinematic stages cannot mutate the player pose")
		await _skip_cut(app)
	check(app.ui.ending_panel.visible and app.ui._ending_wake.visible and app._last_result.is_empty(),"fake ending offers wake and cannot submit a successful score")
	var original_size:=root.size
	root.size=Vector2i(390,844)
	await _frames(3)
	var bounds:=app.ui.get_viewport().get_visible_rect()
	check(bounds.encloses(app.ui.ending_panel.get_global_rect()),"portrait ending card stays within the viewport and scrolls its longer text")
	await _frames(2)
	check(bounds.encloses(app.ui._ending_wake.get_global_rect()) and not app.ui._ending_scroll.is_ancestor_of(app.ui._ending_wake),"wake button remains reachable outside the scrolling ending text")
	root.size=original_size
	await _frames(2)
	app.ui._ending_wake.pressed.emit()
	check(app.story().ended=="" and app.school().day==3 and app.school().tsec==441 and app.session.world_id=="teach1" and app.player.seated,"wake returns to the own seat on the following morning")
	check(app.items().has("coin") and app.items().has("torch") and app.knife().done and not app.patrol().local_threat(),"waking retains other items and clears the capturing patrol")
	check(app.school().pressure_clock>=app.school().game_clock() and app.saves.exists(),"wake immediately records the next-day pressure and saves")
	app.load_game()
	_quiet(app)
	check(app.knife().done and app.school().day==3 and not app.items().has("small_knife"),"wake save cannot return the confiscated item")
	app.return_to_menu()
	app.speedrun.arm("hard")
	app.settings.wuda_armed=true
	app.start_new_game("hard","code")
	app._opening_done(false)
	_quiet(app)
	check(not app.wuda_kid().on and not app.items().has("torch"),"speedrun excludes even the manually enabled starting gift")
	app.items().add("small_knife")
	app.knife_flow.catch_player("caught")
	app.knife_flow.use("small_knife")
	app.knife_flow.use("small_knife")
	if DisplayServer.get_name()!="headless": await _skip_cut(app)
	check(app.speedrun.run["status"]=="running","fake ending keeps the speedrun alive")
	app.knife_flow.wake()
	check(app.speedrun.run["status"]=="running" and app.story().ended=="","wake continues the same speedrun")
	app.return_to_menu()
	app.speedrun.disarm()
	app.settings.wuda_armed=false
	app.start_new_game("hard","immune")
	_quiet(app)
	check(not app.knife().done and not app.wuda_kid().on,"new run resets hidden progress")
	app.items().add("small_knife")
	app.items().set_hot(0,"small_knife")
	app.knife_flow.catch_player("caught")
	app._touch_hot(0)
	app._touch_hot(0)
	check(app.knife_flow.captured() and app.story().ended=="","two mobile hotbar presses cannot pass the bag-only requirement")
	app.knife_flow.step(1.01)
	check(not app.story().dead and not app.knife_flow.captured() and app.player.enabled and app.talent().consumed.get("fatalProtection",false),"fatal protection on timeout returns body control once")
	app.knife().held=false
	app.knife_flow.catch_player("caught again")
	app.knife_flow.step(1.01)
	check(app.story().dead and app.story().death_source=="patrol","second timeout uses the real patrol death path")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
