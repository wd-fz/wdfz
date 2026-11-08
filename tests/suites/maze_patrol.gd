extends "res://tests/support/test_suite.gd"


func _reference() -> Dictionary:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/maze_patrol-reference.json.gz")
	return JSON.parse_string(bytes.decompress_dynamic(8*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())


func test_reference() -> void:
	var nav:=CampusData.patrol_nav()
	var fixture:=_reference()
	var began:=Time.get_ticks_usec()
	for spec: Dictionary in fixture["paths"]:
		var points:=nav.path(spec["a"],spec["b"])
		check(points.is_empty()==(spec["path"]==null),"maze path reachability matches original: "+spec["id"])
		if points.is_empty(): continue
		var length:=nav.length(points)
		check(absf(length-float(spec["length"]))<.001,"height-aware route length matches original %s: %.5f vs %.5f" % [spec["id"],length,spec["length"]])
		var invalid:=[]
		for p: Dictionary in points:
			if not nav.maze.supported(p): invalid.append(p)
		check(invalid.is_empty(),"route stays on supported voxel/ramp surfaces: %s %s" % [spec["id"],invalid.slice(0,2)])
		check(same_json(points,nav.path(spec["a"],spec["b"])),"reusing a route does not mutate its points")
	var mismatches:=[]
	for sample: Dictionary in fixture["sight"]:
		if nav.los(sample["a"],sample["b"])!=sample["seen"]: mismatches.append(sample)
	check(fixture["sight"].size()==1296 and mismatches.is_empty(),"1,296 original lines of sight agree across floors, walls and ramps: %s" % str(mismatches.slice(0,2)))
	print("MAZE NAV FIRST PASS: %.3f s" % ((Time.get_ticks_usec()-began)/1e6))
	var warmed:=MazePatrolNav.new(nav.maze.shape,nav.maze.room)
	var batches:=0
	while not warmed.warm_done and batches<10000:
		warmed.warm_step()
		batches+=1
	check(warmed.warm_done,"bounded incremental warmup finishes the static maze graph")
	for spec: Dictionary in fixture["paths"].slice(0,2):
		var points:=warmed.path(spec["a"],spec["b"])
		check(same_json(points,nav.path(spec["a"],spec["b"])),"precomputed neighbors retain the original A* route: "+spec["id"])
		points.pop_front()
		check(same_json(warmed.path(spec["a"],spec["b"]),nav.path(spec["a"],spec["b"])),"consuming a movement route leaves its cached path intact")
	for spec: Dictionary in fixture["flows"]:
		var pm:=CampusData.make_patrol()
		pm.reset()
		pm.elevator=ElevatorModule.new(CampusData.rooms())
		pm.elevator.ride={"host":spec["host"],"origin":int(spec["origin"]),"phase":"dream"}
		var p: Dictionary=spec["player"]
		pm.set_context(_pctx(p["scene"],Vector2(p["x"],p["y"]),{"fy":p["fy"],"active_seconds":100}))
		pm.left_scene(spec["host"]+str(int(spec["origin"])),"lift_dream")
		check(same_json(pm.pat["mazeGateway"],spec["before"]["mazeGateway"]),"scene boundary remembers the original elevator: "+spec["id"])
		pm.restore({"pat":spec["before"],"hide":pm.hide})
		for step: Dictionary in spec["steps"]:
			pm.tick(.1)
			var actual:=pm.pat
			check(actual["room"]==step["room"] and absf(actual["x"]-step["x"])<.001 and absf(actual["y"]-step["y"])<.001 and absf(actual["fy"]-step["fy"])<.00001 and same_json(actual["transition"],step["transition"]),"original two-second gateway and destination: "+spec["id"])
	CampusData.clear_caches()


func test_save() -> void:
	var converter:=preload("res://tests/suites/legacy.gd").new(_runner)
	for spec: Dictionary in _reference()["saves"]:
		var session:=SessionFactory.create()
		var result: Dictionary=converter._convert(spec["save"],session)
		check(result["error"]=="","old maze patrol save converts: %s %s" % [spec["id"],result["error"]])
		if result["error"]!="": continue
		check(session.validate(result["snapshot"],PackedStringArray(CampusData.rooms().keys()+["out"])).is_empty(),"imported maze patrol validates before replacing a run")
		session.restore(result["snapshot"])
		var pm: PatrolModule=session.modules.get_module(&"patrol.world")
		var expected: Dictionary=spec["expected"]
		check(pm.pat["room"]==expected["room"] and absf(pm.pat["x"]-expected["x"])<.001 and absf(pm.pat["y"]-expected["y"])<.001 and absf(pm.pat["fy"]-expected["fy"])<.00001 and same_json(pm.pat["mazeGateway"],expected["mazeGateway"]),"height and origin retained; unsupported placement uses original safe spawn: "+spec["id"])
		var store:=SaveStore.new(_test_path.get_base_dir()+"/maze-patrol/save.json")
		check(store.write(session.capture(result["snapshot"]["player"])).is_empty(),"maze patrol persists through the real save boundary")
		var restored:=SessionFactory.create()
		restored.restore(store.read()["data"])
		check(same_json(restored.modules.get_module(&"patrol.world").capture(),pm.capture()),"native save retains the same patrol location and gateway")
	# A transition is a live timer, not a fresh two-second trip when the game loads.
	var pm:=CampusData.make_patrol()
	pm.reset()
	pm.pat["mazeGateway"]={"host":"lab","origin":4}
	var floor_room:=CampusData.layout("lab4")
	var w:=CampusGeometry.tile_center(floor_room,10,18)
	pm._put(PatrolNav.point("lab4",w.x,w.y))
	pm.pat["permanent"]=true
	pm.pat["behavior"]="chase"
	pm.pat["safety"]=0
	pm.set_context(_pctx("lift_dream",Vector2(0,0),{"fy":0.0}))
	var goal:=pm.nav.maze.point(0,15)
	pm._prepare_path(goal)
	pm.pat["transition"]["remaining"]=.6
	var save: Dictionary=JSON.parse_string(JSON.stringify(pm.capture()))
	var loaded:=CampusData.make_patrol()
	loaded.restore(save)
	loaded.set_context(_pctx("lift_dream",Vector2(goal["x"],goal["y"])))
	loaded.tick(.59)
	check(loaded.pat["transition"]!=null and loaded.pat["room"]=="lab4","load continues the remaining gateway delay")
	loaded.tick(.02)
	check(loaded.pat["transition"]==null and loaded.pat["room"]=="lift_dream","gateway finishes once at the original spawn")
	var invalid:=pm.capture()
	invalid["pat"]["mazeGateway"]["origin"]=99
	check(not pm.validate(invalid).is_empty(),"invalid elevator origin cannot enter a loaded run")
	CampusData.clear_caches()


func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/maze-patrol-app/slot.json")
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/maze-patrol-app/settings.json")
	root.add_child(app)
	await _frames(2)
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.elevator().ride={"host":"lab","origin":4,"target":4,"phase":"dream","remaining":0.0,"rare":true,"pending":null}
	app.travel("lift_dream",{"position":[0,0,0],"yaw":0.0,"pitch":0.0},false)
	await _frames(2)
	check(app.patrol().pat["mazeGateway"]=={"host":"lab","origin":4},"real scene change carries the elevator origin into patrol state")
	var fixture:=_reference()
	var shape:=CapsuleShape3D.new()
	shape.radius=.30
	shape.height=1.1 # the original patrol checks feet+step through head; no artificial foot blocking
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=1
	query.margin=.0001
	var space:=app.player.get_world_3d().direct_space_state
	for spec: Dictionary in fixture["paths"].slice(0,2):
		var path:=app.patrol().nav.path(spec["a"],spec["b"])
		var blocked:=[]
		for i in path.size():
			var p: Dictionary=path[i]
			var at:=CampusGeometry.to_scene(CampusData.layout("lift_dream"),Vector2(p["x"],p["y"]))
			query.transform=Transform3D(Basis(),Vector3(at.x,p["fy"]+1,at.y))
			if not space.intersect_shape(query,1).is_empty(): blocked.append(i)
		check(blocked.is_empty(),"patrol route clears real maze collision at all nodes: %s %s" % [spec["id"],blocked.slice(0,5)])
	var pm:=app.patrol()
	var route:=pm.nav.path(fixture["paths"][0]["a"],fixture["paths"][0]["b"])
	pm._put(route[0])
	pm.pat["behavior"]="chase"
	pm.pat["permanent"]=true
	pm.pat["safety"]=0
	var goal: Dictionary=route[-1]
	var steps:=0
	while not pm._navigate(goal,pm.nav.chase*.1) and steps<500:
		steps+=1
	check(steps<500 and pm.pat["fy"]< -7.5 and pm.pat["stuck"]==0,"actual patrol movement descends ramps to the southern exit without teleporting")
	app.save_game()
	var saved:=pm.position()
	app.load_game()
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	check(same_json(app.patrol().position(),saved) and app.patrol().pat["mazeGateway"]["origin"]==4,"live application save/load keeps the deep-floor patrol instead of resetting it to the campus")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
