extends SceneTree
## The menu photo (menu-photo.js): the campus at 22:18, shot once and kept as assets/ui/menu_photo.jpg.
## godot --path . --script res://tools/capture/capture_menu_photo.gd  (needs a display)

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://menuphoto/save.json")
	app.settings = GameSettings.new("user://menuphoto/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app.school().tsec = 1338.0
	var spot := DayBanner.spot(CampusData.layout("out"))
	app.travel("out", {"position": [spot.x - 10.0, 1.2, spot.z + 22.0], "yaw": 0.35, "pitch": 0.12}, false)
	app.player.enabled = false
	for _i in 60:
		app.school().tsec = 1338.0
		await process_frame
	app.ui.get_node("Root").visible = false
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg("res://assets/ui/menu_photo.jpg", 0.85)
	quit()
