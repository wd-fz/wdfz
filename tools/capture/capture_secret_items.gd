extends SceneTree
## Capture the migrated scene through actual item use and the real ending controller.
const APP:=preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/secret-items/%s.png" % name)


func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/secret-items")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-secret-items/save.json")
	app.settings=GameSettings.new("user://capture-secret-items/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1.0
	app.start_new_game("hard","code")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app._school_step(0,app.campus())
	app.ui.show_runtime(app.session.clock.active_seconds)
	app.items().add("small_knife")
	app.knife_flow.catch_player("一只手按住了你的头顶。它在点名。")
	app._open_bag()
	app._use_item("small_knife")
	app.knife_flow.step(.3)
	app._use_item("small_knife")
	app._ending_cut.set_process(false)
	for frame: Array in [[1.5,"管制刀具-停手"],[5.0,"管制刀具-登记"],[9.0,"管制刀具-日光"],[13.0,"管制刀具-留校"]]:
		app._ending_cut._apply(float(frame[0])/16.0)
		await _shot(frame[1])
	app._ending_cut.end(true)
	await _shot("管制刀具-醒来入口")
	app.knife_flow.wake()
	app._school_step(0,app.campus())
	app.ui.show_runtime(app.session.clock.active_seconds)
	await _shot("管制刀具-次日早读")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
