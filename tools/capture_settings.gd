extends SceneTree
## The settings panel (needs a display): godot --path . --script res://tools/capture_settings.gd
## Output: build/previews/settings/. Opened over the main menu.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://settings-preview/unused.json")
	app.settings = GameSettings.new("user://settings-preview/settings.json")
	root.add_child(app)
	for _i in 10:
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/settings")
	app.ui.settings_requested.emit()
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/settings/menu-settings.png")
	quit()
