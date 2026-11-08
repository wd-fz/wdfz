extends SceneTree
## Looking out of a stairwell door at the floor beyond (needs a display): godot --path . --script res://tools/capture/capture_shaft.gd
## Output: build/previews/shaft/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://shaftpreview/save.json")
	app.settings = GameSettings.new("user://shaftpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/shaft")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app.travel("stair_teach_w", {"position": [0.0, 3.25, -1.0], "yaw": 0.0, "pitch": 0.0}, false)
	app.player.enabled = false
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/shaft/shaft.png")
	print("LEVELS ", app._campus_world()._shaft_levels.keys())
	quit()
