extends "res://tests/support/test_suite.gd"

func test_catalog() -> void:
	var catalogue: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/archive.json"))
	for entry: Dictionary in catalogue.get("deaths",[]):
		var id:=String(entry["id"])
		var scene:=DeathCG.resolve(id,String(entry["fx"]))
		check(DeathCG.has(scene),"recorded death has a source-specific presentation: "+id)
	for id: String in DeathCG.CAUSES:
		check(DeathCG.title(id)!=id and DeathCG.duration(id,0)>=3.6 and DeathCG.duration(id,0)<=6,"named, bounded death shot: "+id)
	check(DeathCG.resolve("patrol","grip")=="patrol" and DeathCG.resolve("garage","grip")=="garage" and DeathCG.resolve("car_entry","grip")=="car_entry" and DeathCG.resolve("car_chase","shatter")=="car_chase","shared gameplay effects no longer collapse distinct deaths into a grip")
	check(DeathCG.resolve("an:moth","grip")=="swarm" and DeathCG.resolve("void_lost","vignette")=="void" and DeathCG.resolve("x.rules.knock","vignette")=="rules_knock","anomaly, maze and DLC records resolve to their live scene")
	check(DeathCG.resolve("extension","vignette")=="vignette" and DeathCG.resolve("extension","unknown")=="","extensions retain the documented fallback")

func _snapshot(cg: DeathCG) -> Array:
	var result: Array=[cg.cam.transform,cg.cam.fov]
	for node: Node in cg.F.find_children("*","Node3D",true,false):
		result.append([node.transform,node.visible])
	return result

func _same_frames(a: Array,b: Array) -> bool:
	if a.size()!=b.size() or not a[0].is_equal_approx(b[0]) or not is_equal_approx(a[1],b[1]): return false
	for i in range(2,a.size()):
		if not a[i][0].is_equal_approx(b[i][0]) or a[i][1]!=b[i][1]: return false
	return true

func test_scenes() -> void:
	var app:=await _app("scenes")
	app._stand_up()
	var saved_size:=root.size
	var player_transform:=app.player.transform
	var camera_transform:=app.player.camera.transform
	var view:=app.player.camera
	var fov:=view.fov
	var near_clip:=view.near
	var sounds: Array[String]=[]
	# Include an upstairs seated player looking down, as well as an ultrawide standing player.
	for seated in [false,true]:
		root.size=Vector2i(1920,800) if not seated else Vector2i(1280,720)
		app.player.position=Vector3(17,12 if seated else 0,-8)
		app.player.rotation.y=.73
		view.position=Vector3(.04,1.03 if seated else 1.65,.02)
		view.rotation=Vector3(-.9 if seated else .3,.04,.035)
		view.fov=82
		view.near=.07
		var initial:=view.transform
		var pose:=app.player.capture_pose()
		for id: String in DeathCG.CAUSES:
			var cg:=DeathCG.new()
			app.add_child(cg)
			sounds.clear()
			cg.sound_output=func(sound: String,_opts: Dictionary) -> void: sounds.append(sound)
			cg.begin(id,app.player,app._campus_world(),app.ui,DeathCG.duration(id,0),seated)
			for fraction: float in [.0,.2,.58,.81]: cg.update(cg.dur*fraction)
			cg.update(cg.dur*.58)
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				check(not root.get_texture().get_image().is_empty(),"real Vulkan frame produced at contact: "+id)
			var first:=_snapshot(cg)
			cg.update(cg.dur*.3)
			cg.update(cg.dur*.58)
			check(_same_frames(first,_snapshot(cg)),"seeking does not accumulate camera or prop motion: "+id)
			check(same_json(pose,app.player.capture_pose()),"cinematic never writes gameplay pose: "+id)
			if cg.shots!=null:
				check(cg.shots.root.position.is_equal_approx(cg.F.to_local(app.player.global_transform*initial.origin)),"set follows captured eye, including sitting and upper floors: "+id)
				var point:=cg.shots.focus.global_position
				var screen:=view.unproject_position(point)
				var rectangle:=view.get_viewport().get_visible_rect()
				check(not view.is_position_behind(point) and rectangle.has_point(screen),"key subject stays in frame at contact: "+id+" "+str(screen))
				if id=="bell":
					var mesh: MeshInstance3D=cg.shots.p["bell_model"].find_children("*","MeshInstance3D",true,false)[0]
					var center: Vector3=mesh.global_transform*mesh.mesh.get_aabb().get_center()
					check(not view.is_position_behind(center) and rectangle.has_point(view.unproject_position(center)),"imported bell geometry itself is on camera despite its baked height offset")
				check(not cg.d.has("hands") and not cg.d.has("feet"),"modern scene has no generic floor hand rig: "+id)
				check(cg._cued.has("contact") and cg._cued.size()==sounds.size(),"cinematic sound cues fire once even when seeking: "+id)
				if seated: check(is_zero_approx(view.rotation.z) and is_equal_approx(view.fov,82) and not app.ui._cut_flash.visible,"reduced effects disable shake, zoom pulses and flashes: "+id)
			cg.finish()
			check(view.transform.is_equal_approx(initial) and is_equal_approx(view.fov,82) and is_equal_approx(view.near,.07),"complete camera transform and optics restored: "+id)
			check(app._campus_world().visible and cg.F==null,"stage and hidden world released: "+id)
			cg.queue_free()
			await _frames()
	view.transform=camera_transform
	view.fov=fov
	view.near=near_clip
	app.player.transform=player_transform
	root.size=saved_size
	# Both restart and exit-tree cleanup must restore a world that was already hidden.
	app._campus_world().hide()
	var restart:=DeathCG.new()
	app.add_child(restart)
	restart.begin("patrol",app.player,app._campus_world(),app.ui,4.8)
	restart.update(3)
	restart.begin("garage",app.player,app._campus_world(),app.ui,4.8)
	check(restart._cued.is_empty() and restart.shots.layout=="garage","restarting resets cues and scene ownership")
	restart.update(3)
	restart.queue_free()
	await _frames(2)
	check(view.transform.is_equal_approx(camera_transform) and not app._campus_world().visible,"freeing an active stage restores the original camera and hidden-world state")
	app._campus_world().show()
	await _dispose(app)

func test_live() -> void:
	var app:=await _app("live")
	var initial_mouse:=Input.mouse_mode
	for mode: int in [Input.MOUSE_MODE_CAPTURED,Input.MOUSE_MODE_VISIBLE]:
		Input.mouse_mode=mode
		var previous:=Input.mouse_mode
		var stage:=DeathCG.new()
		app.add_child(stage)
		stage.begin("patrol",app.player,app._campus_world(),app.ui,4.8)
		stage.offer_skip(func() -> void: pass)
		check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"live controls release the cursor temporarily")
		stage.finish()
		check(Input.mouse_mode==previous and stage._skip_layer==null,"closing live controls restores previous capture state")
		stage.queue_free()
		await _frames()
	Input.mouse_mode=initial_mouse
	for pair: Array in [["patrol","grip"],["garage","grip"],["car_entry","grip"],["assimilation","vignette"],["an:moth","swarm"]]:
		var scene:=DeathCG.resolve(pair[0],pair[1])
		app.kill("演出测试",pair[1],pair[0])
		check(app._death_hold==DeathCG.duration(scene,0),"live death duration uses the same catalog on headless and Vulkan: "+pair[0])
		if DisplayServer.get_name()!="headless":
			check(app._death_cg!=null and app._death_cg.fx==scene,"live source chooses the correct scene: "+pair[0])
			var cg:=app._death_cg
			check(cg._skip_button!=null and not cg._skip_button.visible,"touch skip waits for the initial beat")
			app._death_step(.61)
			check(cg._skip_button.visible and cg._skip_button.size.y>=44,"live touch skip is visible and large enough")
			await _tap(cg._skip_button)
			check(app._death_phase=="card" and app._death_cg==null,"touch skip releases stage and goes to the death card")
		app.debug_flow.revive()
		check(not app.story().dead and app._death_cg==null and app.player.enabled,"revival cancels presentation and resumes play")
	app.story().diff="easy"
	app.story().wakes=0
	app.school().day=1
	var wake_mouse:=Input.mouse_mode
	app.kill("梦醒演出测试","grip","patrol")
	app._death_step(app._death_hold+.01)
	check(not app.story().dead and app.story().wakes==1 and app.player.enabled,"dream death still returns control to the seated player")
	check(Input.mouse_mode==wake_mouse,"dream wake restores the mouse mode borrowed by the skip controls")
	await _dispose(app)

func _app(label: String) -> GameApp:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/death-redesign/"+label+"/slot.json")
	app.settings=GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	await _frames(2)
	return app

func _dispose(app: GameApp) -> void:
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
