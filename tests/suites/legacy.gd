extends "res://tests/support/test_suite.gd"


func _fixtures() -> Array:
	var raw := FileAccess.get_file_as_bytes("res://tests/fixtures/save-reference.json.gz")
	return JSON.parse_string(raw.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())["cases"]


func _data(snapshot: Dictionary, id: String) -> Dictionary:
	return snapshot["modules"][id]["data"]


func _convert(raw: Dictionary, session: GameSession) -> Dictionary:
	var plan := LegacySave.plan(raw,CampusData.rooms(),CampusData.campus()["items"],TalentModule.KEYS)
	if plan["error"] != "":
		return plan
	session.start(plan["world"])
	return LegacyState.new().convert(plan,session.capture({"position":[0,0,0],"yaw":0,"pitch":0}),CampusData.rooms(),CampusData.campus(),CampusData.maze_geometry())


func test_reference() -> void:
	for case: Dictionary in _fixtures():
		var session := SessionFactory.create()
		var converted := _convert(case["save"],session)
		var id: String = case["id"]
		check(converted["error"] == "", "old runtime fixture converts: %s (%s)" % [id,converted["error"]])
		if converted["error"] != "":
			continue
		var snapshot: Dictionary = converted["snapshot"]
		var why := session.validate(snapshot,PackedStringArray(CampusData.rooms().keys()+["out"]))
		check(why == "", "converted snapshot validates: %s (%s)" % [id,why])
		if why != "":
			continue
		var e: Dictionary = case["expected"]
		var school := _data(snapshot,"school.day")
		check(school["day"] == e["day"] and school["tsec"] == e["tsec"] and school["san"] == e["san"] and school["viol"] == e["viol"]
			and school["seated"] == e["seated"], "clock, stats and seating match original restore: " + id)
		var room: Variant = CampusData.rooms().get(e["room"]) if e["mode"] == "in" else null
		var point := CampusGeometry.to_scene(room,Vector2(e["x"],e["y"]))
		var p: Array = snapshot["player"]["position"]
		check(absf(p[0]-point.x)<.001 and absf(p[2]-point.y)<.001 and absf(p[1]-.01-float(case["floorY"]))<.001,
			"restore preserves floor and position: %s (%s vs %s at %s)" % [id,p,point,case["floorY"]])
		check(same_json(_data(snapshot,"campus.facilities")["act_cool"],e["actCool"])
			and same_json(_data(snapshot,"anomaly.world")["an"]["cool"],e["anCool"]),"old clock cooldown conversion matches the Web loader: " + id)
		var inv := _data(snapshot,"items.bag")
		check(same_json(inv["bag"],e["bag"]) and same_json(inv["hot"],e["hot"]),"inventory and hot slots match original restore: " + id)
		session.restore(snapshot)
		var roundtrip := session.capture(snapshot["player"])
		var roundtrip_error := session.validate(roundtrip,PackedStringArray(CampusData.rooms().keys()+["out"]))
		check(roundtrip_error.is_empty(),"imported state can be saved again: %s (%s)" % [id,roundtrip_error])
		check(same_json(_data(roundtrip,"legacy.web")["source"],case["save"]),"original fields remain available as inert data: " + id)
		if id == "routes":
			check(_data(roundtrip,"story.routes")["face_quiz"]["done"] == 2 and _data(roundtrip,"story.routes")["data"],"gate progress and synced whitelist survive")
			check(_data(roundtrip,"campus.facilities")["portal"]["work"].get("5") == 1 and _data(roundtrip,"campus.facilities")["portal"]["blueprints"].size() == 2,"portal work and collected blueprints survive")
			check(inv["torch"] and inv["brolly"] and _data(roundtrip,"items.bag")["brolly"],"held torch and open umbrella restore and save")
			check(_data(roundtrip,"story.talent")["consumed"]["fatalProtection"] and _data(roundtrip,"story.death")["wakes"] == 1,"consumed rescue and dream wake cannot be granted again")
			check(_data(roundtrip,"phone.network")["device"]["download"]["elapsed"] == 21 and _data(roundtrip,"story.broadcast")["completed"] == 1,"download and broadcast progress survive")
			check(_data(roundtrip,"campus.world")["open_doors"].size()==2 and _data(roundtrip,"campus.marks")["marks"].size()==1 and not _data(roundtrip,"campus.exploration")["seen"]["teach1"].is_empty(),"open doors, chalk and old per-cell exploration survive")
		if id == "old-classroom":
			check(_data(roundtrip,"school.day")["seat_id"] == CampusData.campus()["own_seat"]["seatId"] and
				same_json(_data(roundtrip,"campus.world")["open_doors"],e["openDoors"].keys()),"older classroom seat and door migrate together")
		if id == "inspection":
			var ins: Dictionary = _data(roundtrip,"school.day")["inspection"]
			check(ins["current"]["t"]==2.4 and ins["current"]["look"]==.3 and ins["calm_room"]=="teach1" and
				ins["current"]["points"][0][0] == e["rt"]["inspection"]["current"]["points"][0]["x"],"inspection timing, place and silhouettes survive")
			var photo: Dictionary = _data(roundtrip,"phone.camera")["photos"][0]
			var img := Image.new()
			check(img.load_jpg_from_buffer(Marshalls.base64_to_raw(photo["img"]))==OK and img.get_width()==64,"original camera data URL is readable by the native album")
		if id == "anomaly":
			var a: Dictionary = _data(roundtrip,"anomaly.world")["an"]
			check(a["active"] and a["id"]=="hand" and a["t"]==3.2 and not a["data"]["asked"] and a["data"]["choiceRemaining"]==1800,"anomaly resumes with remaining question time")
			check(_data(roundtrip,"patrol.world")["pat"]["locked"] and _data(roundtrip,"patrol.world")["pat"]["lock"]==e["mods"]["patrolWorld"]["lock"],"patrol lock matches original restore")
		if id == "garage":
			check(_data(roundtrip,"garage.world")["roam"]["litAcc"]==.8 and _data(roundtrip,"garage.world")["lure"]["t"]==4.3,"garage shadow exposure and coin lifetime remain continuous")
		if id == "maze":
			check(_data(roundtrip,"campus.maze")["elapsed"]==321.5 and _data(roundtrip,"campus.elevator")["ride"]["origin"]==3,"maze pressure and return floor survive")
	CampusData.clear_caches()


func test_atomic_import() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/atomic-legacy/save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/atomic-legacy/settings.json")
	root.add_child(app)
	await _frames(2)
	app.start_new_game("hard", "immune")
	app.set_physics_process(false)
	app.school().san = 61
	app.save_game()
	var before := app.session
	var saved := FileAccess.get_file_as_string(app.saves.path)
	var route: Dictionary = _fixtures().filter(func(c: Dictionary) -> bool: return c["id"]=="routes")[0]["save"]
	var bad := route.duplicate(true)
	bad["rt"]["faceQuiz"]["done"] = 99
	check(not app.import_legacy_save(JSON.stringify(bad)).is_empty() and app.session == before and app.school().san == 61,
		"a later module validation failure leaves the current session untouched")
	check(FileAccess.get_file_as_string(app.saves.path) == saved,"rejected import leaves the existing save untouched")
	for corrupt: Dictionary in [{"inspection":{"current":{"day":1,"slot":0,"points":false}}}, {"portalWork":{"5":[]}}, {"inspection":{"queue":[null]}}]:
		bad = route.duplicate(true)
		bad["rt"].merge(corrupt,true)
		check(not app.import_legacy_save(JSON.stringify(bad)).is_empty() and app.session == before,"malformed nested progress is rejected before replacing the session")
	var why := app.import_legacy_save(JSON.stringify(route))
	check(why.is_empty(),"complete imported run installs through the real app: "+why)
	if why.is_empty():
		app.set_physics_process(false)
		await _frames(3)
		check(app.items().brolly_up and app.routes().data_synced and app.facilities().portal["blueprints"].size()==2,"installed run retains active equipment and route state")
		check(not app.talent().prevent_death(),"import cannot restore a spent one-time rescue")
		app.save_game()
		app.load_game()
		app.set_physics_process(false)
		check(app.items().brolly_up and app.routes().data_synced,"native save/load retains the imported progress")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
