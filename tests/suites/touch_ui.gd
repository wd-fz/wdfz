extends "res://tests/support/test_suite.gd"


func test_layout() -> void:
	var valid := true
	for view: Vector2 in [Vector2(480,800),Vector2(960,540),Vector2(1280,720),Vector2(720,480),Vector2(480,320)]:
		for scale in [85,100,125]:
			for p: Vector2 in [Vector2.ZERO,Vector2(50,50),Vector2(100,100),Vector2(-50,150)]:
				var raw := {}
				for id: String in TouchLayout.IDS:
					raw[id] = {"x":p.x,"y":p.y}
				var rects := TouchLayout.resolve(view,raw,scale,[Rect2(0,0,view.x,68)])
				for i in 3:
					var r: Rect2 = rects[TouchLayout.IDS[i]]
					valid = valid and Rect2(Vector2(8,8),view-Vector2(16,16)).encloses(r)
					valid = valid and not r.intersects(Rect2(0,0,view.x,68))
					for j in i:
						valid = valid and not r.intersects(rects[TouchLayout.IDS[j]])
	check(valid,"touch layout stays in bounds and separates controls at portrait/landscape sizes and extreme saved centres")
	check(TouchLayout.normalize({"stick":{"x":NAN,"y":20},"actions":{"x":50,"y":"bad"},"alien":{"x":0,"y":0}}).is_empty(),
		"malformed or nonfinite layouts cannot enter settings")
	var settings := GameSettings.new(_test_path.get_base_dir()+"/touch-layout.json")
	settings.touch_layout = {"stick":{"x":31,"y":75}}
	settings.set_value("touch_size",125)
	settings.set_value("quality",1)
	check(settings.save_file(),"custom touch layout writes beside settings")
	var restored := GameSettings.new(settings.path)
	restored.load_file()
	check(same_json(restored.touch_layout,settings.touch_layout) and restored.get_int("touch_size") == 125,"layout survives a settings round trip")
	restored.reset_comfort()
	check(restored.touch_layout.is_empty() and restored.get_int("touch_size") == 100 and restored.get_int("quality") == 1,"comfort reset clears the layout without changing quality")
	DirAccess.remove_absolute(settings.path)


func _finger(index: int, point: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = root.get_final_transform()*point
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await _frames(1)


func _drag(index: int, point: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = root.get_final_transform()*point
	ev.relative = root.get_final_transform().basis_xform(relative)
	Input.parse_input_event(ev)
	await _frames(1)


func test_controls() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(960,540)
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	ui.set_touch_enabled(true)
	var signals := {"manual":0,"hot":-1,"torch":0,"interact":0,"look":Vector2.ZERO}
	ui.manual_requested.connect(func() -> void: signals.manual += 1)
	ui.hot_requested.connect(func(i: int) -> void: signals.hot = i)
	ui.torch_requested.connect(func() -> void: signals.torch += 1)
	ui.interact_requested.connect(func() -> void: signals.interact += 1)
	ui.touch_look.connect(func(v: Vector2) -> void: signals.look += v)
	await _tap(ui._touch_tools.get_node("Manual"))
	await _tap(ui._touch_tools.get_node("Torch"))
	await _tap(ui._touch_tools.get_node("Hot2"))
	check(signals.manual == 1 and signals.torch == 1 and signals.hot == 1,"real touch taps reach manual, torch and both hot-slot actions")
	ui.apply_touch_scale(100,{"actions":{"x":70,"y":50}})
	await _frames(2)
	await _tap(ui.get_node("%TouchInteract"))
	check(signals.interact == 1 and signals.look == Vector2.ZERO,"a button moved into the look area consumes its touch without rotating the camera")
	var point := Vector2(930,350)
	await _finger(4,point,true)
	await _drag(4,point+Vector2(-30,20),Vector2(-30,20))
	check(signals.look.length() > 0,"a fresh finger on free space still rotates the view")
	await _finger(4,point,false)
	check(ui.look_pad._finger == -1,"look finger releases after crossing controls")
	ui.show_bag([{"id":"torch","name":"手电筒","text":"测试描述".repeat(100)}])
	await _frames(3)
	var close := ui.bag_panel.find_child("BagClose",true,false) as Button
	var closed := [false]
	ui.bag_closed.connect(func() -> void: closed[0] = true; ui.hide_bag())
	await _tap(close)
	check(closed[0] and not ui.bag_open(),"the bag has a reachable touch close button even with long contents")
	root.size = Vector2i(480,800)
	await _frames(4)
	ui.show_settings(GameSettings.DEFAULTS)
	await _frames(4)
	check(ui.settings_panel.get_global_rect().end.x <= root.get_visible_rect().size.x and ui.settings_panel.get_global_rect().position.x >= 0,
		"settings fit portrait width, including quality choices and reset buttons")
	ui.settings_panel.hide()
	ui.show_touch_layout_editor()
	await _frames(3)
	var edit := ui._layout_editor
	var h: Control = edit._handles["stick"]
	var from := h.get_global_rect().get_center()
	await _finger(3,from,true)
	await _drag(3,from+Vector2(35,-50),Vector2(35,-50))
	await _finger(3,from+Vector2(35,-50),false)
	check(edit.layout.has("stick") and float(edit.layout.stick.y) < 82,"layout preview responds to an actual finger drag")
	await _tap(edit._buttons.get_node("cancel"))
	await _frames(2)
	check(not is_instance_valid(ui._layout_editor),"cancel releases the layout overlay")
	ui.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale


func test_floating_panel() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(480,800)
	root.content_scale_size = Vector2i(480,800)
	var panel := DebugPanel.new({"sfx":{}})
	root.add_child(panel)
	panel.show()
	await _frames(4)
	check(panel.compact and panel.get_global_rect().end.x <= 480 and panel.get_global_rect().end.y <= 800,"developer window automatically fits a portrait screen")
	var from := panel.heading.get_global_rect().get_center()
	var old := panel.position
	await _finger(2,from,true)
	await _drag(2,from+Vector2(-25,50),Vector2(-25,50))
	await _finger(2,from+Vector2(-25,50),false)
	check(panel.position.distance_to(old) > 15,"developer title bar moves with a finger")
	await _tap(panel.find_child("Collapse",true,false))
	check(panel.collapsed and panel.size.x <= 60 and panel.get_theme_stylebox("panel").bg_color.a == 0,"collapse leaves a tiny visible dot with no rectangular window background")
	await _tap(panel._dot)
	check(not panel.collapsed and panel._frame.visible,"tapping the floating dot restores the tool window")
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(960,540)
	await _frames(4)
	check(panel.position.y >= 0 and panel.get_global_rect().end.y <= 540,"rotation keeps the window in bounds")
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(player)
	await _frames(2)
	player.enabled = true
	panel._note.grab_focus()
	Input.action_press("move_forward")
	var before := player.position
	await _frames(3)
	check(player.editing_text() and not player.wants_move() and Vector2(player.position.x,player.position.z).is_equal_approx(Vector2(before.x,before.z)),"typing WASD into a developer note never walks the player")
	panel._note.release_focus()
	await _frames(3)
	check(player.wants_move() and player.position.distance_to(before) > .01,"leaving the note restores movement while the window remains open")
	Input.action_release("move_forward")
	player.queue_free()
	panel.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale
	var audition := DebugPanel.new({"sfx":{"a":{"cat":"test","len":.01,"files":[]},"b":{"cat":"test","len":.01,"files":[]}}})
	root.add_child(audition)
	audition.show()
	var heard: Array[String] = []
	audition.sound_play.connect(func(id: String) -> void: heard.append(id))
	audition._play_all()
	await create_timer(.4).timeout
	audition.stop_audition()
	audition._play_all()
	await create_timer(.95).timeout
	check(heard.count("a") == 2 and heard.count("b") == 1 and audition.playing_all,
		"stale audition timers neither replay a previous queue nor stop its replacement")
	audition.dismiss()
	await create_timer(.4).timeout
	check(not audition.playing_all and heard.size() == 3,"closing developer tools cancels pending audition playback")
	audition.queue_free()
	await _frames(2)


func test_app_actions() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/touch-app.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/touch-app-settings.json")
	app.settings.set_value("quality",0)
	app.settings.save_file()
	root.add_child(app)
	await _frames(3)
	app.ui.set_touch_enabled(true)
	app.start_new_game("hard")
	app.set_physics_process(false)
	await _frames(3)
	await _tap(app.ui._touch_tools.get_node("Manual"))
	check(app.ui.choice_open() and not app.player.enabled,"mobile manual opens through the running app")
	app._choice_made(0)
	check(app.ui.bag_open() and not app.player.enabled,"manual opens the bag with no keyboard")
	await _tap(app.ui.bag_panel.find_child("BagClose",true,false))
	check(app.player.enabled and not app.ui.bag_open(),"touch closing the bag returns gameplay input")
	app.items().add("torch")
	await _tap(app.ui._touch_tools.get_node("Torch"))
	check(app.items().torch_on,"mobile torch action reaches inventory rules")
	app._toggle_debug()
	check(app.debug_panel.visible and app.player.enabled and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"opening developer tools releases the cursor while gameplay remains interactive")
	var audio_rng := app.audio._rng.state
	check(app.audio.audition("ui.click") and app.audio._rng.state == audio_rng,"audition has its own voice and does not consume the world's audio random sequence")
	app.audio.stop_audition()
	app.debug_panel.dismiss()
	app.player.enabled = false  # Driving deliberately disables walking, not the UI joystick.
	var stick := app.ui.stick
	var at := stick.get_global_rect().get_center()
	await _finger(6,at+Vector2(30,-50),true)
	var drive := app._drive_input()
	check(drive.throttle and not drive.braking and float(drive.steering) > 0,"touch joystick accelerates and steers even when the walking controller is disabled")
	await _drag(6,at+Vector2(-25,45),Vector2(-55,95))
	drive = app._drive_input()
	check(not drive.throttle and drive.braking and float(drive.steering) < 0,"pulling the joystick back brakes, matching the reference car controls")
	await _finger(6,at,false)
	app.ui.clear_touch()
	check(app._drive_input() == {"throttle":false,"braking":false,"steering":0.0},"release clears every touch driving input")
	app.pause_game()
	app.ui.show_settings(app.settings.values)
	app.ui.show_touch_layout_editor()
	await _frames(2)
	await _escape()
	check(paused and not is_instance_valid(app.ui._layout_editor) and app.ui.settings_panel.visible,"Escape closes only the layout editor and retains pause")
	await _escape()
	check(paused and not app.ui.settings_panel.visible,"the next Escape closes settings without resuming behind a modal")
	await _escape()
	check(not paused and app.player.enabled,"Escape resumes only after overlays have closed")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()


func _escape() -> void:
	for pressed: bool in [true,false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)
