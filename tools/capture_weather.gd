extends SceneTree
## The smile (both kinds), the far figure and the hallucination (needs a display): godot --path . --script res://tools/capture_phantoms.gd
## Output: build/previews/weather/.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/weather/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://weatherprev/save.json")
	app.settings = GameSettings.new("user://weatherprev/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/weather")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	app.player.enabled = false
	app.set_physics_process(false)
	var world := app._campus_world()
	var cam := app.player.camera.global_position
	var rain := WeatherFx.new()
	world.add_child(rain)
	rain.setup_rain(Vector3(cam.x, 0.0, cam.z))
	for _i in 160:
		rain.update_rain(0.05, cam, 0.0)
	await _shot("rain")
	rain.queue_free()
	var swarm := WeatherFx.new()
	world.add_child(swarm)
	swarm.setup_moths(Vector3(cam.x - 3.0, 0.0, cam.z))
	for _i in 120:
		swarm.update_moths(0.05, cam, 4.0, false)
	await _shot("moths")
	quit()
