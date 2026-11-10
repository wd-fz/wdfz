extends SceneTree
## Native game UI, isolated demonstration profile; screenshots are not playthrough evidence.
const APP := preload("res://game/app/app.tscn")
const OUTPUT := "res://build/previews/ui-expansion/"
var app: GameApp


func _initialize() -> void:
	call_deferred("_run")


func shot(label: String) -> void:
	for _i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 720)
	app = APP.instantiate() as GameApp
	app.saves = SaveStore.new("user://framework-tests/expanded-art-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	for _i in 4: await process_frame
	app._setting_changed("quality", 0)
	app.ui.show_notice("")
	await shot("01-menu")
	var achievements := AchievementsModule.new(AnomalyModule.IDS.size() - 1)
	for id: String in ["n.first_san", "n.stairs", "n.hide"]:
		if AchievementsModule.LIST.has(id): achievements.unlocked[id] = true
	# Use actual IDs from the catalogue for a mixed discovered / sealed page.
	for id: String in AchievementsModule.LIST.keys().slice(0, 3): achievements.unlocked[id] = true
	app.ui.show_achievements(achievements.entries(), achievements.points())
	await shot("02-achievements")
	app.ui.ach_panel.hide()
	app.archive_flow.rules.grant(["misread", "patrol", "garage", "end:car", "cut:opening"])
	app.archive_flow.open("死亡")
	await shot("03-archive")
	app.ui.ach_panel.hide()
	app.ui.show_settings(app.settings.values)
	await shot("04-settings")
	app.ui.settings_panel.dismiss()
	var meta := ScoreRules.sample_meta("S", "car")
	meta["source"] = "debug"
	meta["routeName"] = "《闸门》"
	app.ui.show_results(meta, {"silent": true, "reduce": true})
	await shot("05-results")
	app.ui.hide_results()
	app.start_new_game("easy", "watch")
	if app._opening_cut != null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app._stand_up()
	app.patrol().pat["safety"] = 999
	for _i in 8: await process_frame
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	for sample: Array in [["事实", "钟声响起时，走廊的灯也闪了一次。", "教学楼"], ["推测", "脚步声变近时，先留意附近可躲藏的位置。", "个人推测"], ["验证", "手电使用时会消耗电量。", "亲自操作"], ["线索", "实验楼还有尚未查看的房间。", "楼层草图"], ["规则", "检查期间应留在教室，留意黑影的方向。", "停学单"]]:
		app.investigation().record("art-demo-" + String(sample[0]), String(sample[1]), String(sample[0]), String(sample[2]))
	app._show_notes()
	await shot("06-notes")
	app.ui.notes_panel.hide()
	app._show_map("campus")
	await shot("07-campus-map")
	app.ui.map_panel.hide()
	root.size = Vector2i(844, 390)
	app.ui.apply_text_scale(125)
	app.ui.set_touch_enabled(true)
	app._show_map("teach1")
	await shot("08-floor-mobile")
	app.ui.map_panel.hide()
	app._show_notes()
	await shot("09-notes-mobile")
	app.ui.notes_panel.hide()
	app.return_to_menu()
	app.ui.show_ending("《闸门》", "真结局", ["车灯照亮了前方。校门在后视镜里越来越小。"], "示例画面 · 非自然通关实录", PackedStringArray(), "debug", "car")
	await shot("10-ending-mobile")
	app.ui.ending_panel.hide()
	app.ui.show_death_card("你听见自己的名字。", "那只手按住了头顶。", "巡察者抓住了你。", PackedStringArray(["留意灯光与脚步，寻找躲避的位置。"]), PackedStringArray(), "示例画面", "patrol")
	await shot("11-death-mobile")
	app.ui.death_panel.hide()
	await shot("12-menu-mobile")
	app.queue_free()
	for _i in 3: await process_frame
	print("UI EXPANSION CAPTURE: finished")
	quit()
