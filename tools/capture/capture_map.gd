extends SceneTree
## Real handbook pages from a new run, with the original exploration mask retained.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/map/"+label+".png")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/map")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-map-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	for _i in 5: await process_frame
	app.set_physics_process(false)
	app.set_process(false)
	app.player.set_physics_process(false)
	app._show_map("campus")
	await shot("校园道路与名称")
	root.size = Vector2i(420,900)
	app._setting_changed("text",150)
	app._show_map("teach1")
	await shot("竖屏大字楼层与当前位置")
	app._show_map("campus")
	await shot("竖屏校园总图")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
