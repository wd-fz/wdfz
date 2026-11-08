extends SceneTree
## The lab computer's snake game (needs a display): godot --path . --script res://tools/capture/capture_snake.gd
## Output: build/previews/snake/.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://snake-preview/unused.json")
	app.settings = GameSettings.new("user://snake-preview/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	for _i in 5:
		await process_frame
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/snake")
	app._start_snake()
	var g := app._snake
	g.cd = 0.0
	g.body = [Vector2i(8, 8), Vector2i(7, 8), Vector2i(6, 8), Vector2i(5, 8)]
	g.food = Vector2i(12, 6)
	g.score = 3
	for _i in 8:
		app._snake_step(0.15)
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/snake/snake.png")
	quit()
