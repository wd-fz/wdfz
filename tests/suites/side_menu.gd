extends "res://tests/support/test_suite.gd"
## The side main menu (side_menu.gd), the boot animation (boot_splash.gd) and the orbiting campus preview.


func _ui() -> GameUI:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	return ui


func _run_for(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func test_side_menu() -> void:
	var previous := root.size
	root.size = Vector2i(960, 540)
	var ui := _ui()
	await _frames(3)
	ui.set_mode("menu")
	await _frames(2)
	var side: SideMenu = ui.menu_screen
	check(side.state == "folded" and side.tag_button.is_visible_in_tree() and not side.content.visible, "the menu starts folded into the rune tag")
	var labels: Array = side.items.map(func(b: Button) -> String: return b.text)
	check(labels == Array(side.item_labels) and labels == ["继续入梦", "新的轮回", "画廊与遗物", "感官设置", "逃离现实"], "five items take their copy from the exported labels")
	check(side.items[0].name == "LoadGame", "继续入梦 is the original continue button")
	for id: String in SideMenu.GROUPS:
		var box := side.groups[id] as VBoxContainer
		for child_id: String in SideMenu.GROUPS[id]:
			if child_id == "DebugTools" and not DebugPanel.enabled(): continue
			check(box.find_child(child_id, false, false) != null, "%s sits under %s" % [child_id, id])
	check(side.find_child("SchoolName", true, false) != null and side.description != null, "the school line and its description stay in the menu")
	# Heartbeat when the pointer nears the tag.
	var b0 := SideMenu.heartbeat(0.08)
	check(b0 > 0.9 and SideMenu.heartbeat(0.6) < 0.05, "the heartbeat swells twice per beat and rests between")
	# Opening: tear then stretch, then the text surfaces.
	side.open()
	check(side.state == "opening" and side.body_rect().size.x < side.panel_rect().size.x * 0.5, "opening starts from the tag")
	side.open_amount = side.tear_time / (side.tear_time + side.stretch_time)
	var torn := side.body_rect()
	check(absf(torn.size.y - side.layout_rects()["strip"].size.y) < 1.0 and torn.size.x < side.panel_rect().size.x * 0.3, "the tag first tears along the spine")
	await _run_for(side.tear_time + side.stretch_time + 0.2)
	check(side.state == "open" and absf(side.body_rect().size.x - side.panel_rect().size.x) < 1.0, "then it stretches into the panel")
	await _run_for(side.reveal_step * 10.0 + side.reveal_time + 0.2)
	var title_mat := (side.find_child("Title", true, false) as Control).material as ShaderMaterial
	check(float(title_mat.get_shader_parameter("u_reveal")) >= 0.999, "the title has surfaced out of blur and noise")
	# The peephole follows the focused item.
	side.items[2].grab_focus()
	await _frames(20)
	var g := side.items[2].get_global_rect()
	check(side._hole_target.position.distance_to(side.get_global_transform().affine_inverse() * g.position) < 1.0 and side._hole_on > 0.5, "the wiped peephole slides to the active item")
	# A group opens in place; its first child surfaces.
	side.items[1].pressed.emit()
	await _frames(3)
	check(side.groups["Rebirth"].visible and not side.groups["Gallery"].visible, "新的轮回 opens its own list and only that one")
	side.items[2].pressed.emit()
	await _frames(2)
	check(side.groups["Gallery"].visible and not side.groups["Rebirth"].visible, "opening another group closes the first")
	# Choosing an action: green pulse, fold, then the scab colours seep back.
	var achievements := side.find_child("Achievements", true, false) as Button
	var hits := [0]
	ui.achievements_requested.connect(func() -> void: hits[0] += 1)
	achievements.pressed.emit()
	check(hits[0] == 1 and side.state == "closing" and side._pulse_t >= 0.0, "an action still fires once, then the menu folds with a pulse")
	await _run_for(0.25)
	check(side._shift > 0.8, "the menu turns ghost green while the pulse spreads")
	await _run_for(side.fold_time + 0.1)
	check(side.state == "folded" and side.tag_button.is_visible_in_tree(), "the panel collapses back into the tag")
	await _run_for(side.pulse_time + side.fade_back_time)
	check(side._shift < 0.02, "the colours fade back to the blood-scab palette")
	# Toggles stay in the open menu.
	side.open_now()
	side.reveal(side.find_child("SoundToggle", true, false))
	(side.find_child("SoundToggle", true, false) as CheckButton).button_pressed = false
	await _frames(2)
	check(side.state == "open", "switches such as sound do not fold the menu")
	(side.find_child("SoundToggle", true, false) as CheckButton).button_pressed = true
	# 逃离现实 asks the app to quit through the normal close path.
	var quits := [0]
	ui.quit_requested.connect(func() -> void: quits[0] += 1)
	side.items[4].pressed.emit()
	check(quits[0] == 1, "逃离现实 requests the normal application exit")
	# Keyboard: Enter on the folded tag opens.
	side.enter()
	await _frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)
	check(side.state != "folded", "Enter opens the folded menu from the keyboard")
	# Reduced motion: static and open; actions do not fold or distort.
	side.set_reduce_motion(true)
	side.enter()
	await _frames(2)
	check(side.state == "open" and side.open_amount == 1.0 and float(side._mat.get_shader_parameter("u_motion")) == 0.0, "reduced motion shows the expanded menu statically")
	side.reveal(achievements)
	achievements.pressed.emit()
	check(side.state == "open" and side._pulse_t < 0.0, "reduced motion skips the fold and the pulse")
	side.set_reduce_motion(false)
	# Window height drives the layout; 21:9 keeps the panel on the left third.
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2520, 1080), Vector2i(1920, 1200)]:
		root.size = size
		await _frames(4)
		var view := root.get_visible_rect().size
		var p := side.panel_rect()
		check(p.size.x <= view.x * 0.62 + 1.0 and p.size.y > view.y * 0.85 and p.position.x < view.x * 0.05, "panel follows the window height at %s" % size)
	ui.queue_free()
	await _frames(2)
	root.size = previous


func test_boot_and_preview() -> void:
	var ui := _ui()
	await _frames(3)
	ui.set_mode("menu")
	ui.play_boot(false)
	await _frames(2)
	check(ui.boot_playing() and ui.boot_splash.mouse_filter == Control.MOUSE_FILTER_STOP, "the boot animation covers the menu and takes the first input")
	var finished := [false, false]
	ui.boot_splash.finished.connect(func(skipped: bool) -> void:
		finished[0] = true
		finished[1] = skipped)
	await _run_for(0.4)
	check(not finished[0], "it keeps playing on its own timeline")
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	await _run_for(ui.boot_splash.skip_time + 0.15 if ui.boot_playing() else 0.0)
	check(finished[0] and finished[1] and not ui.boot_playing(), "any key skips it quickly")
	check(ui.menu_screen.state == "folded" and ui.menu.visible, "the menu waits folded behind it")
	ui.play_boot(true)
	await _frames(2)
	check(is_equal_approx(ui.boot_splash.total(), ui.boot_splash.reduced_total), "reduced flashing plays only the short calm fade")
	await _run_for(ui.boot_splash.reduced_total + 0.3)
	check(not ui.boot_playing(), "the calm version ends by itself")
	# The live campus preview: never in headless runs, released outside the menu.
	var preview := ui.menu_preview
	check(preview != null and preview.get_parent() == ui.menu, "the preview lives in the menu layer")
	check(MenuPreview.supported() == (DisplayServer.get_name() != "headless"), "headless runs keep the static menu photo")
	var c := MenuPreview.orbit_center(CampusData.layout("out"))
	check(is_finite(c.x) and is_finite(c.z) and c != Vector3.ZERO, "the orbit centres on the lawn in front of the teaching building")
	ui.set_mode("play")
	check(not is_instance_valid(preview.world) and preview.modulate.a == 0.0, "leaving the menu frees the preview world")
	ui.queue_free()
	await _frames(2)


func test_app_boot() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/side-menu/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/side-menu/settings.json")
	root.add_child(app)
	await _frames(3)
	check(not app.ui.boot_playing(), "embedded apps (tests, capture scripts) skip the boot animation")
	app.queue_free()
	await _frames(2)
	var shown: GameApp = APP.instantiate()
	shown.saves = SaveStore.new(_test_path.get_base_dir() + "/side-menu-boot/slot.json")
	shown.settings = GameSettings.new(_test_path.get_base_dir() + "/side-menu-boot/settings.json")
	shown.play_boot = true
	root.add_child(shown)
	await _frames(3)
	check(shown.ui.boot_playing() and shown.ui.menu.visible and shown.session == null, "the launched app opens on the boot animation over the menu")
	shown.ui.boot_splash.skip()
	await _run_for(0.5)
	check(not shown.ui.boot_playing() and shown.ui.menu_screen.tag_button.is_visible_in_tree(), "after it the folded menu tag is ready")
	shown.queue_free()
	await _frames(2)
