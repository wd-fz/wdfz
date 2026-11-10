extends "res://tests/support/test_suite.gd"

func test_buffers() -> void:
	var metrics:=DebugTelemetry.new()
	for value: float in [0,-1,NAN,INF]: metrics.sample(value)
	check(metrics.capture(false).samples==0,"invalid frame intervals never enter the performance window")
	for value: float in [.01,.02,.04]: metrics.sample(value)
	var state:=metrics.capture(false)
	check(is_equal_approx(state.average_ms,70.0/3) and is_equal_approx(state.p95_ms,40),"measured mean and nearest-rank P95 include real slow frames")
	for _i in DebugTelemetry.MAX_SAMPLES+3: metrics.sample(.016)
	state=metrics.capture(false)
	check(state.samples==DebugTelemetry.MAX_SAMPLES and is_equal_approx(state.average_ms,16) and is_equal_approx(state.p95_ms,16),"rolling frame window stays bounded and evicts old outliers")
	check(not state.rendered and state.draw_calls==-1 and state.primitives==-1,"headless diagnostics do not invent GPU measurements")
	metrics.reset()
	check(metrics.capture().samples==0,"performance reset clears samples without changing engine timing")
	var log:=DebugTrace.new()
	for i in DebugTrace.LIMIT+9: log.add("fact","event",{"i":i})
	check(log.entries.size()==DebugTrace.LIMIT and log.discarded==9 and log.entries[0].seq==10,"event ring retains the latest facts and counts evictions")
	var input:={"x":[1,2],"bad":NAN,"call":func() -> void: pass}
	log.add("command","edit",input)
	input.x[0]=99
	check(log.entries[-1].detail.x[0]==1 and log.entries[-1].detail.bad==null and SaveSchema.is_json_value(log.capture()),"trace owns bounded JSON values, not live dictionaries, callbacks or NaN")
	var shared: Variant={"text":"x".repeat(300)}
	for _i in 5:
		var branch:=[]
		for _j in 24: branch.append(shared)
		shared=branch
	check(JSON.stringify(DebugTrace.clean(shared)).length()<41000,"one event has a total value budget even for a wide shared object graph")
	var snapshot:=log.capture()
	snapshot.entries.clear()
	check(not log.entries.is_empty(),"exported trace is an isolated copy")
	log.recording=false
	log.add("fact","ignored")
	check(log.entries.size()==DebugTrace.LIMIT,"pausing event capture does not change the retained list")
	log.clear()
	check(log.entries.is_empty() and log.discarded==0,"clearing a paused trace still works")

func _app(id: String) -> GameApp:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path.get_base_dir()+"/workbench/"+id+"/slot.json")
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
	app.debug_flow.set_process(false)
	await _frames(2)
	return app

func _dispose(app: GameApp) -> void:
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()

func test_playback_and_steps() -> void:
	var app:=await _app("playback")
	app._toggle_debug()
	var dev:=app.debug_flow
	check(app.debug_panel._pages.has("诊断") and app.debug_panel._pages.has("日志"),"diagnostics and event log are distinct pages")
	var stamp:=app.session.clock.active_seconds
	dev.command("step",{"seconds":1})
	check(app.session.clock.active_seconds==stamp,"logical stepping requires explicit freeze")
	dev.command("freeze")
	for value: float in [-1,0,NAN,INF,1.1]:
		dev.command("step",{"seconds":value})
		check(app.session.clock.active_seconds==stamp,"invalid step cannot advance time")
	dev.command("step",{"seconds":.1})
	check(is_equal_approx(app.session.clock.active_seconds,stamp+.1) and dev.frozen and app.player.debug_frozen,"bounded fixed steps advance game logic and retain explicit freeze")
	var scale:=Engine.time_scale
	var saved:=app.session.capture(app.player.capture_pose())
	var view:=app.player.camera.transform
	var rng:=app.audio._rng.state
	dev.command("preview",{"id":"patrol"})
	check(dev.blocks_simulation() and app.player.debug_frozen,"preview borrows a simulation/input freeze independently of the tools window")
	app._physics_process(1)
	check(same_json(saved,app.session.capture(app.player.capture_pose())),"preview cannot advance hidden gameplay timers or move the real player")
	dev.command("preview_pause")
	var t:=dev.preview.k
	dev._process(.3)
	check(dev.preview.k==t,"paused preview holds its exact frame")
	for value: float in [-.1,NAN,INF,1.1]:
		dev.command("preview_seek",{"fraction":value})
		check(dev.preview.k==t,"invalid seek leaves the current frame intact")
	dev.command("preview_seek",{"fraction":.62})
	check(is_equal_approx(dev.preview.k,dev.preview.dur*.62) and dev.preview_paused,"scrubbing seeks in normalized real scene time and pauses playback")
	check(app.audio._preview_voices.is_empty() and app.audio._rng.state==rng,"scrubbing neither replays crossed cues nor consumes gameplay sound RNG")
	dev.command("preview_rate",{"rate":.25})
	dev.command("preview_pause")
	t=dev.preview.k
	dev._process(.4)
	check(is_equal_approx(dev.preview.k,t+.1),"preview rate affects presentation time only")
	dev.command("preview_seek",{"fraction":1})
	check(is_instance_valid(dev.preview) and dev.preview.on and dev.preview_paused,"the last frame can be inspected without auto-cleanup")
	dev.command("preview_pause")
	check(is_zero_approx(dev.preview.k) and not dev.preview_paused,"resuming at the end restarts from the beginning")
	dev.command("preview_restart")
	check(dev.preview.fx=="patrol" and is_zero_approx(dev.preview.k),"replay rebuilds the chosen scene with no stale actors")
	dev.command("clear_preview")
	check(dev.frozen and app.player.debug_frozen and view.is_equal_approx(app.player.camera.transform),"ending preview restores camera while preserving an earlier explicit freeze")
	dev.command("freeze")
	dev.command("preview",{"id":"mirror"})
	dev.command("clear_preview")
	check(not dev.frozen and not app.player.debug_frozen and not dev.blocks_simulation() and Engine.time_scale==scale,"a standalone preview releases its freeze and never changes global engine time")
	dev.command("freeze")
	var node:=app._campus_world()
	dev.command("preview",{"id":"bell"})
	app.debug_panel.dismiss()
	check(dev.preview==null and not dev.frozen and not app.player.debug_frozen and node.visible,"closing the panel cancels scrub/playback and both freeze owners")
	await _dispose(app)

func test_bookmarks_and_reports() -> void:
	var app:=await _app("bookmarks")
	var dev:=app.debug_flow
	dev.command("bookmark_add",{"name":"座位不可用"})
	check(dev.bookmarks.is_empty(),"bookmarks reject seated poses that cannot become standing teleports")
	app._stand_up()
	var pose:=app.player.capture_pose()
	for i in 9: dev.command("bookmark_add",{"name":"位置 %d" % i})
	check(dev.bookmarks.size()==8 and app.runscore().trusted,"position bookmarks are bounded, in-memory and read-only until used")
	dev.command("export_report")
	var report_path:=app.saves.side_path("debug-report.json")
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(report_path))
	check(data is Dictionary and data.version==1 and data.diagnostics.has("metrics") and data.events.has("entries") and SaveSchema.is_json_value(data),"manual report exports diagnostics and bounded events as valid JSON")
	check(not app.saves.exists() and app.runscore().trusted,"report export never creates a gameplay save or alters trust")
	app.travel("lab1",app.campus().default_spawn("lab1"),false)
	dev.command("bookmark_go",{"id":dev.bookmarks[0].id})
	await _frames(3)
	check(app.session.world_id=="teach1" and same_json(pose,app.player.capture_pose()) and not app.runscore().trusted,"bookmark return restores room, position and look, and invalidates the edited run")
	dev.command("bookmark_go",{"id":dev.bookmarks[0].id})
	var blocker:=StaticBody3D.new()
	blocker.collision_layer=1
	blocker.collision_mask=0
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(1,1.7,1)
	collision.shape=box
	blocker.add_child(collision)
	app._campus_world().add_child(blocker)
	blocker.global_position=app.player.global_position+Vector3.UP*.9
	await _frames(3)
	check(not same_json(pose,app.player.capture_pose()) and dev.history[-1].contains("障碍"),"occupied bookmark falls back safely instead of placing the player inside a wall")
	dev.command("bookmark_go",{"id":dev.bookmarks[0].id})
	app.travel("lab1",app.campus().default_spawn("lab1"),false)
	await _frames(3)
	check(app.session.world_id=="lab1","a later scene change cancels an old bookmark landing callback")
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	check(dev.bookmarks.is_empty(),"position bookmarks cannot leak into a new session")
	check(dev.trace.entries.any(func(entry: Dictionary) -> bool: return entry.title=="bookmark_go") and dev.trace.entries[-1].context.session>=2,"event journal preserves the actions before a new session and marks the session boundary")
	if app._opening_cut!=null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app._stand_up()
	dev.command("bookmark_add")
	dev.command("bookmark_go",{"id":dev.bookmarks[0].id})
	await _dispose(app)
	check(not is_instance_valid(app),"a pending landing check is disconnected when its tool owner is destroyed")

func test_probe_and_layout() -> void:
	var app:=await _app("probe")
	app._toggle_debug()
	var panel:=app.debug_panel
	panel.select_page("诊断")
	var dev:=app.debug_flow
	var world:=app._campus_world()
	var before:=app.session.capture(app.player.capture_pose())
	var colliders:=world.find_children("*","CollisionShape3D",true,false)
	dev.command("collisions")
	check(dev.probe.shown>0 and dev.probe.shown<=DebugWorldProbe.MAX_SHAPES and dev.probe._wires.size()<=DebugWorldProbe.MAX_SHAPES,"physics wireframe shows a bounded set of nearby real shapes")
	check(same_json(before,app.session.capture(app.player.capture_pose())) and colliders.size()==world.find_children("*","CollisionShape3D",true,false).size(),"wireframes do not create physics bodies or edit gameplay state")
	check(dev.probe._batches.size()==2,"physics overlays use at most two render batches rather than a node per shape")
	check(dev.probe._batches.any(func(mesh: MeshInstance3D) -> bool: return mesh.visible and mesh.mesh.get_surface_count()>0),"selected shapes produce actual batched line geometry")
	for mesh: MeshInstance3D in dev.probe._batches:
		for surface in mesh.mesh.get_surface_count(): check(mesh.mesh.surface_get_primitive_type(surface)==Mesh.PRIMITIVE_LINES,"only outline geometry is drawn, not filled shape triangles")
	app.player.position.y=20
	app.player.set_pitch(0)
	var target:=StaticBody3D.new()
	target.name="ProbeTarget"
	target.collision_layer=1
	target.collision_mask=0
	var shape:=CollisionShape3D.new()
	shape.name="ProbeTargetShape"
	shape.shape=BoxShape3D.new()
	target.add_child(shape)
	world.add_child(target)
	target.global_position=app.player.camera.global_position-app.player.camera.global_basis.z*2
	await _frames(3)
	dev.probe.bind_world(world)
	var hit:=dev.probe.inspect(app.player.camera,app.player)
	check(hit.get("hit",false) and String(hit.get("collider","")).contains("ProbeTarget") and hit.shape=="ProbeTargetShape" and hit.distance<2,"view ray reports actual closest collider, shape owner and distance: "+str(hit))
	app.fact({"kind":"workbench-test","detail":"find this event"})
	dev.refresh()
	panel.select_page("日志")
	panel._trace_search.text="find this event"
	panel._trace_search.text_changed.emit(panel._trace_search.text)
	check(panel._trace_view.text.contains("workbench-test") and not panel._trace_view.text.contains("collisions"),"event filtering uses details without keeping unrelated rows")
	dev.command("trace_toggle")
	var count:=dev.trace.entries.size()
	app.fact({"kind":"not-recorded"})
	check(dev.trace.entries.size()==count,"paused event capture stops automatic game facts too")
	dev.command("trace_clear")
	check(dev.trace.entries.is_empty(),"clearing the event log does not log its own clear command")
	var previous_size:=root.size
	var previous_scale:=root.content_scale_size
	for viewport: Vector2i in [Vector2i(1280,720),Vector2i(960,540),Vector2i(854,480)]:
		root.size=viewport
		root.content_scale_size=viewport
		await _frames(4)
		for page: String in ["诊断","日志","事件","场景"]:
			panel.select_page(page)
			await _frames(2)
			check(root.get_visible_rect().encloses(panel.get_global_transform()*Rect2(Vector2.ZERO,panel.size)),"expanded tool page fits landscape viewport: %s %s (position %s, size %s, scale %s)" % [page,viewport,panel.position,panel.size,panel.scale])
		check(panel._preview_slider.custom_minimum_size.y*panel.scale.y*absf(root.get_final_transform().get_scale().y)>=44,"compact timeline remains a usable finger target")
	panel.select_page("事件")
	dev.command("preview",{"id":"patrol"})
	panel._scroll.ensure_control_visible(panel._preview_slider)
	await _frames(3)
	await _tap(panel._preview_slider)
	check(dev.preview_paused and dev.preview.k>0,"finger tap on the visible timeline seeks and pauses presentation")
	panel._scroll.ensure_control_visible(panel._preview_pause)
	await _frames(3)
	await _tap(panel._preview_pause)
	check(not dev.preview_paused,"finger tap resumes preview without affecting the gameplay pause state")
	dev.command("clear_preview")
	panel.set_collapsed(true)
	await _frames(2)
	check(panel.size.x<=60 and panel._dot.visible,"richer tools still collapse to the tiny floating ball")
	panel.set_collapsed(false)
	panel.dismiss()
	check(dev.probe.shown==0 and dev.probe._wires.is_empty() and not dev.collision_view,"closing tools removes all collision overlays")
	root.size=previous_size
	root.content_scale_size=previous_scale
	await _dispose(app)
