extends SceneTree
## The live ending scenes (needs a display): godot --path . --script res://tools/capture/capture_endings.gd
## Output: build/previews/endings/. Frames of the 白名单 scene.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/endings/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://endings-preview/save.json")
	app.settings = GameSettings.new("user://endings-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/endings")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var gate := CampusGeometry.to_scene(null, Vector2(200, 624) * 2.0)
	app.travel("out", {"position": [gate.x - 2.0, 0.05, gate.y], "yaw": 0.0, "pitch": 0.0}, false)
	for _i in 20:
		await process_frame
	app.player.enabled = false
	app._reach_ending("face")
	var cut: EndingCut = app._ending_cut
	cut.set_process(false)
	for spec: Array in [["face-1-red-lamp", 0.1], ["face-2-white-lamp", 0.22], ["face-3-turning", 0.45], ["face-4-crowd", 0.8]]:
		cut.k = float(spec[1])
		cut._apply(cut.k)
		await _shot(String(spec[0]))
	quit()
