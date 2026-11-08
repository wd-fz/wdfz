extends SceneTree
## Chalk writing (needs a display): godot --path . --script res://tools/capture_chalk.gd
## Output: build/previews/chalk/. The forecast on the board, and the truancy writing in a corridor.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/chalk/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://chalk-preview/save.json")
	app.settings = GameSettings.new("user://chalk-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/chalk")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	var room: Dictionary = CampusData.rooms()["teach1"]
	var chalk: ChalkNotes = app._campus_world().chalk
	var p: Array = app.player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	app.player.enabled = false
	app.set_physics_process(false)
	app.player.rotation.y = PI / 2.0            # facing west, to the board
	chalk.update_forecast(true, "10:15", room, w, Vector2(-1, 0), Vector3(float(p[0]), 0, float(p[2])), 2.0)
	await _shot("1-forecast-on-the-board")
	chalk.clear_forecast()
	for i in 14:
		chalk.update_skip(6.0, true, 60.0, room, Vector3(float(p[0]), 0, float(p[2])))
	app.player.rotation.y = 0.8
	await _shot("2-truancy-writing")
	quit()
