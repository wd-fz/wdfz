extends SceneTree
## Native evidence for the restored ending, at reproducible camera frames.
const APP := preload("res://game/app/app.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size=Vector2i(1280,720)
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://beast-preview/slot.json")
	app.settings=GameSettings.new("user://beast-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game("hard")
	app.set_physics_process(false)
	app._stand_up()
	app._campus_world().lighting.update(0,app.school().tsec,app.player.camera)
	app._reach_ending("beast")
	var cut:=app._ending_cut
	cut.set_process(false)
	DirAccess.make_dir_recursive_absolute("res://build/previews/beast")
	for k: float in [.27,.65,.86]:
		cut._apply(k)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/beast/%02d.png" % roundi(k*100))
	app.return_to_menu()
	app.queue_free()
	await process_frame
	CampusData.clear_caches()
	quit()
