extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/inception-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func _state(raw: Dictionary) -> Dictionary:
	var out: Dictionary={"top":bool(raw["top"]),"class_day":{},"entered":{},"settled":{},"dream":{}}
	for pair: Array in [["classDay","class_day"],["entered","entered"],["settled","settled"]]:
		for key: String in raw[pair[0]]: out[pair[1]][key]=bool(raw[pair[0]][key])
	if raw["dream"]!=null:
		out["dream"]=raw["dream"].duplicate(true)
		if out["dream"].get("spin")==null: out["dream"]["spin"]=""
		if out["dream"].get("id")==null: out["dream"]["id"]=""
	return out


func _without_random(module: InceptionModule) -> Dictionary:
	var out:=module.capture()
	out.erase("random")
	return out


func test_reference() -> void:
	var reference:=_reference()
	check(same_json(InceptionModule.GRID,reference["grid"]),"dream geometry is the original 23 by 17 grid")
	var room:=CampusData.layout("dorm2")
	var p:=CampusGeometry.tile_center(room,5,3)
	var from: Dictionary={"room":"dorm2","x":p.x,"y":p.y,"ang":0,"floorY":0}
	for spec: Dictionary in reference["rests"]:
		var inc:=InceptionModule.new(CampusData.rooms())
		var draws: Array[int]=[0]
		inc.roll=func() -> float:
			var value: float=spec["rolls"][draws[0]%spec["rolls"].size()]
			draws[0]+=1
			return value
		check((SchoolClock.need_where(spec["tsec"])=="教室" and not SchoolClock.is_night(spec["tsec"]))==spec["inClass"],"original class/free sleep eligibility at %s" % spec["tsec"])
		for step: Dictionary in spec["steps"]:
			var intercepted:=inc.rest(1,spec["tsec"],spec["inClass"],spec["hasTop"],from)
			check(intercepted==step["intercepted"] and draws[0]==step["draws"] and same_json(_without_random(inc),_state(step["state"])),"original daily sleep/dream draws %s: %s" % [spec["tsec"],spec["rolls"]])
	for spec: Dictionary in reference["paths"]:
		var inc:=InceptionModule.new(CampusData.rooms())
		inc.restore(_state(spec["before"]))
		var cell:=InceptionModule.EXIT if spec["exit"] else Vector2i(9,3)
		var here:=true
		for step: Dictionary in spec["steps"]:
			if here: inc.tick(.2,cell)
			for event: Dictionary in inc.take_events():
				if event["kind"] in ["wake","ending"]: here=false
				elif event["kind"]=="loop": cell=InceptionModule.START
			check(same_json(_without_random(inc),_state(step["state"])) and absf(inc.eye_drop()+float(step["eye"]))<.00001,"original fall/exit branch and camera drop: "+spec["id"])
	for f: Dictionary in reference["frames"]:
		var actual:=InceptionScene.frame(f["k"])
		var look: Array=f["view"]
		check(actual["stage"]==f["stage"] and absf(actual["fade"]-f["fade"])<.00001 and
			actual["from"].distance_to(Vector3(look[0],look[1],look[2]))<.00001 and actual["to"].distance_to(Vector3(look[3],look[4],look[5]))<.00001,"original dream cinematic stage/camera/fade at %.4f" % f["k"])
	var ach:=AchievementsModule.new()
	ach.reset()
	check(ach.fact({"kind":"ending","id":"inception"}).has("h.inception") and ach.points()==60,"dream success unlocks the original hidden sixty-point achievement")
	check(DeathArchive.rows({},{}).all(func(row: Dictionary) -> bool: return row["name"]!="《盗梦空间》") and DeathArchive.rows({},{"inception":1}).any(func(row: Dictionary) -> bool: return row["name"]=="《盗梦空间》") and not Speedrun.ROUTES.has("inception"),"dream archive is hidden; the original does not register a speedrun category")
	CampusData.clear_caches()


func test_save() -> void:
	var converter:=preload("res://tests/suites/legacy.gd").new(_runner)
	var raw: Dictionary=_reference()["saves"][0]
	var session:=SessionFactory.create()
	var result: Dictionary=converter._convert(raw,session)
	check(result["error"]=="","old active dream save converts: "+String(result["error"]))
	if result["error"]!="": return
	check(session.validate(result["snapshot"],PackedStringArray(CampusData.rooms().keys()+["out"])).is_empty(),"old dream and return position validate atomically")
	session.restore(result["snapshot"])
	var inc: InceptionModule=session.modules.get_module(&"story.inception")
	check(same_json(_without_random(inc),_state(raw["rt"]["inception"])) and inc.dream["spin"]=="fall","original spin result survives import")
	inc.set_seed(4829)
	inc.tick(.2,Vector2i(9,3))
	inc.tick(.35,Vector2i(9,3))
	var store:=SaveStore.new(_test_path.get_base_dir()+"/inception/slot.json")
	check(store.write(session.capture(result["snapshot"]["player"])).is_empty(),"falling dream writes to the real JSON save")
	var loaded:=SessionFactory.create()
	loaded.restore(store.read()["data"])
	var restored: InceptionModule=loaded.modules.get_module(&"story.inception")
	check(same_json(inc.capture(),restored.capture()),"fall progress, return pose and RNG survive JSON")
	restored.roll=func() -> float: return 0
	restored.spin(true)
	check(restored.dream["spin"]=="fall" and _of_kind(restored.take_events(),"save").is_empty(),"repeated use after loading cannot reroll the top")
	inc.take_events()
	inc.tick(1.1,Vector2i(9,3))
	restored.tick(1.1,Vector2i(9,3))
	check(same_json(inc.take_events(),restored.take_events()),"loading midway through a fall reaches the same wake settlement")
	restored.wake(true)
	check(not restored.take_events()[0]["settle"],"duplicate wake cannot award a second recovery")
	for _i in 16: check(inc._rng.randf()==restored._rng.randf(),"dream RNG sequence continues across save")
	var missing:=InceptionModule.new(CampusData.rooms())
	missing.ensure_dream(1)
	check(missing.validate(missing.capture()).is_empty() and missing.dream["id"]=="" and missing.dream["spin"]=="fall","old room-only dream gets the original safe return state")
	missing.wake(false)
	check(not missing.take_events()[0]["settle"],"missing dream state awards no rest")
	var broken:=_state(raw["rt"]["inception"])
	broken["dream"]["falling"]=NAN
	check(not inc.validate(broken).is_empty(),"invalid fall timer cannot enter a save")
	broken["dream"]["falling"]=0
	broken["dream"]["from"]["room"]="unregistered"
	check(not inc.validate(broken).is_empty(),"invalid return room is rejected before replacing a session")
	CampusData.clear_caches()


func _quiet(app: GameApp) -> void:
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.patrol().pat["next"]=10000.0
	app.anomaly().an["next"]=10000.0


func _reset_stats(app: GameApp, data: Dictionary) -> void:
	app.school().reset()
	for key: String in ["day","tsec","san","viol","stam"]: app.school().set(key,data[key])
	app.inception().reset()
	app.facilities().reset()
	app.inception().roll=func() -> float: return 0


func _stats(app: GameApp) -> Dictionary:
	var out:=app.school().capture()
	var result: Dictionary={}
	for key: String in ["day","tsec","san","viol","stam"]: result[key]=out[key]
	result["cool"]=app.facilities().act_cool.duplicate()
	return result


func _cell_pose(cell: Vector2i) -> Dictionary:
	var room:=CampusData.layout(InceptionModule.ROOM)
	return _campus_pose(room,CampusGeometry.tile_center(room,cell.x,cell.y),0)


func _path() -> Array[Vector2i]:
	var grid: Array=_reference()["grid"]
	var queue: Array[Vector2i]=[InceptionModule.START]
	var previous: Dictionary={InceptionModule.START:null}
	while not queue.is_empty():
		var cell: Vector2i=queue.pop_front()
		if cell==InceptionModule.EXIT: break
		for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:=cell+offset
			if next.x<0 or next.x>=23 or next.y<0 or next.y>=17 or previous.has(next) or grid[next.y][next.x] in ["#","p"]: continue
			previous[next]=cell
			queue.append(next)
	var path: Array[Vector2i]=[]
	var cell: Variant=InceptionModule.EXIT
	while cell!=null and previous.has(cell):
		path.push_front(cell)
		cell=previous[cell]
	return path


func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/dream-app/slot.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/dream-app/settings.json")
	root.add_child(app)
	await _frames(2)
	app.start_new_game("hard","none")
	_quiet(app)
	app._stand_up()
	var room:=CampusData.layout("dorm2")
	var pose:=_campus_pose(room,CampusGeometry.tile_center(room,5,3),0)
	app.travel("dorm2",pose,false)
	check(app.inception_flow.hint()=="桌上的陀螺" and is_instance_valid(app.inception_flow.fx.pickup),"fixed top is visible and interactable at the original dorm table")
	app._campus_interact()
	check(app.items().has("top") and app.inception().top and app.inception_flow.hint()=="","fixed top is collected once")
	app.items().remove("top")
	for spec: Dictionary in _reference()["ordinary"]:
		_reset_stats(app,spec["before"])
		app.facilities().set_context(app._facility_context())
		app.facilities().rest(spec["key"])
		app._apply_facility_events()
		check(same_json(_stats(app),spec["after"]),"ordinary rest uses original end-time pressure and cooldown: %s day %s at %s; got %s" % [spec["key"],spec["before"]["day"],spec["before"]["tsec"],_stats(app)])
	for spec: Dictionary in _reference()["paths"]:
		if spec["id"] in ["stand-pit","fall-exit"]: continue # Successful ending is exercised separately below.
		_reset_stats(app,spec["start"])
		app.inception().restore(_state(spec["before"]))
		app.travel(InceptionModule.ROOM,_cell_pose(InceptionModule.EXIT if spec["exit"] else Vector2i(9,3)),false)
		for step: Dictionary in spec["steps"]:
			app.inception_flow.step(.2)
			var expected: Dictionary={}
			for key: String in ["day","tsec","san","viol","stam","cool"]: expected[key]=step[key]
			check(same_json(_stats(app),expected) and app.session.world_id==step["room"] and same_json(_without_random(app.inception()),_state(step["state"])),"native wake applies original stats and destination: "+spec["id"])
		if spec["steps"][-1]["room"]=="dorm2":
			check(app.player.position.distance_to(Vector3(pose["position"][0],0,pose["position"][2]))<.001,"wake restores the original bed position")
			var before:=_stats(app)
			app.load_game()
			_quiet(app)
			check(same_json(_stats(app),before),"autosave after waking does not pay twice on load")
	var midnight: Dictionary=_reference()["paths"].filter(func(s: Dictionary) -> bool: return s["id"]=="fall-pit-midnight")[0]
	_reset_stats(app,midnight["start"])
	app.inception().restore(_state(midnight["before"]))
	app.inception().dream["falling"]=1.3
	app.travel(InceptionModule.ROOM,_cell_pose(Vector2i(9,3)),false)
	app._campus_step(.2)
	check(app.session.world_id=="dorm2" and app.school().day==2 and app.school().tsec==520,"wake frame advances exactly ninety game minutes, with no extra ordinary clock tick")
	# The real facility interception and transition: nothing is awarded on entry.
	app.travel("dorm2",pose,false)
	_reset_stats(app,{"day":1,"tsec":755,"san":30,"viol":20,"stam":30})
	app.items().add("top")
	app.facilities().set_context(app._facility_context())
	app.facilities().rest("sleep")
	app._apply_facility_events()
	check(app.session.world_id=="dorm2" and is_instance_valid(app.inception_flow.fade) and app.school().tsec==755,"sleep begins the fade without awarding ordinary recovery")
	app.inception_flow.fade.advance(.16)
	check(app.session.world_id=="dorm2","room changes only after the original 170 ms fade delay")
	app.inception_flow.fade.advance(.011)
	check(app.inception_flow.here() and not app.router.current.advances_calendar,"dream entry freezes the school clock")
	app.inception_flow.fade.advance(.30)
	app._school_step(0,app.campus())
	app.ui.show_runtime(app.session.clock.active_seconds)
	check(app.ui.get_node("%Runtime").text=="??:??","dream HUD uses the original unknown-time label")
	check(app.school().san==30 and app.facilities().act_cool.is_empty(),"entering a dream grants no preliminary rest or cooldown")
	app.inception().roll=func() -> float: return 0.1
	app._use_item("top")
	check(app.inception().dream["spin"]=="stand","bag top chooses its persistent result")
	app.save_game()
	app.load_game()
	_quiet(app)
	app.inception().roll=func() -> float: return .9
	app.items().set_hot(0,"top")
	app._touch_hot(0)
	check(app.inception().dream["spin"]=="stand","mobile hotbar after loading cannot alter the result")
	app._show_map()
	check((not is_instance_valid(app.ui.map_panel) or not app.ui.map_panel.visible) and not paused,"map cannot open in the dream")
	var before:=app.school().tsec
	app.school().step(2,{"calendar":false,"world_id":"dream_top","w":Vector2.ZERO})
	check(app.school().tsec==before,"dream simulation cannot advance the calendar")
	var anomaly:=app.anomaly()
	anomaly.an["next"]=-1.0
	anomaly.set_context(_actx("dream_top",Vector2.ZERO))
	anomaly.tick(10)
	check(not anomaly.is_active(),"dream room suppresses new random anomalies")
	app.player.restore_pose(_cell_pose(InceptionModule.EXIT))
	app.inception_flow.step(.1)
	check(app.inception_flow._cell()==InceptionModule.START and app.inception().dream["spin"]=="stand","standing top loops the door back to the original start")
	app.player.restore_pose(_cell_pose(Vector2i(9,3)))
	app.inception_flow.step(.1)
	app.inception_flow.step(.6)
	check(app.inception().eye_drop()>1 and app.player.position.y>=0,"pit fall affects the view, not the saved body height")
	app.school().san=0
	app._campus_step(.81)
	check(app.story().ended=="inception" and app.inception().dream.is_empty(),"standing top and pit reach the actual hidden ending")
	check(not app.story().dead,"dream completion precedes normal SAN/death settlement, as in the original update loop")
	if DisplayServer.get_name()!="headless":
		check(is_instance_valid(app._ending_cut) and app._ending_cut.kind=="inception","native success starts the twenty-second dream cinematic")
		var scene:=app._ending_cut._inception
		var camera: Camera3D=app._ending_cut.cam
		scene.top_b.rotation=Vector3.ZERO
		scene.top_d.rotation=Vector3.ZERO
		for f: Dictionary in _reference()["frames"]:
			scene.apply(f["k"],camera,.05)
			# Node3D normalizes Euler angles. Compare the orientation, not accumulated full turns.
			var b:=Basis.from_euler(Vector3(f["topB"][0],f["topB"][1],f["topB"][2]))
			var d:=Basis.from_euler(Vector3(f["topD"][0],f["topD"][1],f["topD"][2]))
			check(scene.top_b.basis.x.distance_to(b.x)<.001 and scene.top_b.basis.z.distance_to(b.z)<.001 and scene.top_d.basis.x.distance_to(d.x)<.001 and scene.top_d.basis.z.distance_to(d.z)<.001,"native top animation matches original rotations at %.4f" % f["k"])
		await _skip_cut(app)
	check(app.ui.ending_panel.visible and app.achievements().unlocked.has("h.inception"),"ending card and hidden achievement survive the cut")
	app.return_to_menu()
	app.start_new_game("hard","none")
	_quiet(app)
	app.travel("dorm2",pose,false)
	app.school().tsec=755
	app.items().add("top")
	app.inception().roll=func() -> float: return 0
	app.inception_flow.rest("sleep")
	var stale:=app.inception_flow.fade
	app.return_to_menu()
	stale.advance(1)
	check(app.session==null and not stale.active,"menu cancellation prevents the delayed dream entry from reviving a run")
	app.start_new_game("hard","none")
	_quiet(app)
	app._stand_up()
	var success: Dictionary=_reference()["paths"].filter(func(s: Dictionary) -> bool: return s["id"]=="fall-exit")[0]
	app.inception().restore(_state(success["before"]))
	app.travel(InceptionModule.ROOM,_cell_pose(InceptionModule.START),false)
	await _frames(2)
	var wall:=app.player.move_and_collide(Vector3(-1,0,0))
	check(wall!=null,"dream outer wall stops the real player capsule")
	app.player.restore_pose(_cell_pose(InceptionModule.START))
	var path:=_path()
	check(path.size()==51,"original maze has a continuous route to the exit without a pit")
	for cell: Vector2i in path:
		var p: Array=_cell_pose(cell)["position"]
		var target:=Vector3(p[0],p[1],p[2])
		var blocked:=app.player.move_and_collide(target-app.player.position)
		check(blocked==null and app.player.position.distance_to(target)<.001,"player capsule can traverse original dream route cell %s" % cell)
	app.inception_flow.step(.1)
	check(app.story().ended=="inception","fallen top reaches the same ending through the physically walkable exit")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
