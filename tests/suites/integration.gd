extends "res://tests/support/test_suite.gd"


func _test_campus_app() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path)
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/settings.json")
	root.size = Vector2i(1280, 720)
	root.add_child(app)
	await _frames()
	app.start_new_game()
	await _frames(5)
	check(app.session != null and app.router.current.world_id == &"teach1", "new game opens the formal teach1 scene")
	var world := app.router.get_child(0) as CampusWorld
	check(world != null and world.get_node_or_null("Model") != null, "teach1 model loaded from the exported glb")
	check(world.find_children("*", "MultiMeshInstance3D", true, false).size() > 50, "instanced furniture rebuilt as MultiMesh")
	check(world.door_keys().size() == 8, "teach1 has its eight classroom doors as bodies")
	var lit := world.lighting
	check(lit != null and lit.room_lights.size() == 5, "teach1 lamps: three lit classrooms, the corridor and the lift hall (ROOM_LIGHTS)")
	check(lit.live_count() > 0, "lamp panel materials are found for flicker")
	check(lit.sun_at(12.3)["day"] > 0.99 and lit.sun_at(0.0)["day"] < 0.01, "sunAt: full day at noon, night at midnight")
	check(lit.lamp_health(0) == 1.0, "the first lamp of a room always works")
	var start: Array = app.player.capture_pose()["position"]
	check(absf(start[0] - 17.3) < 0.01 and absf(start[2] - 0.39) < 0.01 and app.school().seated, "a run starts seated on the own seat (ClassroomLayout.anchor)")
	check(app.school().at_my_seat("teach1", CampusGeometry.to_world(CampusData.layout("teach1"), start[0], start[2])), "the start seat counts as the own seat")
	Input.action_press("move_left")
	await _frames(2)
	Input.action_release("move_left")
	await _frames(1)
	var stood: Array = app.player.capture_pose()["position"]
	check(not app.school().seated and absf(stood[2] - 1.4456) < 0.15, "moving stands up into the aisle where leaveSeat puts the body")
	# Real physics: walking into the classroom's north window wall must stop.
	var t1 := CampusData.layout("teach1")
	app.player.restore_pose(_campus_pose(t1, CampusGeometry.tile_center(t1, 54, 9), -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	var stop: Array = app.player.capture_pose()["position"]
	var wall_z := CampusGeometry.to_scene(t1, Vector2(0, float(t1["oy"]) + 7 * float(t1["th"])))
	check(stop[2] > wall_z.y + 0.30 and stop[2] < wall_z.y + 0.40, "north wall stops the body at its radius (z=%.3f)" % stop[2])
	# Closed door blocks, open door lets the body through.
	var corridor := CampusGeometry.tile_center(t1, 10, 17)
	app.player.restore_pose(_campus_pose(t1, corridor, -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	var at_door: Array = app.player.capture_pose()["position"]
	var door_edge := CampusGeometry.to_scene(t1, Vector2(0, float(t1["oy"]) + 16 * float(t1["th"])))
	check(at_door[2] > door_edge.y + 0.3, "closed door blocks the corridor side")
	app.player.request_interaction()
	await _frames(3)
	check(app.campus().is_open("teach1:10:15"), "E with no raycast target reaches the campus rules")
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	var through: Array = app.player.capture_pose()["position"]
	check(through[2] < door_edge.y - 1.0, "open door lets the body into the classroom")
	# Walk out of the seamless south door and back in.
	var spec: Dictionary = CampusData.campus()["campus_doors"]["doors"][0]
	var port := CampusGeometry.door_port(t1, spec)
	app.player.restore_pose(_campus_pose(t1, port["p"] - Vector2(0, 6), PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	await _frames(3)
	check(app.router.current.world_id == &"out" and app.session.world_id == "out", "walking through the south door switches to the campus")
	check(app.router.get_child(0) is CampusWorld, "campus outside scene built")
	app.player.place(_campus_pose(null, port["p"] + CampusGeometry.shift_of(t1) + Vector2(0, 8), -PI * 0.5))
	await _frames()
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	await _frames(3)
	check(app.session.world_id == "teach1", "walking back through the doorway re-enters teach1")
	app.pause_game()
	app.save_game()
	var saved: Dictionary = app.saves.read()["data"]
	check(saved["world_id"] == "teach1" and saved["modules"]["campus.world"]["data"]["open_doors"] == ["teach1:10:15"], "save keeps scene and opened doors")
	app.return_to_menu()
	app.load_game()
	await _frames(3)
	var reloaded := app.router.get_child(0) as CampusWorld
	check(app.campus().is_open("teach1:10:15") and reloaded != null, "load restores the campus door state")
	app.return_to_menu()
	for id: String in CampusData.room_ids():
		var err := app.router.switch_to(id)
		check(err.is_empty(), "world %s registered and instantiable" % id)
	app.router.clear()
	print("CASE: integration._test_stair_walk")
	await _test_stair_walk(app)
	app.queue_free()
	await _frames()


## Steer the real CharacterBody3D through scene-metre waypoints (yaw from the heading).


func _test_stair_walk(app: GameApp) -> void:
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var s := CampusPortals.stair_config(CampusData.campus()["stair_layout"], "stair_teach_w")
	var port := CampusPortals.stair_port(s, 0, CampusData.rooms(), CampusData.layout("out"))
	var p: Vector2 = port["p"]
	app.player.restore_pose(_campus_pose(t1, p - Vector2(0, 14), PI * 0.5))
	await _frames()
	await _walk(app, [CampusGeometry.to_scene(t1, p + Vector2(0, 3))])
	check(app.session.world_id == "stair_teach_w", "walking into the west stair doorway enters the stairwell")
	# One full storey along StairGeometry's walking line, then out of the corridor.
	await _walk(app, [Vector2(-1.25, 0.8), Vector2(-1.25, 5.6), Vector2(-1.25, 6.4), Vector2(1.25, 6.4), Vector2(1.25, 5.6), Vector2(1.25, 0.8), Vector2(0.0, -0.3), Vector2(0.0, -3.2)], 240)
	check(app.session.world_id == "teach2", "climbing one flight pair and walking out reaches teach2 (now %s, y=%.2f)" % [app.session.world_id, app.player.position.y])
	check(absf(app.player.position.y) < 0.2, "teach2 floor is at the scene's own ground level")
	print("CASE: integration._test_spiral_walk")
	await _test_spiral_walk(app)
	print("CASE: integration._test_elevator_walk")
	await _test_elevator_walk(app)
	print("CASE: integration._test_patrol_app")
	await _test_patrol_app(app)
	print("CASE: integration._test_anomaly_fx")
	await _test_anomaly_fx(app)
	print("CASE: integration._test_audio")
	await _test_audio(app)
	print("CASE: integration._test_cut_lifecycle")
	await _test_cut_lifecycle(app)
	print("CASE: integration._test_whitelist_route")
	await _test_whitelist_route(app)
	print("CASE: integration._test_achievement_flow")
	await _test_achievement_flow(app)
	print("CASE: integration._test_archive")
	await _test_archive(app)
	print("CASE: integration._test_death_scene")
	await _test_death_scene(app)
	print("CASE: integration._test_car_route")
	await _test_car_route(app)
	print("CASE: integration._test_portal_route")
	await _test_portal_route(app)
	print("CASE: integration._test_dismissal_route")
	await _test_dismissal_route(app)
	print("CASE: integration._test_cyber_route")
	await _test_cyber_route(app)
	print("CASE: integration._test_vault_app")
	await _test_vault_app(app)
	print("CASE: integration._test_lesson_app")
	await _test_lesson_app(app)
	print("CASE: integration._test_speedrun_app")
	await _test_speedrun_app(app)
	print("CASE: integration._test_marks_app")
	await _test_marks_app(app)
	print("CASE: integration._test_sensory_app")
	await _test_sensory_app(app)
	print("CASE: integration._test_settings_app")
	await _test_settings_app(app)
	print("CASE: integration._test_score_app")
	await _test_score_app(app)
	print("CASE: integration._test_checkup_app")
	await _test_checkup_app(app)
	print("CASE: integration._test_death_flow")
	await _test_death_flow(app)
	app.return_to_menu()


## Synthesised sound: every cue exists, layers follow the context, mute works, rules are untouched.


func _test_audio(app: GameApp) -> void:
	var fx := app.audio
	check(fx.ids().size() == 150, "the baked bank includes all 150 original recipes, including maze and crowd (%d)" % fx.ids().size())
	check(fx.ids().has("void.ping") and fx.ids().has("death.void") and fx.ids().has("step.void"), "the playable maze has its own soundscape and death cues")
	for id: String in ["step.tile", "step.garage", "threat.heartLow", "event.bellEnd", "event.dismissal", "death.generic", "ui.click", "anomaly.bell13", "music.box"]:
		var stream := fx.stream_of(id)
		check(stream is AudioStreamOggVorbis and stream.get_length() > 0.02 and not (stream as AudioStreamOggVorbis).loop, "%s is a baked one-shot" % id)
	check(fx.stream_of("nothing") == null and not fx.play("nothing"), "an unknown sound is nothing, not an error")
	var court := Vector2.ZERO
	var out := CampusData.layout("out")
	for o: Dictionary in out["objects"]:
		if o["k"] == "court":
			court = Vector2(float(o["x"]) + float(o["w"]) * 0.5, float(o["y"]) + float(o["h"]) * 0.5) * float(out["SC"])
	check(AudioFx.surface("garage1", false, Vector2.ZERO, [], 1.0) == "garage" and AudioFx.surface("teach6", false, Vector2.ZERO, [], 1.0) == "roof"
		and AudioFx.surface("bell1", true, Vector2.ZERO, [], 1.0) == "stair" and AudioFx.surface("teach1", false, Vector2.ZERO, [], 1.0) == "tile"
		and AudioFx.surface("out", false, court, out["objects"], float(out["SC"])) == "court" and AudioFx.surface("out", false, Vector2(-9999, -9999), out["objects"], float(out["SC"])) == "road",
		"footing: garage, roof, spiral stairs, tile; outdoors the court, otherwise the road")
	fx.update(0.1, {"menu": true})
	for _i in 30:
		fx.update(0.1, {"menu": true})
	check(fx.bed_playing("pad_menu") and fx.bed_gain("pad_menu") > 0.02, "the menu has its low pad")
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	app.travel("teach1", _campus_pose(t1, CampusGeometry.tile_center(t1, 30, 17), PI), false)
	app.patrol().pat["safety"] = 999.0
	var base := {"scene": "teach1", "out": false, "san": 100.0, "surface": "tile"}
	fx.played.clear()
	var walk := base.duplicate()
	walk["moving"] = true
	fx.update(0.1, walk)
	check(fx.played.has("step.tile"), "walking indoors steps on tile")
	fx.played.clear()
	var low := base.duplicate()
	low["bpm"] = 120.0
	low["body"] = 0.8
	fx.update(0.1, low)
	check(fx.played.has("threat.heartLow") and fx.played.has("threat.breath"), "a shaken body: heartbeat at the sensory rate and breath")
	fx.played.clear()
	var pat := base.duplicate()
	pat["patrol_pos"] = Vector3(3, 0, 3)
	fx.update(0.1, pat)
	check(fx.played.has("step.tile"), "the patroller's footsteps play in space")
	for _i in 30:
		fx.update(0.1, base)
	check(fx.bed_playing("hum") and fx.bed_playing("pad_in_calm") and not fx.bed_playing("wind"), "indoors: the lamp hum and the indoor pad, no wind")
	var outdoors := {"scene": "out", "out": true, "san": 100.0, "anomaly": "rain", "night": 0.0}
	for _i in 40:
		fx.update(0.1, outdoors)
	check(fx.bed_playing("wind") and fx.bed_playing("rain") and fx.bed_playing("pad_day_tense") and fx.bed_gain("hum") < 0.001, "outdoors in the rain: wind, rain and a tenser day pad; the hum fades")
	var dark := base.duplicate()
	dark["blackout"] = true
	for _i in 40:
		fx.update(0.1, dark)
	check(fx.bed_gain("hum") < 0.001, "a blackout kills the hum")
	fx.played.clear()
	fx.anomaly_start("bell13")
	fx.death("swarm")
	fx.death("no_such_death")
	check(fx.played.has("anomaly.base") and fx.played.has("anomaly.bell13") and fx.played.has("death.swarm") and fx.played.has("death.generic"),
		"an anomaly opens with the low drop and its own recipe; a death plays its own sound, or the generic one")
	fx.played.clear()
	app._add_item("pen")
	app.ui.flash_light(0.5)
	check(fx.played.has("ui.pickup") and app.ui.bolt_level() > 0.3, "picking up plays the pickup; lightning whitens the screen")
	var weird := app.anomaly()
	weird.events.append({"kind": "smile", "mode": "jump"})
	app._anomaly_step(0.0, app.school(), CampusData.layout("teach1"), app.player.capture_pose())
	check(fx.played.has("threat.smileJump"), "the smile in your face screams at the ear")
	fx.update(0.1, base)
	fx.play("event.bellEnd")
	await _frames(3)
	check(app.ui.captions_text().contains("下课铃"), "the HUD shows the caption under the status card")
	app.audio.muted = true
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "mute silences the master bus")
	app.audio.muted = false
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "unmute restores it")
	fx.stop_all()
	check(not fx.bed_playing("wind") and not fx.bed_playing("hum"), "stop_all stops the beds")


## Original anomaly props follow the module state and vanish when it ends.


func _test_anomaly_fx(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var spot := CampusGeometry.tile_center(t1, 30, 17)
	app.travel("teach1", _campus_pose(t1, spot, PI), false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	var fx: AnomalyFx = app._campus_world().anomaly_fx
	check(fx != null and fx.current() == "" and fx.shown_count() == 0, "no anomaly, no props")
	var weird := app.anomaly()
	var me := Vector2(spot.x, spot.y)
	var datas := {
		"moth": {"src": {"x": me.x + 40.0, "y": me.y}}, "exercise": {"src": {"x": me.x + 40.0, "y": me.y}}, "hand": {"chosen": null},
		"chalk": {"until": 800.0}, "roster": {"rx": me.x, "ry": me.y, "done": false}, "leak": {"pts": [{"x": me.x + 20.0, "y": me.y}, {"x": me.x + 30.0, "y": me.y + 9.0}]},
		"rite": {"c": {"x": me.x + 30.0, "y": me.y}}, "twin": {"x": me.x + 40.0, "y": me.y, "room": "teach1"},
		"repeat": {"chosen": null}, "stare": {}, "feast": {}, "shadow": {"acc": 0.0}, "lamps": {}, "cold": {"chosen": null},
	}
	for id: String in datas:
		weird.an["id"] = id
		weird.an["active"] = true
		weird.an["t"] = 0.0
		weird.an["next"] = 999.0
		weird.an["data"] = (datas[id] as Dictionary).duplicate(true)
		weird.an["data"]["scene"] = "teach1"
		await _frames(2)
		check(fx.current() == id and fx.shown_count() > 0, "%s draws its props" % id)
		weird.end_now()
		await _frames(2)
		check(fx.current() == "" and fx.shown_count() == 0, "%s props go away with it" % id)
	weird.an["id"] = "broad"
	weird.an["active"] = true
	weird.an["data"] = {"scene": "teach1"}
	await _frames(2)
	check(fx.shown_count() > 0, "the broadcast call shows its original pulsing speakers")
	weird.an["id"]="turn"
	weird.an["data"]={"scene":"teach1","chosen":null,"smile":false}
	await _frames(2)
	check(fx.shown_count()==0,"the shoulder event uses its dedicated smile/choice presentation without an invented following figure")
	weird.end_now()
	weird.an["active"] = true
	weird.an["data"] = {"scene": "out"}
	weird.an["id"] = "moth"
	weird.an["data"]["src"] = {"x": 0.0, "y": 0.0}
	await _frames(2)
	check(fx.shown_count() == 0, "props only show in the scene the anomaly started in")
	weird.end_now()
	# The cup and the cola are outdoor anomalies: indoors the rules end them at once.
	var out := CampusGeometry.to_scene(null, Vector2(1000, 1000))
	app.travel("out", {"position": [out.x, 0.05, out.y], "yaw": 0.0, "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	fx = app._campus_world().anomaly_fx
	for id: String in ["cup", "cola"]:
		weird.an["id"] = id
		weird.an["active"] = true
		weird.an["t"] = 0.0
		weird.an["next"] = 999.0
		weird.an["data"] = {"scene": "out", "phase": 0, "wob": 30.0, "warn": 30.0, "wall": {"x": 520.0, "y": 480.0, "d": 40.0, "id": "teach", "m": 5.0}}
		await _frames(2)
		check(fx.current() == id and fx.shown_count() > 0, "%s draws its prop outdoors" % id)
		weird.end_now()
		await _frames(2)
		check(fx.shown_count() == 0, "%s prop goes away" % id)


func _test_patrol_app(app: GameApp) -> void:
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var spot := CampusGeometry.tile_center(t1, 12, 17)
	app.travel("teach1", _campus_pose(t1, spot, -PI * 0.5), false)
	await _frames(3)
	var watcher := app.patrol()
	check(app.campus().hint("teach1", app.player.capture_pose()) == "躲进柜子", "the locker cell offers to hide")
	app._campus_interact()
	await _frames(2)
	check(bool(watcher.hide["on"]) and app.player.hiding, "E on the locker hides the player")
	var inside: Array = app.player.capture_pose()["position"]
	var cell_center := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 12, 16))
	check(absf(inside[0] - cell_center.x) < 0.05 and absf(inside[2] - (cell_center.y + 0.12 * 1.0)) < 0.4, "the body sits inside the locker cell")
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	var still: Array = app.player.capture_pose()["position"]
	check(Vector2(still[0] - inside[0], still[2] - inside[2]).length() < 0.01, "a hidden player cannot walk")
	app._campus_interact()
	await _frames(2)
	check(not bool(watcher.hide["on"]) and not app.player.hiding, "E again steps out")
	# The figure appears when the patroller is in the player's scene.
	watcher.pat["room"] = "teach1"
	watcher.pat["x"] = CampusGeometry.tile_center(t1, 30, 17).x
	watcher.pat["y"] = CampusGeometry.tile_center(t1, 30, 17).y
	watcher.pat["safety"] = 3.6
	await _frames(4)
	var world := app.router.get_child(0) as CampusWorld
	check(watcher.figure_visible() and world.patrol_figure_shown(), "the patroller figure is drawn in the scene it walks in")
	watcher.pat["room"] = "admin1"
	await _frames(3)
	check(not world.patrol_figure_shown(), "and disappears when it is elsewhere")
	app.return_to_menu()


## Walk the whole whitelist route through the real interactions, ending on the card.


func _test_whitelist_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.items().add("usb")
	app.items().add("pen")
	check(await _press_terminal(app, "lab3"), "E at the lab3 terminal reaches the route rules")
	check(app.routes().hacked, "the USB drive hacks the whitelist through the real interaction")
	check(await _press_terminal(app, "admin3"), "E at the admin3 data machine reaches the route rules")
	check(app.routes().data_synced, "and syncs it")
	var gate := CampusGeometry.to_scene(null, Vector2(401, 1250))
	app.travel("out", {"position": [gate.x, 0.05, gate.y], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	check(app.campus().hint("out", app.player.capture_pose()) == "西小门", "the west gate hint appears")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "the quiz opens as a choice")
	for _n in 3:
		var q: Dictionary = RoutesModule.QUESTIONS[app.routes().face_quiz["order"][int(app.routes().face_quiz["done"])]]
		app._choice_made(int(q["answer"]))
		await _frames(2)
	check(app.ui.choice_open(), "the green gate choice is open")
	app._choice_made(0)
	await _frames(2)
	await _skip_cut(app)
	check(app.story().ended == "face" and app.ui.ending_panel != null and app.ui.ending_panel.visible, "the ending card is shown")
	check(not app.saves.exists() and not app.player.enabled, "the run is over and the save is cleared")
	check(FileAccess.file_exists(app.saves.side_path("ends.json")), "the ending is recorded")
	app.pause_game()
	check(not paused, "no pause menu after an ending")
	app.return_to_menu()
	check(not app.ui.ending_panel.visible and app.session == null, "back to the menu hides the card")


## Stand next to a 'D' cell of `scene` and press E until the rules answer with a terminal.


func _test_achievement_flow(app: GameApp) -> void:
	app.saves.clear()
	var profile := FileAccess.file_exists(app._profile_path())
	if profile:
		DirAccess.remove_absolute(app._profile_path())
	app.start_new_game()
	await _frames(3)
	app.fact({"kind": "day", "day": 2})
	check(app.achievements().unlocked.has("n.day2") and FileAccess.file_exists(app._profile_path()), "an unlock is stored in the profile file")
	app.return_to_menu()
	app._show_achievements()
	check(app.ui.ach_panel != null and app.ui.ach_panel.visible, "the menu opens the list")
	var back := AchievementsModule.new(25)
	app._load_profile(back)
	check(back.unlocked.has("n.day2"), "the next run starts from the stored profile")
	app.start_new_game()
	await _frames(3)
	check(app.achievements().unlocked.has("n.day2") and not app.ui.ach_panel.visible, "a new run loads the profile and hides the list")
	DirAccess.remove_absolute(app._profile_path())


## The archive lists each real cause once, counts repeats, and keeps unseen ones hidden.


func _test_archive(app: GameApp) -> void:
	var rows := DeathArchive.rows({"sources": {"patrol": 3, "an:rain": 1}}, {"face": 1})
	check(rows.size() == DeathArchive.DEATHS.size() + DeathArchive.ENDS.size() and DeathArchive.known(rows) == 3, "the archive counts two deaths and one ending as recorded")
	var by_name := {}
	for r: Dictionary in rows:
		by_name[r["name"]] = r
	check(by_name["点名"]["on"] and by_name["点名"]["count"] == 3 and not by_name["那根弦"]["on"], "a repeated death only adds to its counter; unseen ones stay locked")
	check(rows.filter(func(r: Dictionary) -> bool: return not r["on"] and r["memo"] != "").size() > 0 and DeathArchive.DEATHS.all(func(d: Array) -> bool: return not String(d[0]).begins_with("void")), "locked rows carry the record text for the UI to withhold, and no maze deaths are listed")
	var ids := {}
	for k in StoryModule.SOURCES:
		ids[k] = true
	for k: String in ["laugh", "trap_out", "trap_wall", "trap_beg"]:
		ids[k] = true # kill sources without a cause text in the old table either
	for d: Array in DeathArchive.DEATHS:
		check(ids.has(d[0]) or String(d[0]).begins_with("an:") and AnomalyModule.IDS.has(String(d[0]).substr(3)), "archive entry %s is a real kill source" % d[0])
	app.saves.clear()
	app.return_to_menu()
	app._show_archive()
	check(app.ui.ach_panel != null and app.ui.ach_panel.visible, "the menu opens the archive")


func _test_death_scene(app: GameApp) -> void:
	check(GameUI.death_style("drown")[0] == 1 and GameUI.death_style("swarm")[0] == 2 and GameUI.death_style("floor")[0] == 3 and GameUI.death_style("grip")[0] == 4 and GameUI.death_style("unknown")[0] == 0, "each family of causes has its own death scene style")
	app.ui.show_death_scene("drown", 0.5)
	check(app.ui.death_scene_style() == 1 and app.ui._death_fade.visible, "the scene shows with its style")
	app.ui.show_death_scene("drown", 0.0)
	check(not app.ui._death_fade.visible, "no progress, no scene")
	app.ui.hide_death()
	check(not app.ui._death_fade.visible, "hiding the death card hides the scene")


## The car route through the app: the plate, the key, the drive and the 《闸门》 card.


func _test_car_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	var cars := app.garage()
	var right := cars.car_right_cell().split(":")
	var g := CampusData.layout("garage1")
	var c := int(right[0])
	var r := int(right[1])
	var stand := CampusGeometry.tile_center(g, c, r + 1)
	app.travel("garage1", _campus_pose(g, stand, -PI * 0.5), false)
	app.patrol().pat["safety"] = 999.0
	await _frames(3)
	cars.roam["stage"] = "wait"
	cars.roam["waitT"] = 999.0
	cars.roam["x"] = -1e6
	cars.roam["on"] = true
	check(app.campus().hint("garage1", app.player.capture_pose()).begins_with(GarageModule.car_name(c, r)), "the car hint shows its plate")
	app.items().add("key")
	app._use_item("key")
	check(app.ui.toast_text().contains(cars.key_label()), "the key names the plate of the right car")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at a car offers to try the key")
	app._choice_made(0)
	for _i in 30:
		await process_frame
		if app.driving():
			break
	var waited := 0
	while not app.driving() and waited < 200:
		if is_instance_valid(app._ending_cut) and app._ending_cut.on:
			await _skip_cut(app)
		await process_frame
		waited += 1
	check(app.driving() and app._drive_view != null and app.session.world_id == "out", "the right car starts the drive on the road out")
	check(not app._campus_world().visible, "the campus is hidden behind the road")
	var d: Dictionary = cars.chase
	d["distance"] = 319.0
	d["speed"] = 20.0
	d["x"] = -2.0
	d["nextObstacle"] = 6
	d["nextFork"] = 2
	Input.action_press("move_forward")
	await _frames(4)
	Input.action_release("move_forward")
	await _skip_cut(app)
	check(app.story().ended == "car" and app.ui.ending_panel.visible and not app.driving(), "driving out is the 《闸门》 ending")
	check(app.achievements().unlocked.has("e.end_car") and app.achievements().unlocked.has("e.firstcar"), "with its achievements")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## Stand next to a `ch` tile of `scene` facing it so that E gives `key`; returns false when none.


func _test_portal_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	check(await _face_tile(app, "lab1", "K", "facility"), "the physics bench can be reached")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the bench offers the tunnel")
	app._choice_made(0)
	await _frames(3)
	check(app.session.world_id == "portal_tunnel", "the tunnel is entered")
	check(await _face_tile(app, "portal_tunnel", "u", "facility"), "the diary can be reached")
	app._campus_interact()
	await _frames(2)
	check(bool(app.facilities().portal["diary"]), "the diary is read")
	var answers := {"lab2": [1], "lab4": [2], "lab5": [1, 2, 0]}
	for scene: String in answers:
		check(await _face_tile(app, scene, "K", "facility"), "the %s bench can be reached" % scene)
		for pick: int in answers[scene]:
			app._campus_interact()
			await _frames(2)
			app._choice_made(pick)
			await _frames(2)
	check(bool(app.facilities().portal["sketch"]), "the three blueprints are found through the benches")
	for k: String in FacilitiesModule.PORTAL_PARTS:
		app.items().add(k)
	check(await _face_tile(app, "lab1", "K", "facility"), "back at the bench")
	app._campus_interact()
	await _frames(2)
	app._choice_made(0)
	await _frames(2)
	check(bool(app.facilities().portal["open"]), "the circle opens")
	await _frames(2)
	check(app._campus_world().portal_shown(), "the rig stands on the bench with its door open")
	await create_timer(2.8).timeout
	await _frames(2)
	check(app.ui.choice_open(), "after a moment the circle asks")
	app._choice_made(0)
	await _frames(2)
	await _skip_cut(app)
	check(app.story().ended == "portal" and app.ui.ending_panel.visible, "walking in is the 《门》 ending")
	check(app.achievements().unlocked.has("e.end_portal"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## 《放学》 through the app: the microphone held with E, the bell, the crowd, the north gate.


func _test_dismissal_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	var day := app.school()
	day.day = 2
	day.tsec = 1100.0
	for k: String in ["notice1", "notice2", "notice3", "notice4"]:
		app.items().add(k)
	var radio := app.broadcast()
	radio.b["book"] = true
	radio.b["fuse"] = true
	var a2 := CampusData.layout("admin2")
	var station := _spot("admin2", BroadcastModule.STATION) + Vector2(0, 9)
	app.travel("admin2", _campus_pose(a2, station, -PI * 0.5), false)
	await _frames(2)
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the station opens its menu")
	app._choice_made(3)
	await _frames(2)
	check(app._mic_open and not app.ui.choice_open() and app._mic_panel.visible and not app.get_tree().paused, "the microphone panel opens without pausing the world")
	check(app._mic_panel.chooser.item_count == 4 and app._mic_panel.hold_button.text == "按住朗读 · 空格", "it lists the four papers in hand and offers the hold-to-read button")
	Input.action_press("interact")
	for n in 4:
		for _i in 32:
			app._broadcast_step(0.5)
		if n < 3:
			check(int(radio.b["completed"]) == n + 1, "page %d is read while E is held" % (n + 1))
			radio.select("notice%d" % (n + 2))
	Input.action_release("interact")
	check(radio.b["phase"] == "bell" and not app._mic_open, "the fourth page rings the bell")
	app.travel("out", {"position": [0, 0.05, 0], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(2)
	var won := false
	for _i in 60:
		var p := radio.crowd()
		if not p.is_empty():
			var s := CampusGeometry.to_scene(null, Vector2(float(p["x"]), float(p["y"])))
			app.player.place({"position": [s.x, 0.05, s.y], "yaw": 0.0, "pitch": 0.0})
		app._broadcast_step(1.0)
		await process_frame
		if app.story().ended != "":
			won = true
			break
	await _skip_cut(app)
	check(won and app.story().ended == "dismissal" and app.ui.ending_panel.visible, "following the crowd out of the north gate is 《放学》")
	check(app.achievements().unlocked.has("e.end_dismissal"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## 《网安仙人》 through the app: the lab3 computer, the terminal typed into, ten minutes, the card.


func _test_cyber_route(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.items().add("phone")
	var net := app.phone()
	net.set_context(app._phone_context())
	net.acquire()
	net.device["network"] = true
	net.device["wireless"] = {"status": "complete", "elapsed": 200.0, "target": 200.0}
	net.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	check(await _face_tile(app, "lab3", "n", "facility"), "a lab3 computer can be reached")
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the computer opens its menu")
	app._choice_made(2)
	await _frames(2)
	check(app.ui.terminal_open() and not app.player.enabled, "the terminal opens and takes the keyboard")
	for line: String in _solve_lines(net.puzzle):
		app.ui.terminal_command.emit(line)
		await _frames(1)
	check(net.termination["status"] == "accepted", "typing the solution submits the shutdown")
	app.ui.terminal_closed.emit()
	await _frames(1)
	check(not app.ui.terminal_open() and app.player.enabled, "closing the terminal gives the player back")
	app._phone_step(599.0)
	check(app.story().ended == "", "not before ten minutes")
	app._phone_step(2.0)
	await _frames(2)
	await _skip_cut(app)
	check(app.story().ended == "cyber" and app.ui.ending_panel.visible, "surviving ten minutes is 《网安仙人》")
	check(app.achievements().unlocked.has("e.end_cyber"), "with its achievement")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## Over a bridge railing through the app: E, confirm, fall, land outside hurt.


func _test_vault_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	var l1 := CampusData.layout("link1")
	app.travel("link1", _campus_pose(l1, CampusGeometry.tile_center(l1, 1, 10), PI), false)
	await _frames(2)
	app._campus_interact()
	await _frames(2)
	check(app.ui.choice_open(), "E at the railing asks")
	app._choice_made(0)
	for _i in 90:
		await process_frame
		if app.session.world_id == "out":
			break
	await _frames(3)
	check(app.session.world_id == "out" and app.body().injury == 45.0 and app.player.enabled, "the fall ends on the ground outside, hurt")
	check(app.player.speed_multiplier < 1.0 and app.achievements().unlocked.has("n.vault"), "walking slower, with 换一条路")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## A desk question and studying until the bell, through the app.


func _test_lesson_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.patrol().pat["safety"] = 999.0
	check(app.school().seated, "the run starts seated in class")
	var before := app.school().san
	app._lesson_press()
	await _frames(1)
	check(app.investigation().visible("desk") and not app.ui.choice_open(), "the first R at the own seat reads the parking ticket (the investigation starts there)")
	app._lesson_press()
	await _frames(1)
	check(app.ui.choice_open() and app._choice_left > 11.0, "R opens the desk question with its timer")
	var task: Dictionary = DayModule.TASKS[int(app.days().lessons.values()[0]["task"])]
	app._choice_made(int(task["answer"]))
	await _frames(1)
	check(app.school().san >= minf(100.0, before + 1.9) and app.achievements().unlocked.has("n.desk"), "the right answer helps")
	app._lesson_press()
	await _frames(1)
	app._choice_made(0)
	var t0 := app.school().tsec
	for _i in 30:
		await physics_frame
	var fast := app.school().tsec - t0
	app._lesson_press()
	var t1 := app.school().tsec
	for _i in 30:
		await physics_frame
	var slow := app.school().tsec - t1
	check(app.days().waiting == null and fast > slow * 3.0, "studying runs the class faster (R stops it)")
	app.return_to_menu()
	DirAccess.remove_absolute(app._profile_path())


## A speedrun from the menu: it keeps away from the normal save and records its time.


func _test_speedrun_app(app: GameApp) -> void:
	app.saves.clear()
	if FileAccess.file_exists(app._speedrun_path()):
		DirAccess.remove_absolute(app._speedrun_path())
	app.start_new_game()
	await _frames(2)
	app.save_game()
	check(app.saves.exists(), "a normal save exists")
	app.return_to_menu()
	app._speedrun_menu()
	app._choice_made(0)
	app._choice_made(4)
	await _frames(2)
	check(app.speedrun.active() and app.opening_busy(), "speedrun: talent, prologue")
	await _skip_opening(app)
	await _frames(2)
	check(app.speedrun.run["status"] == "running" and app.ui.speedrun_text != "", "the clock starts at the first move and shows")
	app.save_game()
	app._reach_ending("face")
	await _frames(1)
	check(app.saves.exists() and FileAccess.file_exists(app._speedrun_path()), "the ending records the time and leaves the normal save alone")
	check(app._read_speedrun()["best"].has(Speedrun.key("easy", "face")), "a personal best for 《白名单》 on 预知梦")
	app.return_to_menu()
	app._speedrun_menu()
	app._choice_made(2)
	await _frames(1)
	check(app.ui.ach_panel.visible, "the records list opens")
	DirAccess.remove_absolute(app._speedrun_path())
	DirAccess.remove_absolute(app._profile_path())
	app.saves.clear()


## Chalk through the app, and last run's × in the next run.


func _test_marks_app(app: GameApp) -> void:
	app.saves.clear()
	if FileAccess.file_exists(app.saves.side_path("last_life.json")):
		DirAccess.remove_absolute(app.saves.side_path("last_life.json"))
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.items().add("chalk")
	var t1 := CampusData.layout("teach1")
	app.travel("teach1", _campus_pose(t1, _wall_spot(t1), PI), false)
	await _frames(2)
	app._use_item("chalk")
	await _frames(1)
	check(app.ui.choice_open(), "using the chalk asks what to draw")
	app._choice_made(0)
	await _frames(2)
	check(app.marks().marks.size() == 1 and app._marks_nodes != null and app._marks_nodes.get_child_count() == 1, "the mark is drawn on the wall")
	app.story().diff = "hard"
	app.kill("test", "vignette", "patrol")
	await _frames(1)
	var ll: Variant = app._read_side("last_life.json")
	check(ll is Dictionary and ll["scene"] == "teach1", "the death place is kept for the next run")
	app.return_to_menu()
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.travel("teach1", _campus_pose(t1, CampusGeometry.tile_center(t1, 30, 17), PI), false)
	await _frames(3)
	check(app.marks().last_life is Dictionary and app._marks_nodes.get_child_count() == 1, "the next run shows the last life's × there")
	app.return_to_menu()
	DirAccess.remove_absolute(app.saves.side_path("last_life.json"))
	DirAccess.remove_absolute(app._profile_path())


func _test_checkup_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(2)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.school().day = 3
	app.days().day_events["3"] = "checkup"
	app.school().tsec = 625.0
	var a1 := CampusData.layout("admin1")
	var at := Vector2(float(a1["ox"]) + 1.6 * float(a1["tw"]), float(a1["oy"]) + 15.45 * float(a1["th"]))
	app.travel("admin1", _campus_pose(a1, at, PI), false)
	await _frames(3)
	var w := app._campus_world()
	check(w != null and w.checkup_shown() and w.checkup_queue_blocks(), "on the checkup day admin1 has the rule, scale, chart and a queue that blocks the corridor")
	app._campus_interact()
	await _frames(1)
	check(app.tales().checkup_done(), "pressing E at the rule in the window is the checkup")
	app.school().tsec = 700.0
	await _frames(2)
	check(not w.checkup_queue_blocks(), "after 11:05 the queue is gone")


func _test_sensory_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	check(not app.ui.sensory_on(), "a calm start draws no low-SAN picture")
	app.school().san = 10.0
	await _frames(40)
	check(app.ui.sensory_on() and float(app._sense_view["tunnel"]) > 0.5 and float(app._sense_view["bpm"]) > 100.0, "low SAN narrows the picture and quickens the heart, with no number on the HUD")
	check(float(app._sense_view["halo"]) > 0.5 and float(app._sense_view["warp"]) > 0.0, "low SAN also blooms the lamps and warps the picture")
	app.audio.pulse_t = 0.0
	app.audio.inhale_t = 0.3
	await _frames(1)
	var fresh := float(app._sense_view["pulse_env"])
	var pressed := float(app._sense_view["inhale"])
	app.audio.pulse_t = 1.0
	app.audio.inhale_t = 2.0
	await _frames(1)
	check(fresh > 0.5 * float(app._sense_view["pulse"]) and float(app._sense_view["pulse_env"]) < 0.05 * float(app._sense_view["pulse"]), "the view tightens on the heartbeat and relaxes within a second")
	check(pressed > 0.3 and float(app._sense_view["inhale"]) == 0.0, "the picture presses in as the breath is taken and is back after 1.6 s")
	var ghosted := 0.0
	for _i in 600:
		app._sense_view = {}
		await _frames(1)
		ghosted = maxf(ghosted, float(app._sense_view.get("ghost_env", 0.0)))
		if ghosted > 0.0:
			break
	check(ghosted > 0.0 and ghosted <= float(app._sense_view["ghost"]) + 0.0001, "at very low SAN faint ghost copies drift now and then")
	app.return_to_menu()
	await _frames(2)
	check(not app.ui.sensory_on(), "back at the menu the picture is clear")


func _test_settings_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.ui.settings_requested.emit()
	await _frames(2)
	check(app.ui.settings_panel != null and app.ui.settings_panel.visible, "the settings panel opens")
	app.ui.setting_changed.emit("vol", 40)
	app.ui.setting_changed.emit("amb", 0)
	app.ui.setting_changed.emit("captions", 2)
	app.ui.setting_changed.emit("mouse", 200)
	app.ui.setting_changed.emit("reduce_flash", 1)
	app.ui.setting_changed.emit("bright", 120)
	app.ui.setting_changed.emit("shake", 0)
	var before_quality := app.session.capture(app.player.capture_pose())
	var collision_before := app._campus_world().get_node("Collision").get_instance_id()
	app.ui.setting_changed.emit("quality", 0)
	check(same_json(app.session.capture(app.player.capture_pose()), before_quality), "changing quality does not modify the run or player pose")
	await _frames(3)
	check(absf(app.audio.volume - 0.4) < 0.0001 and not app.audio.ambience and app.audio.captions.mode == 2, "volume, ambience and the caption mode take effect")
	check(absf(app.player.mouse_sensitivity - 0.005) < 0.000001, "look sensitivity follows the setting")
	var cw := app._campus_world()
	check(cw.visual_tier == 0 and cw.get_node("Collision").get_instance_id() == collision_before and cw.lighting.live_count() > 0, "quality replaces the current visual models and rebinds lamps without replacing physics")
	check(not app.player.view_motion.shake_enabled, "the shake setting reaches the player camera")
	check(cw.lighting.reduce_flash and absf(cw.lighting.brightness - 1.2) < 0.0001, "reduce flash and brightness reach the lighting")
	check(absf(app.get_viewport().scaling_3d_scale - 0.55) < 0.0001, "the 流畅 tier renders at 55 %% of the resolution")
	app.ui.setting_changed.emit("distortion", 0)
	app.school().san = 10.0
	await _frames(30)
	check(float(app._sense_view["warp"]) == 0.0 and float(app._sense_view["tunnel"]) > 0.5, "distortion off keeps the static narrowing but stops the warping")
	var saved := GameSettings.new(app.settings.path)
	saved.load_file()
	check(saved.get_int("vol") == 40 and saved.get_int("quality") == 0, "changes are saved immediately")
	app.ui.setting_changed.emit("reset_comfort", 0)
	check(app.settings.get_int("mouse") == 100 and app.settings.get_int("vol") == 40, "restoring comfort defaults keeps the sound")
	app.school().san = 100.0
	app.ui.setting_changed.emit("quality", 2)
	app.ui.setting_changed.emit("reduce_flash", 0)
	app.ui.setting_changed.emit("distortion", 2)
	app.ui.setting_changed.emit("vol", 70)
	app.ui.setting_changed.emit("amb", 1)
	app.ui.setting_changed.emit("captions", 1)
	app.ui.setting_changed.emit("bright", 100)
	app.ui.setting_changed.emit("shake", 1)
	app.ui.settings_panel.visible = false
	app.items().add("coil")
	app.facilities().flags["coil"] = true
	app._drop_item("coil")
	check(not app.items().has("coil") and app.facilities().flags["coil"] == false, "a dropped portal material can be taken again from where it was found")
	app.return_to_menu()
	await _frames(2)


func _test_score_app(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(4)
	app.patrol().pat["safety"] = 999.0
	var sm := app.runscore()
	check(sm != null and sm.run.begins_with("s") and sm.ledger.is_empty() and app._runlog.run == sm.run, "a new game starts a score ledger and a replay log")
	await _frames(30)
	check(app._runlog.samples.size() >= 1 and app._runlog.events.size() >= 0 and sm.min_san <= 100.0, "the log samples the player and the lowest SAN is watched")
	app.fact({"kind": "anomaly", "phase": "start", "id": "rain"})
	app.fact({"kind": "anomaly", "phase": "end", "id": "rain", "survived": true, "lethal": true})
	app.fact({"kind": "face", "correct": true})
	check(sm.ledger.size() == 2 and sm.ledger[0]["pts"] == 40 and app._runlog.events.any(func(e: Array) -> bool: return e[1] == "anomaly"), "facts become ledger lines and replay events")
	var before := app.runs().list().size()
	app._reach_ending("car")
	await _frames(2)
	var res := app._last_result
	check(bool(res.get("rated", false)) and res["route"] == "car" and res["id"] != "" and app.runs().list().size() == before + 1, "a clear is rated and written into the records")
	check(not app.runs().replay(String(res["id"])).is_empty() and app.runs().replay(String(res["id"]))["track"] != "", "with its replay")
	check(res["score"]["items"][0]["cat"] == "结局" and int(res["score"]["total"]) >= 300 + 40 + 10, "the score starts with the ending and the ledger")
	app.return_to_menu()
	await _frames(2)
	app.start_new_game("hard")
	await _frames(3)
	app.patrol().pat["safety"] = 999.0
	app.kill("test", "vignette", "patrol")
	await _frames(2)
	check(app.runscore().last_death_line().has("total") and app._runlog.run == "", "a death gives one score line and drops the replay log")
	app.return_to_menu()
	await _frames(2)


func _test_death_flow(app: GameApp) -> void:
	app.saves.clear()
	app.start_new_game()
	await _frames(3)
	app.items().add("pen")
	app.campus().interact_at("teach1", _campus_pose(CampusData.layout("teach1"), CampusGeometry.tile_center(CampusData.layout("teach1"), 10, 17), -PI * 0.5))
	app.school().tsec = 900.0
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and app._death_phase == "fade" and not app.player.enabled, "SAN 0 kills: the run is dead and input stops")
	app.pause_game()
	check(not paused, "a dead player cannot open the pause menu")
	app.save_game()
	check(not app.saves.exists(), "a dead run cannot be saved")
	await _frames(ceili(app._death_hold*60)+6)
	check(not app.story().dead and app.story().wakes == 1 and app.router.current.world_id == &"teach1", "day one on 预知梦 wakes at the own seat")
	check(absf(app.school().tsec - 700.0) < 1.5 and absf(app.school().san - 78.0) < 1.0 and app.school().seated and app.player.enabled,
		"the dream wake is 11:40, SAN 78, seated, with control back (t %.2f san %.2f)" % [app.school().tsec, app.school().san])
	check(app.items().has("pen"), "the bag survives the dream wake")
	check(FileAccess.file_exists(app._death_log_path()), "the death is counted in the cross-run log")
	app.school().day = 2
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and not app.story().wake_pending, "a day-two death is final")
	app.save_game()
	check(not app.saves.exists(), "the final death keeps the run from being saved")
	await _frames(ceili(app._death_hold*60)+6)
	check(app._death_phase == "card" and app.ui.death_panel.visible, "the record card shows after the scene")
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	check(app._death_phase == "card" and app.story().dead, "E on the card does nothing more")
	app.return_to_menu()
	check(not app.ui.death_panel.visible and app.session == null, "back to the menu clears the card")
	app.start_new_game("hard")
	await _frames(3)
	check(app.story().diff == "hard", "梦魇 starts on the hard difficulty")
	app.school().san = 0.0
	await _frames(3)
	check(app.story().dead and not app.story().wake_pending, "梦魇 deaths are final even on day one")
	app.return_to_menu()


func _test_elevator_walk(app: GameApp) -> void:
	var lift := app.elevator()
	var t1 := CampusData.layout("teach1")
	var hall := lift.world("teach1", 1.5, 0.0)
	app.travel("teach1", _campus_pose(t1, hall, PI * 0.5), false)
	await _frames(3)
	var world := app.router.get_child(0) as CampusWorld
	check(world.lift_leaf_count() == 4, "teach1 has two landing and two car leaves")
	# Closed doors block the doorway.
	await _walk(app, [CampusGeometry.to_scene(t1, lift.world("teach1", -1.2, 0.0))], 60)
	var l: Vector2 = lift.local("teach1", CampusGeometry.to_world(t1, app.player.position.x, app.player.position.z))
	check(l.x > 0.4, "closed elevator doors stop the body in the corridor (a=%.2f)" % l.x)
	app._campus_interact()
	await _frames(70)
	await _walk(app, [CampusGeometry.to_scene(t1, lift.world("teach1", -1.2, 0.0))], 90)
	l = lift.local("teach1", CampusGeometry.to_world(t1, app.player.position.x, app.player.position.z))
	check(l.x < -0.6 and lift.ride.get("phase") == "cabin", "with the doors open the body walks into the cabin and boards")


## Bell tower: walk the spiral two turns up to the 6.4 m top ring (spiral.js), and the ground
## under the stair stays solid outside the entry angles.


func _test_spiral_walk(app: GameApp) -> void:
	var sp: Dictionary = CampusData.campus()["spiral"]
	var c := Vector2(sp["cx"], sp["cz"])
	var th0 := float(sp["th0"])
	var rm := (float(sp["rIn"]) + float(sp["rOut"])) * 0.5
	app.travel("bell1", {"position": [c.x + cos(th0) * 3.4, 0.05, c.y + sin(th0) * 3.4], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	var points: Array = []
	for i in 2 * 24 + 4:
		var a := th0 - 0.1 + i * TAU / 24.0
		points.append(c + Vector2(cos(a), sin(a)) * rm)
	await _walk(app, points, 120)
	check(app.player.position.y > float(sp["topH"]) - 0.2, "walking the spiral two turns reaches the top ring (y=%.2f)" % app.player.position.y)
	app.travel("bell1", {"position": [c.x + cos(th0 + 2.0) * 3.4, 0.05, c.y + sin(th0 + 2.0) * 3.4], "yaw": 0.0, "pitch": 0.0}, false)
	await _frames(3)
	await _walk(app, [c + Vector2(cos(th0 + 2.0), sin(th0 + 2.0)) * rm], 90)
	var q := Vector2(app.player.position.x, app.player.position.z) - c
	check(q.length() > float(sp["rOut"]) + 0.2 and app.player.position.y < 0.2, "ground under the stair is solid away from the entry")


func _test_cut_lifecycle(app: GameApp) -> void:
	if DisplayServer.get_name() == "headless":
		return # Live cinematics are intentionally disabled by the app in this mode.
	for kind: String in ["ending", "opening"]:
		for action: String in ["menu", "new_game"]:
			app.start_new_game()
			if kind == "ending":
				app.travel("out", {"position": [0.0, 0.05, 0.0], "yaw": 0.0, "pitch": 0.0}, false)
				await _frames(2)
				app._reach_ending("face")
			else:
				app._play_opening()
			await _frames(2)
			var old_cut: Node = app._ending_cut if kind == "ending" else app._opening_cut
			check(is_instance_valid(old_cut) and bool(old_cut.get("on")), "a visible " + kind + " starts before " + action)
			var completed := [0]
			old_cut.connect("finished", func(_skipped: bool) -> void: completed[0] += 1)
			if action == "menu":
				app.return_to_menu()
			else:
				app.start_new_game()
			await _frames(3)
			check(app._ending_cut == null and app._opening_cut == null and not is_instance_valid(old_cut) and completed[0] == 0,
				"leaving " + kind + " cancels props and callbacks on " + action)
			check(not paused and (app.ui.ending_panel == null or not app.ui.ending_panel.visible),
				"an abandoned scene cannot reopen its card or pause the next run")
	app.return_to_menu()
