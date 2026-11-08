extends SceneTree
## The corridor bridge seen from inside it (needs a display): godot --path . --script res://tools/capture/capture_link_view.gd
## Output: build/previews/linkview/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://linkview/save.json")
	app.settings = GameSettings.new("user://linkview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/linkview")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["link1"]
	var mid := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + float(room["cols"]) * float(room["tw"]) * 0.5, float(room["oy"]) + float(room["rows"]) * float(room["th"]) * 0.5))
	for yaw: float in [0.0, PI]:
		app.travel("link1", {"position": [mid.x, 0.05, mid.y], "yaw": yaw, "pitch": 0.0}, false)
		app.player.enabled = false
		for _i in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/linkview/link1-yaw%d.png" % int(yaw * 100))
	print("PREVIEWS ", app._campus_world().link_previews.size())
	quit()
