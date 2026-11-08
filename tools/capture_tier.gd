extends SceneTree
## The midnight tier (needs a display): godot --path . --script res://tools/capture_tier.gd
## Output: build/previews/tier/.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://tierpreview/save.json")
	app.settings = GameSettings.new("user://tierpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/tier")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	CampusData.tier = 0
	var room: Dictionary = CampusData.rooms()["teach1"]
	var sc := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + 48.8 * float(room["tw"]), float(room["oy"]) + 11.4 * float(room["th"])))
	app.travel("teach1", {"position": [sc.x, 0.05, sc.y], "yaw": PI / 2.0, "pitch": 0.0}, false)
	print("PATH ", CampusData.scene_path("teach1"))
	app.player.enabled = false
	app.player.seated = false
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/tier/tier0.png")
	quit()
