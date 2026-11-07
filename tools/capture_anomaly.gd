extends SceneTree
## Anomaly lighting previews (needs a display): godot --path . --script res://tools/capture_anomaly.gd
## Output: build/previews/anomaly/. The anomaly is forced on; the schedule itself is covered by the tests.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _force(app: GameApp, id: String) -> void:
	var weird := app.anomaly()
	weird.an["id"] = id
	weird.an["active"] = true
	weird.an["t"] = 0.0
	weird.an["data"] = {}
	weird.an["next"] = 999.0


func _shot(name: String) -> void:
	for _i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/anomaly/%s.png" % name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://anomaly-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	DirAccess.make_dir_recursive_absolute("res://build/previews/anomaly")
	var t1 := CampusData.layout("teach1")
	var me := CampusGeometry.tile_center(t1, 30, 17)
	var s := CampusGeometry.to_scene(t1, me)
	app.travel("teach1", {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(PI), "pitch": 0.0}, false)
	app.patrol().pat["safety"] = 999.0
	await _shot("1-corridor-normal")
	_force(app, "blackout")
	await _shot("2-corridor-blackout")
	app.anomaly().end_now()
	var field := Vector2(1000, 1000)
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == "field":
			field = Vector2((float(o["x"]) + float(o["w"]) / 2.0) * 2.0, (float(o["y"]) + float(o["h"]) / 2.0) * 2.0)
	var out := CampusGeometry.to_scene(null, field)
	app.travel("out", {"position": [out.x, 0.05, out.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": 0.1}, false)
	await _shot("3-outside-normal")
	_force(app, "rain")
	app.anomaly().an["data"] = {"cov": false}
	for _i in 200:
		await process_frame
	await _shot("4-outside-rain")
	quit()
