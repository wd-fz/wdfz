extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/routes-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _v(a: Array, offset: int = 0) -> Vector3:
	return Vector3(a[offset],a[offset+1],a[offset+2])


func test_beast_reference() -> void:
	var reference := _reference()
	for sample: Dictionary in reference["offers"]:
		var routes := RoutesModule.new(CampusData.campus())
		routes.reset()
		var r := CampusData.layout(sample["room"])
		var w := CampusGeometry.tile_center(r,int(sample["cell"][0]),int(sample["cell"][1]))
		var got := routes.offer_item(r,w,sample["t"],1)
		check(got==sample["unlocked"] and routes.beast_drop==got,
			"offering matches original dropSelected: %s %s at %.8f" % [sample["room"],sample["cell"],sample["t"]])
		if got:
			check(not routes.offer_item(r,w,sample["t"],1) and _of_kind(routes.take_events(),"save").size()==1,"an offering unlocks and autosaves only once")
	for sample: Dictionary in reference["frames"]:
		var frame := BeastScene.frame(sample["k"],CampusData.layout("teach1"),sample["shake"])
		check((frame["figure"] as Vector3).distance_to(_v(sample["figure"]))<.0001 and
			(frame["from"] as Vector3).distance_to(_v(sample["view"]))<.0001 and
			(frame["to"] as Vector3).distance_to(_v(sample["view"],3))<.0001 and
			frame["visible"]==sample["visible"] and absf(frame["light"]-sample["light"])<.0001 and
			absf(frame["normal"]-sample["normal"])<.0001 and absf(frame["fade"]-sample["fade"])<.0001,
			"beast camera, figure, light and fades match the original frame %.5f / shake %s" % [sample["k"],sample["shake"]])
	var ach := AchievementsModule.new()
	ach.reset()
	check(ach.entries().filter(func(e: Dictionary) -> bool: return e["id"].begins_with("h.")).is_empty(),"undiscovered achievements stay hidden")
	check(ach.fact({"kind":"ending","id":"beast"}).has("h.beast") and ach.entries()[0]["unlocked"],"reaching the secret ending reveals its achievement")
	check(ach.fact({"kind":"speedrun","status":"finished","route":"beast"}).has("h.beast_run"),"the secret speedrun unlocks its own achievement")
	var sr := Speedrun.new()
	var record := {}
	check(Speedrun.rows(record).size()==12,"secret route does not leak into empty speedrun records")
	sr.arm("hard")
	sr.start()
	check(sr.finish("beast",record)["rec"]["status"]=="finished" and Speedrun.rows(record).size()==14,"completed secret speedrun is recorded and revealed")
	check(DeathArchive.rows({}, {"beast":1}).size()==DeathArchive.rows({},{}).size()+1,"secret CG is revealed only after completing it")
	var f := FacilitiesModule.new(CampusData.rooms(),CampusData.layout("out"),CampusData.campus())
	f.reset()
	f.spots["stall"]=true
	check(f.ideas().any(func(it: Array) -> bool: return it[0]=="beast"),"finding the stall unlocks the original escape idea")
	CampusData.clear_caches()


func test_beast_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/beast/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/beast/settings.json")
	root.add_child(app)
	await _frames(2)
	app.start_new_game("hard","immune")
	app.set_physics_process(false)
	app._stand_up()
	var r := CampusData.layout("teach1")
	app.travel("teach1",_campus_pose(r,CampusGeometry.tile_center(r,59,18),PI),false)
	app.school().tsec = 705.0+14.0/60.0
	app._drop_item("not-an-item")
	check(not app.routes().beast_drop,"dropping an absent item cannot unlock the stall")
	app.items().add("coin")
	app._drop_item("coin")
	check(app.routes().beast_drop and not app.items().has("coin") and app.saves.exists(),"real inventory removal unlocks and saves the route")
	check(app.items().ground.is_empty(),"an accepted offering does not also leave the item on the floor")
	app.load_game()
	app.set_physics_process(false)
	app.player.enabled=false
	check(app.routes().beast_drop and not app.items().has("coin"),"offering persists through native save/load without returning the item")
	app.school().tsec=900
	app._route_hint("beast")
	check(app.ui.choice_panel.visible,"the unlocked stall can be entered after the tiny offering window")
	app._choice_made(1)
	check(not app.story().dead and app.routes().beast_drop and not app.ui.choice_panel.visible,"waiting preserves the unlock and returns control")
	check(await _face_tile(app,"teach1","B","facility"),"a real stall can be reached through the interaction query")
	app.set_physics_process(false)
	app._campus_interact()
	check(app.ui.choice_panel.visible,"the physical stall uses the same route choice")
	var pose := app.player.capture_pose()
	var environment: Environment = app._campus_world().lighting.env
	var adjustment := environment.adjustment_enabled
	var saturation := environment.adjustment_saturation
	app._choice_made(0)
	await _frames(2)
	if DisplayServer.get_name()!="headless":
		check(is_instance_valid(app._ending_cut) and app._ending_cut.kind=="beast","the nine-second live scene precedes the ending card")
		app._ending_cut._apply(.7)
		check(same_json(app.player.capture_pose(),pose),"ending animation never changes the player's saved pose")
		await _skip_cut(app)
		check(environment.adjustment_enabled==adjustment and environment.adjustment_saturation==saturation and app.player.camera.current,"skip restores grading and the player camera")
	check(app.story().over() and app.story().ended=="beast" and app.ui.ending_panel.visible and not app.saves.exists(),"the ending closes the run and clears the normal save")
	check(app.achievements().unlocked.has("h.beast") and app._last_result.get("rated",false),"the legitimate secret route records an achievement and a rated clear")
	app.return_to_menu()
	app.start_new_game("hard","immune")
	app.set_physics_process(false)
	check(not app.routes().beast_drop,"a new run cannot inherit the stall unlock")
	if DisplayServer.get_name()!="headless":
		app._reach_ending("beast")
		var cut := app._ending_cut
		var callbacks := [0]
		cut.finished.connect(func(_skipped: bool) -> void: callbacks[0]+=1)
		app.return_to_menu()
		await _frames(3)
		check(callbacks[0]==0 and not paused and not is_instance_valid(cut),"leaving the ending cancels its props and callback")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
