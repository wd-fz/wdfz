extends SceneTree
## Real menu/settings and a short seated run; temporary profile only.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 6: await process_frame
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
	await shot("横屏通关记录")
	records.hide()
	app.ui.show_results(app.runs().get_record(record),{"silent":true,"reduce":true})
	await shot("横屏结算")
	app.ui.hide_results()
	app.wuda_roll = func() -> float: return 1
	app.settings.rules_armed = true
	app.start_new_game("hard","none")
	await shot("教室时钟与状态")
	root.size = Vector2i(420,900)
	await process_frame
	app._setting_changed("text",150)
	app.rules_dlc_flow.module().read("R03")
	app.rules_dlc_flow.flush()
	await shot("竖屏大字规则批注")
	app._choice_made(-1)
	app.return_to_menu()
	records.open()
	await shot("竖屏大字记录")
	records.hide()
	app.ui.show_results(app.runs().get_record(record),{"silent":true,"reduce":true})
	await shot("竖屏大字结算")
	app.ui.hide_results()
	app.queue_free()
	await process_frame
	quit()
