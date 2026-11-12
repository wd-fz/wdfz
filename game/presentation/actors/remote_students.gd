class_name RemoteStudents
extends Node3D
## Remote avatars interpolate only within their replicated scene; no physical pushing.
var peers: Dictionary = {}
var samples: Dictionary = {}
var _time := 0.0


func receive(data: Dictionary, local_id: String, world: String, names: Dictionary) -> void:
	var visible_ids: Array = []
	for id: String in data.get("players", {}):
		var state: Dictionary = data["players"][id]
		if id == local_id or state["world"] != world or state["dead"] or state["hiding"]: continue
		visible_ids.append(id)
		if not peers.has(id):
			var body := Node3D.new()
			body.name = id
			var model := FigureModel.make("person", Color("768e9a"))
			body.add_child(model)
			var label := Label3D.new()
			label.text = String(names.get(id, {}).get("name", "同学"))
			label.position.y = 2.05
			label.font_size = 34
			label.pixel_size = 0.004
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = false
			body.add_child(label)
			add_child(body)
			peers[id] = body
			samples[id] = []
		var sample := state.duplicate(true)
		sample["at"] = _time
		var history: Array = samples[id]
		if not history.is_empty() and history.back()["scene"] != state["scene"]: history.clear()
		history.append(sample)
		while history.size() > 8: history.pop_front()
	for id: String in peers.keys():
		if id not in visible_ids:
			peers[id].queue_free()
			peers.erase(id)
			samples.erase(id)


func _process(dt: float) -> void:
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
		body.position = Vector3(p[0], p[1], p[2]).lerp(Vector3(q[0], q[1], q[2]), t)
		body.rotation.y = lerp_angle(float(a["pose"]["yaw"]), float(b["pose"]["yaw"]), t)
		body.get_child(0).position.y = -0.35 if b["seated"] else (sin(_time * (14 if b["running"] else 9)) * 0.035 if b["moving"] else 0.0)
