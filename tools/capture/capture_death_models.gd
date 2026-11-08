extends SceneTree
## Maintained landscape captures of the original cup, eyes and moths, in an isolated profile.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/death-models")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://death-models-capture-%d/slot.json" % Time.get_ticks_usec())
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
	for spec: Array in [["floor",[.95,1.9]],["gaze",[2.1,2.6]],["swarm",[1.7,2.8]]]:
		app._start_death_cg(spec[0])
		var cg := app._death_cg
		for time: float in spec[1]:
			cg.update(time)
			for _i in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/previews/death-models/%s-%.2f.png" % [spec[0],time])
		app._stop_death_cg()
		for _i in 3: await process_frame
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
