extends SceneTree
## Native landscape UI gallery, isolated profile and illustrative record fixtures.
## DISPLAY=:96 godot --windowed --path . --script res://tools/capture/capture_interface.gd
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/interface/"+label+".png")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/interface")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-interface-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	await shot("主菜单")
	app.ui.settings_requested.emit()
	await shot("设置")
	app.ui.settings_panel.dismiss()
	app.rules_dlc_flow.menu()
	await shot("模式选择")
	app._choice_made(-1)
	var record := ""
	for route: String in ["car","face","portal","dismissal","cyber","international","beast","knife","inception"]:
		var meta := ScoreRules.sample_meta("A",route)
		meta["routeName"] = String(RoutesModule.ENDINGS[route]["t"]).replace(" ","")
		meta["source"] = "debug"
		record = app.runs().add(meta)
	var records := app.ui.ensure_records(app.runs(),CampusData.rooms())
	records.open()
	await shot("通关记录")
	records.hide()
	app.ui.show_results(app.runs().get_record(record),{"silent":true,"reduce":true})
	await shot("结算")
	app.ui.hide_results()
	app.start_new_game("hard","none")
	app.ui._end_opening(true)
	await shot("游戏内界面")
	app.pause_game()
	await shot("暂停")
	for id: String in ["torch","phone","watch","snack"]: app.items().add(id)
	app._open_bag()
	await shot("背包")
	app.ui.hide_bag()
	app.investigation().record("preview","实验楼的门后藏着另一条离校路线。","线索","实验楼")
	app._show_notes()
	await shot("笔记")
	app.ui.notes_panel.hide()
	app._show_map()
	await shot("地图")
	app.ui.map_panel.hide()
	app._show_achievements()
	await shot("成就")
	app.ui.ach_panel.hide()
	app._ensure_phone_panel()
	app._phone_panel.show()
	app._phone_panel.select("home","test","打开连接列表",false)
	app._phone_panel.status.text = "电量 100% · 校园终端"
	app._phone_panel.copy.text = "设备已准备就绪。\n\n选择左侧应用，查看网络、门禁与相机。"
	await shot("手机")
	app._phone_panel.hide()
	app._start_snake()
	await shot("小游戏")
	app._stop_snake(true)
	root.size = Vector2i(960,540)
	app._setting_changed("text",150)
	await shot("暂停小屏大字")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	CampusData.clear_caches()
	quit()
