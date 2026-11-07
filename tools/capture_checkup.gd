extends SceneTree
## Checkup day in admin1 (needs a display): godot --path . --script res://tools/capture_checkup.gd
## Output: build/previews/checkup/. Injects day 3 as the checkup day at 10:25.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/checkup/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://checkup-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	app.school().day = 3
	app.days().day_events["3"] = "checkup"
	app.school().tsec = 625.0
	DirAccess.make_dir_recursive_absolute("res://build/previews/checkup")
	var a1 := CampusData.layout("admin1")
	var p := func(c: float, r: float) -> Vector2:
		return CampusGeometry.to_scene(a1, Vector2(float(a1["ox"]) + c * float(a1["tw"]), float(a1["oy"]) + r * float(a1["th"])))
	var s: Vector2 = p.call(7.5, 17.4)
	app.travel("admin1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(PI), "pitch": -0.05}, false)
	await _shot("1-queue-in-corridor")
	s = p.call(3.2, 15.4)
	app.travel("admin1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(PI), "pitch": -0.1}, false)
	await _shot("2-rule-and-scale")
	s = p.call(7.9, 15.45)
	app.travel("admin1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(0.0), "pitch": 0.05}, false)
	await _shot("3-eye-chart")
	quit()
