class_name EntranceExamFlow
extends Node
## Presents the normal classroom, personal exam and wake-up before starting the campus clock.
var app: GameApp
var panel: EntranceExamPanel
var _cut := false
var _waiting_for_team := false
var _wake_sent := false


func paper() -> EntranceExam:
	return app.session.modules.feature(&"school.entrance_exam") as EntranceExam


func active() -> bool:
	return panel_visible() or _cut or _waiting_for_team


func panel_visible() -> bool:
	return is_instance_valid(panel) and panel.visible


func normal_classroom() -> bool:
	return panel_visible() and not _waiting_for_team


func begin() -> void:
	paper().prepare()
	app.save_game(true)
	resume_paper()


func resume_paper() -> bool:
	var exam := paper()
	if exam.phase == "done": return false
	if exam.phase == "writing" and exam.deadline <= Time.get_unix_time_from_system():
		_submit()
	get_tree().paused = true
	_present(exam.deadline - Time.get_unix_time_from_system())
	return true


func _lighting(normal: bool) -> void:
	var level := 1.0 if normal else 0.0
	app.ui.set_normal_world(level)
	var world := app._campus_world()
	if world != null and world.lighting != null:
		world.lighting.world_normal = level
		world.lighting.update(0, app.school().tsec, app.player.camera)
	if is_instance_valid(app._mates_nodes): app._mates_nodes.set_normal(normal)


func _present(seconds_left: float) -> void:
	var fresh := not is_instance_valid(panel)
	if fresh:
		panel = EntranceExamPanel.new()
		app.ui.get_node("Root").add_child(panel)
		panel.action.connect(_action)
		panel.expired.connect(_expired)
	if fresh or not panel.visible:
		panel.show()
		panel.move_to_front()
		app.player.clear_input()
		app.player.enabled = false
		app.ui.cut_mode(true)
		if not _waiting_for_team and app.session.world_id == "teach1":
			var room: Dictionary = app.campus().room("teach1")
			app._show_classmates(app.classmates(), room, CampusGeometry.to_world(room, app.player.position.x, app.player.position.z), 0)
			_lighting(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.present(paper(), OpeningStory.student_name(app.session.character_id), seconds_left)


func _action(operation: String, index: int, option: int) -> void:
	if operation == "exam_wake":
		_cut = true
		panel.hide()
		_lighting(false)
		app._play_opening(true)
		return
	if app.lan.playing():
		app.lan.send(operation, {"index": index, "option": option})
		return
	var exam := paper()
	var now := Time.get_unix_time_from_system()
	if operation == "exam_start" and exam.phase == "waiting":
		exam.start(now, RandomNumberGenerator.new())
		app.save_game(true)
		_present(EntranceExam.SECONDS)
		return
	if exam.phase != "writing": return
	if operation == "exam_submit" or now >= exam.deadline:
		_submit()
	elif exam.answer(index, option, now):
		app.save_game(true)
	_present(exam.deadline - now)


func _expired() -> void:
	if not app.lan.playing() and paper().phase == "writing":
		_submit()
		_present(0)


func _submit() -> void:
	if not paper().submit(): return
	_record_perfect()
	if app.talent().all_active() and not app.items().has("phone"):
		app.items().add("phone")
		app.items().take_notices()
	app.save_game(true)


func _record_perfect() -> void:
	if paper().score != EntranceExam.COUNT: return
	var ach := app.achievements()
	if ach.unlocked.has("h.perfect_paper"): return
	var trusted := not app.lan.network.room.debug_run if app.lan.playing() else app.runscore().trusted
	if not ach.fact({"kind": "entrance_exam", "score": paper().score}, trusted).is_empty():
		ach.take_events()
		app._save_profile(ach)


func cut_finished() -> bool:
	if not _cut: return false
	_cut = false
	if app.lan.playing():
		_waiting_for_team = true
		_wake_sent = true
		app.lan.send("exam_wake")
		return true
	paper().wake()
	app.save_game(true)
	cancel()
	return false


## Host snapshots drive the paper and the waiting screen; the network keeps polling throughout.
func team_state(pending: bool, remaining: float) -> void:
	if _cut: return
	_record_perfect()
	if not pending:
		if active() or _wake_sent:
			cancel()
			app.lan.resume()
			app.ui.show_notice(OpeningStory.handover(app.session.character_id))
		return
	if _wake_sent and paper().phase != "done": return
	_waiting_for_team = paper().phase == "done"
	_present(remaining)


func cancel() -> void:
	if is_instance_valid(panel):
		panel.hide()
		panel.queue_free()
		panel = null
		if app.ui.is_inside_tree():
			if app.session != null: _lighting(false)
			app.ui.cut_mode(false)
	_cut = false
	_wake_sent = false
	_waiting_for_team = false
