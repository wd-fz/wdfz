extends SceneTree
## Controlled real cinematic entrance, advancing every frame before landscape sampling.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/death-timelines")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://death-timelines-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.camera.position.y = CameraMotion.EYE
	app.ui.show_notice("")
	app._campus_world().lighting.update(0,app.school().tsec,app.player.camera)
	app.ui.scene_post().parameter("exposure",app._campus_world().lighting.post_exposure)
	for spec: Array in [["trash",1.4],["freeze",2.4],["shatter",2.4],["water",2.5],["liftdoor",2.6],["neck",2.5]]:
		app._start_death_cg(spec[0])
		var cg := app._death_cg
		var sampled := 0.0
		while sampled<float(spec[1]):
			sampled = minf(spec[1],sampled+1.0/60)
			cg.update(sampled)
		for _i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/death-timelines/%s.png" % spec[0])
		app._stop_death_cg()
		for _i in 3: await process_frame
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
