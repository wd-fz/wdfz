extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/crowd-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _state(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if out.has("said"):
		out["said"]=bool(out["said"])
	return out


func test_reference() -> void:
	var ref := _reference()
	for s: Dictionary in ref["eligibility"]:
		var crowd := LiftCrowdModule.new()
		crowd.run=s["run"]
		var ride := {"rare":s["rare"],"crowd":0}
		var allowed := crowd.eligible(ride,s["unsafe"])
		if allowed:
			crowd.board(ride,s["roll"])
		check(allowed==s["allowed"] and ride["crowd"]==s["crowd"],"boarding eligibility and 1%% boundary match original: %s" % s)
	for spec: Dictionary in ref["scenarios"]:
		var crowd := LiftCrowdModule.new()
		crowd.run=120
		var lift := ElevatorModule.new(CampusData.rooms())
		lift.reset()
		lift.set_seed(1234)
		lift.crowd=crowd
		var first: Dictionary=spec["steps"][0]
		lift.ride=first["ride"].duplicate(true)
		lift.ride["crowd"]=1
		var car: Dictionary=lift.lifts[spec["host"]]
		car.merge({"floor":int(spec["floor"]),"target":int(spec["floor"]),"door":0.0,"dir":0,"hold":0.0},true)
		var room_id := String(spec["host"])+str(int(spec["floor"]))
		var room := CampusData.layout(room_id)
		var w := lift.world(room_id,-1.225,0)
		lift.press(first["ride"]["pending"],room_id,_campus_pose(room,w,0))
		var facts := []
		var deaths := []
		var dead := false
		for s: Dictionary in spec["steps"]:
			var t: float=s["t"]
			if t>0:
				var outside: bool=spec.has("leave") and t>=float(spec["leave"]) and not (spec.has("reenter") and t>=float(spec["reenter"]))
				w=lift.world(room_id,1.2 if outside else -1.225,0)
				lift.step(.1,room_id,_campus_pose(room,w,0))
			for e: Dictionary in crowd.take_events():
				if e["kind"]=="fact":
					facts.append(e["fact"])
				elif e["kind"]=="kill":
					deaths.append({"text":e["text"],"fx":e["fx"],"source":e["source"]})
					dead=not bool(spec.get("protected",false))
			if t>0 and not dead:
				crowd.tick(.1,lift.lifts,lift.ride,lift.in_cabin(room_id,w),room_id)
			for e: Dictionary in crowd.take_events():
				if e["kind"]=="fact": facts.append(e["fact"])
			var same := same_json(crowd.state,_state(s["state"]))
			for key: String in ["door","dir","hold","phase","target","remaining"]:
				same=same and same_json(car[key],s[key])
			check(same and dead==s["dead"] and same_json(lift.ride,s["ride"]),"original crowd/elevator timeline %s at %.1f" % [spec["id"],t])
		check(same_json(deaths,spec["deaths"]),"only remaining inside asks for death: "+spec["id"])
		check(facts.filter(func(f: Dictionary) -> bool: return f.get("survived",false)).size()==spec["facts"].filter(func(f: Dictionary) -> bool: return f.get("survived",false)).size(),"escaping/reentering rewards exactly once: "+spec["id"])
	for s: Dictionary in ref["lights"]:
		check(absf(LiftCrowdFx.light_mul(s["t"],s["reduced"])-float(s["mul"]))<.000001,"original crowd light beat with reduced flashing: %.2f / %s" % [s["t"],s["reduced"]])
	for s: Dictionary in ref["frames"]:
		var f := CrowdDeath.frame(s["t"],1 if s["shake"] else 0)
		var same := true
		for key: String in ["yaw","pitch","lift","shade","gap","lit","full","end"]:
			same=same and same_json(f[key],s[key])
		var segments := String(f["segments"]).split("")
		segments.sort()
		check(same and "".join(segments)==s["segments"],"original death camera, light, sign and door at %.3f / %s" % [s["t"],s["shake"]])
	CampusData.clear_caches()


func test_save() -> void:
	var converter := preload("res://tests/suites/legacy.gd").new(_runner)
	for spec: Dictionary in _reference()["saves"]:
		var session := SessionFactory.create()
		var converted: Dictionary=converter._convert(spec["save"],session)
		check(converted["error"]=="","original crowd save converts: "+String(converted["error"]))
		if converted["error"]!="": continue
		var snapshot: Dictionary=converted["snapshot"]
		check(session.validate(snapshot,PackedStringArray(CampusData.rooms().keys()+["out"])).is_empty(),"crowd candidate validates before install")
		session.restore(snapshot)
		var crowd: LiftCrowdModule=session.modules.get_module(&"campus.lift_crowd")
		check(same_json(crowd.state,_state(spec["save"]["rt"]["liftCrowd"])) and crowd.run==spec["save"]["mods"]["lift-crowd"]["run"],"old crowd clock, breathing and phase continue")
		var store := SaveStore.new(_test_path.get_base_dir()+"/crowd/slot.json")
		check(store.write(session.capture(snapshot["player"])).is_empty(),"converted active event saves to native disk")
		var restored := SessionFactory.create()
		restored.restore(store.read()["data"])
		check(same_json(restored.modules.get_module(&"campus.lift_crowd").capture(),crowd.capture()),"native JSON roundtrip preserves remaining decision time")
		var broken := crowd.capture()
		broken["state"]["t"]=INF
		check(not crowd.validate(broken).is_empty(),"infinite decision timers are rejected")
	var ach := AchievementsModule.new()
	ach.reset()
	check(not ach.entries().any(func(e: Dictionary) -> bool: return e["id"]=="h.crowd"),"crowd achievement remains hidden before discovery")
	check(not ach.fact({"kind":"anomaly","phase":"end","id":"crowd","saved":true,"survived":false}).has("h.crowd"),"fatal protection is not an escape")
	check(ach.fact({"kind":"anomaly","phase":"end","id":"crowd","survived":true}).has("h.crowd"),"walking away reveals the hidden achievement")
	check(DeathArchive.rows({"sources":{"crowd":1}},{}).size()==DeathArchive.rows({},{}).size()+1,"full-cabin death archive stays secret until encountered")
	check(DeathCG.has("crowd") and StoryModule.duration("crowd")==4.2,"the correct 4.2-second death scene is registered")
	CampusData.clear_caches()


func _board(app: GameApp, host: String, floor_num: int) -> void:
	var lift := app.elevator()
	var room_id := host+str(floor_num)
	var w := lift.world(room_id,-1.225,0)
	var out: Vector2=lift.frame(room_id)["out"]
	app.travel(room_id,_campus_pose(CampusData.layout(room_id),w,atan2(out.y,out.x)),false)
	app.player.set_physics_process(false)
	app.lift_crowd().run=120
	lift.lifts[host].merge({"floor":floor_num,"target":floor_num,"phase":"idle","door":0.0,"dir":0,"hold":0.0},true)
	lift.ride={"host":host,"origin":floor_num,"target":floor_num,"phase":"cabin","rare":false,"remaining":0.0,"pending":null,"crowd":1}
	lift.press(5 if floor_num!=5 else 1,room_id,app.player.capture_pose())
	app._lift_crowd_step(0)


func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/crowd-app/slot.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/crowd-app/settings.json")
	root.add_child(app)
	await _frames(2)
	for id: String in ["event.liftOverload","threat.crowd","death.crowd"]:
		check(app.audio._index["sfx"].has(id),"original sound recipe is available: "+id)
	app.start_new_game("hard","code")
	app.set_physics_process(false)
	app._stand_up()
	_board(app,"teach",3)
	var san := app.school().san
	var crowd := app.lift_crowd()
	for i in 20:
		app.elevator().step(.1,app.session.world_id,app.player.capture_pose())
		app._lift_crowd_step(.1)
	check(crowd.active() and not app.story().dead and app.elevator().lifts["teach"]["door"]==1,"full cabin opens for the player to leave")
	check(app._camera_context()["crowd"] and is_instance_valid(app._lift_crowd_fx.sign),"photo subject and physical red sign use the same active event")
	var sign := app._lift_crowd_fx.sign
	check(sign.global_basis.z.dot((app.player.camera.global_position-sign.global_position).normalized())>0,"red sign faces into the actual cabin")
	check(sign.position.y+.08<=2.14+.00001,"entire full-cabin display fits below the exported ceiling")
	app.elevator().close_door("teach3",app.elevator().world("teach3",-1.225,0))
	check(app.elevator().lifts["teach"]["dir"]==0 and app.elevator().controls("teach3",app.elevator().world("teach3",-1.225,0)).has("notice"),"close key and panel cannot bypass the six-second decision")
	app.save_game()
	var remaining: float=crowd.state["t"]
	app.load_game()
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	crowd=app.lift_crowd()
	check(absf(crowd.state["t"]-remaining)<.001 and app.elevator().ride["crowd"]==2,"app load resumes the already drawn crowd event")
	app._lift_crowd_step(0)
	# Exercise the real capsule through both animated doors, not a position teleport.
	var out: Vector2=app.elevator().frame("teach3")["out"]
	app._campus_world().apply_lift_doors(app.elevator())
	await _frames(2)
	for i in 70:
		app.player.velocity=Vector3(out.x*2.5,0,out.y*2.5)
		app.player.move_and_slide()
		app.elevator().step(1.0/60,app.session.world_id,app.player.capture_pose())
		app._lift_crowd_step(1.0/60)
		app._campus_world().apply_lift_doors(app.elevator())
		if i%5==0: await _frames(1)
	check(not crowd.active() and not app.story().dead and app.achievements().unlocked.has("h.crowd"),"physical capsule can exit reopened doors and resolve the event")
	check(app.school().san==san,"crowd presentation and escape do not deduct SAN")
	for i in 30:
		app.elevator().step(.1,app.session.world_id,app.player.capture_pose())
		app._lift_crowd_step(.1)
	check(crowd.state.is_empty() and not is_instance_valid(app._lift_crowd_fx.sign),"empty elevator leaves and removes the sign")
	app.return_to_menu()
	app.start_new_game("hard","immune")
	app.set_physics_process(false)
	app._stand_up()
	check(app.lift_crowd().run==0 and app.lift_crowd().state.is_empty(),"new run does not inherit an event or eligibility timer")
	_board(app,"lab",2)
	for i in 80:
		app.elevator().step(.1,app.session.world_id,app.player.capture_pose())
		app._lift_crowd_step(.1)
	check(not app.story().dead and app.talent().consumed.get("fatalProtection",false) and not app.lift_crowd().active(),"fatal protection is consumed once and returns cabin control")
	check(not app.elevator().press(4,"lab2",app.player.capture_pose()).is_empty(),"a protected player can select a floor and depart")
	_board(app,"lab",2)
	for i in 80:
		if app.story().dead: break
		app.elevator().step(.1,app.session.world_id,app.player.capture_pose())
		app._lift_crowd_step(.1)
	check(app.story().dead and app.story().death_source=="crowd" and app.elevator().ride.is_empty(),"staying inside triggers real death and cancels the ride")
	if DisplayServer.get_name()!="headless":
		check(is_instance_valid(app._death_cg) and app._death_cg.fx=="crowd","native play starts the correct live death scene")
		for t in [0.0,1.4,2.4,3.5,4.19]:
			app._death_cg.update(t)
			await _frames(1)
		check(app._death_cg.d["card"].visible and not app._death_cg.d["hands"][0].visible,"the final shot contains only the abandoned student card")
	app.return_to_menu()
	app.start_new_game("hard","code")
	app.set_physics_process(false)
	check(not app._camera_context()["crowd"] and app.player.camera.rotation.is_equal_approx(Vector3(-.06,0,0)) and is_equal_approx(app.player.camera.position.y,CameraMotion.SEATED_EYE),"death exit/new game restores the seated camera and clears crowd presentation")
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
