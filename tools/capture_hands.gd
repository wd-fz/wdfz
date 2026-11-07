extends SceneTree
## The first-person hands (needs a display): godot --path . --script res://tools/capture_hands.gd
## Output: build/previews/hands/. Torch in the right hand; umbrella up in the left; phone open.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/hands/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://hands-preview/save.json")
	app.settings = GameSettings.new("user://hands-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/hands")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var h := HandsView.new()
	app.player.camera.add_child(h)
	h.update(0.1, true, false, false, true, false, false)
	await _shot("torch")
	h.update(0.1, true, true, false, true, false, false)
	await _shot("torch-umbrella")
	h.update(0.1, false, false, true, true, false, false)
	await _shot("phone")
	quit()
