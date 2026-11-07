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


func _back_out(app: GameApp, out: Vector2) -> void:
	if app.session.world_id != "out":
		app.travel("out", {"position": [out.x, 0.05, out.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": 0.1}, false)
	app.patrol().pat["safety"] = 999.0


func _shot(name: String, frames: int = 90) -> void:
	for _i in frames:
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
	# Positional anomalies: forced on with data the rules would have chosen.
	var me_w := Vector2(float(out.x) / CampusGeometry.U2M, float(out.y) / CampusGeometry.U2M)
	var ahead := me_w + Vector2(0, -140)
	_force(app, "exercise")
	app.anomaly().an["data"] = {"scene": "out", "src": {"x": ahead.x, "y": ahead.y}}
	await _shot("5-outside-exercise-crowd", 6)
	app.anomaly().end_now()
	_back_out(app, out)
	_force(app, "rite")
	app.anomaly().an["data"] = {"scene": "out", "c": {"x": ahead.x, "y": ahead.y + 20.0}}
	await _shot("6-outside-rite-circle")
	app.anomaly().end_now()
	_back_out(app, out)
	_force(app, "cola")
	app.anomaly().an["data"] = {"scene": "out", "phase": 1, "warn": 1.6, "tf": 0.0, "lx": me_w.x + 45.0, "ly": me_w.y - 20.0}
	app.anomaly().an["t"] = 1.0
	await _shot("7-outside-cola-falling", 2)
	app.anomaly().end_now()
	_back_out(app, out)
	_force(app, "chalk")
	app.anomaly().an["data"] = {"scene": "out", "until": 800.0}
	await _shot("8-outside-chalk-text")
	app.anomaly().end_now()
	_back_out(app, out)
	_force(app, "rain")
	app.anomaly().an["data"] = {"cov": false}
	await _shot("4-outside-rain", 40)
	quit()
