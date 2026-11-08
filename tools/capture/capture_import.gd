extends SceneTree
## The legacy-save import panel (needs a display): godot --path . --script res://tools/capture/capture_import.gd
## Output: build/previews/import/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://importpreview/save.json")
	app.settings = GameSettings.new("user://importpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/import")
	app.ui.show_import()
	app.ui._import_text.text = "{\"v\": 1, \"mode\": \"in\", \"room\": \"teach1\", \"x\": 500, \"tsec\": 800 ..."
	app.ui.show_import_result("存档位置或时间无效")
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/import/import-panel.png")
	quit()
