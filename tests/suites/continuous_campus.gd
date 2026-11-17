extends "res://tests/support/test_suite.gd"


func test_collision() -> void:
	var worlds: Array[CampusWorld] = []
	var space := CampusSpace.new(CampusData.rooms(),CampusData.layout("out"),CampusData.campus())
	var wall := BoxMesh.new()
	wall.size=Vector3(5,10,.2)
	var xf := Transform3D(Basis.IDENTITY,Vector3(0,5,0))
	var floors := ["teach1","teach2","teach3","teach4"]
	var parts := CampusShell._floor_parts(wall,xf,"teach2",{"teach2":floors},space)
	check(parts.size()==4,"a tall facade is cut into four real height bands")
	for id: String in parts:
		var bounds: AABB=xf*(parts[id] as Mesh).get_aabb()
		var y:=space.frame(id).origin.y
		check(bounds.position.y>=y-.001 and bounds.end.y<=y+3.201,"facade "+id+" cannot cover another storey's open doorway")
	for id: String in space.frames:
		var world := CampusWorld.new()
		world.scene_id=id
		world.space=space
		world.resident=true
		world.collision_only=true
		world.transform=space.frame(id)
		worlds.append(world)
		root.add_child(world)
	await _frames(2)
	for stair: Dictionary in space.campus.stair_layout:
		for level in stair.rooms.size():
			var id: String=stair.rooms[level]
			var port:=CampusPortals.stair_port(stair,level,space.rooms,space.outside)
			var p:=CampusGeometry.to_scene(space.rooms.get(id),port.p)
			var a:=space.frame(id)*Vector3(p.x,0,p.y)
			var b:=space.frame(stair.id)*Vector3(0,level*float(stair.rise),-2.8)
			check(a.distance_to(b)<.001,"align "+id+" "+String(stair.id))
			for d: float in [-.7,0,.7,1.4]:
				var point: Vector3=space.frame(stair.id)*Vector3(0,level*float(stair.rise)+.92,-2.8+d)
				free_at(point,"stair "+id+" "+String(stair.id)+" d="+str(d))
	for door: Dictionary in space.campus.campus_doors.doors:
		var port:=CampusGeometry.door_port(space.rooms[door.room],door)
		var p:=CampusGeometry.to_scene(space.rooms[door.room],port.p)
		for d: float in [-1,0,1]:
			var point:=space.frame(door.room)*Vector3(p.x+port.n.x*d,.92,p.y+port.n.y*d)
			free_at(point,"door "+String(door.room)+" "+str(d))
	for id: String in space.frames:
		for link: Dictionary in CampusPortals.link_ports(space.campus.get("campus_link",{}),space.rooms,id):
			var port: Dictionary=link.self
			var p:=CampusGeometry.to_scene(space.rooms[id],port.p)
			for d: float in [-.8,0,.8]:
				free_at(space.frame(id)*Vector3(p.x+port.n.x*d,.92,p.y+port.n.y*d),"bridge "+id+" "+str(d))
	var lift:=ElevatorModule.new(space.rooms)
	lift.reset()
	lift.lifts.teach.door=1.0
	lift.lifts.lab.door=1.0
	for node: CampusWorld in worlds: node.apply_lift_doors(lift)
	await _frames(2)
	for id: String in ["teach1","lab1"]:
		for d: float in [1.0,.4,0,-.7,-1.2]:
			var local:=CampusGeometry.to_scene(space.rooms[id],lift.world(id,d,0))
			free_at(space.frame(id)*Vector3(local.x,.92,local.y),"lift "+id+" "+str(d))
	for world: CampusWorld in worlds: world.queue_free()
	await _frames(2)


func free_at(p: Vector3,label: String) -> void:
	var shape:=CapsuleShape3D.new()
	shape.radius=.32
	shape.height=1.72
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=1
	query.transform=Transform3D(Basis.IDENTITY,p)
	var hits:=root.world_3d.direct_space_state.intersect_shape(query,10)
	var desc:=[]
	for hit in hits:
		var owner: CollisionObject3D=hit.collider
		var node:=owner.shape_owner_get_owner(owner.shape_find_owner(hit.shape))
		desc.append(str(owner.get_parent().scene_id)+":"+str(node.get_meta("kind","?")))
	check(hits.is_empty(),label+" "+str(p)+" hits "+str(desc))


func test_runtime() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/resident/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	var loading_at := Time.get_ticks_msec()
	app._load_then("teach1", app.start_new_game)
	var reported := -1
	while app.starting():
		if is_instance_valid(app.router.resident):
			var progress := app.router.resident.regions.size() / 10
			if progress != reported:
				reported = progress
				print("CASE: resident preparation ", app.router.resident.regions.size(), "/40")
		await _frames(1)
	print("CAMPUS LOAD: ",Time.get_ticks_msec()-loading_at," ms")
	app.set_physics_process(false)
	app._stand_up()
	app.player.set_physics_process(false)
	var school: CampusResident = app.router.resident
	var model := app._campus_world().get_node("Model")
	var collision := app._campus_world().get_node("Collision")
	check(school.regions.size() == 40 and school.builds == 40, "all forty ordinary regions are prepared once")
	for region: CampusWorld in school.regions.values():
		check(region.get_world_3d() == app.player.get_world_3d(), region.scene_id+" shares the school physics world")
		check(region.door_previews.is_empty() and region._shaft_levels.is_empty(), region.scene_id+" uses real neighbours without preview copies")
	var port := CampusGeometry.door_port(CampusData.layout("teach1"), CampusData.campus().campus_doors.doors[0])
	app.player.place(_campus_pose(CampusData.layout("teach1"),port.p,PI*.5))
	app.player.set_touch_move(Vector2(0,-1))
	app.player.set_touch_sprint(true)
	app.player.velocity=Vector3(.5,0,2)
	var position := app.player.global_position
	var forward := -app.player.camera.global_basis.z
	app.travel("out", _pose(), true)
	check(app.player.global_position.distance_to(position)<.0001 and (-app.player.camera.global_basis.z).distance_to(forward)<.0001,"ordinary crossing preserves actual position and gaze")
	check(app.player.velocity==Vector3(.5,0,2) and app.player._touch_move==Vector2(0,-1) and app.player._touch_sprint,"ordinary crossing preserves momentum and held touch controls")
	for id: String in ["teach2","stair_teach_w","garage1","lift_teach","teach1"]:
		app.travel(id,CampusData.rules().default_spawn(id),false)
		check(school.builds==40,"visiting "+id+" creates no geometry")
	check(app._campus_world().get_node("Model")==model and app._campus_world().get_node("Collision")==collision,"returning retains original mesh and collider objects")
	var lift:=app.elevator()
	lift.reset()
	var crowd:=lift.crowd
	lift.crowd=null
	var cabin:=lift.world("teach1",-1.2,0)
	app.travel("teach1",_campus_pose(CampusData.layout("teach1"),cabin,0),false)
	lift._enter_cabin("teach",1)
	lift.ride.rare=false
	lift.ride.pending=3
	var boarded_at:=app.player.global_position
	app._apply_result(lift._depart("teach1",app.player.capture_pose()))
	check(app.session.world_id=="lift_teach" and app.player.global_position.distance_to(boarded_at)<.001,"departure keeps the rider in the same physical cabin")
	app._campus_step(1.7)
	check(absf(app.player.global_position.y-boarded_at.y-3.2)<.001,"the moving cabin carries the player through the shared school")
	app._campus_step(1.7)
	check(app.session.world_id=="teach3" and absf(app.player.global_position.y-boarded_at.y-6.4)<.001,"arrival keeps physical height while returning to floor-local rules")
	lift.crowd=crowd
	app.travel("teach1",CampusData.rules().start_pose(),false)
	var options:=app.settings.graphics().duplicate()
	options.sun_shadows=0
	school.configure_graphics(options,app.player.camera)
	check(school.regions.lab3.render_options.sun_shadows==0 and school.regions.out.render_options.sun_shadows==0,"graphics options reach dormant regions and the exterior")
	check(not school.regions.lab3.is_processing() and school.regions.teach1.is_processing(),"dormant regions retain geometry without per-frame presentation work")
	app.campus().restore({"open_doors":["teach1:10:15"]})
	app._sync_world()
	await _frames(2)
	check(school.regions.teach1._door_bodies["teach1:10:15"].disabled,"door rules reach persistent colliders")
	app.travel("portal_tunnel",CampusData.rules().default_spawn("portal_tunnel"),false)
	check(not school.visible and school.regions.teach1.get_node("Collision").collision_layer==0,"special space suspends the school physics")
	app.travel("teach1",CampusData.rules().start_pose(),false)
	check(school.visible and school.regions.teach1.get_node("Collision").collision_layer==1,"returning restores the same school")
	app.school().tsec=1380
	app._sync_world()
	app.save_game(true)
	var pose := app.player.capture_pose()
	app.travel("out",_pose(),false)
	app.load_game()
	check(app.session.world_id=="teach1" and same_json(pose,app.player.capture_pose()),"local-coordinate save reloads in the unified world")
	check(app._campus_world().lighting.clock_minutes==1380,"read restores night lighting before the first frame")
	var environments := school.find_children("*","WorldEnvironment",true,false)
	check(environments.size()==1,"only one environment controls the persistent school")
	await check_presentations(app)
	app.return_to_menu()
	await _frames(2)
	check(not is_instance_valid(school) and app.router.coordinate_frame.transform==Transform3D.IDENTITY,"menu releases the complete school and coordinate frame")
	var installed := [false]
	app._load_then("teach1",func() -> void: installed[0]=true)
	app.return_to_menu()
	await _frames(3)
	check(not installed[0] and not app.starting() and not is_instance_valid(app.router.resident),"cancelled initial load cannot recreate the school or install a stale session")
	app.queue_free()
	await _frames(2)


func check_presentations(app: GameApp) -> void:
	app.travel("lab1",CampusData.rules().default_spawn("lab1"),false)
	var cut:=EndingCut.new()
	app.add_child(cut)
	cut.begin("portal",app._campus_world(),CampusData.layout("out"),app.player,app.ui)
	cut.tick(4.0)
	var shot:=EndingCut.portal_camera(.4,cut._device_at,cut._device.ring_y)
	check(cut.cam.global_position.distance_to(cut._root.to_global(shot.from))<.001,"live portal camera follows the lab's translated frame")
	cut.cancel()
	cut.queue_free()
	await _frames(2)
	app.travel("teach1",CampusData.rules().start_pose(),false)
	cut=EndingCut.new()
	app.add_child(cut)
	cut.begin("beast",app._campus_world(),CampusData.layout("out"),app.player,app.ui)
	cut.tick(4.5)
	shot=BeastScene.frame(.5,CampusData.layout("teach1"),app.player.view_motion.shake_enabled)
	check(cut.cam.global_position.distance_to(cut._beast.to_global(shot.from))<.001,"live beast camera stays with the classroom")
	cut.cancel()
	cut.queue_free()
	await _frames(2)
	var death:=DeathCG.new()
	app.add_child(death)
	death.begin("crowd",app.player,app._campus_world(),app.ui,4.2)
	check(not app.router.resident.visible,"isolated death stage hides all ordinary school geometry")
	death.finish()
	check(app.router.resident.visible,"death stage restores the school's visibility")
	death.queue_free()
	app.travel("garage1",CampusData.rules().default_spawn("garage1"),false)
	cut=EndingCut.new()
	app.add_child(cut)
	cut.begin("car",app._campus_world(),CampusData.layout("out"),app.player,app.ui,Callable(),{"switch":func() -> void: pass})
	check(absf(cut._beam.global_position.y-app._campus_world().global_position.y-.02)<.001,"car headlights stay on the underground garage floor")
	cut.cancel()
	cut.queue_free()
	await _frames(2)
	app.travel("teach1",CampusData.rules().start_pose(),false)
	var plane:=PaperPlaneView.new()
	app._campus_world().add_child(plane)
	plane.build()
	var room:=CampusData.layout("teach1")
	var spot:=Vector2(room.ox+room.tw*10,room.oy+room.th*10)
	var event:={"kind":"safe","phase":"flight","lx":spot.x,"ly":spot.y,"f":{"x":spot.x,"y":spot.y,"h":1.5,"yaw":.4,"pitch":.1}}
	plane.show_event(event,room,{"p":spot,"nz":1},app.player.camera)
	var target:=plane.to_global(plane.plane.position+Vector3(cos(.4)*2,sin(.1)*2,sin(.4)*2))
	check((-plane.camera.global_basis.z).dot((target-plane.camera.global_position).normalized())>.999,"paper-plane follow camera looks at the actual school position")
	plane.queue_free()
	await _frames(2)


func test_cooperation() -> void:
	var room := CooperativeRoom.new()
	room.add_member("a","房主",true)
	room.add_member("b","队友")
	room.add_member("c","队友三")
	room.add_member("d","队友四")
	room.ready("a",true,"none")
	room.ready("b",true,"none")
	room.ready("c",true,"none")
	room.ready("d",true,"none")
	room.begin("resident-fixture")
	room.loaded("a")
	room.loaded("b")
	room.loaded("c")
	room.loaded("d")
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room,421)
	var port := CampusGeometry.door_port(CampusData.layout("teach1"),CampusData.campus().campus_doors.doors[0])
	var local := _campus_pose(CampusData.layout("teach1"),port.p,0)
	var global_pose := sim.physics.space.global_pose("teach1",local)
	sim.travel(sim.actor("a"),"out",global_pose)
	sim.travel(sim.actor("b"),"teach1",local)
	await _frames(2)
	var first: CharacterBody3D = sim.physics.bodies.a
	var second: CharacterBody3D = sim.physics.bodies.b
	check(first.get_world_3d()==second.get_world_3d() and first.global_position.distance_to(second.global_position)<.001,"authority actors on opposite sides of a region boundary share actual space")
	var snapshot := sim.motion("a")
	check(snapshot.players.has("b") and snapshot.players.b.school,"replication includes neighbours across ordinary region IDs")
	# Real member IDs have fourteen bytes; allow the same overhead for these fixture IDs.
	check(LanProtocol.encode(snapshot).size()+4*13<1200,"four-player school motion fits one datagram without unreliable fragmentation")
	var avatars := RemoteStudents.new()
	avatars.space=sim.physics.space
	root.add_child(avatars)
	avatars.receive(snapshot,"a","out",room.members)
	avatars._process(.2)
	check(avatars.peers.has("b") and avatars.peers.b.global_position.distance_to(second.global_position)<.001,"remote avatar uses the school position instead of disappearing at a doorway")
	var position := second.global_position
	second.velocity=Vector3(.5,-2,1)
	sim.travel(sim.actor("b"),"out",_pose(),true)
	check(second.global_position.distance_to(position)<.001,"authority crossing preserves physical position")
	check(second.velocity==Vector3(.5,-2,1),"authority crossing preserves world-space momentum")
	sim.travel(sim.actor("b"),"portal_tunnel",CampusData.rules().default_spawn("portal_tunnel"))
	check(first.get_world_3d()!=second.get_world_3d() and not sim.motion("a").players.has("b"),"special worlds stay physically and visually separate in cooperation")
	avatars.queue_free()
	sim.queue_free()
	await _frames(2)
