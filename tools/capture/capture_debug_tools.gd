extends SceneTree
## Native Vulkan workbench captures; maintained landscape sizes only.
const APP:=preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _shot(label: String) -> void:
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/debug-tools/"+label+".png")
func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/debug-tools")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-debug-tools/slot.json")
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	for _i in 8: await process_frame
	app._stand_up()
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._toggle_debug()
	app.debug_panel.select_page("诊断")
	app.debug_flow.command("collisions")
	for _i in 12: await process_frame
	await _shot("桌面诊断")
	var options: OptionButton=app.debug_panel._selectors.DevDeath.option
	for i in options.item_count:
		if options.get_item_metadata(i)=="garage": options.select(i)
	app.debug_flow.command("preview",{"id":"garage"})
	app.debug_flow.command("preview_seek",{"fraction":.58})
	app.debug_panel.select_page("事件")
	for _i in 3: await process_frame
	app.debug_panel._scroll.ensure_control_visible(app.debug_panel._preview_pause)
	await _shot("演出时间轴")
	app.debug_flow.command("clear_preview")
	app.debug_flow.command("collisions")
	root.size=Vector2i(960,540)
	app.ui.set_touch_enabled(true)
	app.debug_panel.select_page("日志")
	app.fact({"kind":"交互检查","result":"座位提示优先于附近课桌","room":"teach1"})
	app.debug_flow.refresh()
	await _shot("横屏日志")
	root.size=Vector2i(854,480)
	app.debug_panel.select_page("场景")
	app.debug_flow.command("bookmark_add",{"name":"教室过道 · 提示检查"})
	for _i in 3: await process_frame
	app.debug_panel._scroll.scroll_vertical=10000
	await _shot("横屏位置书签")
	app.debug_panel.set_collapsed(true)
	await _shot("横屏悬浮球")
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
