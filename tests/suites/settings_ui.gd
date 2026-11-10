extends "res://tests/suites/touch_ui.gd"


func test_editor() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(1280,720)
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/settings-ui-save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/settings-ui.json")
	root.add_child(app)
	await _frames(3)
	app.ui.set_touch_enabled(true)
	app.ui.settings_requested.emit()
	await _frames(6)
	var panel := app.ui.settings_panel
	for key: String in GameSettings.DEFAULTS:
		check(panel.controls.has(key), "settings editor preserves %s" % key)
	check(panel._page_boxes.size() == 6, "settings are split into six navigable categories (key bindings included)")
	check(root.get_visible_rect().encloses(panel.shell.get_global_rect()), "settings fit the viewport on their very first opening")
	var events: Array[String] = []
	app.ui.setting_changed.connect(func(key: String, _value: int) -> void: events.append(key))
	await _tap(panel._nav_buttons["操作"])
	check(panel.selected == "操作" and panel.scroll.scroll_vertical == 0, "touch navigation selects a page at its beginning")
	var slider := panel.controls["touch"] as HSlider
	var original_id := slider.get_instance_id()
	await _tap(panel.find_child("More_touch",true,false))
	check(app.settings.get_int("touch") == 105 and absf(app.player.touch_sensitivity-0.0042)<0.00001,
		"large plus button changes the setting and applies touch sensitivity")
	check(slider.get_instance_id() == original_id and events == ["touch"], "editing preserves widgets and emits exactly one change")
	# An actual slider drag must survive immediate persistence and UI updates.
	var start := slider.get_global_rect().get_center()
	await _finger(0,start,true)
	await _drag(0,start+Vector2(30,0),Vector2(30,0))
	await _finger(0,start+Vector2(30,0),false)
	check(app.settings.get_int("touch") > 105 and slider.get_instance_id() == original_id, "touch-dragging a slider is not interrupted by automatic saving")
	var stored := GameSettings.new(app.settings.path)
	stored.load_file()
	check(stored.get_int("touch") == app.settings.get_int("touch"), "the actual UI persists its value to settings.json")
	panel.scroll.scroll_vertical = 0
	await _frames(3)
	# ScrollContainer's native drag path is gated on the display's touchscreen hint.
	var old_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var description := panel.find_child("Setting_touch",true,false).get_child(1) as Label
	var swipe := description.get_global_rect().get_center()
	await _finger(0,swipe,true)
	await _drag(0,swipe-Vector2(0,25),Vector2(0,-25))
	await _drag(0,swipe-Vector2(0,80),Vector2(0,-55))
	await _finger(0,swipe-Vector2(0,80),false)
	if DisplayServer.is_touchscreen_available():
		check(panel.scroll.scroll_vertical > 0, "a finger swipe scrolls settings content")
	else:
		print("NOTE: native touch-scroll assertion requires a window display with the touchscreen hint")
	Input.emulate_touch_from_mouse = old_emulation
	check(panel._close.get_global_rect().position.y < panel.scroll.get_global_rect().position.y,
		"the close button remains outside the scrolling body")
	await _tap(panel._nav_buttons["声音"])
	check(panel.scroll.scroll_vertical == 0, "changing category resets scroll instead of opening halfway down")
	panel.scroll.ensure_control_visible(panel.controls["amb"])
	await _frames(3)
	await _tap(panel.controls["amb"])
	check(not app.audio.ambience and app.settings.get_int("amb") == 0, "the ambience switch uses the existing audio setting")
	await _tap(panel._nav_buttons["画面"])
	await _tap(panel._graphics_buttons["细节"])
	await _tap(panel.controls["quality"][1])
	check(app.settings.get_int("quality") == 1 and panel._quality_note.text.contains("平衡"), "quality selection shows the active tier and its tradeoff")
	for size: Vector2i in [Vector2i(960,540),Vector2i(1280,800),Vector2i(2340,1080)]:
		root.size = size
		for text_size: int in [100,150]:
			app.ui.setting_changed.emit("text",text_size)
			await _frames(6)
			check(root.get_visible_rect().encloses(panel.shell.get_global_rect()), "settings fit landscape %s at text %d%%" % [size,text_size])
			for id: String in panel._nav_buttons:
				check(root.get_visible_rect().encloses(panel._nav_buttons[id].get_global_rect()), "category %s stays reachable at %s/%d%%" % [id,size,text_size])
			check(root.get_visible_rect().encloses(panel._close.get_global_rect()), "close remains reachable with enlarged text")
	app.ui.setting_changed.emit("text",100)
	root.size = Vector2i(1280,720)
	await _frames(6)
	await _tap(panel._nav_buttons["数据"])
	await _tap(panel.find_child("ResetComfort",true,false))
	check(app.settings.get_int("touch") == 100 and app.settings.get_int("quality") == 1 and app.settings.get_int("amb") == 0,
		"comfort reset updates the visible controls without resetting sound or quality")
	check(panel.selected == "数据" and is_instance_valid(slider), "reset does not rebuild the UI or switch categories")
	panel.scroll.ensure_control_visible(panel._clear)
	await _frames(3)
	await _tap(panel._clear)
	check(panel._confirm_clear and not events.has("clear_last_life"), "destructive clearing requires a second explicit tap")
	await _tap(panel._nav_buttons["操作"])
	check(not panel._confirm_clear, "leaving the data page cancels its pending confirmation")
	await _tap(panel._close)
	check(not panel.visible, "Done closes the new settings overlay")
	app.ui.settings_requested.emit()
	await _frames(4)
	check(panel.selected == "操作" and slider.value == 100, "reopening retains the category and shows saved values")
	panel.scroll.ensure_control_visible(panel.find_child("EditTouchLayout",true,false))
	await _frames(4)
	await _tap(panel.find_child("EditTouchLayout",true,false))
	check(is_instance_valid(app.ui._layout_editor), "touch layout editor is reachable from the controls category")
	await _tap(app.ui._layout_editor._buttons.get_node("cancel"))
	check(panel.visible and not is_instance_valid(app.ui._layout_editor), "cancelling layout returns to settings")
	app.queue_free()
	await _frames(4)
	root.size = old_size
	root.content_scale_size = old_scale
