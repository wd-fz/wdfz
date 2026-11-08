extends "res://tests/support/test_suite.gd"
## Expectations recorded by running the original Web game, not by the Godot implementation.

var _reference: Dictionary


func load_fixture() -> Dictionary:
	if _reference.is_empty():
		var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/web-reference.json.gz")
		_reference = JSON.parse_string(bytes.decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	return _reference


func test_reference_rules() -> void:
	var data := load_fixture()
	var clock_errors: Array = []
	for row: Array in data["clock"]:
		var t := float(row[0])
		if absf(SchoolClock.rate_at(t) - float(row[1])) > 0.000001 or SchoolClock.need_where(t) != row[2] \
			or SchoolClock.is_night(t) != bool(row[3]) or SchoolClock.fmt_clock(t) != row[4] \
			or absf(SchoolClock.clock_boundary(t) - float(row[5])) > 0.000001:
			clock_errors.append(t)
	check(data["clock"].size() == 2126 and clock_errors.is_empty(), "all 2,126 legacy clock samples agree: %s" % str(clock_errors.slice(0, 8)))
	var motion := CameraMotion.new()
	var camera_errors: Array = []
	for i in data["camera"].size():
		var row: Array = data["camera"][i]
		motion.shake_enabled = bool(row[4])
		var view := motion.advance(float(row[0]), bool(row[1]), bool(row[2]), bool(row[3]), float(row[6]), float(row[5]))
		# Web updates its projection only after a 0.01 degree FOV change; Godot accepts
		# every frame. Keep that documented projection tolerance, not a visual guess.
		if absf(float(view["height"]) - float(row[7])) > 0.00001 or absf(float(view["fov"]) - float(row[8])) > 0.01001 or absf(float(view["near"]) - float(row[9])) > 0.00001:
			camera_errors.append(i)
	check(data["camera"].size() == 360 and camera_errors.is_empty(), "360 legacy camera frames agree through walking, running, sitting, injury and ultrawide view: %s" % str(camera_errors.slice(0, 8)))
	for i in data["quality"].size():
		var q: Dictionary = data["quality"][i]
		check(WeatherFx.RAIN_COUNTS[i] == int(q["rain"]) and WeatherFx.MOTH_COUNTS[i] == int(q["moths"]) and GameSettings.QUALITY_SHADOW[i] == bool(q["shadows"]), "quality %d keeps the legacy rain, swarm and sun-shadow settings" % i)


func test_reference_collision() -> void:
	var data := load_fixture()
	var sphere := SphereShape3D.new()
	sphere.radius = float(data["radius"])
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	query.margin = 0.0
	var total := 0
	for scene: Dictionary in data["scenes"]:
		# Load the production collision adapter without its visual models. Attach its actual
		# bodies to the physics world, so this tests shapes rather than another rectangle formula.
		var world := CampusWorld.new()
		world.scene_id = scene["id"]
		world.layout = CampusData.layout(scene["id"])
		world._build_collision()
		var bodies := world.get_children()
		for node: Node in bodies:
			world.remove_child(node)
			root.add_child(node)
		world.free()
		await _frames(2)
		var mismatches: Array = []
		for sample: Array in scene["points"]:
			query.transform = Transform3D(Basis.IDENTITY, Vector3(float(sample[0]), 1.0, float(sample[1])))
			var blocked := not root.world_3d.direct_space_state.intersect_shape(query, 1).is_empty()
			if blocked != bool(sample[2]):
				mismatches.append(sample)
			total += 1
		check(mismatches.is_empty(), "%s physics agrees with %d original-game samples; mismatches %s" % [scene["id"], scene["points"].size(), str(mismatches.slice(0, 5))])
		for node: Node in bodies:
			node.queue_free()
		await _frames(2)
	check(data["scenes"].size() == 34 and total == 55954, "collision comparison covers 34 planar scenes and 55,954 original-game samples")


func test_camera_lifecycle() -> void:
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(player)
	player.seated = true
	var pose := {"position": [3.0, 0.0, 4.0], "yaw": 0.2, "pitch": 0.3}
	player.restore_pose(pose)
	for i in 120:
		player.update_view(1.0 / 60.0)
	check(absf(player.camera.position.y - 1.12) < 0.0001 and absf(player.camera.rotation.x - 0.24) < 0.0001, "sitting lowers the eye and looks slightly down")
	check(same_json(player.capture_pose(), pose), "camera motion never changes the saved body position or look direction")
	player.apply_look(Vector2(0.0, 0.1))
	check(absf(float(player.capture_pose()["pitch"]) - 0.2) < 0.0001, "turning while seated does not accumulate the seat pitch offset")
	player.seated = false
	player.moving = true
	player.sprinting = true
	for i in 60:
		player.update_view(1.0 / 60.0, 0.25)
	check(player.camera.fov > 80.9, "running expands the actual player's FOV")
	player.view_motion.shake_enabled = false
	player.update_view(1.0)
	check(absf(player.camera.position.y - 1.65) < 0.0001, "turning off camera shake removes bob immediately")
	player.restore_pose(pose)
	check(not player.moving and not player.sprinting and absf(player.camera.position.y - 1.65) < 0.0001 and player.camera.fov == 72.0, "restoring a pose resets old movement, injury and FOV presentation")
	player.queue_free()
	await _frames()


func test_swarm_exposure() -> void:
	var fx := AnomalyFx.new()
	root.add_child(fx)
	var an := {"active": true, "id": "moth", "t": 20.0, "acc": 0.0, "data": {"scene": "out", "src": {"x": 0.0, "y": 0.0}}}
	var eye := Vector3(6, 1.12, 0)
	fx.update(0.05, an, null, "out", Vector3(6,0,0), Vector2.LEFT, eye, true)
	var actual: WeatherFx = fx._extra["swarm"]
	var expected := WeatherFx.new()
	root.add_child(expected)
	expected.setup_moths(Vector3.ZERO)
	expected.update_moths(0.05, eye, 0.0, true)
	check((actual._moths[0]["p"] as Vector3).is_equal_approx(expected._moths[0]["p"]), "long-lived moths with zero exposure stay at their origin instead of closing in")
	an["acc"] = 3.0
	fx.update(0.05, an, null, "out", Vector3(6,0,0), Vector2.LEFT, eye, true)
	expected.update_moths(0.05, eye, 3.0, true)
	check((actual._moths[0]["p"] as Vector3).is_equal_approx(expected._moths[0]["p"]), "the swarm uses nightmare exposure and the real seated camera height")
	check(absf(fx.moth_nearness() - clampf(1.0 - actual.distance / 12.0, 0.0, 1.0)) < 0.00001, "wing sounds use the visible swarm's real distance")
	fx.update(0.01, an, null, "teach1", Vector3.ZERO, Vector2.LEFT)
	check(fx.moth_nearness() == 0.0, "a swarm in another scene cannot keep making nearby wing sounds")
	fx.queue_free()
	expected.queue_free()
	await _frames()
