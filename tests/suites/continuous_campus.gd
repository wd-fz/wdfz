extends "res://tests/support/test_suite.gd"


func test_collision() -> void:
	var worlds: Array[CampusWorld] = []
	var space := CampusSpace.new(CampusData.rooms(),CampusData.layout("out"),CampusData.campus())
	var wall := BoxMesh.new()
	wall.size=Vector3(5,10,.2)
	var xf := Transform3D(Basis.IDENTITY,Vector3(0,5,0))
	var floors := ["teach1","teach2","teach3","teach4"]
	var parts := CampusShell._floor_parts(wall,xf,"teach2",{"teach2":floors},space)
	check(parts.size()==5 and parts.has(CampusShell.ROOFLINE),"a tall facade retains the strips between its four playable storeys")
	for id: String in floors:
		var bounds: AABB=xf*(parts[id] as Mesh).get_aabb()
		var y:=space.frame(id).origin.y
		check(bounds.position.y>=y-.001 and bounds.end.y<=y+3.201,"facade "+id+" cannot cover another storey's open doorway")
	var shafts: Array[Dictionary]=[{"rect":Rect2(-1,-1,2,2),"floors":["lift_teach"]}]
	var broad_wall:=QuadMesh.new()
	broad_wall.size=Vector2(34,2)
	var flat:=Transform3D(Basis.IDENTITY,Vector3(0,1,0))
	var pieces:=CampusShell._partition_faces(broad_wall,flat,shafts,space)
	check(pieces.has("lift_teach") and pieces.has("") and absf((pieces.lift_teach as Mesh).get_aabb().size.x-2)<.001,"a 34 m exterior wall loses only the two metres inside the shaft footprint")
	var area:=0.0
	for part: Mesh in pieces.values():
		var faces:=part.get_faces()
		for i in range(0,faces.size(),3): area+=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length()*.5
	check(absf(area-68)<.001,"cutting across the shaft retains the complete visible wall area")
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
	for world in worlds:
		if world.layout.get("walls",[]).is_empty() or world.scene_id in ["lift_teach","lift_lab"]: continue
		var missing: Array[Vector2]=[]
		var expected:=world.get_node("Collision") as StaticBody3D
		var cut:=space.cabin_cut(world.scene_id)
		for wall_rect: Dictionary in world.layout.walls:
			var rect:=Rect2(wall_rect.x0,wall_rect.z0,wall_rect.x1-wall_rect.x0,wall_rect.z1-wall_rect.z0)
			for piece in CampusSpace.subtract_rect(rect,cut):
				var center:=piece.get_center()
				var query:=PhysicsPointQueryParameters3D.new()
				query.position=world.to_global(Vector3(center.x,1.2,center.y))
				query.collision_mask=1
				var found:=false
				for hit in root.world_3d.direct_space_state.intersect_point(query,32):
					if hit.collider!=expected: continue
					var owner:=expected.shape_owner_get_owner(expected.shape_find_owner(hit.shape))
					if owner.get_meta("kind","")=="wall":
						found=true
						break
				if not found: missing.append(center)
		check(missing.is_empty(),"all exported wall segments block at eye height in "+world.scene_id+" "+str(missing))
	# The garage stair only replaces the middle of a seven-metre outdoor obstruction.
	for dir: float in [-1,1]:
		var x:=66.7222 if dir<0 else 73.7222
		var outside:=Vector3(x+.2*dir,1.2,119.6)
		var ray:=PhysicsRayQueryParameters3D.create(outside,outside-Vector3.RIGHT*dir*.4,1)
		var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and hit.collider.get_parent().scene_id=="out","shaft cut retains the outdoor wall beyond each side")
	await _check_garage_entrance(space)
	for bounds: AABB in space.lift_walls():
		var point:=bounds.get_center()
		var across:=(Vector3.RIGHT if bounds.size.x<bounds.size.z else Vector3.BACK)*.19
		for sign_value: float in [-1,1]:
			var ray:=PhysicsRayQueryParameters3D.create(point+across*sign_value,point-across*sign_value,1)
			var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
			check(not hit.is_empty(),"fixed shaft blocks from either side while car is downstairs")
	for world: CampusWorld in worlds: world.queue_free()
	await _frames(2)


func _check_garage_entrance(space: CampusSpace) -> void:
	var shaft := space.frame("stair_garage")
	var street := space.frame("out").origin.y
	var physics := root.world_3d.direct_space_state
	var model := Node3D.new()
	var paving := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 24)
	paving.mesh = plane
	paving.position = Vector3(shaft.origin.x, street, shaft.origin.z)
	model.add_child(paving)
	CampusShell.partition(model, space)
	var visible_paving := paving.mesh.generate_triangle_mesh()
	var edges: Array[Vector2] = [Vector2(-1.6, -2.05), Vector2(1.6, -2.05), Vector2(0, -3.15)]
	for z: float in [-0.7, 3.4, 7.05]:
		edges.append(Vector2(-2.48, z))
		edges.append(Vector2(2.48, z))
	for x: float in [-1.7, 0.0, 1.7]:
		edges.append(Vector2(x, 7.52))
	for edge in edges:
		var p := shaft * Vector3(edge.x, 0, edge.y)
		p.y = street
		var hit := physics.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * .15, p - Vector3.UP * .3, 1))
		check(not hit.is_empty() and absf(hit.position.y - street) < .02, "pavement supports the garage perimeter at %s" % edge)
		var local := p - paving.position
		check(not visible_paving.intersect_segment(local + Vector3.UP, local - Vector3.UP).is_empty(), "visible street reaches the same garage edge at %s" % edge)
	for x: float in [-1.25, 1.25]:
		var p := shaft * Vector3(x, 0, 3.2)
		p.y = street
		var hit := physics.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * .15, p - Vector3.UP * 4.0, 1))
		var depth := 2.4 if x < 0 else .8
		check(not hit.is_empty() and absf(hit.position.y - (street - depth)) < .03, "both descending flights remain open at %s" % x)
		var local := p - paving.position
		check(visible_paving.intersect_segment(local + Vector3.UP, local - Vector3.UP).is_empty(), "outdoor paving leaves the visible flight open at %s" % x)
	model.free()
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	for side: float in [-1.0, 1.0]:
		var start := shaft * Vector3(side * 1.65, 0, -4.3)
		start.y = street + .04
		player.global_position = start
		player.velocity = Vector3.ZERO
		for tick in 105:
			await physics_frame
			var axis := Vector2.DOWN if tick < 36 else Vector2.ZERO
			CharacterMotor.advance(player, axis, shaft.basis.get_euler().y, true, 1.0, 1.0 / 60.0)
		var finish := shaft.affine_inverse() * player.global_position
		check(finish.z > -2.2 and player.is_on_floor() and absf(player.global_position.y - street) < .03, "sprinting past the garage entrance jamb stays on the pavement on side %s" % side)
	player.queue_free()
	for id: String in ["stair_garage", "garage1"]:
		var valid_pose := {"position": [0.0, 0.0, 0.0], "yaw": 1.0, "pitch": -.2}
		check(space.garage_resume_pose(id, valid_pose) == valid_pose, "legal below-street saves use the local floor in " + id)
		var fallen := {"position": [0.0, -25.0, 0.0], "yaw": 1.0, "pitch": -.2}
		var rescued := space.garage_resume_pose(id, fallen)
		var at: Array = rescued.position
		var feet := space.frame(id) * Vector3(at[0], at[1], at[2])
		var ground := physics.intersect_ray(PhysicsRayQueryParameters3D.create(feet, feet - Vector3.UP * .12, 1))
		check(not ground.is_empty() and fallen.position[1] == -25.0 and rescued.yaw == fallen.yaw and rescued.pitch == fallen.pitch, "load restores solid footing and the saved view in " + id)


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
	check(school.regions.out.get_node_or_null("Model/"+CampusShell.ROOFLINE)!=null,"the occupied school retains an independent exterior roof")
	var rules:=app.campus()
	for floor_index in range(1,6):
		var floor_id:="teach%d" % floor_index
		var room:=CampusData.layout(floor_id)
		for col in [10,22,34,46]:
			var desk:=CampusGeometry.tile_center(room,col,10)+Vector2(0,float(room.th)*.5)
			for side: float in [-1,1]:
				var standing:=desk+Vector2(0,side*9.0)
				var aim:=_campus_pose(room,standing,-side*PI/2)
				var reply:=rules.interact_at(floor_id,aim)
				check(reply.get("podium")==[col,10],"the real desk can be used from both aisles at %s/%s" % [floor_id,col])
			if floor_index==1 and col==46:
				var exact:=_campus_pose(room,desk+Vector2(0,9),-PI/2)
				app.player.place(exact)
				check(rules.hint(floor_id,exact)=="看移交单","the handover prompt matches its desk")
				app._campus_interact()
				check(app.ui.choice_open() and app.investigation().visible("notice"),"using the lectern opens the transfer note in live single player")
				if app.ui.choice_open(): app._choice_made(1)
				check(app.items().has("chalk"),"the lectern choice really gives chalk")
	app.player._look_pitch=-1.30
	app._process(.03)
	check(not app.player.has_node("FirstPersonBody") and is_instance_valid(app._hands),"looking down keeps the hand view without spawning a local body")
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
	var damaged := {"position": [68.55, -24.0, 124.58], "yaw": .7, "pitch": -.3}
	app.travel("out", damaged, false)
	app.save_game(true)
	app.load_game()
	var restored := app.player.capture_pose()
	check(app.session.world_id == "out" and absf(app.player.global_position.y - .05) < .001 and absf(restored.yaw - damaged.yaw) < .001 and absf(restored.pitch - damaged.pitch) < .001, "loading a run saved under the old garage rim puts the player on the street with the same view")
	await check_presentations(app)
	test_portal_continuity(app)
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


func test_portal_continuity(app: GameApp) -> void:
	var school := app.router.resident
	var lift := app.elevator()
	var covered := {}
	app.school().day = 3
	for portal: Dictionary in CampusConnections.resident_portals(school.space):
		var a: String = portal["a"]
		var b: String = portal["b"]
		covered[a] = true
		covered[b] = true
		if a.begins_with("lift_"):
			lift.lifts[a.trim_prefix("lift_")]["floor"] = school.space.rooms[b]["floor"]
			school.update_lifts(lift)
		var at: Vector3 = portal["at"] + Vector3.UP * .05
		var pose := {"position": [at.x, at.y, at.z], "yaw": .55, "pitch": -.15}
		var label := a + " / " + b
		for minutes: float in [730.0, 1100.0, 1350.0]:
			app.school().tsec = minutes
			app.anomaly().an["active"] = true
			app.anomaly().an["id"] = "blackout" if minutes == 1350.0 else "rain"
			app.dread().visits.clear() # Compare the shared view without the deliberate revisit scares.
			check(app.travel(a, school.space.local_pose(a, pose), false).is_empty(), "can approach " + label)
			check(school.regions[a].get_node("Model").visible and school.regions[b].get_node("Model").visible, "both models are visible at " + label)
			var visuals := _portal_visuals(school)
			var light := app._campus_world().lighting
			light.time = 19.0
			light.overcast = .6
			app._update_campus_lighting(app._campus_world(), 0)
			var shared := _portal_light_levels(light)
			for destination: String in [b, a]:
				app.dread().visits.clear()
				check(app.travel(destination, pose, true).is_empty(), "can cross " + label + " toward " + destination)
				check(app.player.global_position.distance_to(at) < .001 and _portal_visuals(school) == visuals, "the same position sees the same surfaces through " + label + " toward " + destination)
				light = app._campus_world().lighting
				check(is_equal_approx(light.time, 19.0) and is_equal_approx(light.overcast, .6), "lighting and rain keep their phase through " + label)
				check(_portal_light_levels(light).is_equal_approx(shared), "sky, camera fill and fog stay continuous through %s at %d" % [label, minutes])
	check(covered.size() == school.regions.size(), "every resident region has a tested crossing")
	app.anomaly().an["active"] = false
	for id: String in CampusSpace.SEPARATE:
		check(app.travel(id, CampusData.rules().default_spawn(id), false).is_empty() and not school.visible, "isolated world keeps its own visuals on entry: " + id)
		check(app.travel("teach1", CampusData.rules().start_pose(), false).is_empty() and school.visible, "returning restores the school after " + id)


func _portal_light_levels(light: CampusLighting) -> Vector4:
	return Vector4(light.env.ambient_light_energy, light.env.fog_density, light.cam_light.light_energy, light.post_exposure)


func _portal_visuals(school: CampusResident) -> Array[bool]:
	var result: Array[bool] = []
	for world: CampusWorld in school.regions.values():
		result.append(world.get_node("Model").is_visible_in_tree())
		result.append(world._fixed_props != null and world._fixed_props.is_visible_in_tree())
	for facade: Node3D in (school.regions.out as CampusWorld).shells.values():
		result.append(facade.is_visible_in_tree())
	return result


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


func test_nearby_visuals() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/nearby/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	app._setting_changed("quality", 0)
	app.router.school_ids()
	var school := app.router.resident
	school.nearby_visuals = true
	await app._load_then("teach1", app.start_new_game)
	var models := 0
	for world: CampusWorld in school.regions.values():
		check(world.has_node("Collision"), "a cold Android room keeps its physical floor: " + world.scene_id)
		if world.geometry_ready: models += 1
	check(school.regions.size() == 40 and models < 12 and school.regions.out.geometry_ready and school.regions.teach1.geometry_ready, "mobile entry loads just the nearby models and all 40 regions share physics")
	var lab: CampusWorld = school.regions.lab4
	var body := lab.get_node("Collision")
	var door: String = lab.door_keys()[0]
	app.campus().restore({"open_doors": [door]})
	app._sync_world()
	await _frames(2)
	check(not lab.has_node("Model") and lab._door_bodies[door].disabled, "a distant floor receives door changes without loading its meshes")
	school.configure_graphics(app.settings.graphics(), app.player.camera)
	check(not lab.has_node("Model"), "changing graphics leaves distant floors cold")
	# Force a crossing that outruns prefetch: the room adapter changes immediately
	# and the model arrives separately on the same collider and coordinate frame.
	app.travel("stair_lab", {"position":[0.0, 9.65, -2.9], "yaw":0.0, "pitch":0.0}, false)
	var cold_view := lab.get_node_or_null("ColdGeometry")
	check(cold_view != null and cold_view.is_visible_in_tree(), "the cold floor is visible through the doorway before crossing")
	var at := app.player.global_position
	app.player.velocity = Vector3(0, 0, -1)
	app.travel("lab4", CampusData.rules().default_spawn("lab4"), true)
	check(app.session.world_id == "lab4" and app.player.global_position.distance_to(at) < .001 and app.player.velocity.z == -1, "a cold stair crossing keeps position and movement")
	check(not lab.geometry_ready and lab.get_node_or_null("ColdGeometry") == cold_view and lab.get_node("Collision") == body, "crossing retains the same temporary surfaces and live collision")
	var until := Time.get_ticks_msec() + 20000
	while not lab.geometry_ready and Time.get_ticks_msec() < until: await _frames(1)
	check(lab.geometry_ready and not lab.has_node("ColdGeometry"), "the visual worker replaces the temporary surfaces without another crossing")
	if lab.geometry_ready:
		check(lab._door_leaves[door]["open"].visible and lab._door_bodies[door].disabled and lab.get_node("Collision") == body, "adoption retains the current door pose and permanent physics")
	app.travel("teach1", CampusData.rules().start_pose(), false)
	school.update_view(app.player.global_position)
	until = Time.get_ticks_msec() + 8000
	while lab.geometry_ready and Time.get_ticks_msec() < until: await _frames(1)
	check(not lab.has_node("Model") and lab.get_node("Collision") == body and lab.visual_ground._nodes.is_empty(), "distant models are released in bounded steps while physics remains")
	app.queue_free()
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
	var watched: Node3D = avatars.peers.b
	avatars.remove_from_view("b")
	check(not watched.visible and not avatars.peers.has("b"),"taking a teammate’s first-person view hides that body before the next motion packet")
	var position := second.global_position
	second.velocity=Vector3(.5,-2,1)
	sim.travel(sim.actor("b"),"out",_pose(),true)
	check(second.global_position.distance_to(position)<.001,"authority crossing preserves physical position")
	check(second.velocity==Vector3(.5,-2,1),"authority crossing preserves world-space momentum")
	sim.travel(sim.actor("b"),"portal_tunnel",CampusData.rules().default_spawn("portal_tunnel"))
	check(first.get_world_3d()!=second.get_world_3d() and not sim.motion("a").players.has("b"),"special worlds stay physically and visually separate in cooperation")
	var checkpoint := sim.capture()
	checkpoint.actors.a.session.player.position = [68.55, -24.0, 124.58]
	sim.restore(checkpoint)
	var reported: Array = sim.actor("a").pose.position
	check(absf(first.global_position.y - .05) < .001 and first.position.is_equal_approx(Vector3(reported[0], reported[1], reported[2])), "cooperative restore moves the authority and replicated pose back onto the garage pavement")
	avatars.queue_free()
	sim.queue_free()
	await _frames(2)
