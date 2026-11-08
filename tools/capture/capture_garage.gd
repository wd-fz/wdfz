extends SceneTree
## Garage and drive previews (needs a display): godot --path . --script res://tools/capture/capture_garage.gd
## Output: build/previews/garage/. Positions and the chase state are injected.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String, frames: int = 40) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/garage/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://garage-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/garage")
	var g := CampusData.layout("garage1")
	var me := CampusGeometry.tile_center(g, 54, 13)
	var s := CampusGeometry.to_scene(g, me)
	app.travel("garage1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(PI), "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	app.items().add("torch")
	app.items().torch_on = true
	var cars := app.garage()
	cars.roam["on"] = true
	cars.roam["stage"] = "approach"
	cars.roam["cd"] = 999.0
	cars.roam["x"] = me.x - 55.0
	cars.roam["y"] = me.y
	cars.roam["litAcc"] = -999.0
	await _shot("1-garage-driveway-shadow", 6)
	cars.start_chase()
	app._apply_garage_events()
	var d: Dictionary = cars.chase
	d["distance"] = 98.0
	d["speed"] = 15.0
	d["nextObstacle"] = 2
	d["x"] = 1.6
	await _shot("2-drive-fork-signs", 4)
	quit()
