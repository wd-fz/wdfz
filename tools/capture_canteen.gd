extends SceneTree
## The midnight canteen (needs a display): godot --path . --script res://tools/capture_canteen.gd
## Output: build/previews/canteen/.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://canteenpreview/save.json")
	app.settings = GameSettings.new("user://canteenpreview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/canteen")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var room: Dictionary = CampusData.rooms()["canteen1"]
	var ly := CanteenView.layout(room)
	var lamp: Vector2 = ly["lamp"]
	var stand := lamp + Vector2(0, 5.0 * float(room["th"]))
	var sc := CampusGeometry.to_scene(room, stand)
	app.school().tsec = 1350.0
	app.travel("canteen1", {"position": [sc.x, 0.05, sc.y], "yaw": 0.0, "pitch": 0.1}, false)
	app.player.enabled = false
	app.player.seated = false
	for _i in 30:
		app.school().tsec = 1350.0
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/canteen/midnight-canteen.png")
	quit()
