extends "res://tests/support/test_suite.gd"

func test_theme_and_clock() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	var base := GameUI.BASE_THEME
	for scale: int in [85,100,150,100]:
		ui.apply_text_scale(scale)
		var applied: Theme = ui.get_node("Root").theme
		check(applied != base and applied.default_font == base.default_font and applied.get_stylebox("normal","Button") == base.get_stylebox("normal","Button"),"text scaling preserves theme font and button styles")
		check(applied.get_stylebox("panel","PanelContainer") == base.get_stylebox("panel","PanelContainer") and applied.default_font_size == roundi(16*scale/100.0),"text scaling preserves opaque choice panels and scales text only")
	check(base.default_font_size == 16,"scaling does not mutate the shared theme")
	ui.set_mode("play")
	ui.show_status("教学楼 1F","第四节 · 上课","","??:??")
	ui.show_location("教学楼 2F")
	ui.show_runtime(123)
	check(ui.get_node("%Runtime").text == "??:??","location updates never overwrite the unknown watch time")
	ui.show_status("教学楼 2F","午休","","12:51")
	check(ui.get_node("%Runtime").text == "12:51","in-world clock updates in the same HUD pass")
	ui.speedrun_text = "00:15.200"
	ui.show_runtime(999)
	check(ui.get_node("%Runtime").text == "12:51 · 速通 00:15.200","speedrun elapsed time remains visible separately")
	ui.speedrun_text = ""
	ui.reset_status()
	ui.show_location("走廊")
	ui.show_runtime(999)
	check(ui.get_node("%Runtime").text == "走廊" and not ui.get_node("%Runtime").text.contains("运行"),"fallback location does not expose engine runtime")
	var old_size := root.size
	var old_scale := root.content_scale_size
	for size: Vector2i in [Vector2i(960,540),Vector2i(420,900)]:
		root.size = size
		await _frames(3)
		for scale: int in [85,100,150]:
			ui.apply_text_scale(scale)
			ui.show_choice("桌沿的铅笔字上写着：\n「看见它以后，低头就行。\n走开前一定要回头确认。」",["记为可信","记为存疑","先不标"])
			await _frames(5)
			check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(ui.choice_panel.get_global_rect()),"wrapped choice stays inside %s at %d %% text" % [size,scale])
	ui.queue_free()
	await _frames(2)
	root.size = old_size
	root.content_scale_size = old_scale


func test_records_layout() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	var store := RunRecords.new(_test_path.get_base_dir()+"/interface-records")
	var scenes := ["teach1","teach2","teach3","teach4","teach5","exp1","exp2","exp3","exp4"]
	var pack := {"v":1,"run":"layout","scenes":scenes,"track":RunTrack.encode([[0,0,40,30,0],[10,0,44,30,0],[20,0,44,34,16]]),"pat":[],"clock":[],"events":[[10,"anomaly","遭遇「下不完的雨」并进入教学楼，准备寻找不会被巡察者发现的出口。",0,0,44,30]],"start":1,"partial":0}
	var record := ""
	for route: String in ["car","face","portal","dismissal","cyber","international","beast","knife","inception"]:
		var meta := ScoreRules.sample_meta("A",route)
		meta["routeName"] = String(RoutesModule.ENDINGS[route]["t"]).replace(" ","")
		meta["source"] = "real"
		record = store.add(meta,pack)
	var panel := ui.ensure_records(store,CampusData.rooms())
	var old_size := root.size
	var old_scale := root.content_scale_size
	var back := [0]
	ui.show_results(store.get_record(record),{"silent":true,"reduce":true})
	ui.results_panel.back_pressed.connect(func() -> void: back[0]+=1)
	for screen: Vector2i in [Vector2i(960,540),Vector2i(640,360),Vector2i(420,900),Vector2i(320,640)]:
		root.size = screen
		await _frames(3)
		for scale: int in [85,100,150]:
			ui.apply_text_scale(scale)
			ui.hide_results()
			ui.show_list("CG 档案馆 · 死亡  1 / 24",[{"text":"点名","on":true,"memo":"灯按拍子闪的时候，它就在这一层。一只手从后面按住了我的头顶。"}])
			var tabs := []
			for tab: String in ["死亡","演出","规则怪谈","结算"]: tabs.append({"text":tab,"action":func() -> void: pass})
			ui.list_tabs(tabs)
			ui.list_footer("调试：解锁全部 CG",func() -> void: pass)
			await _frames(8)
			check(root.get_visible_rect().encloses(ui.ach_panel.get_global_rect()),"archive title and tabs fit %s / %d" % [screen,scale])
			ui.ach_panel.hide()
			panel.open()
			await _frames(8)
			var bounds := Rect2(Vector2.ZERO,root.get_visible_rect().size)
			check(bounds.encloses(panel.get_global_rect()),"record filters stay inside %s / %d" % [screen,scale])
			check(panel._body.size.x <= panel._scroll.size.x and bounds.encloses(panel._close_button.get_global_rect()),"record content wraps and close stays visible")
			for mode: String in ["rank","grades"]:
				panel._mode = mode
				panel._refresh()
				await _frames(5)
				check(bounds.encloses(panel.get_global_rect()),"records %s remains inside screen" % mode)
			for foot: bool in [false,true]:
				check(panel.open_view(record,foot),"real record opens its replay or footprint")
				await _frames(8)
				check(bounds.encloses(panel.get_global_rect()) and bounds.encloses(panel._close_button.get_global_rect()),"many scene tabs and replay controls fit the viewport")
			panel.hide()
			ui.show_results(store.get_record(record),{"silent":true,"reduce":true})
			await _frames(8)
			var result := ui.results_panel
			check(bounds.encloses(result.get_global_rect()) and bounds.encloses(result.back_button.get_global_rect()),"grade and result footer fit %s / %d" % [screen,scale])
			for child in result.body.get_children():
				if child is Button: child.button_pressed = true
			await _frames(5)
			result._scroll.scroll_vertical = 99999
			await _frames(3)
			check(bounds.encloses(result.back_button.get_global_rect()) and result._scroll.scroll_vertical > 0,"expanded results scroll without losing navigation")
			var before: int = back[0]
			await _tap(result.back_button)
			check(back[0] == before+1,"result return button responds to actual screen touches")
	ui.queue_free()
	await _frames(2)
	root.size = old_size
	root.content_scale_size = old_scale
