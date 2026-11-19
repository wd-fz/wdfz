class_name RemoteStudents
extends Node3D
## Render a little behind the host clock. Packets arriving in a burst still
## have distinct simulation times; interpolation never runs backwards.
signal stepped(at: Vector3, running: bool, world: String)
const BUFFER := 0.10
var space: CampusSpace
var peers: Dictionary = {}
var samples: Dictionary = {}
var _steps: Dictionary = {}
var _time := 0.0
var _latest := -1.0
var _cursor := -1.0
var _tick := -1
var frozen := false


func receive(data: Dictionary, local_id: String, world: String, names: Dictionary) -> void:
	var stamp := _time
	if data.has("tick"):
		var tick := int(data["tick"])
		if tick <= _tick: return
		_tick = tick
		stamp = float(tick) / Engine.physics_ticks_per_second
	if _latest < 0 or stamp - _latest > .55: _cursor = stamp - BUFFER
	_latest = stamp
	var visible_ids: Array = []
	for id: String in data.get("players", {}):
		var state: Dictionary = data["players"][id]
		var common := space != null and space.contains(world) and space.contains(String(state["world"]))
		if id == local_id or (state["world"] != world and not common) or state["hiding"]: continue
		visible_ids.append(id)
		var member: Dictionary = names.get(id, {})
		if not peers.has(id): _add(id)
		var body: Node3D = peers[id]
		var avatar: StudentAvatar = body.get_child(0)
		avatar.dress(StudentCast.resolve(member.get("character")))
		var label: Label3D = body.get_meta("label")
		label.text = String(member.get("name", "同学")) + ("（暂离）" if not member.get("connected", true) else "")
		var sample := state.duplicate()
		if common and not state.get("school",false): sample["pose"] = space.global_pose(String(state["world"]), state["pose"])
		var raw: Array = sample["pose"]["position"]
		sample["position"] = Vector3(raw[0], raw[1], raw[2])
		sample["at"] = stamp
		sample["received"] = _time
		sample["online"] = member.get("connected", true)
		var history: Array = samples[id]
		if not history.is_empty() and history.back()["scene"] != state["scene"]:
			if not common or not state.get("seam", false) or history.back()["world"] == state["world"] or sample["position"].distance_to(history.back()["position"]) > 3.0:
				history.clear()
		if history.is_empty():
			body.position = sample["position"]
			body.rotation.y = float(sample["pose"]["yaw"])
		history.append(sample)
		while history.size() > 12: history.pop_front()
	for id: String in peers.keys():
		if id not in visible_ids: remove_from_view(id)


func remove_from_view(id: String) -> void:
	if not peers.has(id): return
	var actor: Node3D = peers[id]
	actor.hide()
	actor.queue_free()
	peers.erase(id)
	samples.erase(id)
	_steps.erase(id)


func _add(id: String) -> void:
	var body := Node3D.new()
	body.name = id
	body.add_child(StudentAvatar.new())
	var label := Label3D.new()
	label.position.y = 2.05
	label.font_size = 34
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 22
	body.add_child(label)
	body.set_meta("label", label)
	add_child(body)
	peers[id] = body
	samples[id] = []
	_steps[id] = 0.0


func _process(dt: float) -> void:
	if frozen: return
	_time += dt
	if _latest < 0: return
	var rate := clampf(1.0 + (_latest - BUFFER - _cursor) * 3.0, .85, 1.15)
	_cursor = minf(_latest, _cursor + dt * rate)
	for id: String in peers:
		var history: Array = samples[id]
		while history.size() > 2 and history[1]["at"] <= _cursor: history.pop_front()
		var a: Dictionary = history[0]
		var b: Dictionary = history[mini(1, history.size()-1)]
		var t := clampf((_cursor - float(a["at"])) / maxf(.001, float(b["at"]) - float(a["at"])), 0, 1)
		var state := b if t >= .5 else a
		var body: Node3D = peers[id]
		var last_yaw := body.rotation.y
		body.position = (a["position"] as Vector3).lerp(b["position"], t)
		body.rotation.y = lerp_angle(float(a["pose"]["yaw"]), float(b["pose"]["yaw"]), t)
		var fresh: bool = history.back()["online"] and _time - float(history.back()["received"]) < .35
		var velocity: Vector3 = (b["position"] - a["position"]) / maxf(.001, float(b["at"]) - float(a["at"]))
		var local_velocity := velocity.rotated(Vector3.UP, -body.rotation.y)
		var turn := wrapf(body.rotation.y - last_yaw, -PI, PI) / maxf(.001, dt)
		var moving := bool(state["moving"]) and fresh
		var action := StudentAvatar.locomotion(local_velocity, moving, state["running"], turn if fresh else 0.0)
		if state["seated"]: action = "sit"
		var upper := ""
		if state["dead"]: action = "down"
		elif fresh and state.has("act"):
			var act: String = state["act"]
			if (act in ["interact","read","speak","bandage","search"] and (moving or state["seated"])) or (act == "type" and not state["seated"]):
				upper = act
			else: action = act
		var avatar: StudentAvatar = body.get_child(0)
		var pace := 1.0
		if moving and velocity.length() > .01:
			pace = Vector2(velocity.x,velocity.z).length() / (CharacterMotor.RUN if state["running"] else CharacterMotor.WALK)
		avatar.advance(action, dt, pace, int(state.get("gear", 0)), lerpf(float(a["pose"].get("pitch", 0)), float(b["pose"].get("pitch", 0)), t), upper)
		if moving and not state["seated"] and not state["dead"]:
			_steps[id] = float(_steps[id]) - dt
			if _steps[id] <= 0.0:
				_steps[id] = .33 if state["running"] else .52
				stepped.emit(body.global_position, bool(state["running"]), String(state["world"]))
		else: _steps[id] = 0.0
