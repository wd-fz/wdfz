extends SceneTree
## Formal campus previews from the real Godot window (needs a display; under CI use xvfb-run).
## godot --path . --script res://tools/capture_campus.gd
## Output: build/previews/campus/ (disposable). Never touches the gameplay save.

const APP := preload("res://scenes/app.tscn")
const OUT := "res://build/previews/campus"
## [file, world, old world x, old world y, old heading (rad), pitch]
const SHOTS := [
	["01-教学楼1F-开局起身位置.png", "teach1", "start", 0, 0, 0.0],
	["02-教学楼1F-走廊西望.png", "teach1", 1330, 1910, PI, -0.03],
	["03-教学楼1F-南门门槛看出去.png", "teach1", 1122, 1925, PI * 0.5, -0.02],
	["04-室外-教学楼正门.png", "out", 1077.5, 2060, -PI * 0.5, 0.12],
	["05-室外-行政楼与实验楼.png", "out", 1023, 1300, -PI * 0.5, 0.1],
	["06-行政楼1F.png", "admin1", "spawn", 0, 0, -0.05],
	["07-食堂.png", "canteen1", "spawn", 0, 0, -0.05],
	["08-北宿舍1F.png", "dorm1", "spawn", 0, 0, -0.05],
	["09-地下车库.png", "garage1", "spawn", 0, 0, 0.0],
	["10-钟楼.png", "bell1", "spawn", 0, 0, 0.0],
	["11-西楼梯井-一楼平台.png", "stair_teach_w", "xyz", -0.2, -0.6, 0.25],
	["12-连廊二.png", "link2", "spawn", 0, 0, 0.0],
	["13-教学楼1F-电梯厅.png", "teach1", 1023, 1925, PI * 0.5, -0.05],
]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Preview capture needs a rendering display, not --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://campus-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app._stand_up()
	for shot: Array in SHOTS:
		var world := String(shot[1])
		var rules := app.campus()
		var pose: Dictionary
		if shot[2] is String and shot[2] == "start":
			pose = rules.start_pose()
		elif shot[2] is String and shot[2] == "xyz":
			pose = {"position": [float(shot[3]), 0.05, float(shot[4])], "yaw": PI, "pitch": 0.0}
		elif shot[2] is String:
			pose = rules.default_spawn(world)
		else:
			var room: Variant = rules.room(world)
			var p := CampusGeometry.to_scene(room, Vector2(shot[2], shot[3]))
			pose = {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(float(shot[4])), "pitch": 0.0}
		pose["pitch"] = float(shot[5])
		app.travel(world, pose, false)
		app.ui.show_notice("")
		await _save_frame(String(shot[0]))
	app.queue_free()
	paused = false
	await process_frame
	print("Campus previews saved to ", ProjectSettings.globalize_path(OUT))
	quit()


func _save_frame(filename: String) -> void:
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT.path_join(filename))
	if error != OK:
		printerr("Could not capture ", filename, ": ", error_string(error))
		quit(1)
