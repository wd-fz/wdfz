extends SceneTree
## Death scene styles over the corridor (needs a display): godot --path . --script res://tools/capture_death.gd
## Output: build/previews/death/. The overlay is shown directly at a fixed progress; the death flow itself is covered by the tests.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://death-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/death")
	var t1 := CampusData.layout("teach1")
	var s := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 30, 17))
	app.travel("teach1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(PI), "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	for fx: String in ["vignette", "drown", "swarm", "floor", "grip"]:
		app.ui.show_death_scene(fx, 0.7)
		for _i in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/death/%s.png" % fx)
	quit()
