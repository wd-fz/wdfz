extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/checkup-reference.json.gz").decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func near(actual: Vector3, expected: Array) -> bool:
	return actual.distance_to(Vector3(expected[0],expected[1],expected[2]))<.00001

func compare(node: Node3D, sample: Dictionary, label: String) -> void:
	var q: Array = sample["q"]
	var rotation := Basis.from_euler(node.rotation,node.rotation_order).get_rotation_quaternion()
	check(near(node.position,sample["p"]) and near(node.scale,sample["s"]) and absf(rotation.dot(Quaternion(q[0],q[1],q[2],q[3])))>.99999,label+" original position, rotation and scale")
	check(node.get_child_count()==sample["children"].size(),label+" original child count")
	if sample.has("bounds"):
		var mesh := node as MeshInstance3D
		var bounds := mesh.mesh.get_aabb()
		var mat := mesh.material_override as BaseMaterial3D
		check(near(bounds.position,sample["bounds"][0]) and near(bounds.end,sample["bounds"][1]),label+" original geometry bounds")
		check(mat.albedo_color.to_html(false)==sample["color"] and (sample.get("emission")==null or mat.emission.to_html(false)==sample["emission"]),label+" original colour and emission")
		check((mat.albedo_texture!=null)==sample["texture"],label+" original mapped surface")
		if sample["emissionMap"]:
			check(mat.emission_texture==mat.albedo_texture and mat.emission_operator==BaseMaterial3D.EMISSION_OP_MULTIPLY,label+" original emissive texture multiplication")
	for i in mini(node.get_child_count(),sample["children"].size()): compare(node.get_child(i),sample["children"][i],label+"/"+str(i))

func test_original_props() -> void:
	var data := original_data()
	check(same_json(CheckupProps.LINES,data["lines"]),"all five original eye-chart risk lines are available")
	for frame: Dictionary in data["frames"]:
		var props := CheckupProps.new()
		props.build(CampusData.layout("admin1"),frame["line"])
		root.add_child(props)
		for i in 4: compare(props.get_child(i),frame["props"][i],"medical prop "+str(i))
		var chart: MeshInstance3D = props.get_child(2)
		var material := chart.material_override as BaseMaterial3D
		check(material.albedo_texture.resource_path.ends_with("checkup-chart-%d.png" % int(frame["index"])) and material.emission_texture==material.albedo_texture,"eye chart chooses the matching original canvas and emission map")
		props.free()

func test_world() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/checkup-props/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.travel("admin1",_campus_pose(CampusData.layout("admin1"),CampusGeometry.tile_center(CampusData.layout("admin1"),6,18),0),false)
	var world := app._campus_world()
	world.show_checkup(true,true,CheckupProps.LINES[0])
	check(world._checkup.get_node_or_null("MedicalProps") is CheckupProps and world._checkup_queue.get_child_count()==10,"real medical scene retains five original people and their five collision shapes")
	world.show_checkup(true,false,CheckupProps.LINES[0])
	await _frames(2)
	check(not world._checkup_queue.visible and not world.checkup_queue_blocks(),"outside queue time removes the actual collision with the people")
	var previous := world._checkup
	world.show_checkup(true,false,CheckupProps.LINES[4])
	await _frames(2)
	check(not is_instance_valid(previous) and world._checkup_line==CheckupProps.LINES[4],"changing the day's chart replaces and releases its old props")
	world.show_checkup(false,false,"")
	await _frames(2)
	check(world._checkup==null,"leaving the checkup day removes its presentation")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
