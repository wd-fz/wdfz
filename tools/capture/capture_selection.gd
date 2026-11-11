extends SceneTree
## Native screenshots of the live talent picker and item confirmation.
## godot --path . --script res://tools/capture/capture_selection.gd
## Output: build/previews/selection/. Uses an isolated profile and no game save.


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int = 8) -> void:
	for _i in count: await process_frame


func _shot(file: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/selection/"+file+".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/selection")
	root.size = Vector2i(1280,720)
	var app: GameApp = preload("res://game/app/app.tscn").instantiate()
	app.saves = SaveStore.new("user://selection-preview/unused.json")
	app.settings = GameSettings.new("user://selection-preview/settings.json")
	root.add_child(app)
	await _frames()
	app.ui.set_touch_enabled(true)
	app._pick_talent("easy")
	await _frames()
	app.ui.selection_panel.select(0)
	await _shot("01-选择与确认")
	root.size = Vector2i(844,390)
	app.ui.apply_text_scale(150)
	await _frames()
	app.ui.selection_panel.select(2)
	await _shot("02-短横屏大字号")
	app.ui.selection_panel.select(7)
	app.ui.selection_panel.list_scroll.ensure_control_visible(app.ui.selection_panel.cards[7])
	await _shot("03-随机天赋")
	app.ui.hide_choice()
	app.ui.apply_text_scale(100)
	root.size = Vector2i(1280,720)
	app.ui.show_bag([
		{"id":"torch","name":"手电筒","text":"照亮身前的黑暗，照退车库里靠近的黑影。"},
		{"id":"phone","name":"旧手机","text":"查看无线网络、拍照和查询巡察者。"},
		{"id":"key","name":"车钥匙","text":"一把尚未找到对应车辆的钥匙。"},
	])
	await _frames()
	var drop := app.ui.bag_panel.find_child("Drop_torch",true,false) as Button
	app.ui._bag_scroll.ensure_control_visible(drop)
	await _frames()
	for down: bool in [true,false]:
		var event := InputEventScreenTouch.new()
		event.pressed = down
		event.position = root.get_final_transform() * drop.get_global_rect().get_center()
		Input.parse_input_event(event)
		await _frames(2)
	await _shot("04-丢弃确认")
	app.ui.hide_bag()
	root.size = Vector2i(844,390)
	app.ui.apply_text_scale(150)
	app.ui.show_ending("闸门","真结局",["车窗外的道路终于有了颜色。你松开方向盘，确认身后的黑影没有追来。".repeat(12)],"第 1 天",PackedStringArray(),"rated","car")
	await _shot("05-结局固定操作")
	app.ui.show_ending("再睁开眼","",["那一刻，你觉得自己终于离开了学校。\n".repeat(16)],"第 2 天",PackedStringArray(),"","inception")
	app.ui.set_ending_wake(true)
	await _shot("06-醒来按钮")
	app.ui.hide_ending()
	app.ui.apply_text_scale(100)
	app._toggle_debug()
	app.debug_panel.select_page("工具")
	await _shot("07-触屏开发工具")
	app.debug_panel.dismiss()
	app.queue_free()
	await _frames(2)
	CampusData.clear_caches()
	quit()
