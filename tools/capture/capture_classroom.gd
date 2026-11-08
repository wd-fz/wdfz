extends SceneTree
## Classroom with classmates (needs a display): godot --path . --script res://tools/capture/capture_classroom.gd
## Output: build/previews/classroom/. The run starts seated; the second shot injects 75 violations.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/classroom/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://classroom-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app.patrol().pat["safety"] = 999.0
	DirAccess.make_dir_recursive_absolute("res://build/previews/classroom")
	await _shot("1-seated-class")
	app._stand_up()
	var t1 := CampusData.layout("teach1")
	var s := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 46, 9))
	app.travel("teach1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(0.0), "pitch": -0.1}, false)
	app.school().viol = 75.0
	await _shot("2-classmates-staring")
	quit()
