extends SceneTree
## The smile (both kinds), the far figure and the hallucination (needs a display): godot --path . --script res://tools/capture/capture_phantoms.gd
## Output: build/previews/phantoms/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/phantoms/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://phantoms/save.json")
	app.settings = GameSettings.new("user://phantoms/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/phantoms")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	app.player.enabled = false
	app.set_physics_process(false)
	var ph: Phantoms = app._campus_world().phantoms
	var cam := app.player.camera.global_position
	var ang := CampusGeometry.ang_from_yaw(app.player.rotation.y)
	ph.show_smile("behind", cam, ang)
	await _shot("smile-behind")
	ph.show_smile("jump", cam, ang)
	ph.tick_smile(0.3, cam)
	await _shot("smile-jump")
	ph.clear_smile()
	var f := ph._figure("person")
	f.position = Vector3(cam.x + cos(ang) * 9.0, 0.0, cam.z + sin(ang) * 9.0)
	f.rotation.y = atan2(f.position.x - cam.x, f.position.z - cam.z)
	f.visible = true
	await _shot("far-figure")
	quit()
