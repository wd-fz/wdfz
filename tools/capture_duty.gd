extends SceneTree
## The duty roster at assimilation tiers (needs a display): godot --path . --script res://tools/capture_duty.gd
## Output: build/previews/duty/. The roster beside the blackboard of the first classroom at tier 0, 2 and 4.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/duty/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://duty-preview/unused.json")
	app.settings = GameSettings.new("user://duty-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/duty")
	var board: MeshInstance3D = app._campus_world().duty.boards[0]
	var bp := board.global_position
	app.player.global_position = Vector3(bp.x + 1.3, 0.05, bp.z)
	app.player.rotation.y = PI * 0.5
	app.player.camera.rotation.x = 0.0
	for tt in [0.0, 45.0, 85.0]:
		app.school().tt = tt
		for _i in 6:
			await process_frame
		await _shot("tier-%d" % int(tt / 20.0))
	quit()
