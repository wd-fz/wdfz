extends SceneTree
## Low-SAN picture (needs a display): godot --path . --script res://tools/capture_sensory.gd
## Output: build/previews/sensory/. Same corridor at SAN 100, 35 and 8.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/sensory/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://sensory-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app.patrol().pat["safety"] = 999.0
	DirAccess.make_dir_recursive_absolute("res://build/previews/sensory")
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var s := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 46, 9))
	app.travel("teach1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(0.0), "pitch": -0.05}, false)
	for san in [100.0, 35.0, 8.0]:
		app.school().san = san
		app._blink_next = 999.0
		await _shot("san-%d" % int(san))
	quit()
