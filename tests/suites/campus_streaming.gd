extends "res://tests/support/test_suite.gd"


class SeedProbe extends CampusWorld:
	var reused: Mesh

	func prepare_geometry() -> void:
		var seed := get_node_or_null("VisualSeeds/out") as MeshInstance3D
		if seed != null:
			reused = seed.mesh
		geometry_ready = true


func test_queue_and_late_seeds() -> void:
	var stream := CampusStream.new()
	var owner := CampusWorld.new()
	var outside := Node3D.new()
	var upstairs := Node3D.new()
	owner.add_child(outside)
	owner.add_child(upstairs)
	stream.request_preview(owner, outside, "out", Plane())
	var first := SeedProbe.new()
	first.scene_id = "teach2"
	stream.prepare(first)
	stream.request_preview(owner, upstairs, "teach3", Plane())
	var next := SeedProbe.new()
	next.scene_id = "teach3"
	stream.prepare(next)
	check(stream._queue.map(func(job: Dictionary) -> String: return job["id"]) == ["teach2", "teach3", "out", "teach3"],
		"later upstairs previews cannot overtake an already queued landing")
	stream.clear()
	check(not outside.has_meta("stream_pending") and not upstairs.has_meta("stream_pending"), "clearing reordered work releases every preview ticket")
	owner.free()
	# The campus is still being built when the floor is requested, then becomes
	# resident before dispatch. A detached copy must share its processed mesh.
	var landing := SeedProbe.new()
	landing.scene_id = "teach2"
	stream.prepare(landing)
	var campus := CampusWorld.new()
	campus.scene_id = "out"
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = BoxMesh.new()
	campus.add_child(model)
	stream.keep(campus)
	var mesh := model.mesh
	var until := Time.get_ticks_msec() + 10000
	while not stream.has("teach2") and Time.get_ticks_msec() < until:
		stream.poll()
		await _frames(1)
	check(stream.has("teach2") and landing.reused == mesh, "queued floor reuses a neighbour that completed after it was requested")
	check(landing.get_node_or_null("VisualSeeds/out") != model and model.get_parent() == campus,
		"late seeding copies the detached tree without stealing the resident model")
	stream.clear()


## The exporter folds small furniture batches into static geometry on lower tiers.
## Every table still needs exactly one replacement at its playable tile.
func test_campus_fittings() -> void:
	for tier in [0, 2, 3]:
		var canteen := CampusArchitecture.refit(CampusData.instantiate_model("canteen1", tier), "canteen1")
		var dining := canteen.find_child("CanteenTable", true, false) as MultiMeshInstance3D
		check(dining != null and dining.multimesh.instance_count == 90, "all dining tables have benches at tier %d" % tier)
		if dining != null:
			var room := CampusData.layout("canteen1")
			var tiles := {}
			for i in dining.multimesh.instance_count:
				var p := CampusPreview.instance_transform(dining, i).origin
				tiles[CampusGeometry.to_world(room,p.x,p.z)] = true
			for r in int(room.rows):
				for c in int(room.cols):
					if String(room.grid[r]).substr(c,1) == "t":
						check(tiles.has(CampusGeometry.tile_center(room,c,r)), "dining table shares its gameplay footprint")
		canteen.free()
	var bridge := CampusWorld.build_visual("link2", 0)
	var frame := bridge.find_child("Frame", true, false) as MeshInstance3D
	check(frame != null, "the orange walkway uses the structural model in previews")
	if frame != null:
		var faces := frame.mesh.generate_triangle_mesh()
		check(faces.intersect_segment(Vector3(0,1.65,-11.9),Vector3(0,1.65,11.9)).is_empty(), "the truss leaves the crossing clear")
		check(not faces.intersect_segment(Vector3(0,4.3,4.5),Vector3(0,3.4,4.5)).is_empty(), "the pitched roof spans the deck")
	bridge.free()


func test_connections() -> void:
	for door: Dictionary in CampusData.campus()["campus_doors"]["doors"]:
		var id := String(door["room"])
		var room := CampusData.layout(id)
		var p: Vector2 = CampusGeometry.door_port(room, door)["p"]
		var outside := (p + CampusGeometry.shift_of(room)) * CampusGeometry.U2M
		var inside := CampusGeometry.to_scene(room, p)
		check(CampusConnections.nearby("out", Vector3(outside.x, 0, outside.y)).has(id), "approaching %s prepares the correct building" % id)
		check(CampusConnections.nearby(id, Vector3(inside.x, 0, inside.y)).has("out"), "%s prepares the campus before its exit" % id)
	for stair: Dictionary in CampusData.campus()["stair_layout"]:
		for level in (stair["rooms"] as Array).size():
			var ids := CampusConnections.nearby(String(stair["id"]), Vector3(0, level * float(stair["rise"]), 0))
			check(ids.has(String(stair["rooms"][level])) and ids.size() <= 2, "%s level %d warms its landing without loading the whole building" % [stair["id"], level])
	check(CampusConnections.nearby("missing", Vector3.ZERO).is_empty(), "unregistered space cannot request arbitrary assets")


func test_daylight() -> void:
	var previous_mobile := CampusLighting.mobile_renderer
	CampusLighting.mobile_renderer = RenderingServer.get_current_rendering_method() == "mobile"
	var outside := CampusLighting.new()
	root.add_child(outside)
	outside.setup("out", null, null, 0)
	for id: String in ["teach1", "teach2", "admin1", "lab1", "dorm1", "canteen1", "stair_teach_w"]:
		var room := CampusLighting.new()
		root.add_child(room)
		room.setup(id, CampusData.layout(id), null, 0)
		for minutes: float in [360, 720, 1080, 1140, 1380]:
			outside.update(0, minutes, null)
			room.update(0, minutes, null)
			check(is_equal_approx(room.env.ambient_light_energy, outside.env.ambient_light_energy)
				and room.env.ambient_light_color.is_equal_approx(outside.env.ambient_light_color)
				and is_equal_approx(room.sun_light.light_energy, outside.sun_light.light_energy)
				and room.sun_light.basis.is_equal_approx(outside.sun_light.basis), "%s and outdoors share sky/sun at %d" % [id, minutes])
			check(is_equal_approx(room.env.fog_density, outside.env.fog_density) and is_equal_approx(room.post_exposure, outside.post_exposure), "crossing %s does not jump fog/exposure at %d" % [id, minutes])
		room.update(0, 720, null)
		var daylight := room.env.ambient_light_energy
		var fill := room.cam_light.light_energy
		room.update(0, 1380, null)
		check(room.env.ambient_light_energy < daylight * .1 and room.cam_light.light_energy < fill * .15, "%s becomes dark at night, including the camera fill" % id)
		room.update(0, 720, null)
		room.blackout = true
		room.update(0, 720, null)
		if not room._open_air():
			check(room.env.ambient_light_energy < daylight * .2 and room.room_lights.all(func(l: OmniLight3D) -> bool: return is_zero_approx(l.light_energy)), "blackout still extinguishes %s" % id)
		room.free()
	var garage := CampusLighting.new()
	root.add_child(garage)
	garage.setup("garage1", CampusData.layout("garage1"), null, 0)
	outside.update(0, 720, null)
	garage.update(0, 720, null)
	check(garage.env.ambient_light_energy < outside.env.ambient_light_energy * .2, "underground garage retains its intentional darkness")
	garage.free()
	outside.free()
	CampusLighting.mobile_renderer = previous_mobile


func test_residency(quality: int = -1) -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/streaming/save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/streaming/settings.json")
	root.add_child(app)
	await _frames(2)
	if quality >= 0:
		app._setting_changed("quality", quality)
	app.router.continuous_campus = false
	app.router.stream.allow_headless = true
	app.start_new_game()
	print("STREAM: starting region built")
	app.set_physics_process(false)
	app.set_process(false)
	app.player.enabled = false
	var first := app._campus_world()
	var mesh := first.get_node("Model")
	var collision := first.get_node("Collision")
	var old_fx := first.anomaly_fx
	var door: Dictionary = CampusData.campus()["campus_doors"]["doors"][0]
	var port := CampusGeometry.door_port(first.layout, door)
	app.school().seated = false
	app.player.seated = false
	app.player.place(_campus_pose(first.layout, (port["p"] as Vector2) + (port["n"] as Vector2) * 2.0, PI * .5))
	app.player.enabled = true
	app._campus_step(.016)
	check(app.session.world_id == "teach1" and app.router.stream.pending("out") and first.get_node("Model") == mesh,
		"a cold walking threshold queues preparation and keeps valid collision instead of synchronously switching")
	app.player.enabled = false
	app.router.prepare("out")
	var until := Time.get_ticks_msec() + 180000
	while not app.router.warm("out") and Time.get_ticks_msec() < until:
		await _frames(1)
	check(app.router.warm("out"), "outdoor geometry is ready before crossing")
	print("STREAM: outdoor region ready")
	var prepared: CampusWorld = app.router.stream.cached.get("out")
	if prepared == null:
		app.queue_free()
		await _frames(2)
		return
	var outdoor_model := prepared.get_node("Model")
	check(not prepared.is_inside_tree() and prepared.lighting == null and prepared.anomaly_fx == null, "prefetch has no active collision, light environment or anomaly adapters")
	Input.action_press("move_forward")
	app.player.enabled = true
	app.player.set_touch_move(Vector2(0, -1))
	app.player.set_touch_sprint(true)
	app.player.velocity = Vector3(0, 0, -3)
	var source_yaw := app.player.rotation.y
	var pose := {"position": [100.0, 0.05, 220.0], "yaw": source_yaw + PI / 2, "pitch": .2}
	var switched_at := Time.get_ticks_usec()
	app.travel("out", pose, true)
	print("STREAM: prepared exit took ", (Time.get_ticks_usec() - switched_at) / 1000.0, " ms")
	check(app._campus_world().get_node("Model") == outdoor_model and app.router.stream.hits > 0, "crossing adopts the already built model without loading it again")
	check(Input.is_action_pressed("move_forward") and app.player.velocity.distance_to(Vector3(-3, 0, 0)) < .001, "seamless crossing preserves held input and rebases momentum")
	check(app.player._touch_move == Vector2(0, -1) and app.player._touch_sprint, "crossing keeps the held touch stick and sprint toggle")
	Input.action_release("move_forward")
	app.player.enabled = false
	app.player.clear_input()
	check(app.router.stream.cached.has("teach1") and not (app.router.stream.cached["teach1"] as Node).is_inside_tree(), "the building stays resident with its physics removed from the live world")
	check(app._campus_world().door_previews[0].get_child_count() > 0, "the view back through the entry is ready before crossing")
	var preview := app._campus_world().door_previews[3]
	var threshold: Vector2 = preview.get_meta("door_threshold")
	app._campus_world().set_player_scene(Vector3(threshold.x, 0, threshold.y))
	check(preview.get_child_count() == 0 and preview.get_meta("stream_pending", false), "approaching a door queues its view without synchronously loading or clipping geometry")
	until = Time.get_ticks_msec() + 180000
	while preview.get_child_count() == 0 and Time.get_ticks_msec() < until:
		await _frames(1)
	check(preview.get_child_count() > 0, "the worker installs the connected interior view")
	await _frames(2)
	check(not is_instance_valid(old_fx), "leaving discards old anomaly presentation instead of caching it")
	app.campus().restore({"open_doors": ["teach1:10:15"]})
	app.school().tsec = 1380
	app.travel("teach1", CampusData.rules().start_pose(), true)
	check(second_light_is_night(app), "the first frame after a night-time crossing already has night lighting")
	await _frames(2)
	var second := app._campus_world()
	check(second.get_node("Model") == mesh and second.get_node("Collision") == collision, "returning through the door reuses the original mesh and collision objects")
	check(second._door_bodies["teach1:10:15"].disabled, "reactivation synchronizes current door rules with retained collision")
	check(app.router.get_child_count() == 1, "only the current region contributes physics and an environment")
	var active := app.router.world_instance()
	check(app.router.switch_to("not_registered") != "" and app.router.world_instance() == active, "invalid destinations leave the current world and cache untouched")
	for id: String in ["guard1", "gear1", "trash1", "bell1"]:
		app.travel(id, CampusData.rules().default_spawn(id), false)
		check(app.router.stream.cached.size() <= CampusStream.CACHE_LIMIT, "residency stays bounded after visiting %s" % id)
	app.router.prepare("lab1")
	app.return_to_menu()
	check(app.router.stream.cached.is_empty() and app.router.stream._queue.is_empty(), "returning to menu releases the complete residency cache")
	app.queue_free()
	await _frames(3)


func second_light_is_night(app: GameApp) -> bool:
	var light := app._campus_world().lighting
	return is_equal_approx(light.clock_minutes, 1380) and float(light.terms["day"]) < .01
