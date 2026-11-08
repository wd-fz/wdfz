extends SceneTree
## The midnight doorview (needs a display): godot --path . --script res://tools/capture_doorview.gd
## Output: build/previews/doorview/.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://doorpreview/save.json")
	app.settings = GameSettings.new("user://doorpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/doorview")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["teach1"]
	var sh := CampusGeometry.shift_of(room)
	var door := Vector2(float(room["ox"]) + 31.5 * float(room["tw"]), float(room["oy"]) + float(room["rows"]) * float(room["th"])) + sh
	var sc := CampusGeometry.to_scene(null, door + Vector2(0, 5.0 * 9.0))
	app.travel("out", {"position": [sc.x, 0.05, sc.y], "yaw": 0.0, "pitch": 0.0}, false)
	app.player.enabled = false
	app.player.seated = false
	for _i in 30:
				await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/doorview/door-view.png")
	quit()
