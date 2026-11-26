extends "res://tests/support/test_suite.gd"


func test_paper() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 619
	var exam := EntranceExam.new()
	check(not EntranceExam.pending_in({}) and not EntranceExam.pending_in({"modules": []}), "legacy and malformed saves can be presented to the normal loader")
	check(EntranceExam.pending_in({"modules": {"school.entrance_exam": {"data": {"phase": "graded"}}}}), "a submitted paper still opens in the classroom on continue")
	var seen := {}
	for subject in 6:
		check(EntranceExam.rows(subject).size() == 50, "50 questions in " + EntranceExamBank.SUBJECTS[subject])
		for row: String in EntranceExam.rows(subject):
			var cells := row.split("|")
			var options := {}
			for i in range(1, cells.size()): options[cells[i]] = true
			check(cells.size() == 5 and options.size() == 4 and not seen.has(cells[0]), "unique four-option question: " + cells[0])
			seen[cells[0]] = true
	var seen_answers := {}
	for seed_index in 20:
		exam.prepare()
		exam.start(10, rng)
		check(exam.validate(exam.capture()).is_empty() and exam.deadline == 610, "balanced paper with a ten-minute deadline")
		for i in EntranceExam.COUNT:
			check(exam.question(i).subject == EntranceExamBank.SUBJECTS[floori(i / 5.0)], "five questions per subject")
			seen_answers[exam.option_order(i).find(0)] = true
	check(seen_answers.size() == 4, "correct choices appear in all four slots")
	exam.answer(0, 0, 100)
	exam.answer(0, 1, 200)
	var save: Dictionary = JSON.parse_string(JSON.stringify(exam.capture()))
	var copy := EntranceExam.new()
	copy.restore(save)
	check(copy.question(0) == exam.question(0) and copy.answers[0] == 1 and copy.deadline == 610, "restoring preserves choices, edits and clock")
	check(not copy.answer(0, 3, 610) and not copy.answer(-1, 2, 300), "late and invalid updates rejected")
	for i in EntranceExam.COUNT: copy.answer(i, copy.option_order(i).find(0), 500)
	check(copy.submit() and not copy.submit() and copy.score == 30 and not copy.capture().has("answers"), "one grade, no answer sheet after submission")
	var all := TalentModule.new(copy)
	for key: String in TalentModule.KEYS: check(all.has(key), "full marks grant " + key)
	check(all.prevent_death() and not all.prevent_death() and all.face_remedy() and not all.face_remedy(), "one-shot talents retain independent charges")
	copy.wake()
	check(copy.phase == "done" and all.all_active(), "all effects survive waking")
	var partial := EntranceExam.new()
	partial.restore(save)
	partial.answers.fill(-1)
	partial.submit()
	check(partial.score == 0 and not TalentModule.new(partial).all_active(), "blank paper gets zero")
	var ach := AchievementsModule.new()
	ach.reset()
	check(not ach.entries().any(func(entry: Dictionary) -> bool: return entry.id == "h.perfect_paper"), "full marks stay hidden before discovery")
	check(ach.fact({"kind": "entrance_exam", "score": 29}).is_empty() and ach.fact({"kind": "entrance_exam", "score": 30}).has("h.perfect_paper"), "only full marks unlock the secret")
	var invalid: Dictionary = save.duplicate(true)
	invalid.paper[1] = invalid.paper[0]
	check(not exam.validate(invalid).is_empty(), "duplicate saved draws rejected")


func test_live() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/exam/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app._start_at_desk("hard", "code", StudentCast.DEFAULT, false)
	await _until_started(app)
	var exam := app.exam_flow.paper()
	var panel := app.exam_flow.panel
	check(app.school().seated and paused and not app.player.enabled and exam.phase == "waiting", "normal campus starts seated at the exam")
	var uniforms := ClassmatesView._uniforms
	check(not uniforms.is_empty() and (uniforms[0].surface_get_material(0) as BaseMaterial3D).vertex_color_use_as_albedo, "normal students wear the colours painted on the meshes")
	var staff_cloth: BaseMaterial3D
	for child in app._mates_nodes.teacher.get_children():
		if child is StudentAvatar:
			var uniform := child.find_child("Uniform", true, false) as MeshInstance3D
			if uniform != null: staff_cloth = uniform.get_active_material(0) as BaseMaterial3D
	check(staff_cloth != null and staff_cloth.vertex_color_use_as_albedo, "the invigilator uses the authored clothing and skin colours")
	panel._submit.pressed.emit()
	panel._pick(2)
	panel._go(1)
	panel._pick(0)
	panel._go(0)
	panel._pick(1)
	check(exam.answers[0] == 1 and exam.answers[1] == 0, "navigation permits revising answers")
	var original := exam.capture()
	app.return_to_menu()
	app.load_game()
	exam = app.exam_flow.paper()
	panel = app.exam_flow.panel
	check(same_json(original, exam.capture()) and paused and panel.visible, "continue resumes the same signed paper in class")
	exam.deadline = Time.get_unix_time_from_system() - 1
	app.exam_flow._expired()
	check(exam.phase == "graded" and panel._prompt.text.begins_with("得分") and not panel._options[0].visible, "time expiry shows only the score")
	panel._submit.pressed.emit()
	check(app.opening_busy() and not app.player.enabled, "score hands off to falling asleep")
	if app.ui.opening_on(): app.ui._end_opening(true)
	elif is_instance_valid(app._opening_cut):
		app._opening_cut.tick(OpeningCut.DUR_SHORT)
	check(app.exam_flow.paper().phase == "done" and not paused and app.player.enabled, "waking returns control and starts the school")
	app.return_to_menu()
	app.load_game()
	check(not app.opening_busy() and app.player.enabled, "completed prologue stays complete")
	app._reach_ending("false_normal")
	check(app.story().ended.is_empty(), "the ending requires full assimilation")
	app.school().tt = 100
	app.school()._resolve_assimilation()
	app._handle_deaths()
	check(app.story().ended == "false_normal" and not app.saves.exists() and app._last_result.is_empty(), "assimilation ends run without a clear or a resumable save")
	var entry: Dictionary = app.archive_flow.rules.entries["end:false_normal"]
	check(app.archive_flow.rules.real(entry, app._read_side("ends.json"), false), "the false ending is recorded in the archive")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)

func test_cooperation() -> void:
	var room := CooperativeRoom.new()
	room.add_member("a", "甲", true)
	room.add_member("b", "乙")
	room.ready("a", true, "ear")
	room.ready("b", true, "night")
	room.begin("exam-test")
	room.loaded("a")
	room.loaded("b")
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 71)
	var a := sim.actor("a")
	var b := sim.actor("b")
	for actor: CooperativeActor in [a, b]: actor.entrance_exam().prepare()
	var cmd := func(actor: CooperativeActor, op: String, extra: Dictionary = {}) -> Dictionary:
		var msg := {"epoch": room.epoch, "seq": actor.command_sequence + 1, "scene": actor.scene_version, "action": op}
		msg.merge(extra)
		return sim.command(actor.id, msg)
	var clock := sim.calendar.tsec
	cmd.call(a, "exam_start")
	cmd.call(b, "exam_start")
	check(not cmd.call(a, "interact").ok and sim.exam_pending(), "neither peer can explore during the exam")
	var a_paper := a.entrance_exam()
	for i in EntranceExam.COUNT: cmd.call(a, "exam_answer", {"index": i, "option": a_paper.option_order(i).find(0)})
	var checkpoint := sim.capture()
	check(CooperativeValidation.validate(checkpoint).is_empty(), "checkpoint with two independent papers is valid")
	cmd.call(a, "exam_submit", {"score": 0})
	cmd.call(a, "exam_wake")
	sim.tick(0.25)
	check(sim.calendar.tsec == clock and a.talent().all_active() and a.bag().is_bound("phone") and a.bag().has("phone"), "host grades its own answers and waits with all gifts")
	check(not b.talent().all_active() and not b.bag().has("phone"), "one student's perfect paper cannot reward another")
	b.entrance_exam().deadline = Time.get_unix_time_from_system() - 1
	sim.tick(.25)
	check(b.entrance_exam().phase == "graded" and b.entrance_exam().score == 0, "server auto-submits even when the peer sends no input")
	cmd.call(b, "exam_wake")
	sim.tick(.25)
	check(not sim.exam_pending() and sim.calendar.tsec > clock, "both students waking releases the shared calendar")
	a.school().tt = 100
	sim.gameplay.kill(a, "同化", "names", "assimilation")
	check(a.fate().ended == "false_normal" and room.alive_ids() == ["b"] and room.phase == "playing", "assimilation only ends the affected participant's run")
	sim.queue_free()
	await _frames(2)
