extends SceneTree
## Controlled native shots through the formal ending flow, in an isolated profile.
## Output: build/previews/endings/. Frames of the 网安仙人 scene.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/endings/%s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/endings")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://cyber-preview-%d/save.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	for screen: Vector2i in [Vector2i(1280,720),Vector2i(1600,720)]:
		root.size = screen
		for _i in 4: await process_frame
		app.start_new_game("hard","none")
		app.set_physics_process(false)
		app.set_process(false)
		app.player.set_physics_process(false)
		await app._reach_ending("cyber")
		var cut: EndingCut = app._ending_cut
		cut.set_process(false)
		for spec: Array in [["1-racks",.08],["2-corridor",.3],["3-archive",.675],["4-dawn",.9]]:
			cut.k = float(spec[1])
			cut._apply(cut.k)
			await _shot(("cyber-wide-" if screen.x>1280 else "cyber-landscape-")+String(spec[0]))
		app.return_to_menu()
		for _i in 3: await process_frame
	app.queue_free()
	await process_frame
	quit()
