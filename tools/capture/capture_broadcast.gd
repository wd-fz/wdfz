extends SceneTree
## Broadcast / dismissal previews (needs a display): godot --path . --script res://tools/capture/capture_broadcast.gd
## Output: build/previews/broadcast/. State and positions are injected.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String, frames: int = 30) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/broadcast/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://broadcast-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/broadcast")
	app.patrol().pat["safety"] = 999.0
	var a2 := CampusData.layout("admin2")
	var st := Vector2(float(a2["ox"]) + 5.5 * float(a2["tw"]), float(a2["oy"]) + 5.5 * float(a2["th"]))
	var s := CampusGeometry.to_scene(a2, st)
	app.travel("admin2", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": -0.2}, false)
	app._campus_interact()
	await _shot("1-station-menu")
	app._choice_made(4)
	var radio := app.broadcast()
	radio.b["book"] = true
	radio.b["fuse"] = true
	radio.b["completed"] = 4
	radio.b["phase"] = "bell"
	radio.b["bell"] = 30.0
	app.school().day = 2
	app.school().tsec = 1100.0
	var gates: Dictionary = CampusData.campus()["gates"]
	var p := radio.crowd()
	var behind := Vector2(float(p["x"]), float(p["y"])) - Vector2(cos(float(p["angle"])), sin(float(p["angle"]))) * 60.0
	var b := CampusGeometry.to_scene(null, behind)
	app.travel("out", {"position": [b.x, 0.05, b.y], "yaw": CampusGeometry.yaw_from_ang(float(p["angle"])), "pitch": 0.0}, false)
	await _shot("2-dismissal-crowd", 4)
	quit()
