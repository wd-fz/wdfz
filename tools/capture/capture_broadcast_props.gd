extends SceneTree
## The broadcast station props (needs a display): godot --path . --script res://tools/capture/capture_broadcast_props.gd
## Output: build/previews/broadcastprops/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://bprops/save.json")
	app.settings = GameSettings.new("user://bprops/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/broadcastprops")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["admin2"]
	var st := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + 5.5 * float(room["tw"]), float(room["oy"]) + 3.5 * float(room["th"])))
	app.travel("admin2", {"position": [st.x, 0.05, st.y + 2.0], "yaw": 0.0, "pitch": 0.0}, false)
	app.player.enabled = false
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/broadcastprops/station.png")
	quit()
