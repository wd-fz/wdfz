extends SceneTree
## Actual dorm pickup -> sleep -> persistent top -> pit -> ending; no mock scene.
const APP:=preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/inception/%s.png" % name)


func _pose(id: String, cell: Vector2, ang: float, pitch: float = 0) -> Dictionary:
	var room:=CampusData.layout(id)
	var p:=CampusGeometry.to_scene(room,Vector2(room["ox"]+(cell.x+.5)*room["tw"],room["oy"]+(cell.y+.5)*room["th"]))
	return {"position":[p.x,0,p.y],"yaw":CampusGeometry.yaw_from_ang(ang),"pitch":pitch}


func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/inception")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-inception/save.json")
	app.settings=GameSettings.new("user://capture-inception/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.school().tsec=755
	app.travel("dorm2",_pose("dorm2",Vector2(6.1,3),PI,-.55),false)
	app._school_step(0,app.campus())
	app.ui.show_runtime(app.session.clock.active_seconds)
	app.ui.show_notice("")
	app.ui.show_prompt(app.inception_flow.hint())
	await _shot("盗梦空间-宿舍陀螺")
	app._campus_interact()
	app.inception().roll=func() -> float: return .01
	app.inception_flow.rest("sleep")
	app.inception_flow.fade.advance(.48)
	app.player.restore_pose(_pose("dream_top",Vector2(8,3),0,-.4))
	app._school_step(0,app.campus())
	app.ui.show_runtime(app.session.clock.active_seconds)
	app.ui.show_notice("")
	await _shot("盗梦空间-黑坑边缘")
	app._use_item("top")
	await _shot("盗梦空间-确认梦境")
	app.player.restore_pose(_pose("dream_top",Vector2(9,3),0,-.4))
	app.inception_flow.step(.01)
	app.inception_flow.step(1.4)
	app._ending_cut.set_process(false)
	for f: Array in [[1.5,"盗梦空间-坠落"],[6.0,"盗梦空间-课桌"],[12.0,"盗梦空间-醒来"],[17.0,"盗梦空间-仍在旋转"]]:
		app._ending_cut._apply(float(f[0])/20)
		await _shot(f[1])
	app._ending_cut.end(true)
	await _shot("盗梦空间-结局")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
