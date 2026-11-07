extends SceneTree
## The clear records screen (needs a display): godot --path . --script res://tools/capture_records.gd
## Output: build/previews/records/. Sample records (not played): the list, the replay and the footprint map.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/records/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://records-preview/unused.json")
	app.settings = GameSettings.new("user://records-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/records")
	var store := RunRecords.new("user://records-preview/records")
	for f in DirAccess.get_files_at("user://records-preview/records"):
		DirAccess.remove_absolute("user://records-preview/records/" + f)
	var samples: Array = []
	var room: Dictionary = CampusData.rooms()["teach1"]
	var ox := (float(room["ox"]) + float(room["tw"]) * 4.0) / 2.0
	var oy := (float(room["oy"]) + float(room["th"]) * 3.0) / 2.0
	for i in 40:
		samples.append([i * 5, 0, roundi(ox + i * 3.0), roundi(oy + (i % 7 if i < 20 else 6) * 2.0), (i * 2) % 64])
	var pack := {"v": 1, "run": "r", "scenes": ["teach1"], "track": RunTrack.encode(samples), "pat": [[20, 0, roundi(ox + 40.0), roundi(oy)], [60, 0, roundi(ox + 60.0), roundi(oy + 4.0)]],
		"clock": [], "events": [[40, "anomaly", "遭遇「下不完的雨」", 0, 0, 40, 25], [120, "inspect", "学生会检查 · 在教室", 20, 0, 50, 30]], "start": 1, "partial": 0}
	for spec: Array in [["car", "《闸门》", "easy", "B"], ["face", "《镜面》", "hard", "A"], ["car", "《闸门》", "hard", "S"]]:
		var m := ScoreRules.sample_meta(String(spec[3]), String(spec[0]), String(spec[2]))
		m["routeName"] = spec[1]
		m["source"] = "play"
		m["at"] = float(Time.get_unix_time_from_system() * 1000.0) - randf() * 8.64e7
		store.add(m, pack)
	app._runs_store = store
	app._runs_path = app.saves.side_path("records")
	var panel := app.ui.show_records(store, CampusData.rooms())
	await _shot("list")
	var id: String = String(store.list()[0]["id"])
	panel.open_view(id, false)
	panel._t = 100.0
	panel._redraw()
	await _shot("replay")
	panel.open_view(id, true)
	await _shot("footprint")
	quit()
