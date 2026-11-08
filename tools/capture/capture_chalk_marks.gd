extends SceneTree
## The chalk textures and marks in a room (needs a display): godot --path . --script res://tools/capture/capture_chalk_marks.gd
## Output: build/previews/chalkmarks/. A sheet of the eight symbols, and marks on a wall and floor.

const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://build/previews/chalkmarks")
	var sheet := Image.create(128 * 4, 128 * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.14, 0.15, 0.17, 1))
	var i := 0
	for sym: String in ChalkTexture.SYMBOLS:
		var img := ChalkTexture.image(sym)
		sheet.blend_rect(img, Rect2i(0, 0, 128, 128), Vector2i((i % 4) * 128, (i / 4) * 128))
		i += 1
	sheet.save_png("res://build/previews/chalkmarks/symbols.png")
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://chalkmarks/save.json")
	app.settings = GameSettings.new("user://chalkmarks/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game("easy")
	for _i in 10:
		await process_frame
	app._stand_up()
	var mk := app.marks()
	var room: Dictionary = CampusData.rooms()["teach1"]
	var p: Array = app.player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var n := 0
	for sym: String in ["x", "up", "o", "tri"]:
		n += 1
		mk.marks.append({"room": "teach1", "x": w.x - 30.0 - n * 2.0, "y": w.y - 18.0 + n * 9.0, "h": 1.3, "face": "wall", "a": 0.0, "s": sym, "n": n})
	for sym: String in ["q", "bar", "left"]:
		n += 1
		mk.marks.append({"room": "teach1", "x": w.x - 12.0, "y": w.y - 10.0 + n * 5.0, "h": 0.0, "face": "floor", "a": PI, "s": sym, "n": n})
	mk.serial += 1
	app.player.enabled = false
	app.player.rotation.y = PI / 2.0
	app.player.camera.rotation.x = -0.35
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/chalkmarks/marks.png")
	quit()
