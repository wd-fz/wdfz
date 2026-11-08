extends SceneTree
## The late mirror (needs a display): godot --path . --script res://tools/capture/capture_mirror.gd
## Output: build/previews/mirror/. SAN 90 (in step), SAN 10 with the arm raised.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/mirror/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://mirrorpreview/save.json")
	app.settings = GameSettings.new("user://mirrorpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/mirror")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["teach1"]
	var spots: Array = app.tales().mirrors("teach1")
	print("MIRRORS ", spots.size())
	var m: Dictionary = spots[0]
	var n: Vector2 = m["n"]
	var stand: Vector2 = (m["w"] as Vector2) + n * 1.6 * float(room["tw"])
	print("W ", m["w"], " N ", n, " STAND ", stand, " CH ", CampusGeometry.tile_at(room, stand), " room ", room["ox"], " ", room["oy"], " tw ", room["tw"])
	var sc := CampusGeometry.to_scene(room, stand)
	var ang := atan2(-n.y, -n.x)
	app.travel("teach1", {"position": [sc.x, 0.05, sc.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": 0.0}, false)
	app.player.enabled = false
	app.player.seated = false
	for _i in 20:
		await process_frame
	app.school().san = 90.0
	for _i in 10:
		app._phantom_step(0.1, app.school(), room, app.player.capture_pose(), app.anomaly())
	await _shot("san90")
	app.school().san = 10.0
	app.tales().raise = 1.0
	for _i in 20:
		app._phantom_step(0.1, app.school(), room, app.player.capture_pose(), app.anomaly())
	await _shot("san10-arm")
	quit()
