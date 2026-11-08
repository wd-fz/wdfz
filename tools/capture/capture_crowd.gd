extends SceneTree
## Native captures of the actual reopened cabin and 4.2 s death scene.
const APP := preload("res://game/app/app.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/crowd/%s.png" % name)


func _run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/crowd")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-crowd/save.json")
	app.settings=GameSettings.new("user://capture-crowd/settings.json")
	root.add_child(app)
	await process_frame
	app.start_new_game("hard","code")
	app.set_physics_process(false)
	app._stand_up()
	var lift := app.elevator()
	var r := CampusData.layout("teach2")
	var s := CampusGeometry.to_scene(r,lift.world("teach2",-1.225,0))
	var out: Vector2=lift.frame("teach2")["out"]
	app.travel("teach2",{"position":[s.x,.01,s.y],"yaw":CampusGeometry.yaw_from_ang(atan2(out.y,out.x)),"pitch":.25},false)
	app.player.enabled=false
	app.player.set_physics_process(false)
	app.player.update_view(1)
	lift.lifts["teach"].merge({"floor":2,"target":2,"phase":"idle","door":0.0,"dir":0,"hold":0.0},true)
	lift.ride={"host":"teach","origin":2,"target":2,"phase":"cabin","rare":false,"remaining":0.0,"pending":null,"crowd":1}
	lift.press(5,"teach2",app.player.capture_pose())
	for i in 10:
		lift.step(.1,"teach2",app.player.capture_pose())
		app._lift_crowd_step(.1)
	app._campus_world().apply_lift_doors(lift)
	var lighting := app._campus_world().lighting
	lighting.crowd_state=app.lift_crowd().state
	lighting.update(0,760,app.player.camera)
	app.ui.scene_post().parameter("exposure",lighting.post_exposure)
	await _shot("满员-重新开门")
	app._lift_crowd_fx.clear()
	app.player.set_pitch(0)
	app._start_death_cg("crowd")
	for frame: Array in [[.4,"满员-门关闭"],[2.4,"满员-楼层跳动"],[3.9,"满员-学生证"]]:
		app._death_cg.update(frame[0])
		await _shot(frame[1])
	app._stop_death_cg()
	app.queue_free()
	await process_frame
	quit()
