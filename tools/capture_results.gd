extends SceneTree
## The result page and the nine grade pictures (needs a display): godot --path . --script res://tools/capture_results.gd
## Output: build/previews/results/. Sample records (not played): the page for B, and the grade picture of each grade.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/results/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://results-preview/unused.json")
	app.settings = GameSettings.new("user://results-preview/settings.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/results")
	var m := ScoreRules.sample_meta("B", "car", "easy")
	m["routeName"] = "《闸门》"
	m["score"]["items"].append({"cat": "应对 · 异象", "text": "化解「下不完的雨」", "pts": 40, "n": 1})
	m["score"]["items"].append({"cat": "校规与巡察", "text": "学生会检查 · 在教室", "pts": 20, "n": 2})
	app.ui.show_results(m, {"silent": true, "reduce": true})
	await _shot("page-B")
	for g in ["F", "E", "D", "C", "A", "S", "SS", "SSS"]:
		app.ui.show_results(ScoreRules.sample_meta(g, "car"), {"silent": true, "reduce": true})
		await _shot("grade-" + g)
	quit()
