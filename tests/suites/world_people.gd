extends "res://tests/support/test_suite.gd"
## Independent Web frame captures, adjusted only for FigureModel's -Z front.

func original_frames() -> Dictionary:
	var data := FileAccess.get_file_as_bytes("res://tests/fixtures/world_people-reference.json.gz")
	return JSON.parse_string(data.decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func v3(p: Array) -> Vector3:
	return Vector3(p[0],p[1],p[2])

func material(fig: Node3D) -> StandardMaterial3D:
	return fig.find_children("*","MeshInstance3D",true,false)[0].material_override

func appearance(fig: Node3D, old: Dictionary) -> void:
	check(fig.get_child(0).scene_file_path.ends_with("/"+String(old["kind"])+".glb") and fig.scale.distance_to(v3(old["scale"]))<.00001,"original person asset and scale: %s / %s" % [fig.get_child(0).scene_file_path,fig.scale])
	var mat := material(fig)
	check(mat.albedo_color.is_equal_approx(Color(old["color"])) and (mat.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED)==old["unlit"] and mat.disable_fog==not old["fog"] and mat.vertex_color_use_as_albedo==old["vertexColors"],"original colour, lighting, fog and vertex tint flag")
	if old["emission"]!=null:
		check(mat.emission_enabled and mat.emission.is_equal_approx(Color(old["emission"])),"original faint emissive silhouette")

func transform_matches(fig: Node3D, old: Dictionary) -> void:
	check(fig.position.distance_to(v3(old["p"]))<.0001,"original world placement")
	var facing := Vector3(sin(old["yaw"]),0,cos(old["yaw"]))
	check((-fig.basis.z).normalized().distance_to(facing)<.00001,"original facing after +Z to -Z model conversion")

func test_app() -> void:
	var old := original_frames()
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/people/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.travel("out",_campus_pose(null,Vector2(1080,900),0),false)
	var visit := app.exchange()
	for sample: Dictionary in old["exchange"]:
		var path: Dictionary = sample["path"].duplicate(true)
		path["pts"] = path["pts"].map(func(p: Array) -> Vector2: return Vector2(p[0],p[1]))
		visit.s["path"] = path
		visit.s["phase"] = sample["phase"]
		visit.s["prog"] = sample["progress"]
		visit.s["search"] = [{"x":1000,"y":800},{"x":1040,"y":700},{"x":900,"y":500}] if sample["phase"]=="escort" else []
		app._show_visit(visit)
		for i in 7:
			var fig := app._visit_nodes.get_child(i) as Node3D
			var expected: Dictionary = sample["figures"][i]
			appearance(fig,expected)
			check(fig.visible==expected["visible"],"searchers are visible only during escort")
			if fig.visible: transform_matches(fig,expected)
	visit.s["phase"] = "over"
	app._show_visit(visit)
	check(app._visit_nodes==null,"group is removed when the visit is over")
	app.travel("admin1",CampusData.rules().default_spawn("admin1"),false)
	for sample: Dictionary in old["gaze"]:
		var room: Dictionary = CampusData.rules().room(sample["room"])
		var win: Dictionary = sample["window"]
		app.player.restore_pose(_campus_pose(room,Vector2(sample["player"][0],sample["player"][1]),0))
		app.gaze().s["ev"] = {"room":sample["room"],"c":win["c"],"r":win["r"]}
		app.gaze().set_context(app._gaze_context())
		var before := app.session.capture(app.player.capture_pose()).duplicate(true)
		app._show_gaze(app.gaze())
		var view := app._gaze_nodes
		var body := view.get_child(0) as Node3D
		appearance(body,sample["body"])
		check(body.global_position.distance_to(v3(sample["body"]["p"]))<.00001,"window body retains its original floor and glass offset")
		var expected_front := Vector3(sin(sample["body"]["yaw"]),0,cos(sample["body"]["yaw"]))
		check((-body.global_basis.z).normalized().distance_to(expected_front)<.00001,"body faces into the room at either outer wall")
		var eye: MeshInstance3D = view.eyes.get_child(0)
		check(view.eyes.global_position.distance_to(v3(sample["eyes"]["p"]))<.00001 and view.eyes.global_basis.z.normalized().distance_to(v3(sample["eyes"]["direction"]))<.00001,"eyes at the glass follow the player at three lateral positions")
		check(absf(eye.mesh.radius-sample["eyes"]["size"])<.00001 and eye.scale.distance_to(v3(sample["eyes"]["scale"]))<.00001 and eye.material_override.albedo_color.is_equal_approx(Color(sample["eyes"]["color"])) and eye.material_override.disable_fog,"original flattened eye shape and fog-independent colour")
		check(same_json(before,app.session.capture(app.player.capture_pose())),"visual tracking never changes gaze rules or saved player pose")
	app.gaze().s["ev"] = null
	app._show_gaze(app.gaze())
	check(app._gaze_nodes==null,"ended gaze removes both figure and eyes")
	var fake: Dictionary = old["fake"]
	var classroom: Dictionary = CampusData.rules().room(fake["room"])
	app.travel(fake["room"],_campus_pose(classroom,Vector2(fake["player"][0],fake["player"][1]),0),false)
	app.fake_normal().fn["on"] = true
	app.fake_normal().fn["v"] = 10
	app._fake_people_random.seed = 42
	app._fake_people_step(app.fake_normal(),classroom)
	check(app._fake_people.get_child_count()==4,"fake-normal day supplies four figures on open tiles")
	for fig: Node3D in app._fake_people.get_children():
		appearance(fig,fake["figures"][0]["body"])
		var to_player := app.player.position-fig.position
		to_player.y = 0
		check(to_player.length()>=2.2 and to_player.length()<=7.5 and (-fig.basis.z).normalized().dot(to_player.normalized())>.9999,"fake-normal figures face the player at the original range")
	app.fake_normal().fn["v"] = 72
	app._fake_people_step(app.fake_normal(),classroom)
	check(app._fake_people==null,"figures disappear at exactly 72 laughs")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)

func test_inspection_and_checkup() -> void:
	var old := original_frames()
	var world := CampusWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.scene_id = "admin1"
	var sample: Dictionary = old["inspection"]
	var room: Dictionary = CampusData.rules().room("admin1")
	var player_scene := CampusGeometry.to_scene(room,Vector2(sample["player"][0],sample["player"][1]))
	world.set_player_scene(Vector3(player_scene.x,0,player_scene.y))
	var points: Array = sample["points"].map(func(p: Dictionary) -> Array: return [p["x"],p["y"]])
	world.show_silhouettes(points,room,0)
	for i in sample["figures"].size():
		var expected: Dictionary = sample["figures"][i]
		var fig := world._silhouettes.get_child(i) as Node3D
		appearance(fig,expected["body"])
		check(fig.position.distance_to(v3(expected["p"]))<.00001 and (-fig.basis.z).normalized().distance_to(Vector3.BACK)<.00001,"inspection originals stand at the sampled points")
	# Scatter must use the original spawn directions even if a penalized player moved during the check.
	world.set_player_scene(Vector3(200,0,-200))
	world.show_silhouettes([],room,0)
	for frame: Dictionary in sample["frames"]:
		world._process(.2)
		if frame["figures"].is_empty():
			check(world._scatter==null,"inspection scatter finishes after the original 0.8 seconds")
			continue
		for i in frame["figures"].size():
			var fig := world._scatter.get_child(i) as Node3D
			check(fig.position.distance_to(v3(frame["figures"][i]["p"]))<.00001 and absf(material(fig).albedo_color.a-frame["figures"][i]["alpha"])<.00001,"inspection scatter follows original movement and opacity frames")
	world.show_checkup(true,true,"reference")
	for i in old["checkup"].size():
		var fig := world._checkup_queue.get_child(i*2) as Node3D
		appearance(fig,old["checkup"][i])
		transform_matches(fig,old["checkup"][i])
		check((world._checkup_queue.get_child(i*2+1) as CollisionShape3D).shape!=null,"queue retains physical collision with the restored figure")
	check(world.checkup_queue_blocks(),"active queue blocks the corridor")
	world.show_checkup(true,false,"reference")
	check(not world.checkup_queue_blocks() and not world._checkup_queue.visible,"queue removal disables both collision and visible figures")
	world.show_checkup(false,false,"")
	check(not world.checkup_shown(),"ordinary day clears the medical scene")
	world.queue_free()
	await _frames(3)
