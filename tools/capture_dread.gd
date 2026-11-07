extends SceneTree
## A revisit's note on the floor (needs a display): godot --path . --script res://tools/capture_dread.gd
## Output: build/previews/dread/. Picks a day whose second visit to teach1 leaves a note.

const APP := preload("res://scenes/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://dread-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	var day := 1
	while DreadModule.VISIT_KINDS[floori(DreadModule.lhash("%d:teach1:2" % day) * 4.0)] != "note":
		day += 1
	app.school().day = day
	app.dread().visits = {}
	var t1 := CampusData.layout("teach1")
	var s := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 46, 9))
	var pose := {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(0.0), "pitch": -1.0}
	app.travel("teach2", app.campus().default_spawn("teach2"), false)
	app.travel("teach1", pose, false)
	app.travel("teach2", app.campus().default_spawn("teach2"), false)
	app.travel("teach1", pose, false)
	# Step up to the note and look down at it.
	var n: Node3D = app._campus_world().get_node("DreadNote")
	var cam_at := n.global_position + Vector3(0.0, 0.0, 0.0)
	app.player.global_position = Vector3(cam_at.x, 0.05, cam_at.z + 0.55)
	app.player.rotation.y = 0.0
	app.player.camera.rotation.x = -1.2
	DirAccess.make_dir_recursive_absolute("res://build/previews/dread")
	for _i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/dread/note.png")
	print("note: ", app._campus_world().dread_note_text())
	quit()
