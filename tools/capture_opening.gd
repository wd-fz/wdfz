extends SceneTree
## The live opening (needs a display): godot --path . --script res://tools/capture_opening.gd
## Output: build/previews/opening/. Frames at several points of the storyboard.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/opening/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://opening-preview/save.json")
	app.settings = GameSettings.new("user://opening-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/opening")
	DirAccess.remove_absolute(app.saves.side_path("opening_seen"))
	app.start_new_game("easy")
	for _i in 20:
		await process_frame
	app._play_opening()
	var cut: OpeningCut = app._opening_cut
	cut.set_process(false)
	for spec: Array in [["1-back-row", 0.12], ["2-teacher", 0.34], ["3-dust-stops", 0.47], ["3-turn-to-you", 0.56], ["4-slump", 0.66], ["5-wake", 0.85], ["6-handover", 0.98]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		await _shot(String(spec[0]))
	quit()
