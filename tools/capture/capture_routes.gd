extends SceneTree
## Route/ending previews (needs a display): godot --path . --script res://tools/capture/capture_routes.gd
## Output: build/previews/routes/. Positions and state are injected; the route rules are covered by the tests.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/routes/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://routes-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/routes")
	var gate := CampusGeometry.to_scene(null, Vector2(401, 1250))
	app.travel("out", {"position": [gate.x, 0.05, gate.y], "yaw": 0.0, "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	var rt := app.routes()
	rt.hacked = true
	rt.data_synced = true
	await _shot("1-west-gate-hint")
	app._campus_interact()
	await _shot("2-quiz-question")
	for _n in 3:
		var q: Dictionary = RoutesModule.QUESTIONS[rt.face_quiz["order"][int(rt.face_quiz["done"])]]
		app._choice_made(int(q["answer"]))
	await _shot("3-green-light")
	app._choice_made(0)
	await _shot("4-ending-card")
	quit()
