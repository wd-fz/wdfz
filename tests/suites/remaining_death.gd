extends "res://tests/support/test_suite.gd"

func _near(value: Vector3, data: Array) -> bool:
	return value.distance_to(Vector3(data[0],data[1],data[2]))<.0002

func _compare(props: RemainingDeathProps, state: Dictionary, label: String) -> void:
	var issues:=[]
	if props.items.size()!=state.items.size(): issues.append("item count")
	else:
		for i in props.items.size():
			var item:=props.items[i]
			var expected: Dictionary=state.items[i]
			if not _near(item.position,expected.p): issues.append("%d local position %s != %s" % [i,item.position,expected.p])
			if not _near(item.global_position,expected.world): issues.append("%d global position" % i)
			if not _near(item.scale,expected.s): issues.append("%d scale" % i)
			var q: Array=expected.q
			var rotation:=Basis.from_euler(item.rotation,item.rotation_order).get_rotation_quaternion()
			if absf(rotation.dot(Quaternion(q[0],q[1],q[2],q[3])))<.99999: issues.append("%d rotation" % i)
			if item.visible!=expected.v: issues.append("%d visible" % i)
			if expected.has("bounds") and expected.bounds!=null:
				var mesh:=item as MeshInstance3D
				var bounds:=mesh.mesh.get_aabb()
				if not _near(bounds.position,expected.bounds[0]) or not _near(bounds.end,expected.bounds[1]): issues.append("%d bounds" % i)
				var mat:=mesh.material_override as BaseMaterial3D
				if absf(mat.albedo_color.a-expected.alpha)>.00001: issues.append("%d alpha" % i)
				# Names originally bake each tint into 42 merged plate vertices; native uses the same uniform tint.
				if props.kind!="names" and mat.albedo_color.to_html(false)!=expected.color: issues.append("%d color" % i)
		if props.kind=="face":
			var hole: Dictionary=state.items[0].children[1]
			if not _near(props._hole.position,hole.p) or not _near(props._hole.scale,hole.s) or props._hole.visible!=hole.v: issues.append("face hole")
	if props.camera_pitch!=null and absf(float(props.camera_pitch)-state.pitch)>.00001: issues.append("camera")
	check(issues.is_empty(),"original death props %s: %s" % [label,issues.slice(0,5)])

func test_reference() -> void:
	var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/remaining_death-reference.json.gz")
	var reference: Dictionary=JSON.parse_string(bytes.decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	for sample: Dictionary in reference.cases:
		var props:=RemainingDeathProps.new()
		root.add_child(props)
		props.stage(sample.kind,Vector3(sample.feet[0],sample.feet[1],sample.feet[2]),sample.ang)
		_compare(props,sample.initial,"%s %s initial" % [sample.kind,sample.ang])
		var elapsed:=0.0
		for frame: Dictionary in sample.frames:
			elapsed+=frame.dt
			props.present(elapsed,Vector3(frame.feet[0],frame.feet[1],frame.feet[2]),frame.ang)
			_compare(props,frame.state,"%s %s %.2f" % [sample.kind,sample.ang,elapsed])
		props.free()

func test_app() -> void:
	var app: GameApp=APP.instantiate()
	app.saves=SaveStore.new(_test_path)
	app.settings=GameSettings.new(_test_path.get_base_dir()+"/remaining-death-settings.json")
	root.add_child(app)
	await _frames(2)
	app.wuda_roll=func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.set_pitch(.2)
	app.player.rotation.y=.4
	var pose:=app.player.capture_pose()
	var view:=app.player.camera.transform
	for cause: String in RemainingDeathProps.CAUSES:
		var cg:=DeathCG.new()
		app.add_child(cg)
		cg.begin(cause,app.player,app._campus_world(),app.ui,StoryModule.duration(cause))
		check(cg.shots!=null and cg.shots.root!=null,"death dispatcher creates an eye-level scene: "+cause)
		cg.update(1.7)
		check(same_json(pose,app.player.capture_pose()),"death stage keeps gameplay pose independent: "+cause)
		cg.finish()
		check(app.player.camera.transform.is_equal_approx(view) and app._campus_world().visible,"finishing restores camera/world: "+cause)
		cg.queue_free()
		await _frames()
	if DisplayServer.get_name()!="headless":
		app.kill("test","face","debug")
		check(app._death_cg!=null and app._death_cg.shots!=null and app._death_hold==DeathCG.duration("face",0),"actual route death selects the redesigned stage and duration")
		app._death_step(DeathCG.duration("face",0))
		check(app._death_phase=="card" and app._death_cg==null,"actual death ends at the normal record card")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
