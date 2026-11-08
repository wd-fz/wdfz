extends SceneTree
## Native DLC screenshots with injected locations/time, using the real interaction path.
const APP:=preload("res://game/app/app.tscn")
func _initialize() -> void: call_deferred("_run")
func _shot(label: String) -> void:
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/rules-dlc/"+label+".png")
func _light(app: GameApp) -> void:
	var world:=app._campus_world()
	if world!=null and world.lighting!=null:
		world.lighting.update(0,app.school().tsec,app.player.camera)
		app.ui.scene_post().parameter("exposure",world.lighting.post_exposure)
	app.ui.show_notice("")
func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute("res://build/previews/rules-dlc")
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new("user://capture-rules-dlc/save.json")
	app.settings=GameSettings.new("user://capture-rules-dlc/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll=func() -> float: return 1
	app.settings.rules_armed=true
	app.rules_dlc_flow.menu()
	await _shot("模式菜单")
	app._choice_made(-1)
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.rules_dlc_flow.set_process(false)
	app._stand_up()
	var flow:=app.rules_dlc_flow
	var spot: Dictionary=flow.module().spots().filter(func(s: Dictionary) -> bool: return s["item"]["id"]=="R03")[0]
	var room:=CampusData.layout(spot["p"]["room"])
	var p:=CampusGeometry.to_scene(room,Vector2(spot["p"]["x"],spot["p"]["y"]))
	app.travel(room["id"],{"position":[p.x,0,p.y+.7],"yaw":0,"pitch":-.6},false)
	flow.show_props()
	app.ui.show_location(app._location_name())
	app.ui.show_runtime(0)
	_light(app)
	flow.interact()
	await _shot("规则载体与批注")
	app._choice_made(1)
	app.travel("dorm1",app.campus().default_spawn("dorm1"),false)
	app.school().tsec=1340
	app.ui.show_location(app._location_name())
	app.ui.show_runtime(0)
	_light(app)
	flow.step(8)
	flow._process(3.6)
	await _shot("第三声敲门")
	app._choice_made(0)
	if app._death_cg==null:
		push_error("DLC choice did not start its death stage")
		quit(1)
		return
	app._death_cg.update(4.7)
	await _shot("门外有你的名字")
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit()
