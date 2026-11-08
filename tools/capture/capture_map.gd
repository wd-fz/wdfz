extends SceneTree
## The map page (needs a display): godot --path . --script res://tools/capture/capture_map.gd
## Output: build/previews/map/. A floor sketch after a walk along the corridor, and the campus plan.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/map/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://map-preview/unused.json")
	app.settings = GameSettings.new("user://map-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/map")
	var t1 := CampusData.layout("teach1")
	# Walk along the corridor and into the first classroom.
	for c in range(8, 58, 4):
		var s := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, c, 18))
		app.player.global_position = Vector3(s.x, 0.05, s.y)
		app.player.rotation.y = CampusGeometry.yaw_from_ang(0.0)
		app._explore_step(0.4)
	app._show_map("teach1")
	await _shot("floor-sketch")
	app._show_map("campus")
	await _shot("campus-plan")
	quit()
