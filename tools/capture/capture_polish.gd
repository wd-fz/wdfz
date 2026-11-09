extends SceneTree
## 界面审美、控件布局与光影渲染: settings key page, touch layout editor, HUD and lighting tiers.
## xvfb-run -a godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_polish.gd
## Output: build/previews/polish/. SHOTS=keys,touch,hud,light (default: all).
const APP := preload("res://game/app/app.tscn")
var _want: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func shot(label: String) -> void:
	for _i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/polish/" + label + ".png")


func want(id: String) -> bool:
	return _want.is_empty() or _want.has(id)


func _run() -> void:
	var env := OS.get_environment("SHOTS")
	if env != "":
		_want = env.split(",")
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/polish")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-polish-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	if want("menu"):
		await shot("menu")
	if want("keys"):
		app.ui.settings_requested.emit()
		app.ui.settings_panel.select_page("键位")
		await shot("settings-keys")
		(app.ui.settings_panel._key_buttons["interact"][1] as Button).pressed.emit()
		await shot("settings-keys-capture")
		app.ui.settings_panel._stop_capture()
		app.ui.settings_panel.select_page("画面")
		await shot("settings-picture")
		app.ui.settings_panel.dismiss()
	app.start_new_game("easy", "none")
	app.ui._end_opening(true)
	app._stand_up()
	if want("hud"):
		for id: String in ["torch", "phone"]:
			app.items().add(id)
		await shot("hud")
		app.pause_game()
		await shot("pause")
		app.resume_game()
	if want("touch"):
		app.ui.set_touch_enabled(true)
		await shot("hud-touch")
		app.ui.show_touch_layout_editor()
		app.ui._layout_editor.select("interact")
		app.ui._layout_editor._size_slider.value = 130
		await shot("touch-editor")
		if app.ui._layout_editor != null:
			app.ui._layout_editor.cancelled.emit()
		app.ui.set_touch_enabled(false)
	if want("light"):
		for q in [0, 2, 4]:
			app._setting_changed("quality", q)
			for spec: Array in [["teach1", 700.0, "classroom-day"], ["teach1", 1380.0, "classroom-night"], ["out", 700.0, "out-day"], ["out", 1150.0, "out-dusk"]]:
				var pose: Dictionary = app.campus().start_pose() if spec[0] == "teach1" else {"position": [1023.0 / 9.0, 0.05, 1300.0 / 9.0], "yaw": 0.0, "pitch": 0.1}
				app.travel(spec[0], pose, false)
				app.school().tsec = spec[1]
				for _i in 20:
					await process_frame
				await shot("q%d-%s" % [q, spec[2]])
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
