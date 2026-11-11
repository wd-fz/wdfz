extends "res://tests/support/test_suite.gd"
## The side main menu (side_menu.gd), the boot animation (boot_splash.gd) and the orbiting campus preview.


func _ui() -> GameUI:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	return ui


## Advance a node's own animation by fixed 1/60 s steps, independent of the real frame rate.
func _step(node: Node, seconds: float) -> void:
	var n := ceili(seconds * 60.0)
	for i in n:
		if not is_instance_valid(node): return
		node._process(1.0 / 60.0)


func test_side_menu() -> void:
	var previous := root.size
	root.size = Vector2i(960, 540)
	var ui := _ui()
	await _frames(3)
	ui.set_mode("menu")
	await _frames(2)
	var side: SideMenu = ui.menu_screen
	side.set_process(false)
	check(side.find_child("MenuTag", true, false) == null and side.state == "opening" and side.content.visible, "entering the menu opens it by itself: there is no tag to click first")
	var labels: Array = side.items.map(func(b: Button) -> String: return b.text)
	check(labels == Array(side.item_labels) and labels == ["继续入梦", "新的轮回", "画廊与遗物", "感官设置", "逃离现实"], "five items take their copy from the exported labels")
	check(side.items[0].name == "LoadGame", "继续入梦 is the original continue button")
	for id: String in SideMenu.GROUPS:
		var box := side.groups[id] as VBoxContainer
		for child_id: String in SideMenu.GROUPS[id]:
			if child_id == "DebugTools" and not DebugPanel.enabled(): continue
			check(box.find_child(child_id, false, false) != null, "%s sits under %s" % [child_id, id])
	check(side.find_child("SchoolName", true, false) != null and side.description != null, "the school line and its description stay in the menu")
	# The boot animation's heartbeat.
	var b0 := SideMenu.heartbeat(0.08)
	check(b0 > 0.9 and SideMenu.heartbeat(0.6) < 0.05, "the heartbeat swells twice per beat and rests between")
	# Opening: tear along the spine, then stretch, then the text surfaces.
	check(side.body_rect().size.x < side.panel_rect().size.x * 0.5, "opening starts from a torn sliver at the spine")
	side.open_amount = side.tear_time / (side.tear_time + side.stretch_time)
	var torn := side.body_rect()
	check(absf(torn.size.y - side.layout_rects()["strip"].size.y) < 1.0 and torn.size.x < side.panel_rect().size.x * 0.3, "it first tears along the spine")
	side.open_amount = 0.0
	_step(side, side.tear_time + side.stretch_time + 0.2)
	check(side.state == "open" and absf(side.body_rect().size.x - side.panel_rect().size.x) < 1.0, "then it stretches into the panel")
	check(side.items[1].mouse_filter != Control.MOUSE_FILTER_IGNORE and side.items[1].focus_mode == Control.FOCUS_ALL, "items take input and focus throughout (the opening never locks the menu)")
	var title := side.find_child("Title", true, false) as Control
	check(title.material is ShaderMaterial, "text starts blurred under the reveal shader")
	_step(side, side.reveal_step * 10.0 + side.reveal_time + 0.2)
	check(title.material == null and side.items.all(func(b: Button) -> bool: return b.material == null), "once sharp, text drops the reveal shader (plain batched text)")
	check(not side._revealing, "the reveal finishes")
	# The peephole follows the focused item.
	await _frames(2)     # opening ends by focusing the first usable item (deferred)
	side.items[2].grab_focus()
	await _frames(2)
	_step(side, 0.6)
	var g := side.items[2].get_global_rect()
	check(side._hole_target.position.distance_to(side.get_global_transform().affine_inverse() * g.position) < 1.0 and side._hole_on > 0.5, "the wiped peephole slides to the active item")
	# A group opens in place; its first child surfaces.
	side.items[1].pressed.emit()
	await _frames(3)
	check(side.groups["Rebirth"].visible and not side.groups["Gallery"].visible, "新的轮回 opens its own list and only that one")
	side.items[2].pressed.emit()
	await _frames(2)
	check(side.groups["Gallery"].visible and not side.groups["Rebirth"].visible, "opening another group closes the first")
	# Choosing an action: green pulse from the item, the menu stays open, the scab colours seep back.
	var achievements := side.find_child("Achievements", true, false) as Button
	var hits := [0]
	ui.achievements_requested.connect(func() -> void: hits[0] += 1)
	achievements.pressed.emit()
	check(hits[0] == 1 and side.state == "open" and side._pulse_t >= 0.0 and not side.idle(), "an action fires once and sends a pulse; the menu stays open")
	_step(side, 0.25)
	check(side._shift > 0.8, "the menu turns ghost green while the pulse spreads")
	_step(side, side.pulse_time + side.fade_back_time)
	check(side._shift < 0.02 and side.idle(), "the colours fade back to the blood-scab palette and the menu is idle again")
	# Toggles stay in the open menu.
	side.open_now()
	side.reveal(side.find_child("SoundToggle", true, false))
	(side.find_child("SoundToggle", true, false) as CheckButton).button_pressed = false
	await _frames(2)
	check(side.state == "open" and side._pulse_t < 0.0, "switches such as sound send no pulse")
	(side.find_child("SoundToggle", true, false) as CheckButton).button_pressed = true
	# 逃离现实 asks the app to quit through the normal close path.
	var quits := [0]
	ui.quit_requested.connect(func() -> void: quits[0] += 1)
	side.items[4].pressed.emit()
	check(quits[0] == 1, "逃离现实 requests the normal application exit")
	# Re-entering the menu (back from a run) opens it by itself again.
	side.enter()
	check(side.state == "opening", "returning to the menu replays the opening without any click")
	_step(side, side.tear_time + side.stretch_time + 0.1)
	check(side.state == "open", "and ends open")
	# Reduced motion: static and open; actions do not fold or distort.
	side.set_reduce_motion(true)
	side.enter()
	await _frames(2)
	check(side.state == "open" and side.open_amount == 1.0 and float(side._mat.get_shader_parameter("u_motion")) == 0.0, "reduced motion shows the expanded menu statically")
	side.reveal(achievements)
	achievements.pressed.emit()
	check(side.state == "open" and side._pulse_t < 0.0, "reduced motion skips the pulse")
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
	ui.boot_splash.set_process(false)
	await _frames(2)
	check(ui.boot_playing() and ui.boot_splash.mouse_filter == Control.MOUSE_FILTER_STOP, "the boot animation covers the menu and takes the first input")
	var finished := [false, false]
	ui.boot_splash.finished.connect(func(skipped: bool) -> void:
		finished[0] = true
		finished[1] = skipped)
	var splash := ui.boot_splash
	_step(splash, 0.4)
	check(not finished[0] and splash.elapsed() > 0.39, "it keeps playing on its own timeline")
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	_step(splash, splash.skip_time + 0.05)
	await _frames(2)
	check(finished[0] and finished[1] and not ui.boot_playing(), "any key skips it quickly")
	check(ui.menu_screen.state == "opening" and ui.menu.visible, "when it ends the menu opens by itself")
	ui.play_boot(true)
	ui.boot_splash.set_process(false)
	await _frames(2)
	check(is_equal_approx(ui.boot_splash.total(), ui.boot_splash.reduced_total), "reduced flashing plays only the short calm fade")
	_step(ui.boot_splash, ui.boot_splash.reduced_total + 0.1)
	await _frames(2)
	check(not ui.boot_playing(), "the calm version ends by itself")
	# The live campus preview: off by default, never in headless runs, released outside the menu.
	var preview := ui.menu_preview
	check(GameSettings.DEFAULTS["menu_orbit"] == 0 and not preview.orbit, "the live orbit is off by default (still picture, saves power)")
	preview.enabled = true
	preview.begin_load()
	check(not preview._requested, "with the orbit off nothing 3D is loaded")
	preview.set_orbit(true)
	check(preview.orbit and (preview._requested == MenuPreview.supported()), "switching it on starts the load where a display exists")
	preview.set_orbit(false)
	check(not preview._requested and not is_instance_valid(preview.world), "switching it off releases everything")
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
	check(not app.ui.menu_preview.enabled and not app.ui.menu_preview._requested, "embedded apps never start the live preview's background load")
	app.ui._last_input_ms = -100000
	app._menu_frame_cap()
	check(not app._menu_fps_capped, "embedded apps are never frame-capped on the menu")
	app.queue_free()
	await _frames(2)
	var shown: GameApp = APP.instantiate()
	shown.saves = SaveStore.new(_test_path.get_base_dir() + "/side-menu-boot/slot.json")
	shown.settings = GameSettings.new(_test_path.get_base_dir() + "/side-menu-boot/settings.json")
	shown.play_boot = true
	root.add_child(shown)
	await _frames(3)
	check(shown.ui.boot_playing() and shown.ui.menu.visible and shown.session == null, "the launched app opens on the boot animation over the menu")
	check(shown.ui.menu_preview.enabled, "the launched app turns the live preview on")
	var shown_splash := shown.ui.boot_splash
	shown_splash.set_process(false)
	shown_splash.skip()
	_step(shown_splash, 0.4)
	await _frames(2)
	check(not shown.ui.boot_playing() and shown.ui.menu_screen.state in ["opening", "open"], "after it the menu opens by itself")
	# Idle menu frame cap in the launched app: 30 fps when nothing moves, normal at once on input.
	shown.ui.menu_screen.open_now()
	shown.ui._last_input_ms = -100000
	shown._menu_frame_cap()
	check(shown._menu_fps_capped and Engine.max_fps == GameApp.MENU_IDLE_FPS, "an idle main menu runs at the lower frame rate")
	shown.ui._last_input_ms = Time.get_ticks_msec()
	shown._menu_frame_cap()
	check(not shown._menu_fps_capped and Engine.max_fps == shown.settings.get_int("fps_limit"), "any input restores the player's frame limit")
	shown.ui._last_input_ms = -100000
	shown.ui.show_settings(shown.settings.values)
	shown._menu_frame_cap()
	check(not shown._menu_fps_capped, "an open settings panel is never throttled")
	shown.ui.settings_panel.dismiss()
	shown.queue_free()
	await _frames(2)
