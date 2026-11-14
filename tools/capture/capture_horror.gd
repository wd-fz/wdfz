extends SceneTree
## The 2026-11-14 horror plan (needs a display): godot --path . --script res://tools/capture/capture_horror.gd
## Output: build/previews/horror/. The corridor notice (one red line without the stamp) and a revisit's chalk
## line, both on a wall picked by the dread module, the camera turned to them. Injected, not natural play.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/horror/%s.png" % name)


func _show(app: GameApp, kind: String, lines: Array) -> void:
	var d := app.dread()
	d.set_context(app._dread_context())
	var sp: Variant = d.spot(2.5, 5.0)
	if sp == null:
		return
	var face: Dictionary = app._wall_face(sp)
	app._campus_world().show_wall_text(kind, lines, face["pos"], float(face["yaw"]))
	var cam_from: Vector3 = app.player.camera.global_position
	var to: Vector3 = (face["pos"] as Vector3) - cam_from
	app.player.rotation.y = atan2(-to.x, -to.z)
	app.player.camera.rotation.x = 0.0


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://horror-preview/save.json")
	app.settings = GameSettings.new("user://horror-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/horror")
	app.start_new_game("easy")
	while app.starting():
		await process_frame
	for _i in 10:
		await process_frame
	app._stand_up()
	for _i in 30:
		await process_frame
	app.player.enabled = false
	app.set_physics_process(false)
	var content := DreadModule.notice_lines(2, 530.0)
	await _show(app, "notice", content["lines"])
	await _shot("1-corridor-notice")
	app.player.camera.fov = 30.0
	await _shot("1b-corridor-notice-close")
	app.player.camera.fov = 75.0
	await _show(app, "board", [DreadModule.BOARD_LINES[0]])
	await _shot("2-revisit-chalk-line")
	quit()
