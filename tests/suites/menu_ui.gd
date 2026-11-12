extends "res://tests/support/test_suite.gd"


func test_menus() -> void:
	var original_size := root.size
	var original_scale := root.content_scale_size
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(4)
	var hits := {}
	for id: String in ["new_requested","new_hard_requested","load_requested","settings_requested","achievements_requested","archive_requested","records_requested","speedrun_requested","dlc_requested","fullscreen_requested","debug_requested","resume_requested","save_requested","menu_requested"]:
		hits[id] = 0
		ui.connect(id,func() -> void: hits[id] += 1)
	hits["notes_requested"] = 0
	hits["map_requested"] = 0
	ui.notes_requested.connect(func(_q: String) -> void: hits.notes_requested += 1)
	ui.map_requested.connect(func(_q: String) -> void: hits.map_requested += 1)
	var main := {"NewGame":"new_requested","HardGame":"new_hard_requested","LoadGame":"load_requested","SettingsMenu":"settings_requested","Achievements":"achievements_requested","Archive":"archive_requested","RecordsMenu":"records_requested","Speedrun":"speedrun_requested","DlcMenu":"dlc_requested","FullscreenMenu":"fullscreen_requested","DebugTools":"debug_requested"}
	var pause := {"Resume":"resume_requested","Save":"save_requested","Reload":"load_requested","BackToMenu":"menu_requested","SettingsPause":"settings_requested","NotesPause":"notes_requested","MapPause":"map_requested","DlcMenu":"dlc_requested","FullscreenPause":"fullscreen_requested","DebugTools":"debug_requested"}
	for resolution: Vector2i in [Vector2i(960,540),Vector2i(1280,800),Vector2i(2340,1080),Vector2i(2520,1080)]:
		root.size = resolution
		for scale: int in [100,150]:
			ui.apply_text_scale(scale)
			for mode: String in ["menu","pause"]:
				ui.set_mode(mode)
				ui.set_save_available(true)
				await _frames(6)
				var side: SideMenu = ui.menu_screen
				var pause_screen: MenuScreen = ui.pause_screen
				var specs: Dictionary = main if mode == "menu" else pause
				var bounds := root.get_visible_rect()
				if mode == "menu":
					check(side.state in ["opening", "open"], "the side menu opens by itself at %s %d%%" % [resolution,scale])
					side.open_now()
					await _frames(3)
					check(bounds.encloses(side.content.get_global_rect()) and side.panel_rect().size.x <= bounds.size.x * 0.63 + 1.0, "side menu panel fits %s at %d%% text and leaves the campus visible" % [resolution,scale])
				else:
					check(bounds.encloses(pause_screen._card.get_global_rect()), "pause menu fits %s at %d%% text" % [resolution,scale])
				var screen: Control = side if mode == "menu" else pause_screen
				var scroll: ScrollContainer = side.scroll if mode == "menu" else pause_screen.scroll
				for id: String in specs:
					var button := screen.find_child(id,true,false) as Button
					if mode == "menu" and button != null: side.reveal(button)
					await _frames(3)
					check(button != null and button.is_visible_in_tree(), "menu retains %s" % id)
					if button == null: continue
					if scroll.is_ancestor_of(button): scroll.ensure_control_visible(button)
					await _frames(3)
					check(bounds.encloses(button.get_global_rect()) and button.size.y >= 44, "%s stays reachable with a touch target" % id)
					if resolution == Vector2i(960,540):
						var before := int(hits[specs[id]])
						await _tap(button)
						check(int(hits[specs[id]]) == before+1, "real touch invokes %s exactly once" % id)
				if mode == "pause":
					var sticky := pause_screen.find_child("Resume",true,false) as Control
					check(not pause_screen.scroll.is_ancestor_of(sticky), "primary action stays outside menu scroll")
	ui.set_mode("menu")
	ui.set_save_available(false)
	check(ui.get_node("%LoadGame").disabled and ui.get_node("%NewGame").theme_type_variation == "PrimaryButton", "empty profile highlights New Game and disables Continue")
	ui.set_fullscreen(true)
	check(ui.menu_screen.find_child("FullscreenMenu",true,false).text == "退出全屏", "menu describes the available fullscreen action")
	ui.apply_text_scale(100)
	ui.menu_screen.reveal(ui.menu_screen.find_child("ImportMenu",true,false))
	await _frames(3)
	await _tap(ui.menu_screen.find_child("ImportMenu",true,false))
	check(ui._import_panel.visible, "old-save import is reachable from the reorganized menu")
	ui._import_panel.hide()
	ui.show_list("档案",[{"id":"first","text":"一个回忆","memo":"条目说明","on":true,"action":func() -> void: pass}])
	await _frames(4)
	ui.focus_list_entry("first")
	check(root.gui_get_focus_owner().get_meta("entry_id","") == "first", "archive return restores focus inside an entry card")
	ui.queue_free()
	await _frames(3)
	root.size = original_size
	root.content_scale_size = original_scale


func test_launch_defaults() -> void:
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "Android export starts in landscape before the scene runs")
	check(ProjectSettings.get_setting("display/window/size/mode") == DisplayServer.WINDOW_MODE_WINDOWED, "desktop launch defaults to windowed")
	check(ProjectSettings.get_setting("display/window/size/mode.android") == DisplayServer.WINDOW_MODE_FULLSCREEN, "Android launch is fullscreen before scene initialization")
	check(ProjectSettings.get_setting("display/display_server/driver.linuxbsd") == "wayland", "Linux prefers native Wayland")
	var settings := GameSettings.new(_test_path.get_base_dir()+"/launch-settings.json")
	settings.load_file()
	check(settings.get_int("full_screen") == 0, "fresh desktop profiles default to windowed")
	settings.set_value("full_screen",1)
	settings.save_file()
	var restored := GameSettings.new(settings.path)
	restored.load_file()
	check(restored.get_int("full_screen") == 1, "an explicit saved desktop fullscreen preference is retained")
	settings.set_value("full_screen",0)
	settings.save_file()
	var android := GameSettings.new(settings.path,"Android")
	android.load_file(true)
	check(android.get_int("full_screen") == 1 and android.values.full_screen == 1, "Android ignores a saved windowed preference")
	check(android.set_value("full_screen",0) == 1, "Android rejects fullscreen-off requests, including launch flags")
	android.save_file()
	android.load_file(true)
	check(android.get_int("full_screen") == 1, "Android persists its fullscreen policy")
	var fresh := GameSettings.new(settings.path+"-fresh","Android")
	fresh.load_file(true)
	check(fresh.get_int("full_screen") == 1, "fresh Android profiles are fullscreen")
	check(not GameSettings.can_toggle_fullscreen("Android") and GameSettings.can_toggle_fullscreen("Windows") and GameSettings.can_toggle_fullscreen("Linux"), "only Android locks fullscreen; touch emulation does not change desktop policy")


func test_android_fullscreen_ui() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	ui.fullscreen_toggle_allowed = false
	root.add_child(ui)
	for mode: String in ["menu","pause"]:
		ui.set_mode(mode)
		ui.set_fullscreen(true)
		await _frames(2)
		var screen: Control = ui.menu_screen if mode == "menu" else ui.pause_screen
		var button := screen.find_child("Fullscreen*",true,false) as Button
		check(not button.is_visible_in_tree() and button.disabled, "Android %s hides and disables fullscreen action" % mode)
		ui.show_settings(GameSettings.new("user://unused","Android").values)
		check(not ui.settings_panel.controls.has("full_screen") and ui.settings_panel.find_child("O_full_screen",true,false) == null, "Android settings contain no fullscreen switch")
		check(ui.settings_panel.controls.has("quality") and ui.settings_panel.controls.has("auto_land"), "Android keeps quality and landscape controls")
		ui.settings_panel.dismiss()
	ui.queue_free()
	await _frames(3)


func test_devices() -> void:
	var original_size := root.size
	var original_scale := root.content_scale_size
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	ui.set_mode("play")
	var phone := PhonePanel.new()
	ui.get_node("Root").add_child(phone)
	var snake := SnakePanel.new()
	ui.get_node("Root").add_child(snake)
	var taps := {"phone":0,"snake":0,"page":""}
	phone.closed.connect(func() -> void: taps.phone += 1)
	phone.app_selected.connect(func(id: String) -> void: taps.page = id)
	snake.closed.connect(func() -> void: taps.snake += 1)
	for resolution: Vector2i in [Vector2i(960,540),Vector2i(1280,800)]:
		root.size = resolution
		for scale: int in [100,150]:
			ui.apply_text_scale(scale)
			phone.show()
			for page: String in ["home","camera","plane"]:
				phone.select(page,"test","开始操作",false)
				phone.copy.text = "当前连接与调查记录。".repeat(40)
				await _frames(6)
				check(root.get_visible_rect().encloses(phone.get_global_rect()), "phone %s fits landscape with %d%% text" % [page,scale])
				check(root.get_visible_rect().encloses(phone.find_child("PhoneClose",true,false).get_global_rect()), "phone close stays outside scroll")
			phone._nav_scroll.ensure_control_visible(phone.app_buttons.camera)
			await _tap(phone.app_buttons.camera)
			check(taps.page == "camera", "phone app navigation works inside its scroll area")
			var before := int(taps.phone)
			await _tap(phone.find_child("PhoneClose",true,false))
			check(int(taps.phone) == before+1, "phone closes with one touch")
			phone.hide()
			snake.show()
			snake.hint.text = "方向键或在画面上滑动转向 · 点「离开」退出 · 玩一会儿，缓口气"
			await _frames(6)
			check(root.get_visible_rect().encloses(snake.get_global_rect()), "snake board and controls fit landscape at %d%% text" % scale)
			before = int(taps.snake)
			await _tap(snake.find_child("SnakeClose",true,false))
			check(int(taps.snake) == before+1, "snake exit remains touchable")
			snake.hide()
	ui.queue_free()
	await _frames(3)
	root.size = original_size
	root.content_scale_size = original_scale
