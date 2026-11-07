extends SceneTree
## Menu and achievements previews (needs a display): godot --path . --script res://tools/capture_menu.gd
## Output: build/previews/menu/. The unlocks are injected into a throw-away profile.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for _i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/menu/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://menu-preview/unused.json")
	root.add_child(app)
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://build/previews/menu")
	await _shot("1-main-menu")
	app.start_new_game()
	await process_frame
	for f: Dictionary in [{"kind": "day", "day": 2}, {"kind": "anomaly", "phase": "start", "id": "rain", "public": true},
			{"kind": "anomaly", "phase": "end", "id": "rain", "survived": true, "lethal": true}, {"kind": "inspection", "day": 1, "slot": 0, "compliant": true}]:
		app.fact(f)
	app.return_to_menu()
	app._show_achievements()
	await _shot("2-achievements")
	app.ui.ach_panel.visible = false
	app._pick_talent("easy")
	await _shot("3-talent-pick")
	root.size = Vector2i(720, 1280)
	await _shot("4-talent-pick-portrait")
	root.size = Vector2i(1280, 720)
	app._choice_made(0)
	for _i in 4:
		app.ui._next_opening()
	await _shot("5-opening-page")
	app.ui._end_opening(true)
	DirAccess.remove_absolute(app._profile_path())
	quit()
