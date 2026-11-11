extends "res://tests/support/test_suite.gd"


func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = position
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh


func _collider(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _frame(cg: DeathCG) -> Array:
	var result: Array = [cg.cam.transform,cg.cam.fov]
	for node in cg.F.find_children("*","Node3D",true,false): result.append([node.transform,node.visible])
	return result


func _same_frame(a: Array, b: Array) -> bool:
	if a.size()!=b.size() or not a[0].is_equal_approx(b[0]) or not is_equal_approx(a[1],b[1]): return false
	for i in range(2,a.size()):
		if not a[i][0].is_equal_approx(b[i][0]) or a[i][1]!=b[i][1]: return false
	return true


func test_modes_and_geometry() -> void:
	var original_size := root.size
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	ui.set_mode("play")
	var stage_root := Node3D.new()
	root.add_child(stage_root)
	var world := Node3D.new()
	stage_root.add_child(world)
	var floor := _box(world,Vector3(0,-.08,0),Vector3(10,.1,10),Color("647661"))
	_box(world,Vector3(0,1.5,-2.4),Vector3(8,3,.1),Color("7e8d9a"))
	_collider(world,Vector3(0,-.08,0),Vector3(10,.1,10))
	_collider(world,Vector3(0,1.5,-2.4),Vector3(8,3,.1))
	var witness := _box(world,Vector3(.8,.6,-1),Vector3(.4,1.2,.4),Color("b28858"))
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	stage_root.add_child(player)
	player.enabled = false
	player.set_physics_process(false)
	await _frames(3)
	for seated: bool in [false,true]:
		root.size = Vector2i(1920,800) if not seated else Vector2i(844,390)
		world.position.y = 8 if seated else 0
		player.position = Vector3(0,world.position.y,0)
		player.set_pitch(-.9 if seated else .2)
		player.camera.position.y = 1.02 if seated else 1.65
		await _frames(3)
		var initial := player.camera.transform
		var optics := Vector2(player.camera.fov,player.camera.near)
		var pose := player.capture_pose()
		var original_count := world.get_child_count()
		for id: String in DeathCG.CAUSES:
			var cg := DeathCG.new()
			stage_root.add_child(cg)
			var sounds: Array[String] = []
			cg.sound_output = func(sound: String,_options: Dictionary) -> void: sounds.append(sound)
			cg.begin_live(id,player,world,ui,DeathCG.duration(id,0),seated)
			var onsite := id not in ["crowd","void","abyss"]
			check(DeathSceneCatalog.uses_live_world(id)==onsite and cg.live_scene and ((cg.shots is DeathInPlace)==onsite), "live entry selects the explicit site/space policy: "+id)
			for fraction: float in [0.0,.22,.58,.8]:
				cg.update(cg.dur*fraction)
				if onsite:
					check(world.visible and cg._sky==null, "ordinary death preserves its real world throughout the contact beat: "+id)
					check(world.get_child_count()==original_count and witness.visible and floor.visible, "ordinary death does not replace world geometry: "+id)
			cg.update(cg.dur*.58)
			var first := _frame(cg)
			cg.update(cg.dur*.3)
			cg.update(cg.dur*.58)
			check(_same_frame(first,_frame(cg)) and same_json(pose,player.capture_pose()), "onsite seeking leaves deterministic visuals and unchanged player state: "+id)
			if onsite:
				check(cg.shots.clearance>0 and cg.shots.clearance<=2.4, "nearby geometry bounds the effect's physical size: "+id)
				check(cg._cued.size()==sounds.size(), "onsite sound cues fire once when scrubbing: "+id)
				var focus: Vector3 = cg.shots.focus.global_position
				check(not player.camera.is_position_behind(focus) and root.get_visible_rect().has_point(player.camera.unproject_position(focus)), "onsite cue stays visible for sitting, pitch and upper floors: "+id)
				if seated: check(is_equal_approx(player.camera.fov,optics.x) and player.camera.transform.basis.is_equal_approx(initial.basis), "reduced camera effects preserve the captured look: "+id)
			else:
				check(not world.visible and cg._sky!=null, "only an explicit impossible-space death replaces the world: "+id)
			cg.finish()
			check(world.visible and cg.F==null and player.camera.transform.is_equal_approx(initial) and is_equal_approx(player.camera.near,optics.y), "live death restores camera and temporary nodes: "+id)
			cg.queue_free()
			await _frames(1)
	# Tight head space must shrink just the effects, not the scene or the player.
	world.position.y = 0
	player.position = Vector3.ZERO
	player.set_pitch(0)
	player.camera.position.y = 1.65
	var wall := _collider(world,Vector3(0,1.65,-.38),Vector3(3,3,.04))
	await _frames(3)
	var close := DeathCG.new()
	stage_root.add_child(close)
	close.begin_live("patrol",player,world,ui,4.8)
	check(close.shots.clearance<.3 and world.visible, "a nearby wall constrains props without hiding the wall")
	close.finish()
	close.queue_free()
	wall.queue_free()
	stage_root.queue_free()
	ui.queue_free()
	await _frames(3)
	root.size = original_size


func test_borrowed_visuals() -> void:
	var original_size := root.size
	root.size = Vector2i(960,540)
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/onsite/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	app.settings.set_value("quality",0)
	app.settings.save_file()
	root.add_child(app)
	await _frames(3)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	await _frames(3)
	var world := app._campus_world()
	var player := app.player
	var pose := player.capture_pose()
	var transform := player.camera.transform
	var feet := player.position
	world.show_patrol(true,Vector2(feet.x-.7,feet.z),feet.y,player.global_position)
	world.show_garage_shadow(true,Vector2(feet.x+.7,feet.z),feet.y)
	for id: String in ["patrol","garage"]:
		var actor := world._patrol_figure if id=="patrol" else world._garage_shadow
		var initial := actor.transform
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin_live(id,player,world,app.ui,4.8)
		cg.update(3)
		check(world.visible and cg.shots._attacker==actor and not cg.shots.p.has("visitor") and not cg.shots.p.has("shadow"), "live attack reuses the actual scene actor without spawning a duplicate: "+id)
		var contact := actor.transform
		var contact_camera := player.camera.transform
		cg.update(1)
		cg.update(3)
		check(actor.transform.is_equal_approx(contact) and player.camera.transform.is_equal_approx(contact_camera), "borrowed actor and camera seeking are deterministic, including blocked approaches: "+id)
		cg.finish()
		check(actor.transform.is_equal_approx(initial) and actor.visible and same_json(pose,player.capture_pose()) and player.camera.transform.is_equal_approx(transform), "borrowed actor, camera and gameplay pose are restored: "+id)
		cg.begin_live(id,player,world,app.ui,4.8,true)
		cg.update(3)
		check(player.camera.transform.is_equal_approx(transform), "reduced effects keep the original camera even beside a real attacker: "+id)
		cg.finish()
		cg.queue_free()
		await _frames(2)
	world.show_patrol(false,Vector2.ZERO,0,Vector3.ZERO)
	world.show_garage_shadow(false,Vector2.ZERO,0)
	var mates := ClassmatesView.new()
	world.add_child(mates)
	var person := Node3D.new()
	person.position = player.position+Vector3(0,0,-1)
	mates.add_child(person)
	mates.figures = [{"node":person}]
	var cg := DeathCG.new()
	app.add_child(cg)
	cg.begin_live("san",player,world,app.ui,5)
	cg.update(4)
	check(not person.visible and world.visible, "SAN erasure affects actual classmates while leaving the classroom visible")
	cg.queue_free()
	await _frames(3)
	check(person.visible, "freeing a live death restores borrowed classmate visibility")
	var gaze := WindowGazeView.new()
	world.add_child(gaze)
	gaze.build(1)
	gaze.position = player.position+Vector3(0,0,-1)
	var gaze_transform := gaze.transform
	cg = DeathCG.new()
	app.add_child(cg)
	cg.begin_live("window_gaze",player,world,app.ui,5.2)
	cg.update(3)
	check(cg.shots._gaze==gaze and not cg.shots.p.has("head") and gaze.transform==gaze_transform, "the real window figure remains on its original side of the glass")
	cg.finish()
	cg.begin("patrol",player,world,app.ui,4.8)
	check(not cg.live_scene and not world.visible and not cg.shots is DeathInPlace, "reusing a live instance for a replay restores isolated presentation mode")
	cg.finish()
	cg.queue_free()
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	root.size = original_size
	CampusData.clear_caches()
