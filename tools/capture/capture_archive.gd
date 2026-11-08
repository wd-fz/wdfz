extends SceneTree
## Isolated native archive screenshots; all grants are capture-only debug grants.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func shot(label: String) -> void:
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/archive/"+label+".png")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/archive")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-archive-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new("user://capture-archive/settings.json")
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	app.set_process(false)
	var flow := app.archive_flow
	flow.rules.record("patrol","grip",false,false,null,123456)
	flow.open()
	await shot("真实记录与封存")
	flow.unlock_all()
	flow.open("演出")
	await shot("演出列表")
	root.size = Vector2i(420,900)
	await process_frame
	flow.open("死亡")
	await shot("竖屏档案")
	root.size = Vector2i(1280,720)
	await process_frame
	flow.play("x.rules.knock")
	flow.stage.set_process(false)
	flow.stage.death.update(4.7)
	await shot("独立重播")
	flow.stop(true)
	flow.play("cut:void_out")
	flow.stage.cut.set_process(false)
	flow.stage.cut.apply_frame(.6)
	await shot("电梯返回过场")
	flow.stop()
	app.queue_free()
	await process_frame
	quit()
