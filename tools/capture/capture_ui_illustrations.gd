extends SceneTree
## Actual game UI with generated art. Uses a disposable profile and controlled inventory.
## Output: build/previews/ui-illustrations/. Portrait is outside the maintained target.
const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func shot(label: String) -> void:
	for _i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/ui-illustrations/%s.png" % label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/ui-illustrations")
	root.size = Vector2i(1280, 720)
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new("user://framework-tests/art-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	for _i in 3: await process_frame
	app._setting_changed("quality", 0)
	app._pick_talent("easy")
	await shot("01-talents")
	app.ui._choice_scroll.ensure_control_visible(app.ui._choice_box.get_child(5))
	await shot("02-talents-lower")
	app.ui.hide_choice()
	app.start_new_game("easy", "watch")
	app.ui._end_opening(true)
	app._stand_up()
	app.patrol().pat["safety"] = 999
	for id: String in ["card", "torch", "phone", "watch", "key", "pill", "paper", "coil"]:
		app.items().add(id)
	app.items().set_hot(0, "torch")
	app.items().set_hot(1, "phone")
	for _i in 8: await process_frame
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._open_bag()
	await shot("03-bag")
	app._close_bag()
	await shot("04-hot-slots")
	app._open_phone()
	await shot("05-phone-home")
	app._phone_select("camera")
	await app._shoot()
	await shot("06-phone-camera")
	app._close_phone()
	root.size = Vector2i(844, 390)
	app.ui.set_touch_enabled(true)
	app.ui.apply_text_scale(125)
	app._open_phone()
	await shot("07-phone-mobile")
	app._close_phone()
	await shot("08-touch-hot-slots")
	app.return_to_menu()
	app._pick_talent("easy")
	await shot("09-talents-mobile")
	app.ui.hide_choice()
	app.queue_free()
	for _i in 3: await process_frame
	print("UI ART CAPTURE: finished")
	quit()
