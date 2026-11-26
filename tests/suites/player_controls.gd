extends "res://tests/suites/touch_ui.gd"


func test_seated_prompt() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/seat-prompt.json")
	app.settings = GameSettings.new(_test_path.get_base_dir()+"/seat-prompt-settings.json")
	app.settings.set_value("quality", 0)
	root.add_child(app)
	await _frames(3)
	app.ui.set_touch_enabled(true)
	app.start_new_game("hard", "none", "xu")
	await _frames(3)
	app._update_minimap()
	check(app.ui.minimap.visible and app.ui.minimap._room.id == "teach1", "the HUD map opens on the current floor")
	check(app.ui.minimap._floor_turn == 2 and app._floor_map_turn(app.campus().room("lift_teach")) == 2 and app._floor_map_turn(app.campus().room("lift_lab")) == 0, "the floor maps show physical north inside each building and its elevator")
	await _tap(app.ui.minimap)
	check(is_instance_valid(app.ui.map_panel) and app.ui.map_panel.visible and not app.player.enabled, "tapping the HUD map opens its floor and suspends movement")
	app.ui._close_map()
	app._show_notes()
	app.ui.notes_panel.set_page("rules")
	var notes: Array[Node] = app.ui.notes_panel.entries.find_children("*", "Label", true, false)
	check(notes.any(func(label: Label) -> bool: return label.text.contains("许棠") and label.text.contains("广播站") and label.text.contains("答完六科综合测验") and label.text.contains("底联")), "the notes let the selected student reread her memory, signed exam and first lead")
	check(app.investigation_brief().contains("北门旁的保安岗") and app.investigation().entries.is_empty() and app.school().seat_card.proof.is_empty(), "the background explains the first destination without silently granting evidence")
	app.ui.notes_panel.dismiss()
	var prompt := app.ui.get_node("%Prompt") as Label
	var wrong: Array[String] = []
	for i in 30:
		await _frames(1)
		if prompt.text != "交互 · 站起来": wrong.append(prompt.text)
	check(wrong.is_empty(), "seated prompt stays stand-up across every nearby-search refresh: %s" % str(wrong))
	check(app.school().seated, "observing the prompt never leaves the chair")
	app.ui.touch_look.emit(Vector2(0, 2000))
	await _frames(2)
	check(prompt.text.contains("名牌") and app._mates_nodes._card_text.text == StudentCast.PEOPLE[app.session.character_id]["name"], "looking down reveals the current character's named desk card")
	await _tap(app.ui.get_node("%TouchInteract"))
	check(app.ui.choice_open() and app.investigation().visible("desk"), "touching the card opens the real offer and records the piece of evidence")
	app._choice_made(0)
	await _frames(2)
	check(app.school().seat_card.armed == "1:0" and app._mates_nodes._card_fold == 1, "the confirmed card visibly stands on its desk")
	app.player.set_pitch(0)
	await _frames(2)
	await _tap(app.ui.get_node("%TouchInteract"))
	check(not app.school().seated and not app.player.seated, "the displayed stand-up action actually leaves the seat")
	await _frames(10)
	check(prompt.text != "交互 · 站起来", "standing restores the nearby action instead of leaving a stale seat prompt")
	var view := app._mates_nodes
	var seat := "teach1:49:11"
	var room := CampusData.layout("teach1")
	var point := CampusGeometry.tile_center(room, 49, 11)
	view.show_seat_witness(seat, "xu", point, 6)
	var echo: StudentAvatar = view._echoes[seat]["node"]
	check(echo.character == "xu" and echo.clip == "sit" and echo.find_children("*", "CollisionShape3D",true,false).is_empty(), "a witness sees the borrower's seated model without a body collider")
	view.advance(.1, point, 0, null, false, false, null)
	check(view._echoes.is_empty() and not echo.visible, "walking up to the seat makes the figure vanish immediately")
	view.show_seat_witness(seat, "xu", point, .1)
	view.advance(.11, point + Vector2(20,0), 0, null, false, false, null)
	check(view._echoes.is_empty(), "the figure also disappears when watched from a distance")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)


func test_touch_sprint() -> void:
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.size = Vector2i(1280, 720)
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	var player: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	collision.position.y = -0.5
	floor_body.add_child(collision)
	root.add_child(floor_body)
	root.add_child(player)
	root.add_child(ui)
	await _frames(3)
	ui.touch_move.connect(player.set_touch_move)
	ui.touch_sprint.connect(player.set_touch_sprint)
	player.touch_sprint_changed.connect(ui.show_touch_sprint)
	ui.touch_look.connect(player.look_from_touch)
	player.enabled = true
	ui.set_mode("play")
	ui.set_touch_enabled(true)
	await _frames(3)
	var sprint := ui.get_node("%TouchSprint") as Button
	var stick_point := ui.stick.get_global_rect().get_center() + Vector2(0, -ui.stick.size.y * 0.4)
	await _finger(0, stick_point, true)
	await _frames(4)
	var walk_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.moving and not player.sprinting and absf(walk_velocity-player.walk_speed) < 0.01,
		"full touch stick walks with sprint off (speed %.3f)" % walk_velocity)
	var button_point := sprint.get_global_rect().get_center()
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	await _frames(3)
	var run_velocity := Vector2(player.velocity.x, player.velocity.z).length()
	check(sprint.button_pressed and player.sprinting and absf(run_velocity-player.sprint_speed) < 0.01,
		"second finger enables real sprint while first holds the stick (speed %.3f)" % run_velocity)
	check(ui.stick._finger == 0 and ui.movement_touch().length() > 0.96,
		"tapping sprint does not release or hijack the movement finger")
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	await _frames(3)
	check(not sprint.button_pressed and not player.sprinting and absf(Vector2(player.velocity.x,player.velocity.z).length()-player.walk_speed) < 0.01,
		"second tap returns to walking even with the stick fully pushed")
	await _finger(0, stick_point, false)
	# Primary taps must still toggle exactly once (never twice through mouse emulation).
	await _tap(sprint)
	check(sprint.button_pressed and player._touch_sprint, "a primary-finger sprint tap toggles exactly once")
	await _tap(sprint)
	check(not sprint.button_pressed and not player._touch_sprint, "a primary-finger second tap turns sprint off")
	# The view, stick and run button each retain their own finger.
	var look_point := Vector2(540,240)
	await _finger(0, stick_point, true)
	await _finger(2, look_point, true)
	await _drag(2, look_point+Vector2(20,0), Vector2(20,0))
	var yaw := player.rotation.y
	await _finger(1, button_point, true)
	await _finger(1, button_point, false)
	check(sprint.button_pressed and ui.look_pad._finger == 2 and ui.stick._finger == 0,
		"three fingers can move, look and toggle sprint without stealing ownership")
	await _drag(2, button_point, Vector2(20,0))
	check(player.rotation.y != yaw and sprint.button_pressed, "dragging the look finger over sprint still looks instead of toggling it")
	await _finger(2,button_point,false)
	player.can_sprint = false
	ui.show_sprint_available(false)
	await _frames(3)
	check(not player.sprinting and sprint.text == "暂不能跑" and sprint.button_pressed,
		"exhaustion/injury blocks running and explains the still-enabled toggle")
	player.can_sprint = true
	ui.show_sprint_available(true)
	await _frames(3)
	check(player.sprinting and sprint.text == "奔跑：开", "running resumes when the player's stamina or injury permits it")
	ui.set_mode("pause")
	check(not sprint.button_pressed and not player._touch_sprint and player._touch_move == Vector2.ZERO,
		"pausing clears held movement and the run toggle together")
	await _finger(0,stick_point,false)
	ui.set_mode("play")
	await _finger(1,button_point,true)
	await _finger(1,button_point+Vector2(-200,0),false)
	check(not sprint.button_pressed, "releasing a button finger outside cancels the tap")
	await _tap(sprint)
	player.restore_pose(player.capture_pose())
	check(not sprint.button_pressed and not player._touch_sprint,
		"restoring a pose or changing scenes cannot leave a lit sprint toggle with no running input")
	player.enabled = false
	await _tap(sprint)
	check(not sprint.button_pressed and not player._touch_sprint, "a rejected tap while gameplay is disabled cannot light the run toggle")
	player.enabled = true
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(3)
	check(player.sprinting, "desktop Shift still enables running")
	Input.action_release("sprint")
	await _frames(3)
	check(not player.sprinting and player.moving, "releasing Shift restores walking")
	Input.action_release("move_forward")
	ui.queue_free()
	player.queue_free()
	floor_body.queue_free()
	await _frames(3)
	root.size = old_size
	root.content_scale_size = old_scale


func test_west_gate_walk(attendance: String = "ink") -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/west-gate-" + attendance + "/save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/west-gate/settings.json")
	app.settings.set_value("quality", 0)
	root.add_child(app)
	await _frames(2)
	app.start_new_game()
	await _frames(3)
	if attendance == "proxy":
		app.player.set_pitch(-.8)
		app.player.request_interaction()
		app._choice_made(0)
		app.player.set_pitch(0)
		app._stand_up()
		app.travel("out", _campus_pose(null, app.routes().west_gate_center() + Vector2(55, 0), PI), false)
	if attendance in ["present", "proxy"]:
		var school := app.school()
		var at := CampusGeometry.to_world(app.campus().room(app.session.world_id), app.player.position.x, app.player.position.z)
		school.start_inspection({"day":1, "slot":0}, app.session.world_id, at, func(_p: Vector2) -> bool: return true)
		for tick in 81: school.step(.1, {"world_id":app.session.world_id, "w":at, "calendar":false})
	if app.school().seated: app._stand_up()
	var room := CampusData.layout("guard1")
	var counter := Vector2i(-1, -1)
	for row in room["grid"].size():
		var col := String(room["grid"][row]).find("k")
		if col >= 0:
			counter = Vector2i(col, row)
			break
	var cabinet := CampusGeometry.tile_center(room, counter.x, counter.y)
	app.travel("guard1", _campus_pose(room, cabinet + Vector2(0, 9), -PI / 2), false)
	await _frames(3)
	app.player.request_interaction()
	await _frames(2)
	check(app.school().seat_card.proof == attendance and app.investigation_brief().contains("西小门"), "the real guard cabinet and the pause lead open the early route")
	var observation := String(app.investigation().entries.get("dutyBook1987", {}).get("text", ""))
	check(observation.contains("17 号工单") and observation.contains("在模型里给甲纸打孔"), "the guard exhibit links the ticket to the experimental action")
	check(observation.contains("现实的岗亭") and observation.contains("乙纸四边还齐"), "the independent observer finds a physical effect only on the paired sample")
	if attendance == "ink":
		app._show_map("campus")
		check(app.ui._map_route_select.visible and app.ui._map_route_select.get_item_metadata(2) == "car" and app.ui.map_view.plan.get("target") == app.routes().west_gate_center() / 2.0, "the beginner task has a map marker and the vehicle remains selectable")
		app.ui._map_route_select.item_selected.emit(2)
		var target: Vector2 = app.ui.map_view.plan.get("target", Vector2.INF)
		check(target.is_finite() and target != app.routes().west_gate_center() / 2.0 and app.ui._map_note.text.contains("行政楼五楼校长室"), "selecting the vehicle lead marks the key's building and names the floor")
		app.ui._close_map()
		app._show_map("campus")
		check(app.ui.map_view.plan.get("target") == target, "reopening the map remembers an explicit choice")
		app.ui._close_map()
	if attendance == "present":
		var old := app.session.capture(app.player.capture_pose())
		old["modules"]["school.day"]["data"]["seat_card"] = {"armed":"", "answered":"", "checked":false}
		app.saves.write(old)
		app.load_game()
		check(app.school().seat_card.proof == "present" and app.school().seat_card.present_slot == "1:0" and not app.school().seat_card.reading("guard1",app.school().active_seconds), "an old solo cabinet record and settled attendance restore the facts without replaying the reading grace")
	app._show_notes()
	for button: Button in app.ui.notes_panel.entries.find_children("*","Button",true,false):
		if button.text == "地图定位 · 西小门": button.pressed.emit()
	check(is_instance_valid(app.ui.map_view) and app.ui.map_view.plan.get("target") == app.routes().west_gate_center() / 2, "the notebook opens the correct marked campus destination")
	check(app.ui._map_head.text.contains("保安岗") and app.ui._map_note.text.contains("西南") and app.ui._map_note.text.contains("闸机"), "the map gives a readable origin, bearing and action at phone size")
	if is_instance_valid(app.ui.map_panel): app.ui._close_map()
	var reader := app.routes().west_gate_center() + Vector2(44, -RollcallCard.EXIT_NORTH)
	app.travel("out", _campus_pose(null, reader, PI), false)
	await _frames(5)
	app.player.request_interaction()
	await _frames(1)
	check(app.ui.choice_open(), "the normal outdoor interaction opens the paper reader")
	var answer: int = {"ink":2, "present":0, "proxy":1}[attendance]
	app._choice_made((answer + 1) % 3)
	check(app.school().seat_card.clearance == 0 and app.story().ended.is_empty(), "the red stamp leaves the run playable")
	app.player.request_interaction()
	app._choice_made(answer)
	await _frames(2)
	var punched_edge: String = {"ink":"左边", "present":"上边", "proxy":"右边"}[attendance]
	check(app.school().seat_card.journal().contains(punched_edge + "有个半圆缺口"), "the returned counterfoil shows the notch for this run's actual evidence")
	check(app.story().ended.is_empty() and app.school().seat_card.clearance == 1, "green light waits for the player's own steps")
	check(app._campus_world()._west_display.text.contains("已核验"), "the physical west gate shows the personal clearance")
	var run := app.session
	var day := app.school().day
	Input.action_press("move_forward")
	for frame in 150:
		await _frames(1)
		if app.school().seat_card.trial_done(): break
	Input.action_release("move_forward")
	check(app.school().seat_card.trial_done() and app.session == run and app.school().day == day and not app.story().over(), "ordinary walking through the real gate completes the trial and continues the same day")
	var line := app.routes().west_gate_center().x + RollcallCard.EXIT_OFFSET
	check(app.session.world_id == "out" and app.player.position.x > line * CampusGeometry.U2M and app.player.enabled, "the student is back on the campus side with control")
	check(app._campus_world()._west_display.text.contains("纸面核验完成"), "the gate display recognizes the completed exercise")
	check(app._last_result.is_empty() and not app.achievements().unlocked.has("e.end_face") and not app.achievements().unlocked.has("e.whitelist"), "no score or ending achievement is written")
	var snapshot: Dictionary = app.saves.read().get("data", {})
	check(snapshot.get("modules", {}).get("school.day", {}).get("data", {}).get("seat_card", {}).get("trial_punch") == attendance, "the save preserves personal proof and the original run")
	check(app.investigation().visible("westTrial") and app.investigation().entries["westTrial"].kind == "验证", "the completed trial records the gate observation")
	check(app.investigation_brief().contains("校长室") and app.investigation().routes().any(func(r: Array) -> bool: return r[0] == "face"), "the journal hands off to the vehicle and electronic whitelist leads")
	var archive := ArchiveRules.new(CampusData.archive())
	check(app._read_side("ends.json") == null and not archive.locked().has("end:facePaper"), "this exercise does not unlock a new ending replay")
	if attendance == "ink":
		app.load_game()
		await _frames(3)
		check(app.school().seat_card.trial_done() and not app.story().over() and app.investigation().visible("westTrial"), "continuing preserves the trial without replaying it")
		app.routes().hacked = true
		app.routes().data_synced = true
		app.player.request_interaction()
		await _frames(1)
		check(app.ui.choice_open() and app.ui._choice_text.text.contains("白名单验证 1/3"), "after separate synchronization the same gate still starts the real whitelist quiz")
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
