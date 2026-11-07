## Lighting previews at fixed clock times (needs a display): godot --path . --script res://tools/capture_lighting.gd
extends SceneTree
const APP := preload("res://scenes/app.tscn")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://light-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/light")
	for spec: Array in [["teach1", 700.0, "classroom-day"], ["teach1", 1380.0, "classroom-night"], ["out", 700.0, "out-day"], ["out", 1150.0, "out-dusk"], ["out", 1400.0, "out-night"]]:
		var pose: Dictionary = app.campus().start_pose() if spec[0] == "teach1" else {"position": [1023.0 / 9.0, 0.05, 1300.0 / 9.0], "yaw": 0.0, "pitch": 0.1}
		app.travel(spec[0], pose, false)
		app.school().tsec = spec[1]
		for _i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/light/%s.png" % spec[2])
	quit()
