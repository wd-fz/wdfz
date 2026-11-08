extends SceneTree
## The death scenes by cause (needs a display): godot --path . --script res://tools/capture_death.gd [-- grip neck ...]
## Output: build/previews/deathcg/<cause>-<n>.png, frames at 25 / 55 / 85 % of the scene.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/deathcg/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://deathcg/save.json")
	app.settings = GameSettings.new("user://deathcg/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/deathcg")
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	app.player.enabled = false
	var which: Array = OS.get_cmdline_user_args() if not OS.get_cmdline_user_args().is_empty() else DeathCG.CAUSES
	for cause: String in which:
		app._start_death_cg(cause)
		var cg: DeathCG = app._death_cg
		cg.set_process(false)
		var n := 0
		for frac: float in [0.25, 0.55, 0.85]:
			n += 1
			cg.k = cg.dur * frac
			cg.update(cg.k)
			await _shot("%s-%d" % [cause, n])
		app._stop_death_cg()
		for _i in 3:
			await process_frame
	quit()
