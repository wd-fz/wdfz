extends SceneTree
## 地面物品与背包界面: dropped items on the classroom floor (day / night), the pick prompt, the bag and the HUD.
## xvfb-run -a godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_ground_items.gd
## Output: build/previews/ground/. SHOTS=floor,night,bag,hud (default: all).
const APP := preload("res://game/app/app.tscn")
var _want: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func shot(label: String) -> void:
	for _i in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/ground/" + label + ".png")


func want(id: String) -> bool:
	return _want.is_empty() or _want.has(id)


func _look(app: GameApp, pose: Dictionary, pitch: float) -> void:
	var p := pose.duplicate(true)
	p["pitch"] = pitch
	app.player.restore_pose(p)


func _run() -> void:
	var env := OS.get_environment("SHOTS")
	if env != "":
		_want = env.split(",")
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/ground")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-ground-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.start_new_game("easy", "none")
	app.ui._end_opening(true)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	app.patrol().pat["next"] = 100000.0
	app.anomaly().an["next"] = 100000.0
	app._setting_changed("quality", 2)
	var bag := app.items()
	for id: String in ["torch", "phone", "watch", "chalk", "pen", "notebook"]:
		bag.add(id)
	bag.take_notices()
	bag.set_hot(0, "torch")
	bag.set_hot(1, "phone")
	var start: Dictionary = app.campus().start_pose()
	app.travel("teach1", start, false)
	app.school().tsec = 700.0
	if want("floor") or want("night"):
		# Drop three things a step apart, then step back and look down at them.
		var yaw := float(start["yaw"])
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		var base := Vector3(start["position"][0], start["position"][1], start["position"][2])
		for spec: Array in [["notebook", 0.9, -0.35], ["pen", 1.05, 0.3], ["chalk", 1.4, 0.0]]:
			var at: Vector3 = base + fwd * float(spec[1]) + side * float(spec[2])
			bag.drop(String(spec[0]))
			bag.place_on_ground(String(spec[0]), "teach1", at)
		bag.take_notices()
		_look(app, start, -0.62)
		await shot("floor-day")
		var near := start.duplicate(true)
		near["position"] = [base.x + fwd.x * 0.75, base.y, base.z + fwd.z * 0.75]
		_look(app, near, -0.95)
		await shot("floor-pick-prompt")
		if want("night"):
			app.school().tsec = 1380.0
			_look(app, start, -0.62)
			await shot("floor-night")
			bag.torch_on = true
			await shot("floor-night-torch")
			bag.torch_on = false
			app.school().tsec = 700.0
		_look(app, start, 0.0)
	if want("hud"):
		await shot("hud")
	if want("bag"):
		app._open_bag()
		await shot("bag")
		var first := app.ui.bag_panel.find_child("Slot_phone", true, false) as Button
		if first != null:
			first.pressed.emit()
			await shot("bag-selected-phone")
		var drop := app.ui.bag_panel.find_child("Drop_phone", true, false) as Button
		if drop != null:
			drop.pressed.emit()
			await shot("bag-drop-confirm")
			app.ui._cancel_drop()
		app._close_bag()
		root.size = Vector2i(960, 540)
		app._open_bag()
		await shot("bag-960x540")
		app._close_bag()
		root.size = Vector2i(1280, 720)
		var empty := bag.bag.duplicate()
		for id: String in empty:
			bag.remove(id)
		app._open_bag()
		await shot("bag-empty")
		app._close_bag()
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
