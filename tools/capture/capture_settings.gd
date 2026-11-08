extends SceneTree
## The settings panel (needs a display): godot --path . --script res://tools/capture/capture_settings.gd
## Output: build/previews/settings/. Opened over the main menu.

const APP := preload("res://game/app/app.tscn")


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
	app.ui.settings_panel.set_values(GameSettings.DEFAULTS)
	for page: String in ["画面", "声音", "操作", "舒适", "数据"]:
		app.ui.settings_panel.select_page(page)
		for _i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/settings/"+page+".png")
	app.ui.settings_panel.select_page("舒适")
	var large := GameSettings.DEFAULTS.duplicate()
	large["text"] = 150
	app.ui.settings_panel.set_values(large)
	for _i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/settings/大字体.png")
	app.queue_free()
	await process_frame
	CampusData.clear_caches()
	quit()
