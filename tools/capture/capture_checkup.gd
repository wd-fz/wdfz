extends SceneTree
## Original medical props through the real campus view, maintained landscape, isolated profile.
const APP := preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/checkup")
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://checkup-capture-%d/slot.json" % Time.get_ticks_usec())
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	var room := CampusData.layout("admin1")
	var helper := preload("res://tests/support/test_suite.gd").new(self)
	for spec: Array in [["身高尺与秤",4.0,15.45,PI,-.28],["原版视力表",6.9,15.45,0,0],["医务室门牌",7.0,18.5,-PI/2,0]]:
		var position := Vector2(room["ox"]+float(spec[1])*room["tw"],room["oy"]+float(spec[2])*room["th"])
		var pose := helper._campus_pose(room,position,spec[3])
		pose["pitch"] = spec[4]
		app.travel("admin1",pose,false)
		app.player.camera.position.y = CameraMotion.EYE
		app._campus_world().show_checkup(true,false,CheckupProps.LINES[0])
		app.ui.show_notice("")
		app.ui.show_status("行政楼 1F","体检 · 行政楼一楼医务室","","")
		app._campus_world().lighting.update(0,630,app.player.camera)
		app.ui.scene_post().parameter("exposure",app._campus_world().lighting.post_exposure)
		for _i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/previews/checkup/"+spec[0]+".png")
	app.return_to_menu()
	app.queue_free()
	for _i in 3: await process_frame
	quit()
