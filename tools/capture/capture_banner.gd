extends SceneTree
## The anniversary banner (needs a display): godot --path . --script res://tools/capture/capture_banner.gd
## Output: build/previews/banner/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://banner-preview/save.json")
	app.settings = GameSettings.new("user://banner-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/banner")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	var facade := DayBanner.facade(CampusData.layout("out"))
	var eye := facade * Vector3(0, 0.05, 11.82)
	app.travel("out", {"position": [eye.x, eye.y, eye.z], "yaw": facade.basis.get_euler().y, "pitch": 0.45}, false)
	for _i in 20:
		await process_frame
	app._campus_world().banner.set_on(true)
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/banner/banner.png")
	quit()
