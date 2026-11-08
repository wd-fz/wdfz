extends "res://tests/support/test_suite.gd"

func _original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/death_models-reference.json.gz").decompress_dynamic(16*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func near(value: Vector3, data: Array, tolerance: float = .0002) -> bool:
	return value.distance_to(Vector3(data[0],data[1],data[2]))<tolerance

func pose(node: Node3D, expected: Dictionary) -> bool:
	var q: Array = expected["q"]
	var rotation := Basis.from_euler(node.rotation,node.rotation_order).get_rotation_quaternion()
	return near(node.position,expected["p"]) and near(node.scale,expected["s"]) and absf(rotation.dot(Quaternion(q[0],q[1],q[2],q[3])))>.99999

func matrices(mesh: MultiMeshInstance3D, expected: Array, label: String) -> void:
	# The headless dummy rendering server does not store MultiMesh transforms.
	# Actual upload/readback is therefore checked by the native-window suite.
	if DisplayServer.get_name()=="headless": return
	var wrong := []
	for i in mini(mesh.multimesh.instance_count,expected.size()):
		var actual := mesh.multimesh.get_instance_transform(i)
		var e: Array = expected[i]
		# Godot Vector3 uses float32; at campus coordinates this can shift near-zero velocity headings by <0.03 degrees.
		if not near(actual.basis.x,e.slice(0,3),.0005) or not near(actual.basis.y,e.slice(4,7),.0005) or not near(actual.basis.z,e.slice(8,11),.0005) or not near(actual.origin,e.slice(12,15)):
			wrong.append(i)
	check(mesh.multimesh.instance_count==expected.size() and wrong.is_empty(),label+" original instance matrices, mismatches: "+str(wrong.slice(0,6)))

func test_geometry() -> void:
	var sample: Dictionary = _original_data()["cases"][2]["geometry"]
	var shape := MothShape.wing()
	var data := shape.surface_get_arrays(0)
	var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var vertices: Array = sample["vertices"]
	var okay := points.size()*3==vertices.size()
	for i in points.size(): okay = okay and near(points[i],vertices.slice(i*3,i*3+3),.000001)
	check(okay,"moth forewing and hindwing use every original quadratic-curve vertex")
	var index: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var area := 0.0
	var expected_area := 0.0
	var original: Array = sample["indices"]
	for i in range(0,index.size(),3):
		area += (points[index[i+1]]-points[index[i]]).cross(points[index[i+2]]-points[index[i]]).length()*.5
	for i in range(0,original.size(),3):
		expected_area += (points[int(original[i+1])]-points[int(original[i])]).cross(points[int(original[i+2])]-points[int(original[i])]).length()*.5
	check(index.size()==original.size() and absf(area-expected_area)<.0000001,"wing triangulation fills the same nonrectangular outline")

func test_deaths() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/death-models/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.camera.position.y = _original_data()["eye"]
	app.player.camera.rotation = Vector3.ZERO
	var before := app.player.capture_pose().duplicate(true)
	var camera := app.player.camera.transform
	for sample: Dictionary in _original_data()["cases"]:
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin(sample["kind"],app.player,app._campus_world(),app.ui,3.5)
		if sample["kind"]=="swarm":
			check(same_json(cg.d["moths"],sample["initial"]),"original seeded moth positions, speed and flap parameters")
		if sample["kind"]=="floor":
			var painted := false
			for mi: MeshInstance3D in cg.d["cup"].find_children("*","MeshInstance3D",true,false):
				for surface in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(surface) as BaseMaterial3D
					painted = painted or (m!=null and m.albedo_texture!=null)
			check(painted,"death cup reuses the original painted model")
		if sample["kind"]=="gaze":
			var visible_through_walls := true
			for eye: MeshInstance3D in cg.d["eyes"]:
				var m := eye.material_override as BaseMaterial3D
				visible_through_walls = visible_through_walls and m.no_depth_test and m.albedo_texture!=null and m.billboard_mode==BaseMaterial3D.BILLBOARD_ENABLED
			check(visible_through_walls,"original gaze sprites have an iris and eyelid and remain visible through walls")
		for frame: Dictionary in sample["frames"]:
			cg.update(frame["t"])
			check(absf(cg.cam.rotation.x-float(frame["view"]["pitch"]))<.0001 and absf(cg.cam.position.y-cg._base_y-float(frame["view"]["eyeLift"]))<.0001,"original death camera: %s %s" % [sample["kind"],frame["t"]])
			var props: Dictionary = frame["props"]
			match sample["kind"]:
				"floor":
					check(pose(cg.d["cup"],props["cup"]) and pose(cg.d["cup"].get_child(0),props["body"]) and pose(cg.d["lid"],props["lid"]),"original cup centre, lid offset and separate rolling: "+str(frame["t"]))
				"gaze":
					var okay := pose(cg.d["smile"],props["smile"])
					for i in props["eyes"].size():
						var eye: MeshInstance3D = cg.d["eyes"][i]
						okay = okay and pose(eye,props["eyes"][i]) and absf(eye.material_override.albedo_color.a-float(props["eyes"][i]["alpha"]))<.00001
					check(okay,"original gaze random positions, opening lids, opacity and approach: "+str(frame["t"]))
				"swarm":
					matrices(cg.d["wingIM"],props["wings"],"death wings at "+str(frame["t"]))
					matrices(cg.d["bodyIM"],props["bodies"],"death bodies at "+str(frame["t"]))
					check(pose(cg.d["glow"],props["glow"]) and absf(cg.d["glow"].material_override.albedo_color.a-float(props["glow"]["alpha"]))<.00001,"original lamp halo position, size and fade")
			check(same_json(before,app.player.capture_pose()),"death prop animation never mutates the saved player pose")
		cg.finish()
		check(app.player.camera.transform.is_equal_approx(camera),"death exit restores the camera for "+sample["kind"])
		cg.queue_free()
		await _frames()
	app.return_to_menu()
	app.queue_free()
	await _frames(2)

func test_weather() -> void:
	for sample: Dictionary in _original_data()["weather"]:
		var weather := WeatherFx.new()
		root.add_child(weather)
		var source := Vector3(1000*CampusGeometry.U2M,0,400*CampusGeometry.U2M)
		weather.setup_moths(source,sample["quality"])
		check(weather._moths.size()==sample["count"] and weather._dust_count==sample["dust"],"original moth and dust budgets at quality "+str(sample["quality"]))
		var okay := true
		for i in weather._moths.size():
			var actual: Dictionary = weather._moths[i]
			var expected: Dictionary = sample["initial"][i]
			okay = okay and near(actual["p"],expected["p"])
			for key: String in ["a","r","sp","ph","fl","h"]: okay = okay and absf(actual[key]-expected[key])<.00001
		check(okay,"original presentation random stream and speed distribution")
		for frame: Dictionary in sample["frames"]:
			weather.update_moths(frame["dt"],source+Vector3(1,1.65,-1),frame["acc"],true)
			matrices(weather._wings,frame["wings"],"weather wings at "+str(frame["acc"]))
			matrices(weather._bodies,frame["bodies"],"weather bodies at "+str(frame["acc"]))
			check(absf(weather.distance-float(frame["distance"]))<.0002,"original moth distance drives the sound without changing exposure")
			okay = true
			for i in weather._dust_count:
				okay = okay and near(weather._dust_p[i],frame["dust"].slice(i*3,i*3+3)) and absf(float(weather._dust_life[i])-float(frame["life"][i]))<.00001
			check(okay,"original dust emission, lifetime and drift")
		weather.free()
