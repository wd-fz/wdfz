extends SceneTree
## The live ending scenes (needs a display): godot --path . --script res://tools/capture/capture_endings.gd
## Output: build/previews/endings/. Frames of the 闸门 scene.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/endings/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://endings-preview/save.json")
	app.settings = GameSettings.new("user://endings-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/endings")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app.travel("garage1", {"position": [28.5, 0.05, -0.5], "yaw": 1.5708, "pitch": 0.0}, false)
	for _i in 30:
		await process_frame
	app.player.enabled = false
	app._play_car_intro()
	var cut: EndingCut = app._ending_cut
	cut.set_process(false)
	for spec: Array in [["car-1-lights", 0.1], ["car-2-lights-steady", 0.28], ["car-3-gate", 0.45], ["car-3b-gate", 0.65], ["car-4-chase", 0.85]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		await _shot(String(spec[0]))
	quit()
