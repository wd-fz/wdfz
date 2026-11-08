extends SceneTree
## The phone shell, the paper plane and the camera (needs a display): godot --path . --script res://tools/capture_phone.gd
## Output: build/previews/phone/.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/phone/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://phone-preview/unused.json")
	app.settings = GameSettings.new("user://phone-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	app.items().add("phone")
	DirAccess.make_dir_recursive_absolute("res://build/previews/phone")
	app._open_phone()
	await _shot("home")
	app._phone_select("wireless")
	await _shot("wireless")
	app._phone_select("plane")
	app.phone().plane.flap()
	for _i in 50:
		app._phone_shell_step(0.02)
		if _i % 9 == 0:
			app.phone().plane.flap()
	await _shot("plane")
	app._phone_select("camera")
	await app._shoot()
	await app._shoot()
	await _shot("camera")
	print("photos: ", app.camera().photos.size(), " img bytes ", String(app.camera().photos[0]["img"]).length())
	quit()
