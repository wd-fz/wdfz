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
	ui.set_save_available(false)
	await _frames(3)
	var side := ui.menu_screen
	var start := ui.get_node("%NewGame") as Button
	var load := ui.get_node("%LoadGame") as Button
	var settings := side.find_child("SettingsMenu", true, false) as Button
	var opened := [0]
	side.add_coop_action(func() -> void: opened[0] += 1)
	var coop := side.find_child("LanCoop", true, false) as Button
	await _frames(3)
	check(start.is_visible_in_tree() and settings.is_visible_in_tree() and coop.is_visible_in_tree(), "new game, settings and co-op are available on the first page")
	check(load.disabled and start.get_index() < load.get_index(), "a fresh player sees Start before the disabled Continue action")
	await _tap(coop)
	check(opened[0] == 1, "one tap on the first page opens cooperation")
	ui.set_save_available(true)
	check(not load.disabled and load.get_index() < start.get_index(), "a returning player's continue action comes first")
	root.size = Vector2i(844, 390)
	ui.apply_text_scale(150)
	await _frames(5)
	var commands := side.scroll.get_global_rect()
	check(commands.encloses(start.get_global_rect()) and commands.encloses(load.get_global_rect()), "both solo actions fit the first page on a short landscape screen")
	check(commands.encloses(coop.get_global_rect()) and commands.encloses(settings.get_global_rect()), "co-op and settings stay visible without scrolling at 150% text")
	ui.apply_text_scale(100)
	root.size = Vector2i(960, 540)
	await _frames(4)
	var controls := side.find_child("QuickOptions", true, false) as Button
	await _tap(controls)
	check(side.groups.QuickOptions.visible and not coop.is_visible_in_tree(), "quick options have their own page")
	var back := side.find_child("QuickOptionsBack", true, false) as Button
	await _tap(back)
	check(coop.is_visible_in_tree() and root.gui_get_focus_owner() == controls, "returning to the first page restores focus to its entry")
	var backdrop := side.find_child("MenuBackdrop", true, false) as Button
	var requested: Array[int] = []
	ui.setting_changed.connect(func(id: String, value: int) -> void:
		if id == "menu_orbit": requested.append(value))
	await _tap(backdrop)
	check(requested == [1], "switching the cover uses the existing saved panorama setting")
	var quits := [0]
	ui.quit_requested.connect(func() -> void: quits[0] += 1)
	await _tap(side.find_child("QuitGame", true, false))
	check(quits[0] == 1, "Quit asks the app to take the normal exit path")
	side.enter()
	side.set_process(false)
	check(side.state == "opening" and start.is_visible_in_tree(), "the menu opens immediately and its entrance does not block input")
	_step(side, SideMenu.ENTRANCE_SECONDS + 0.1)
	check(side.idle() and side.content.modulate.a == 1.0, "the entrance settles and leaves no running menu animation")
	side.set_reduce_motion(true)
	side.enter()
	check(side.idle() and side.content.modulate.a == 1.0, "reduced motion opens the menu at full opacity")
	check(SideMenu.heartbeat(0.08) > 0.9 and SideMenu.heartbeat(0.6) < 0.05, "the boot heartbeat still swells and rests")
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
	await _test_boot_timeline()
	await _test_loading_screen()
	# The campus panorama behind the menu: off by default, a baked picture panned round, released outside the menu.
	var preview := ui.menu_preview
	check(GameSettings.DEFAULTS["menu_orbit"] == 0, "fresh profiles show the rainy campus cover")
	var old_path := _test_path.get_base_dir() + "/side-menu-orbit/settings.json"
	DirAccess.make_dir_recursive_absolute(old_path.get_base_dir())
	FileAccess.open(old_path, FileAccess.WRITE).store_string(JSON.stringify({"version": 2, "values": {"menu_orbit": 0, "mouse": 130}}))
	var old := GameSettings.new(old_path)
	old.load_file()
	check(old.get_int("menu_orbit") == 0 and old.get_int("mouse") == 130, "older settings files preserve stored values")
	old.set_value("menu_orbit", 1)
	old.save_file()
	var again := GameSettings.new(old_path)
	again.load_file()
	check(again.get_int("menu_orbit") == 1, "an explicit switch to the panorama is kept")
	DirAccess.remove_absolute(old_path)
	preview.set_orbit(false)
	preview.enabled = true
	preview.begin_load()
	check(preview.texture == null and preview.material == null, "with the orbit off no panorama is loaded")
	check(MenuPreview.supported(), "the baked panorama ships with the game")
	preview.set_orbit(true)
	check(preview.orbit and preview.ready_to_show() and preview.material is ShaderMaterial, "switching it on loads the panorama picture")
	var pano := preview.texture
	check(pano.get_width() >= 4 * pano.get_height() and pano.get_width() >= 2048, "it is a full-circle strip (%dx%d)" % [pano.get_width(), pano.get_height()])
	check(preview.find_children("*", "SubViewport", true, false).is_empty() and preview.get_child_count() == 0, "nothing 3D: no viewport, no campus, no camera behind the menu")
	preview.size = Vector2(1280, 720)
	preview._layout()
	var span := float((preview.material as ShaderMaterial).get_shader_parameter("span"))
	check(is_equal_approx(span, preview.tall * pano.get_height() * 1280.0 / (720.0 * pano.get_width())), "the visible arc follows the screen's aspect without stretching")
	var start := preview.angle
	preview._process(15.0)
	check(is_equal_approx(fposmod(preview.angle - start, 1.0), 15.0 / preview.orbit_seconds) and is_equal_approx(float((preview.material as ShaderMaterial).get_shader_parameter("yaw")), preview.angle), "it pans one turn per orbit period")
	preview.still = true
	var held := preview.angle
	preview._process(5.0)
	check(preview.angle == held, "reduced motion holds one angle")
	preview.still = false
	preview.set_orbit(false)
	check(preview.texture == null and preview.material == null and preview.modulate.a == 0.0, "switching it off releases the picture")
	check(preview != null and preview.get_parent() == ui.menu, "the preview lives in the menu layer")
	var eye := MenuPreview.EYE
	var between := {}
	for box: Dictionary in CampusData.layout("out")["boxes"]:
		var inside := eye.x > float(box["x0"]) and eye.x < float(box["x1"]) and eye.z > float(box["z0"]) and eye.z < float(box["z1"])
		check(not inside, "the panorama's eye point is in the open, not inside %s" % String(box.get("id", box["k"])))
		if String(box["k"]) == "building" and eye.x > float(box["x0"]) and eye.x < float(box["x1"]):
			between[String(box.get("id", ""))] = true
	check(between.has("lab") and between.has("teach"), "the panorama is baked in the courtyard between the lab and teaching buildings")
	preview.set_orbit(true)
	ui.set_mode("play")
	check(preview.texture == null and preview.modulate.a == 0.0, "leaving the menu drops the panorama")
	ui.queue_free()
	await _frames(2)


func test_app_boot() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/side-menu/slot.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/side-menu/settings.json")
	root.add_child(app)
	await _frames(3)
	check(not app.ui.boot_playing(), "embedded apps (tests, capture scripts) skip the boot animation")
	check(not app.ui.menu_preview.enabled and app.ui.menu_preview.texture == null, "embedded apps keep the static photo (no panorama)")
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
	check(shown.ui.menu_preview.enabled, "the launched app turns the panorama on (shown when the setting allows)")
	var shown_splash := shown.ui.boot_splash
	shown_splash.set_process(false)
	shown_splash.skip()
	_step(shown_splash, 0.4)
	await _frames(2)
	check(not shown.ui.boot_playing() and shown.ui.menu_screen.state in ["opening", "open"], "after it the menu opens by itself")
	# The menu's entrance (2026-11-13): the campus behind wakes, eyelids part with one blink, the panorama eases back.
	var wake := shown.ui.menu_wake
	check(wake != null and shown.ui.menu_entering() and wake.get_parent() == shown.ui.menu and wake.get_index() < shown.ui.menu_screen.get_index() and wake.get_index() > shown.ui.menu_preview.get_index(), "the menu's entrance plays between the panorama and the side menu")
	check(wake.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the entrance never blocks the menu")
	check(wake.openness(0.0) == 0.0 and wake.openness(wake.blink_peak) > 0.3 and wake.openness(wake.blink_shut) < 0.05 and is_equal_approx(wake.openness(wake.open_time), 1.0) and wake.darkness(wake.open_time) == 0.0, "eyelids: shut, half open, blink shut, then fully open with no darkness left")
	wake.set_process(false)
	wake._t = 0.0
	wake._apply()
	check(is_equal_approx(shown.ui.menu_preview.zoom, shown.ui.menu_preview.entrance_zoom), "the panorama starts pushed in")
	check(not shown.ui.menu_idle(), "the menu is not idle while it wakes")
	wake.finish()
	await _frames(1)
	check(not shown.ui.menu_entering() and shown.ui.menu_preview.zoom == 1.0, "the entrance frees itself and leaves the panorama at rest")
	shown.ui._enter_menu(false)
	check(not shown.ui.menu_entering(), "re-entering a menu that is already open does not replay the entrance")
	var calm := MenuWake.new()
	calm.reduce_motion = true
	check(calm.openness(0.1) == 1.0 and calm.total() == calm.reduced_time and calm.darkness(calm.reduced_time) == 0.0, "reduced flashing: a short fade from black, no blink")
	calm.free()
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
	# The loading screen (2026-11-13): over everything, takes input, eases its bar, fades out and frees itself.
	var screen := shown.ui.show_loading("读取校园")
	await _frames(1)
	check(shown.ui.loading() and screen.mouse_filter == Control.MOUSE_FILTER_STOP and screen.get_parent() == shown.ui.get_node("Root") and screen.get_index() == screen.get_parent().get_child_count() - 1, "the loading screen covers everything and takes input")
	shown.ui._last_input_ms = -100000
	check(not shown.ui.menu_idle(), "the menu is not throttled while a run loads")
	screen.set_progress(0.6, "布置教室")
	screen.set_progress(0.3)
	check(screen.progress == 0.6 and screen.stage == "布置教室", "progress never runs backwards")
	screen._process(5.0)
	check(screen.shown_progress > 0.0 and screen.shown_progress <= 0.6, "the bar eases towards the progress without jumping on a long frame")
	shown.ui.hide_loading()
	check(not shown.ui.loading() and screen.closing() and screen.mouse_filter == Control.MOUSE_FILTER_IGNORE, "closing lets input through at once while it fades")
	for _i in 6:
		if is_instance_valid(screen): screen._process(0.1)
	await _frames(1)
	check(not is_instance_valid(screen), "the faded loading screen frees itself")
	var paths := CampusWorld.asset_paths("teach1")
	check(paths.has(CampusData.scene_path("teach1")) and paths.has(CampusWorld.PATROL_FIGURE) and CampusWorld.asset_paths("migration_lab").is_empty(), "the loading screen reads the start classroom's models first (none for non-campus worlds)")
	for path: String in paths:
		check(ResourceLoader.exists(path), "listed model exists: " + path)
	shown.queue_free()
	await _frames(2)


## The 2026-11-14 boot animation: tube flicker, the clock ticking to 18:00, one step back, the tube dying to black.
func _test_boot_timeline() -> void:
	var splash := BootSplash.new()
	root.add_child(splash)
	splash.set_process(false)
	await _frames(1)
	check(splash.light(0.0) == 0.0 and splash.light(splash.light_at + 0.01) == 1.0 and splash.light(splash.light_at + 0.1) == 0.0, "the tube starter-flickers on")
	check(splash.light(splash.title_at) > 0.9 and splash.light(splash.back_tick_at) > 0.9, "then it hums steadily")
	check(splash.light(splash.die_at + splash.die_time) == 0.0 and splash.light(splash.total()) == 0.0, "it dies and leaves black")
	check(is_equal_approx(splash.second_hand(0.0), BootSplash.START_SECOND) and not splash.at_six(1.0), "the clock starts at 17:59:52")
	check(splash.at_six(splash.title_at + 0.9) and absf(splash.second_hand(splash.back_tick_at - 0.05) - 60.0) < 0.05, "the second hand reaches twelve and the clock reads 18:00")
	check(absf(splash.second_hand(splash.back_tick_at + 0.3) - 59.0) < 0.05, "then it ticks one step back")
	var cues: Array = []
	splash.cue.connect(func(id: String) -> void: cues.append(id))
	var ended := [false]
	splash.finished.connect(func(skipped: bool) -> void: ended[0] = not skipped)
	_step(splash, splash.total() + 0.1)
	check(cues == ["world.lampFlicker", "threat.heartLow", "dread.knock", "world.lampFlicker"], "cues: tube on, heartbeat, the backward knock, tube off (%s)" % [cues])
	check(ended[0], "it ends by itself on black")
	var calm := BootSplash.new()
	calm.reduce_motion = true
	root.add_child(calm)
	calm.set_process(false)
	await _frames(1)
	var rising := true
	var last := -1.0
	for i in 20:
		var at := calm.reduced_total * 0.45 * i / 19.0
		rising = rising and calm.light(at) >= last
		last = calm.light(at)
	check(rising and calm.second_hand(0.2) == 60.0 and calm.at_six(0.0), "reduced flashing: the light only fades up (no flicker) on a still clock at 18:00")
	var calm_cues: Array = []
	calm.cue.connect(func(id: String) -> void: calm_cues.append(id))
	_step(calm, calm.total() + 0.1)
	check(calm_cues.is_empty(), "reduced flashing plays no flicker or knock cues")


## The 2026-11-14 loading screen: clock follows the progress, rotating lines, percentage and the ember bar.
func _test_loading_screen() -> void:
	var screen := LoadingScreen.new()
	root.add_child(screen)
	screen.set_process(false)
	await _frames(2)
	screen.set_progress(0.5, "读取校园")
	screen.shown_progress = 0.5
	screen._apply()
	var clock := (screen.get_node("LoadingColumn").find_child("LoadingClock", true, false) as ColorRect).material as ShaderMaterial
	check(is_equal_approx(float(clock.get_shader_parameter("u_minute_hand")), 30.0) and is_equal_approx(float(clock.get_shader_parameter("u_minutes")), 1050.0), "half way the clock reads 17:30")
	check((screen.find_child("LoadingPercent", true, false) as Label).text == "50%" and (screen.find_child("LoadingStage", true, false) as Label).text == "读取校园", "percentage and step are shown under the bar")
	var bar := screen.find_child("LoadingBar", true, false) as ColorRect
	check(absf(bar.size.x - screen._bar_back.custom_minimum_size.x * 0.5) < 0.5, "the bar's filled length follows the progress")
	var first: Array = screen.line_at(0.5)
	var second: Array = screen.line_at(LoadingScreen.LINE_TIME + 1.5)
	check(first[1] == 1.0 and second[1] == 1.0 and first[0] != second[0], "the quiet line changes every few seconds")
	check(screen.line_at(LoadingScreen.LINE_TIME - 0.01)[1] < 0.1 and screen.line_at(LoadingScreen.LINE_TIME + 0.01)[1] < 0.1, "lines crossfade through nothing")
	screen.set_progress(0.2)
	check(screen.progress == 0.5, "progress never runs backwards")
	screen.queue_free()
	await _frames(1)
