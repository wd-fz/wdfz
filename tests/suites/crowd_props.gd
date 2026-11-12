extends "res://tests/support/test_suite.gd"

func original_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_bytes("res://tests/fixtures/crowd_props-reference.json.gz").decompress_dynamic(32*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())

func test_frames() -> void:
	var original := original_data()
	var comparison := preload("res://tests/suites/death_timelines.gd").new(_runner)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/crowd-props/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.player.global_position = Vector3.ZERO
	app.player.rotation.y = CampusGeometry.yaw_from_ang(original["baseAng"])
	app.player.camera.position.y = original["eye"]
	app.player.camera.rotation = Vector3.ZERO
	var saved := app.player.capture_pose().duplicate(true)
	var camera := app.player.camera.transform
	var window_size := root.size
	for sample: Dictionary in original["cases"]:
		root.size = Vector2i(sample["size"][0],sample["size"][1])
		await _frames(2)
		var cg := DeathCG.new()
		app.add_child(cg)
		app.player.camera.fov = sample["frames"][0]["fov"]
		cg.begin("crowd",app.player,app._campus_world(),app.ui,4.2,sample["shake"]==0)
		for frame: Dictionary in sample["frames"]:
			cg.update(frame["t"])
			var label := "crowd %s shake=%s t=%s" % [sample["size"],sample["shake"],frame["t"]]
			var errors := []
			for key: String in frame["props"]:
				comparison.compare(cg.d["segs"].values() if key=="segs" else cg.d.get(key),frame["props"][key],key,errors)
			# The old fx hand frames keep their transforms and timing (compared above); inside each, the
			# low-poly fx mesh became a jointed HorrorKit shadow hand, still near-black and fogged.
			for i in cg.d["hands"].size():
				var frame_node: Node3D = cg.d["hands"][i]
				if frame_node.get_child_count()!=1 or not frame_node.get_child(0).has_meta("horror_hand"): errors.append("hand model")
				else:
					for mesh: MeshInstance3D in frame_node.get_child(0).find_children("*","MeshInstance3D",true,false):
						var material := mesh.material_override as ShaderMaterial
						if material==null or (material.get_shader_parameter("base_color") as Color).get_luminance()>.05: errors.append("hand material")
			check(errors.is_empty(),label+" original props/materials: "+str(errors.slice(0,8)))
			check(absf(cg.cam.rotation.x-float(frame["view"]["pitch"]))<.0001 and absf(cg.cam.rotation.y+float(frame["view"]["ang"])-float(original["baseAng"]))<.0001 and absf(cg.cam.position.y-cg._base_y-float(frame["view"]["eyeLift"]))<.0001,label+" original camera")
			check(absf(cg.veil_mesh.material_override.albedo_color.a-float(frame["shade"]))<.00001,label+" original closing shade")
		var display: MeshInstance3D = cg.d["full"]
		check((display.mesh as QuadMesh).size.is_equal_approx(Vector2(.19,.07)) and display.material_override.albedo_texture.resource_path=="res://assets/campus/crowd/full.png","death display uses the original canvas and plane size")
		cg.finish()
		check(same_json(saved,app.player.capture_pose()) and app.player.camera.transform.is_equal_approx(camera),"crowd restores the player and camera")
		cg.queue_free()
		await _frames()
	# Hands must stay relative to the camera when the player is elsewhere in the campus.
	var poses := [Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,.7),Vector3(20,4,-12))]
	var relative := []
	for pose: Transform3D in poses:
		app.player.transform = pose
		var cg := DeathCG.new()
		app.add_child(cg)
		cg.begin("crowd",app.player,app._campus_world(),app.ui,4.2)
		cg.update(2.4)
		var actual := []
		for hand: Node3D in cg.d["hands"]: actual.append(hand.transform)
		if relative.is_empty(): relative=actual
		else:
			for i in actual.size(): check(actual[i].is_equal_approx(relative[i]),"hand remains in the same view-relative pose after a world translation/turn")
		cg.finish()
		cg.queue_free()
		await _frames()
	var sign := LiftCrowdFx.display_face(.26,.1)
	var texture: Texture2D = sign.material_override.albedo_texture
	check(texture.get_width()==original["textureSize"][0] and texture.get_height()==original["textureSize"][1] and (sign.mesh as QuadMesh).size.is_equal_approx(Vector2(.26,.1)),"real cabin and cinematic share the original 256 by 96 canvas")
	sign.free()
	app.return_to_menu()
	app.queue_free()
	root.size = window_size
	await _frames(2)
