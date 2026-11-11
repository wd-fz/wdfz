extends SceneTree
## Real gameplay worlds, live death effects. No standalone death sets.
## godot --path . --script res://tools/capture/capture_death_onsite.gd
## Output: build/previews/death-onsite/<world>-<cause>-<phase>.png


func _initialize() -> void:
	call_deferred("_run")


func _frames(n: int = 4) -> void:
	for _i in n: await process_frame


func _shot(name: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/death-onsite/"+name+".png")


func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/death-onsite")
	var app: GameApp = preload("res://game/app/app.tscn").instantiate()
	app.saves = SaveStore.new("user://death-onsite-capture/unused.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	app.settings.set_value("quality",0)
	app.settings.save_file()
	root.add_child(app)
	await _frames()
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	await _frames(8)
	app._stand_up()
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.ui.cut_mode(true)
	for sample: Array in [["teach1","patrol"],["teach1","drown"],["teach1","san"],["garage1","garage"],["out","swarm"],["out","neck"]]:
		var world_id := String(sample[0])
		var cause := String(sample[1])
		if app.session.world_id != world_id:
			var pose: Dictionary
			if world_id=="out":
				var at := CampusGeometry.to_scene(null,Vector2(1077.5,2060))
				pose = {"position":[at.x,.05,at.y],"yaw":CampusGeometry.yaw_from_ang(-PI*.5),"pitch":0.0}
			else: pose = app.campus().default_spawn(world_id)
			var why := app.travel(world_id,pose,false)
			if not why.is_empty(): push_error(why); quit(1); return
		app.player.enabled = false
		app.player.set_physics_process(false)
		app.player.set_pitch(0)
		app.ui.cut_mode(true)
		await _frames(6)
		var world := app._campus_world()
		# The simulation is frozen. Initialise each new world's real lighting as
		# the HUD tick normally does, instead of capturing its uninitialised fog.
		world.update_lighting(.2,app.school().tsec,app.player.camera)
		var position := app.player.global_position
		var ahead := position-app.player.camera.global_basis.z*1.4
		if cause=="patrol": world.show_patrol(true,Vector2(ahead.x,ahead.z),position.y,position)
		if cause=="garage": world.show_garage_shadow(true,Vector2(ahead.x,ahead.z),position.y)
		await _shot(world_id+"-"+cause+"-before")
		app._start_death_cg(cause)
		for phase: float in [.25,.58,.78]:
			app._death_cg.update(app._death_cg.dur*phase)
			await _shot(world_id+"-"+cause+"-"+str(roundi(phase*100)))
		app._stop_death_cg()
		world.show_patrol(false,Vector2.ZERO,0,Vector3.ZERO)
		world.show_garage_shadow(false,Vector2.ZERO,0)
		await _frames()
		print("ONSITE CAPTURED: "+world_id+" / "+cause)
	app.return_to_menu()
	app.queue_free()
	await _frames()
	CampusData.clear_caches()
	quit()
