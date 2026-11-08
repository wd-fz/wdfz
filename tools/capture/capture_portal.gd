extends SceneTree
## Portal route previews (needs a display): godot --path . --script res://tools/capture/capture_portal.gd
## Output: build/previews/portal/. State and positions are injected.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String, frames: int = 40) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/portal/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://portal-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/portal")
	app.patrol().pat["safety"] = 999.0
	var t := CampusData.layout("portal_tunnel")
	var s := CampusGeometry.to_scene(t, Vector2(float(t["ox"]) + 3.5 * float(t["tw"]), float(t["oy"]) + 21.5 * float(t["th"])))
	app.travel("portal_tunnel", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": 0.0}, false)
	await _shot("1-tunnel")
	app.facilities().portal["open"] = true
	var lab := CampusData.layout("lab1")
	var m := CampusGeometry.to_scene(lab, Vector2(float(lab["cx"]), float(lab["cy"])))
	app.travel("lab1", {"position": [m.x, 0.05, m.y], "yaw": 0.0, "pitch": 0.0}, false)
	await _shot("2-lab1-circle-front", 6)
	quit()
