extends SceneTree
## The midnight gallery (needs a display): godot --path . --script res://tools/capture/capture_gallery.gd
## Output: build/previews/gallery/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://gallerypreview/save.json")
	app.settings = GameSettings.new("user://gallerypreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/gallery")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["teach3"]
	var sc := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + 30.5 * float(room["tw"]), float(room["oy"]) + (float(room["rows"]) - 2.5) * float(room["th"])))
	app.travel("teach3", {"position": [sc.x, 6.45, sc.y], "yaw": PI, "pitch": -0.05}, false)
	app.player.enabled = false
	app.player.seated = false
	for _i in 30:
				await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/gallery/gallery.png")
	quit()
