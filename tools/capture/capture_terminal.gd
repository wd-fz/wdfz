extends SceneTree
## Lab3 terminal preview (needs a display): godot --path . --script res://tools/capture/capture_terminal.gd
## Output: build/previews/terminal/. The phone state is injected; the commands are typed through the UI signal.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://terminal-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/terminal")
	app.patrol().pat["safety"] = 999.0
	app.items().add("phone")
	var net := app.phone()
	net.set_context(app._phone_context())
	net.acquire()
	net.device["network"] = true
	net.device["wireless"] = {"status": "complete", "elapsed": 200.0, "target": 200.0}
	net.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	var lab := CampusData.layout("lab3")
	var s := CampusGeometry.to_scene(lab, Vector2(float(lab["cx"]), float(lab["cy"])))
	app.travel("lab3", {"position": [s.x, 0.05, s.y], "yaw": 0.0, "pitch": 0.0}, false)
	for _i in 5:
		await process_frame
	net.set_context(app._phone_context())
	var here := Vector2(float(net._c["x"]), float(net._c["y"]))
	net.open_terminal(here.x, here.y)
	app._apply_phone_events()
	for line: String in ["cat /school/site.txt", "cat /school/assets.tsv | grep controller", "campusctl hint 1"]:
		app.ui.terminal_command.emit(line)
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/terminal/1-lab3-terminal.png")
	quit()
