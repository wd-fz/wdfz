extends SceneTree
## Real viewport captures of portrait controls, the draggable tool window and its small dot.
const APP := preload("res://game/app/app.tscn")
var app: GameApp

func _initialize() -> void:
	call_deferred("_run")

func _shot(id: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/touch/%s.png" % id)

func _run() -> void:
	root.size = Vector2i(480,800)
	app = APP.instantiate()
	app.saves = SaveStore.new("user://touch-preview/save.json")
	app.settings = GameSettings.new("user://touch-preview/settings.json")
	app.settings.set_value("quality",1)
	app.settings.save_file()
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/touch")
	app.ui.set_touch_enabled(true)
	app.start_new_game("hard")
	app._stand_up()
	app.player.rotation.y = PI/2
	for i in 3:
		await physics_frame
		await process_frame
	app.set_physics_process(false)
	app.ui.show_notice("")
	await _shot("portrait-controls")
	app._toggle_debug()
	await _shot("portrait-debug")
	app.debug_panel.set_collapsed(true)
	await _shot("portrait-dot")
	app.debug_panel.hide()
	app.pause_game()
	app.ui.show_settings(app.settings.values)
	await _shot("portrait-settings")
	app.ui.show_touch_layout_editor()
	await _shot("portrait-layout")
	app.ui._layout_editor.queue_free()
	app.ui.settings_panel.hide()
	app.resume_game()
	root.size = Vector2i(1280,720)
	await _shot("landscape-controls")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	CampusData.clear_caches()
	quit()
