extends SceneTree
## Controlled paper event via the real pickup, read and throw flow. Landscape, isolated profile.
const APP := preload("res://game/app/app.tscn")
var app: GameApp
func _initialize() -> void: call_deferred("_run")
func _shot(label: String) -> void:
	var world := app._campus_world()
	world.lighting.update(0,app.school().tsec,app.player.camera)
	app.ui.scene_post().parameter("exposure",world.lighting.post_exposure)
	for _i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/paper/"+label+".png")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/paper")
	root.size = Vector2i(1280,720)
	app = APP.instantiate()
	app.saves = SaveStore.new("user://paper-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.ui.set_touch_enabled(true)
	var helper := preload("res://tests/support/test_suite.gd").new(self)
	var spot: Dictionary = helper._paper_spot("danger")
	var room: Dictionary = CampusData.rules().room(spot["room"])
	app.travel(spot["room"],helper._campus_pose(room,spot["stand"],spot["look"]),false)
	app.school().tsec = 780
	var school := app.school()
	app.ui.show_status(school.place_name(spot["room"],app.player.position.y),school.period_text(false),school.period_class(false),school.clock_text(false))
	app.ui.show_notice("")
	var win: Dictionary = spot["w"]
	var plane := app.paper()
	plane.s["ev"] = {"kind":"danger","room":spot["room"],"c":win["c"],"r":win["r"],"phase":"fly","t":1.2,"lx":spot["stand"].x,"ly":spot["stand"].y,"text":PaperPlaneModule.DANGER_TEXT}
	plane.set_context(app._paper_context())
	app._show_plane(plane)
	await _shot("横屏-飞入与窗后手掌")
	plane.s["ev"]["phase"] = "wait"
	plane.use_here()
	app._apply_paper_events()
	app._show_plane(plane)
	app._paper_step(1)
	await _shot("横屏-阅读倒计时")
	app._choice_made(0)
	plane.set_context(app._paper_context())
	plane.use_here()
	app._show_plane(plane)
	await _shot("横屏-跟拍与四向控制")
	root.size = Vector2i(1600,720)
	await _shot("宽横屏-跟拍与四向控制")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
