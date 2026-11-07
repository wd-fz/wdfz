extends SceneTree
## The broadcast room's microphone panel (needs a display): godot --path . --script res://tools/capture_mic.gd
## Output: build/previews/mic/. Day 2, evening, four papers in hand, mid-reading.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://mic-preview/unused.json")
	app.settings = GameSettings.new("user://mic-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	app.school().day = 2
	app.school().tsec = 1100.0
	for k: String in ["notice1", "notice2", "notice3", "notice4"]:
		app.items().add(k)
	var radio := app.broadcast()
	radio.b["book"] = true
	radio.b["fuse"] = true
	var a2 := CampusData.layout("admin2")
	var at: Array = BroadcastModule.STATION
	var station := Vector2(float(a2["ox"]) + (float(at[0]) + 0.5) * float(a2["tw"]), float(a2["oy"]) + (float(at[1]) + 0.5) * float(a2["th"])) + Vector2(0, 9)
	var p := CampusGeometry.to_scene(a2, station)
	app.travel("admin2", {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": 0.0}, false)
	for _i in 3:
		await process_frame
	app._open_mic()
	app._mic_hold_button = true
	for _i in 12:
		app._broadcast_step(0.5)
	for _i in 6:
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/mic")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/mic/mic.png")
	quit()
