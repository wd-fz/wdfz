extends "res://tests/support/test_suite.gd"


func test_geometry() -> void:
	var geometry := CampusData.maze_geometry()
	var raw := FileAccess.get_file_as_bytes("res://tests/fixtures/maze-reference.json.gz")
	var reference: Dictionary = JSON.parse_string(raw.decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var wrong: Array = []
	for p: Array in reference["points"]:
		var depth := geometry.depth_at(float(p[0]), float(p[1]), 1.0 / 3.0, float(p[2]))
		var ground := geometry.ground_at(float(p[0]), float(p[1]), float(p[2]) + float(geometry.cfg["step"]))
		if absf(depth - float(p[3])) > 0.00001 or (p[4] == null and is_finite(ground)) or (p[4] != null and absf(ground - float(p[4])) > 0.00001):
			wrong.append(p)
	check(reference["points"].size() == 10545 and wrong.is_empty(), "maze geometry agrees with 10,545 original runtime depth/height samples: %s" % str(wrong.slice(0, 3)))
	var volume := 0
	for box: AABB in geometry.solid_boxes():
		volume += roundi(box.size.x * box.size.y * box.size.z)
	var occupied := 0
	for value: int in geometry._voxels:
		occupied += value
	check(volume == occupied and geometry.solid_boxes().size() < 1000, "merged maze solids preserve every voxel without excessive bodies (%d boxes)" % geometry.solid_boxes().size())


func test_rules() -> void:
	var maze := MazeModule.new(CampusData.maze_geometry(), CampusData.maze_data())
	maze.set_seed(9)
	var pose := maze.enter()
	check(maze.active and maze.geometry.valid_ground_pose(pose), "entering the maze chooses a safe spawn")
	var ctx := {"feet": Vector3.ZERO, "airborne": false, "dead": false, "moving": false, "pitch": 0.0, "ang": 0.0}
	maze.step(1.0, ctx)
	var first := maze.take_events()
	check(absf(float(first[0]["amount"]) + 0.02010556) < 0.0000001, "maze pressure starts at the original per-second drain")
	maze.elapsed = 301.0
	maze.step(0.1, ctx)
	check(maze.drain_rate() > 0.05 and maze.take_events().any(func(e: Dictionary) -> bool: return e["kind"] == "notice"), "pressure grows with time and the five-minute reminder is emitted")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(maze.capture()))
	var restored := MazeModule.new(CampusData.maze_geometry(), CampusData.maze_data())
	check(restored.validate(saved).is_empty(), "maze state validates after a JSON round trip")
	restored.restore(saved)
	check(same_json(restored.enter(pose, true), pose) and restored.elapsed == maze.elapsed, "loading preserves a valid pose and elapsed pressure instead of restarting the visit")
	maze.elapsed = 7201.0
	saved = JSON.parse_string(JSON.stringify(maze.capture()))
	check(restored.validate(saved).is_empty(), "a long maze visit can still be saved without resetting elapsed pressure")
	restored.restore(saved)
	check(restored.elapsed == 7201.0, "long visits retain their accumulated pressure on load")
	var invalid := {"position": [20.0, 0.0, 0.0], "yaw": 0.0, "pitch": 0.0}
	check(restored.geometry.valid_ground_pose(restored.enter(invalid, true)), "an old or blocked saved spawn is repaired before control returns")
	ctx["feet"] = Vector3(0,-14,-20)
	maze.step(0.1, ctx)
	var events := maze.take_events()
	check(maze.falls == 1 and events.any(func(e: Dictionary) -> bool: return e["kind"] == "san" and e["amount"] == -3.0)
		and events.any(func(e: Dictionary) -> bool: return e["kind"] == "respawn" and maze.geometry.valid_ground_pose(e["pose"])), "falling into the void costs three SAN and returns to a safe point")
	check(maze.nearby_exit(Vector3(-3,-8,37), false).get("id") == "exit1" and maze.nearby_exit(Vector3(-7,4,-37), false).get("id") == "exit2", "both exits require the correct position and height")
	check(maze.nearby_exit(Vector3(-3,0,37), false).is_empty() and maze.nearby_exit(Vector3(-3,-8,37), true).is_empty(), "an exit cannot be used from the wrong floor or while falling")
	check(maze.near_chalk(Vector3(2.2,0,1.6), false), "the half stick of chalk can be picked up at the spawn")
	maze.leave()
	check(not maze.active and maze.elapsed == 0.0 and maze.eggs["seen"].is_empty(), "leaving clears transient encounters and pressure")


func test_app_flow() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path)
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/maze-settings.json")
	root.add_child(app)
	await _frames()
	app.start_new_game("hard")
	app._stand_up()
	app.set_physics_process(false) # Drive the rule step explicitly; retain real character physics/rendering.
	var lift := app.elevator()
	lift.ride = {"host":"teach","origin":2,"target":2,"phase":"cabin","rare":true,"remaining":0.0,"pending":null}
	app._apply_result(lift._enter_dream("67"))
	var cut := app.maze_flow.cut
	cut.set_process(false)
	check(app.session.world_id == "lift_dream" and paused and not app.player.enabled and app.school().san == 95.0, "wrong button spends five SAN and enters a frozen live cinematic")
	var clock := app.school().tsec
	await _frames(3)
	check(app.school().tsec == clock and app.maze().elapsed == 0.0, "entry does not advance clock or maze pressure")
	for time in [.1,.24,.5,.7,.86,1.0]:
		cut.apply_frame(time)
		check(cut.cam.global_position.is_finite(), "entry camera is finite at storyboard %s" % time)
	cut.finish()
	await _frames(3)
	check(not paused and app.player.enabled and app.player.camera.current and not is_instance_valid(app.maze_flow.cut), "finishing restores input, pause and the player camera")
	app._campus_interact()
	check(app.session.world_id == "lift_dream" and not is_instance_valid(app.maze_flow.cut), "E in the middle of the maze does not leave")
	app.player.restore_pose({"position":[2.2,.01,1.6],"yaw":0.0,"pitch":0.0})
	await _frames(4)
	app._campus_interact()
	check(app.items().has("chalk"), "the real interaction picks up the half stick of chalk")
	app.items().add("watch")
	app._use_item("watch")
	check(app.ui.toast_text().contains("???"), "watch use reports the lost time")
	app._show_map()
	check((app.ui.map_panel == null or not app.ui.map_panel.visible) and app.ui.toast_text().contains("什么也没有"), "map action stays in play and reports the blank map")
	app.maze().elapsed = 301.0
	app.player.restore_pose({"position":[-7,4.01,-36.8],"yaw":0.0,"pitch":-.3})
	await _frames(4)
	app.save_game()
	var saved: Dictionary = app.saves.read()["data"]
	app.load_game()
	app.set_physics_process(false)
	await _frames(4)
	check(app.maze().elapsed == 301.0 and absf(app.player.position.y-4.0)<.05 and not is_instance_valid(app.maze_flow.cut), "load preserves upper-floor height and pressure without replaying entry")
	check(app.player.gravity_override == 18.0 and app.player.max_fall_speed == 28.0, "maze falling uses the original acceleration and terminal speed")
	app._campus_interact()
	cut = app.maze_flow.cut
	check(is_instance_valid(cut), "grounded E near exit 2 starts its cinematic")
	if is_instance_valid(cut):
		cut.set_process(false)
		cut.apply_frame(.3)
		check(app.session.world_id == "lift_dream", "exit remains in maze until the white transition")
		cut.apply_frame(.45)
		check(app.session.world_id == "lab2" and cut.moved, "exit 2 changes to the other building at the original floor")
		cut.apply_frame(.9)
		cut.finish()
		check(app.session.world_id == "lab2" and app.elevator().ride.is_empty() and not app.maze().active, "exit completion never transfers a second time")
		check(app.player.gravity_override == 0.0 and app.player.floor_snap_length == .25, "normal movement is restored outside the maze")
	# Restoring a previous visit is independent of the now-empty elevator / transient FX.
	app.saves.write(saved)
	app.load_game()
	app.set_physics_process(false)
	await _frames(3)
	app._campus_interact()
	cut = app.maze_flow.cut
	cut.set_process(false)
	cut.finish() # Skip before the transfer frame.
	check(app.session.world_id == "lab2" and not paused, "skipping before the white transition still transfers exactly once")
	app.saves.write(saved)
	app.load_game()
	app.set_physics_process(false)
	app.school().san = 40.0
	app.player.restore_pose({"position":[0,-14,-20],"yaw":0.0,"pitch":0.0})
	app.maze_flow.step(.01)
	check(app.maze().falls == 1 and app.school().san < 37 and app.school().san > 36.99 and app.maze().geometry.valid_ground_pose(app.player.capture_pose()), "falling really respawns the player with the original SAN cost")
	app.items().add("elixir")
	app.school().san = 2.0
	app.player.position.y = -14
	app.maze_flow.step(.01)
	check(not app.story().dead and not app.items().has("elixir") and app.maze().geometry.valid_ground_pose(app.player.capture_pose()), "death protection still permits a safe fall respawn")
	app.school().san = 2.0
	app.player.position.y = -14
	app.maze_flow.step(.01)
	check(app.story().dead and app.story().death_source == "void_fall" and app.story().death_fx == "abyss", "fatal fall uses its own death scene instead of generic SAN death")
	if DisplayServer.get_name() != "headless":
		check(is_instance_valid(app._death_cg) and app._death_cg.fx == "abyss", "the displayed fatal fall actually starts its live scene")
	app.return_to_menu()
	check(not is_instance_valid(app.maze_flow.fx) and not is_instance_valid(app.maze_flow.cut), "menu clears all maze presentation and pending transfers")
	app.start_new_game("hard")
	app._stand_up()
	app.travel("lift_dream", _pose(), false)
	app.set_physics_process(false)
	app.school().san = .000001
	app.maze_flow.step(.1)
	check(app.story().death_source == "void_lost" and app.story().death_fx == "void", "elapsed depletion gets the maze-lost source before the generic SAN settlement")
	if DisplayServer.get_name() != "headless":
		check(is_instance_valid(app._death_cg) and app._death_cg.fx == "void", "the displayed lost death actually starts its live scene")
	app.return_to_menu()
	app.queue_free()
	await _frames()
	paused = false


func test_chalk_and_archive() -> void:
	var marks := MarksModule.new(CampusData.rooms())
	var ctx := {"scene":"lift_dream","x":0.0,"y":0.0,"ang":0.0,"pitch":-.6,"floor":4.0,"eye":1.65,"has_chalk":true,
		"solid":func(_p: Vector2) -> bool: return false, "floor_at":func(_p: Vector2) -> Variant: return 4.0}
	marks.set_context(ctx)
	check(marks.target()["h"] == 4.0, "chalk follows the actual upper floor")
	ctx["floor_at"] = func(_p: Vector2) -> Variant: return null
	marks.set_context(ctx)
	check(not marks.use_chalk() and marks.marks.is_empty(), "chalk cannot be placed over a chasm")
	var low := {"face":"wall","room":"lift_dream","x":0.0,"y":0.0,"a":0.0,"h":1.5,"floor":-8.0}
	marks.place("x",low)
	var upper := low.duplicate()
	upper["floor"] = 4.0
	check(marks._near_mark(upper) == -1 and marks._near_mark(low) == 0, "wall marks on different storeys cannot erase one another")
	var restored := MarksModule.new()
	restored.restore(JSON.parse_string(JSON.stringify(marks.capture())))
	check(restored.marks[0]["f"] == -8.0, "wall height survives a JSON save round trip")
	var empty := DeathArchive.rows({}, {})
	var found := DeathArchive.rows({"sources":{"void_fall":2}}, {})
	check(found.size() == empty.size()+1 and DeathArchive.known(found) == 1, "only an encountered maze death appears in the archive")


func test_death_scenes() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(player)
	await _frames()
	var before := player.capture_pose()
	for id: String in ["void","abyss"]:
		var cg := DeathCG.new()
		root.add_child(cg)
		cg.begin(id,player,world,null,3.6)
		# The previous node was queued for deletion, but the new scene already owns the view.
		await _frames(2)
		check(not world.visible and is_instance_valid(cg.veil_mesh), "deferred deletion of the previous death cannot restore the world or remove the next veil")
		for t in [0,.7,1.2,1.8,2.3,2.98,3.6]:
			cg.update(t)
			check(player.camera.global_transform.is_finite(), "maze death camera remains finite: %s at %s" % [id,t])
		cg.finish()
		check(world.visible and same_json(player.capture_pose(),before), "maze death %s restores world and player pose" % id)
		cg.queue_free()
	player.queue_free()
	world.queue_free()
	await _frames()


func test_physical_routes() -> void:
	var world := CampusWorld.new()
	world.scene_id = "lift_dream"
	root.add_child(world)
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(player)
	player.floor_snap_length = 0.45
	player.enabled = true
	player.restore_pose({"position": [0.0,0.05,0.0], "yaw": 0.0, "pitch": 0.0})
	await _frames(3)
	# Continuous walks through the real collision bodies, with no position snapping at ramps.
	var south := [Vector2(0,13),Vector2(-9,13),Vector2(-15,13),Vector2(-15,23),Vector2(-9,23),Vector2(-9,13),Vector2(-3,13),Vector2(-3,25),Vector2(-6,25),Vector2(-6,28),Vector2(-3,28),Vector2(-3,37)]
	var arrived := await _walk_maze(player, south)
	check(arrived and absf(player.position.y + 8.0) < 0.12, "real player descends the tower and reaches exit 1 at minus eight metres: %s" % player.position)
	player.restore_pose({"position": [0.0,0.05,0.0], "yaw": 0.0, "pitch": 0.0})
	await _frames(3)
	var north := [Vector2(0,-30),Vector2(10.5,-30),Vector2(10.5,-31.5),Vector2(3,-31.5),Vector2(3,-26),Vector2(-3,-26),Vector2(-3,-31.5),Vector2(-7,-31.5),Vector2(-7,-37)]
	arrived = await _walk_maze(player, north)
	check(arrived and absf(player.position.y - 4.0) < 0.12, "real player climbs the bridge and bypasses the broken span to exit 2: %s" % player.position)
	player.queue_free()
	world.queue_free()
	await _frames()


func _walk_maze(player: PlayerController, route: Array) -> bool:
	for target: Vector2 in route:
		var reached := false
		for frame in 1000:
			var d := target - Vector2(player.position.x, player.position.z)
			if d.length() < 0.09:
				reached = true
				break
			player.rotation.y = atan2(-d.x, -d.y)
			player.set_touch_move(Vector2(0,-0.8))
			await physics_frame
			await process_frame
		player.clear_input()
		if not reached:
			print("MAZE ROUTE STUCK at ", player.position, " towards ", target)
			return false
	return true
