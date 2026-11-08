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
