extends "res://tests/support/test_suite.gd"

const SPECIAL := ["lift_lab", "lift_teach", "dream_top", "lift_dream"]


static func reading_pose(site: Dictionary, distance: float = 1.08) -> Dictionary:
	var normal: Vector2 = site.normal
	var point: Vector2 = site.anchor + normal * distance
	return {"position": [point.x, site.base + 0.045, point.y], "yaw": CampusGeometry.yaw_from_ang((-normal).angle()), "pitch": 0.0}


func test_sites() -> void:
	var rules := CampusData.make_module()
	var book := InvestigationModule.new()
	book.reset()
	book.focus = "car"
	var ids := {}
	var worlds := CampusData.rooms().keys() + ["out"]
	for world: String in worlds:
		var sites := rules.observations(world)
		if world in SPECIAL:
			check(sites.is_empty(), world + " retains its own panel or spatial puzzle")
			continue
		check(not sites.is_empty(), world + " has an observation")
		for site: Dictionary in sites:
			check(not ids.has(site.id), "unique physical observation " + site.id)
			ids[site.id] = true
			var pose := reading_pose(site)
			check(rules.hint(world, pose).contains(site.title), world + " visible label and use target agree")
			check(rules.interact_at(world, pose).get("observation", {}).get("id") == site.id, "read " + site.id)
			check(rules.observation_at(world, reading_pose(site, -0.7)).is_empty(), "cannot read back of " + site.id)
			check(rules.observation_at(world, reading_pose(site, 2.5)).is_empty(), "cannot read across room " + site.id)
			var looking_away := pose.duplicate(true)
			looking_away.yaw += PI
			check(rules.observation_at(world, looking_away).is_empty(), "turn away from " + site.id)
			looking_away = pose.duplicate(true)
			looking_away.pitch = PI / 2
			check(rules.observation_at(world, looking_away).is_empty(), "looking at ceiling clears " + site.id)
			if CampusObservations.INDOORS.has(world):
				var d: Array = CampusObservations.INDOORS[world]
				var room: Dictionary = rules.room(world)
				var wall := Vector2i(CampusGeometry.NORMALS[d[2]])
				check(room.grid[d[1]][d[0]] == "." and room.grid[d[1] + wall.y][d[0] + wall.x] == "#", world + " mounted on the visitor side of a wall")
			book.set_context({"day": 2, "place": world})
			book.observe(site)
			book.take_events()
			if site.id in ["lab1", "stair_teach_w"]: book.choose(2)
	check(book.list().found == ids.size() and book.focus == "car", "finding every object leaves the chosen route intact")
	var saved := book.capture()
	var restored := InvestigationModule.new()
	restored.restore(saved)
	check(restored.validate(saved).is_empty() and restored.list("试音带").found == 1 and restored.paper_sample() == "", "ordinary observations persist and remain searchable before the punch")
	var older_notebook := saved.duplicate(true)
	older_notebook.entries["campus:teach1"].text = "旧版换座申请"
	restored.restore(older_notebook)
	check(restored.entries == saved.entries and restored.recent == saved.recent, "an old seating note gets today's exhibit text and keeps its original discovery details")
	restored.restore({})
	check(not restored.visible("campus:teach1"), "loading an unexplored classroom does not reveal the seating note")
	var terminal := CampusTerminal.fresh("fieldwork")
	var incident: String = CampusTerminal.run(terminal, "cat /school/shift.txt").text
	check(incident.contains("姓名栏找到了答题的人") and incident.contains("楼梯间只剩测绘时的录音"),
		"the local report identifies the exam link and the source of the stairwell voice")
	var lab_site: Dictionary = rules.observations("lab1")[0]
	for choice in 2:
		var trial := InvestigationModule.new()
		trial.restore(saved)
		trial.observe(lab_site)
		trial.choose(choice)
		var selected := trial.paper_sample()
		check(selected == ("甲" if choice == 0 else "乙"), "one punch chooses the visible sheet")
		var round_trip: Dictionary = JSON.parse_string(JSON.stringify(trial.capture()))
		trial.restore(round_trip)
		trial.observe(lab_site)
		trial.choose(1 - choice)
		check(trial.paper_sample() == selected, "saving and rereading cannot punch a second sheet")
		for id: String in RoutesModule.ENDINGS:
			var card := RoutesModule.card(id, null, selected)
			var confirmed: bool = RoutesModule.ENDINGS[id].get("true", false)
			check(card.evidence.has("sample") == confirmed, id + " only a witnessed waking can show the real box")
			if confirmed:
				var joined := "".join(card.lines)
				check(joined.contains("甲纸上边少了半圆" if choice == 0 else "甲、乙两张纸的上边都很平"), id + " physical result follows pairing")
			check(not RoutesModule.card(id).evidence.has("sample"), id + " archive/default card cannot invent an experiment")
	var props := ObservationProps.new()
	props.build("lab1", [lab_site], Callable())
	var intact: Mesh = props._samples[0].mesh
	props.set_sample("乙")
	check(props._samples[0].mesh == intact and props._samples[1].mesh != intact and props._samples[1].mesh.get_faces().size() > intact.get_faces().size(), "only the chosen model sheet has a physical cutout")
	props.set_sample("")
	check(props._samples[1].mesh == intact, "a fresh session removes the previous notch")
	props.free()
	var broken := saved.duplicate(true)
	for key: String in ["paper:lesson:A", "paper:lesson:B"]: broken.entries[key] = {"text":"", "kind":"验证"}
	check(not restored.validate(broken).is_empty(), "a damaged save cannot certify two choices for the same punch")


func _command(sim: CooperativeSimulation, id: String, action: String, extra: Dictionary = {}) -> Dictionary:
	var payload := {"seq": sim.actor(id).command_sequence + 1, "scene": sim.actor(id).scene_version, "action": action, "epoch": sim.room.epoch}
	payload.merge(extra)
	var result := sim.command(id, payload)
	check(result.get("ok", false), "%s %s accepted: %s" % [id, action, result.get("error", "")])
	return result


func test_authority() -> void:
	var room := CooperativeRoom.new()
	room.add_member("a", "房主", true)
	room.add_member("b", "同学")
	room.ready("a", true, "none")
	room.ready("b", true, "none")
	room.begin("campus-paper")
	room.loaded("a")
	room.loaded("b")
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 36)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	var book := sim.actor("a").feature(&"story.investigation") as InvestigationModule
	var worlds := CampusData.rooms().keys() + ["out"]
	for world: String in worlds:
		for site: Dictionary in sim.campus().observations(world):
			var pose := reading_pose(site)
			sim.travel(sim.actor("b"), world, pose)
			await _frames(1)
			var frame := sim.physics.geometry[world] as CampusWorld
			var physics := frame.get_world_3d().direct_space_state
			var p: Array = pose.position
			var feet := Vector3(p[0], p[1], p[2])
			query.transform = Transform3D(Basis.IDENTITY, frame.to_global(feet + Vector3.UP * 0.91))
			check(physics.intersect_shape(query, 1).is_empty(), "reader's capsule fits at " + site.id)
			var anchor: Vector2 = site.anchor + site.normal * 0.07
			var at := Vector3(anchor.x, site.base + (0.89 if world in ["link1", "link2"] else 1.5), anchor.y)
			var ray := PhysicsRayQueryParameters3D.create(frame.to_global(feet + Vector3.UP * 1.58), frame.to_global(at), 1)
			check(physics.intersect_ray(ray).is_empty(), "actual wall and fixtures leave the front visible at " + site.id)
			_command(sim, "b", "interact")
			check(book.visible("campus:" + String(site.id)), "normal authoritative E reaches " + site.id)
			if site.id == "lab1" and not sim.actor("b").choice.is_empty():
				_command(sim, "b", "choice", {"index": 2, "choice_id": sim.actor("b").choice.id})
			if site.id == "stair_teach_w" and not sim.actor("b").choice.is_empty():
				_command(sim, "b", "choice", {"index": 1, "choice_id": sim.actor("b").choice.id})
				check(book.visible("landing:star") and sim.actor("b").school().seat_card.stair_promise and not sim.actor("a").school().seat_card.stair_promise, "the group can read the reply and only the speaker makes the promise")
	var lab := reading_pose(sim.campus().observations("lab1")[0])
	for id: String in ["a", "b"]: sim.travel(sim.actor(id), "lab1", lab)
	_command(sim, "b", "interact")
	_command(sim, "a", "interact")
	check(not sim.actor("b").choice.is_empty() and sim.actor("a").choice.is_empty(), "only one participant holds the shared punch")
	if not sim.actor("b").choice.is_empty():
		_command(sim, "b", "choice", {"index": 1, "choice_id": sim.actor("b").choice.id})
	check(book.paper_sample() == "乙", "a guest's control choice is authoritative")
	_command(sim, "a", "interact")
	check(sim.actor("a").choice.is_empty() and book.paper_sample() == "乙", "host sees already punched control sheet")
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.capture()))
	sim.restore(data)
	for id: String in ["a", "b"]:
		var restored := sim.actor(id).feature(&"story.investigation") as InvestigationModule
		check(restored.paper_sample() == "乙" and restored.visible("campus:out.north"), "team checkpoint restores fieldwork for " + id)
		check(sim.actor(id).school().seat_card.stair_promise == (id == "b"), "personal promise survives the checkpoint for " + id)
	sim.queue_free()
	await _frames(2)


func test_player() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/fieldwork/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	app.settings.set_value("quality", 0)
	root.add_child(app)
	await _frames(2)
	app.start_new_game()
	await _until_started(app)
	await _frames(3)
	app._stand_up()
	for world: String in ["teach1", "out", "stair_teach_w", "link2", "lab1"]:
		var site: Dictionary = app.campus().observations(world)[0]
		app.travel(world, reading_pose(site), false)
		await _frames(5)
		if app.session.world_id != world: await _until_world(app, world)
		app._hint_cooldown = 0.0
		app._refresh_interaction_prompt()
		var prompt := app.ui.get_node("%Prompt") as Label
		check(prompt.text.contains(site.title) and prompt.anchor_top > 0.8, world + " HUD leaves the lettering and paper edges visible")
		check(is_instance_valid(app._campus_world().observation_props), world + " exhibits appear in the real streamed world")
		app.player.request_interaction()
		check(app.investigation().visible("campus:" + String(site.id)), world + " input reaches notebook")
		if CampusObservations.INDOORS.has(world):
			var coords: Array = CampusObservations.INDOORS[world]
			check(app._map_label(app.campus().room(world), coords[0], coords[1]) == "记", world + " records the inspected wall on its floor sketch")
		if world == "stair_teach_w" and app.ui.choice_open():
			app._choice_made(0)
			check(app.investigation().visible("landing:knock") and app.school().seat_card.stair_promise, "the stairwell answers this player's timing and remembers the promise")
	check(app.ui.choice_open(), "the lab offers both sheets and a way to leave")
	if app.ui.choice_open(): app._choice_made(0)
	app._sync_world(false)
	check(app.investigation().paper_sample() == "甲" and app._campus_world().observation_props._selected == "甲", "the actual lab mesh follows the player's choice")
	app.save_game(true)
	app.load_game()
	await _frames(4)
	check(app.investigation().paper_sample() == "甲", "normal game save retains model sample")
	await app._reach_ending("dismissal")
	if is_instance_valid(app._ending_cut):
		var cut := app._ending_cut
		cut._apply(12.7 / 18)
		check(cut._dis_desk.visible and not cut._world.visible, "the broadcast returns to the real classroom before the gate")
		cut._apply(14.7 / 18)
		var hidden := cut._dis_model_props.duplicate()
		check(not cut._dis_desk.visible and cut._world.visible and not hidden.is_empty() and hidden.all(func(n: Node3D) -> bool: return not n.visible), "only the physical campus appears after school")
		cut.end(true)
		check(hidden.all(func(n: Node3D) -> bool: return n.visible), "skipping the gate shot restores exactly the borrowed visibility")
	check(app.ui._ending_text.text.contains("甲纸上边少了半圆") and app.ui._ending_papers.visible and app.ui._ending_papers._samples == "甲", "the normal ending screen displays the real sheets the player earned")
	check(not app.ui.hud.visible and not app.ui.touch_controls.visible, "the simulated clock, location, and controls stay off the physical evidence")
	app.queue_free()
	await _frames(3)
