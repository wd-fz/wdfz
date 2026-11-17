class_name RemoteStudents
extends Node3D
## Remote avatars interpolate in the common school, or in one isolated special space.
signal stepped(at: Vector3, running: bool, world: String)
var space: CampusSpace
var peers: Dictionary = {}
var samples: Dictionary = {}
var _steps: Dictionary = {}
var _time := 0.0
var frozen := false


func receive(data: Dictionary, local_id: String, world: String, names: Dictionary) -> void:
	var visible_ids: Array = []
	for id: String in data.get("players", {}):
		var state: Dictionary = data["players"][id]
		var common := space != null and space.contains(world) and space.contains(String(state["world"]))
		if id == local_id or (state["world"] != world and not common) or state["dead"] or state["hiding"]: continue
		visible_ids.append(id)
		if not peers.has(id):
			var body := Node3D.new()
			body.name = id
			var model := FigureModel.make("person", LanRoomView.color(id))
			body.add_child(model)
			var label := Label3D.new()
			label.text = String(names.get(id, {}).get("name", "同学"))
			label.position.y = 2.05
			label.font_size = 34
			label.pixel_size = 0.004
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = false
			label.visibility_range_end = 22.0
			body.add_child(label)
			add_child(body)
			peers[id] = body
			body.set_meta("label", label)
			samples[id] = []
			_steps[id] = 0.0
		var sample := state.duplicate(true)
		var title: Label3D = peers[id].get_meta("label")
		title.text = String(names.get(id, {}).get("name", "同学")) + ("（暂离）" if not names.get(id, {}).get("connected", true) else "")
		sample["at"] = _time
		if common and not state.get("school",false): sample["pose"] = space.global_pose(String(state["world"]), state["pose"])
		var history: Array = samples[id]
		if not history.is_empty() and history.back()["scene"] != state["scene"]:
			var p: Array = history.back()["pose"]["position"]
			var q: Array = sample["pose"]["position"]
			if not common or history.back()["world"] == state["world"] or Vector3(p[0],p[1],p[2]).distance_to(Vector3(q[0],q[1],q[2])) > 3.0: history.clear()
		if history.is_empty():
			var first: Array = sample["pose"]["position"]
			peers[id].position = Vector3(first[0], first[1], first[2])
			peers[id].rotation.y = float(sample["pose"]["yaw"])
		history.append(sample)
		while history.size() > 8: history.pop_front()
	for id: String in peers.keys():
		if id not in visible_ids:
			peers[id].queue_free()
			peers.erase(id)
			samples.erase(id)
			_steps.erase(id)


func _process(dt: float) -> void:
	if frozen: return
	_time += dt
	for id: String in peers:
		var history: Array = samples[id]
		if history.is_empty(): continue
		var a: Dictionary = history[0]
		var b := a
		for sample: Dictionary in history:
			if float(sample["at"]) <= _time - 0.1: a = sample
			b = sample
			if float(sample["at"]) >= _time - 0.1: break
		var t := clampf((_time - 0.1 - float(a["at"])) / maxf(0.001, float(b["at"]) - float(a["at"])), 0, 1)
		var p: Array = a["pose"]["position"]
		var q: Array = b["pose"]["position"]
		var body: Node3D = peers[id]
		var fresh := _time - float(history.back()["at"]) < 0.35
		body.position = Vector3(p[0], p[1], p[2]).lerp(Vector3(q[0], q[1], q[2]), t)
		body.rotation.y = lerp_angle(float(a["pose"]["yaw"]), float(b["pose"]["yaw"]), t)
		body.get_child(0).position.y = -0.35 if b["seated"] else (sin(_time * (14 if b["running"] else 9)) * 0.035 if b["moving"] and fresh else 0.0)
		if b["moving"] and not b["seated"] and fresh:
			_steps[id] = float(_steps[id]) - dt
			if _steps[id] <= 0.0:
				_steps[id] = 0.33 if b["running"] else 0.52
				stepped.emit(body.global_position, bool(b["running"]), String(b["world"]))
		else: _steps[id] = 0.0
