extends SceneTree
## The live ending scenes (needs a display): godot --path . --script res://tools/capture_endings.gd
## Output: build/previews/endings/. Frames of the 门 scene.

const APP := preload("res://scenes/app.tscn")


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
	app.player.enabled = false
	app._reach_ending("portal")
	var cut: EndingCut = app._ending_cut
	cut.set_process(false)
	for spec: Array in [["portal-1-charge", 0.2], ["portal-2-rails", 0.4], ["portal-3-open", 0.58], ["portal-4-through", 0.9]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		await _shot(String(spec[0]))
	quit()
