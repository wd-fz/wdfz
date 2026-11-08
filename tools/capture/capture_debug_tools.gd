extends SceneTree
const APP:=preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _shot(label: String) -> void:
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/debug-tools/"+label+".png")
func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute("res://build/previews/debug-tools")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-debug-tools/save.json")
	app.settings=GameSettings.new("user://capture-debug-tools/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._school_step(0,app.campus())
	app._toggle_debug()
	await _shot("桌面状态")
	root.size=Vector2i(480,800)
	root.content_scale_size=root.size
	app.ui.set_touch_enabled(true)
	app.debug_panel.select_page("事件")
	await _shot("竖屏事件")
	app.debug_panel.set_collapsed(true)
	await _shot("竖屏悬浮球")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
