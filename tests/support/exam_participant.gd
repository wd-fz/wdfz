extends RefCounted
## A test student hands in a blank paper using the normal UI or the reliable command channel.
static func advance(network: LanSession, data: Dictionary, app: GameApp = null) -> void:
	if network.room == null or network.room.phase != "playing" or not data.get("exam_pending", false): return
	if app != null:
		var panel := app.exam_flow.panel
		if app.exam_flow._cut:
			if app.ui.opening_on(): app.ui._end_opening(true)
			elif is_instance_valid(app._opening_cut): app._opening_cut.tick(OpeningCut.DUR_SHORT)
		elif is_instance_valid(panel) and panel.visible and panel._submit.visible and not panel._submit.disabled:
			panel._submit.pressed.emit()
		return
	var phase: String = data.session.modules["school.entrance_exam"].data.phase
	var op: String = {"waiting": "exam_start", "writing": "exam_submit", "graded": "exam_wake"}.get(phase, "")
	if not op.is_empty(): network.command(op, {"scene": data.scene})
