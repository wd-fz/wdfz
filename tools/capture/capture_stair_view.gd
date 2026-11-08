extends SceneTree
## The midnight stairview (needs a display): godot --path . --script res://tools/capture_stairview.gd
## Output: build/previews/stairview/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://stairpreview/save.json")
	app.settings = GameSettings.new("user://stairpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/stairview")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["teach1"]
	var sc := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + 6.5 * float(room["tw"]), float(room["oy"]) + 18.5 * float(room["th"])))
	app.travel("teach1", {"position": [sc.x, 0.05, sc.y], "yaw": PI, "pitch": -0.1}, false)
	app.player.enabled = false
	app.player.seated = false
	for _i in 30:
				await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/stairview/stair-view.png")
	quit()
