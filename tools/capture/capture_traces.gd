extends SceneTree
## What anomalies leave on the floor (needs a display): godot --path . --script res://tools/capture/capture_traces.gd
## Output: build/previews/traces/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://tracespreview/save.json")
	app.settings = GameSettings.new("user://tracespreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/traces")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	var room: Dictionary = CampusData.rooms()["teach1"]
	var p: Array = app.player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	app.player.enabled = false
	app.player.rotation.y = PI / 2.0
	app.player.camera.rotation.x = -0.45
	app.anomaly().traces = [{"k": "puddle", "x": w.x - 45.0, "y": w.y, "room": "teach1"}, {"k": "moths", "x": w.x - 30.0, "y": w.y + 14.0, "room": "teach1"},
		{"k": "feet", "x": w.x - 20.0, "y": w.y - 10.0, "a": PI, "room": "teach1"}, {"k": "paper", "x": w.x - 36.0, "y": w.y - 14.0, "room": "teach1"}]
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/traces/leftovers.png")
	quit()
