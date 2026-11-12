class_name CooperativeSimulation
extends Node
## Host authority. No UI or device input; one simulation tick for the shared campus.
signal checkpoint_requested
var room: CooperativeRoom
var actors: Dictionary = {}
var shared: Dictionary = {}
var calendar := SchoolCalendar.new()
var inventory := CooperativeItems.new()
var patrol := CooperativePatrol.new()
var physics := CooperativePhysics.new()
var gameplay: CooperativeGameplay
var leases: Dictionary = {}
var _seconds := 0.0
var _last_save := 0.0
var timings: Dictionary = {}
var spectators: Dictionary = {}


func setup(state: CooperativeRoom, seed_value: int) -> void:
	room = state
	physics.name = "Physics"
	add_child(physics)
	var slot := 0
	for id: String in room.members:
		var a := CooperativeFactory.actor(id, slot, room.difficulty, String(room.members[id]["talent"]), seed_value, shared)
		actors[id] = a
		room.members[id]["seat"] = a.own_seat
		inventory.reconcile(a)
		physics.place(a)
		slot += 1
	patrol.main = CampusData.make_patrol()
	# Authority navigation must never share mutable door callbacks with the host's replica.
	patrol.main.nav = PatrolNav.new(CampusData.patrol_data(), CampusData.rooms(), CampusData.campus(), CampusData.maze_geometry())
	for a: CooperativeActor in actors.values(): a.watcher().nav = patrol.main.nav
	(shared[&"story.exchange"] as ExchangeModule)._nav = patrol.main.nav
	(shared[&"story.broadcast"] as BroadcastModule)._nav = patrol.main.nav
	patrol.main.reset()
	patrol.main.nav.door_open = func(scene: String, c: int, r: int) -> bool: return campus().is_open("%s:%d:%d" % [scene, c, r])
	patrol.synchronize(actors)
	gameplay = CooperativeGameplay.new(self)
	gameplay.setup(seed_value)
	inventory.containers["rng_seed"] = str(seed_value)
	inventory.containers["rng_state"] = str((actors.values()[0] as CooperativeActor).bag()._rng.state)


func campus() -> CampusModule:
	return shared[&"campus.world"] as CampusModule


func actor(id: String) -> CooperativeActor:
	return actors.get(id)


func lease(key: String, id: String) -> bool:
	if leases.has(key) and leases[key] != id: return false
	leases[key] = id
	return true


func release(id: String) -> void:
	for key: String in leases.keys():
		if leases[key] == id: leases.erase(key)
	inventory.release(id)
	if actors.has(id):
		actors[id].bag().cancel_search()
		if actors[id].choice.get("source") == "day":
			(actors[id].feature(&"school.days") as DayModule).answer(-1, CooperativeContext.base(actors[id]))
		actors[id].choice.clear()
		actors[id].terminal = false
		actors[id].clear_input()


func disconnect_member(id: String) -> void:
	gameplay.disconnected(id)


func departed(id: String) -> void:
	if not actors.has(id): return
	var a: CooperativeActor = actors[id]
	release(id)
	inventory.recover(a)
	physics.remove_actor(id)


func tick(dt: float) -> void:
	if room == null or room.phase != "playing" or room.paused_left > 0.0: return
	var started := Time.get_ticks_usec()
	_seconds += dt
	room.tick += 1
	room.record_participation(dt)
	var minutes := calendar.advance(dt)
	var contexts := {}
	var active: Array = []
	for id: String in actors:
		var a: CooperativeActor = actors[id]
		if room.members[id]["state"] == "departed": continue
		a.input_age += dt
		a.enter_cool = maxf(0.0, a.enter_cool - dt)
		if a.input_age > 0.25 or not room.members[id]["connected"]: a.clear_input()
		a.school().advance_game_time(minutes)
		a.session.clock.advance(dt)
		if a.school().seated and (absf(float(a.input["x"])) + absf(float(a.input["y"]))) > 0.08 and a.choice.is_empty():
			var stood := a.school().stand_up()
			if stood.has("pose"): a.pose = stood["pose"]
		physics.advance(a, dt)
		active.append(a.location())
		gameplay.personal(a, dt)
		contexts[id] = CooperativeContext.patrol(a)
	var personal_end := Time.get_ticks_usec()
	for e: Dictionary in patrol.step(dt, actors, contexts):
		if actors.has(e["member"]): gameplay.apply_event(actors[e["member"]], "patrol", e)
	var patrol_end := Time.get_ticks_usec()
	gameplay.shared_tick(dt)
	var shared_end := Time.get_ticks_usec()
	for a: CooperativeActor in actors.values():
		inventory.reconcile(a)
		if room.members[a.id]["state"] == "departed": continue
		a.bag().desk_used = inventory.containers["desk_used"]
		if not a.fate().over():
			for death: Dictionary in a.school().take_deaths(): gameplay.kill(a, String(death["msg"]), String(death["fx"]), String(death["source"]))
		if not a.fate().over() and a.choice.is_empty():
			var crossed := campus().crossing(a.location(), a.pose)
			if not crossed.is_empty(): travel(a, String(crossed["world"]), crossed["pose"])
		for text: String in a.bag().take_notices(): a.event("notice", {"text": text})
		for text: String in a.school().take_notices(): a.event("notice", {"text": text})
	active.append(String(patrol.main.pat["room"]))
	physics.sync_doors(campus(), gameplay.lifts)
	physics.maintain(dt, active)
	timings = {"personal_us": personal_end - started, "patrol_us": patrol_end - personal_end, "shared_us": shared_end - patrol_end, "finish_us": Time.get_ticks_usec() - shared_end}
	if _seconds - _last_save >= 30.0:
		_last_save = _seconds
		checkpoint_requested.emit()


func spawn(world: String) -> Dictionary:
	if world == "out": return {"position": [120.0, 0.05, 222.0], "yaw": 0.0, "pitch": 0.0}
	return campus().default_spawn(world)


func travel(a: CooperativeActor, world: String, pose: Dictionary) -> void:
	if not campus().knows(world) or not pose.get("position") is Array or pose["position"].size() != 3 or not pose.has("yaw") or not pose.has("pitch"): return
	if a.id == patrol.target:
		patrol.main.set_context(CooperativeContext.patrol(a))
		patrol.main.left_scene(a.location(), world)
	gameplay.cancel_actor_jobs(a)
	a.school().seated = false
	a.school().seat_id = ""
	a.travel(world, pose)
	physics.place(a)


func command(id: String, data: Dictionary) -> Dictionary:
	if not actors.has(id) or data.get("epoch") != room.epoch: return {"ok": false, "error": "会话已失效。"}
	var a: CooperativeActor = actors[id]
	var sequence := int(data.get("seq", -1))
	var cached: Variant = room.cached(id, sequence)
	if cached is Dictionary: return cached
	if sequence <= a.command_sequence or sequence < 0: return {"ok": false, "error": "操作已过期。"}
	a.command_sequence = sequence
	var result := {"ok": false, "error": "当前无法操作。"}
	if data.get("action") == "spectate" and data.get("target") is String and a.fate().dead and not a.fate().wake_pending:
		var who := String(data.get("target", ""))
		if who in room.alive_ids():
			spectators[id] = who
			result = {"ok": true}
	if room.phase == "playing" and not a.fate().over() and room.members[id]["connected"] and room.paused_left <= 0.0:
		result = gameplay.command(a, data)
	room.remember(id, sequence, result)
	inventory.reconcile(a)
	return result


func input(id: String, data: Dictionary) -> void:
	if actors.has(id) and room.phase == "playing" and data.get("epoch") == room.epoch and room.members[id]["connected"] and LanProtocol.input_valid(data):
		actors[id].accept_input(data)


func reachable(a: CooperativeActor, entry: Dictionary) -> bool:
	var p := a.point(CampusData.rooms())
	var q := CampusGeometry.to_world(CampusData.rooms().get(a.location()), float(entry["x"]), float(entry["z"]))
	return patrol.main.nav.los(PatrolNav.point(a.location(), p.x, p.y, float(a.pose["position"][1])), PatrolNav.point(a.location(), q.x, q.y, float(entry["y"])))


func motion(for_id: String) -> Dictionary:
	var data := {"epoch": room.epoch, "tick": room.tick, "players": {}}
	if not actors.has(for_id): return data
	var viewer: CooperativeActor = actors[for_id]
	var observing := observed(for_id)
	if observing != "": viewer = actor(observing)
	for id: String in actors:
		var a: CooperativeActor = actors[id]
		if room.members[id]["state"] == "departed": continue
		if id != for_id and a.location() != viewer.location(): continue
		if id != viewer.id and bool(a.watcher().hide["on"]): continue
		data["players"][id] = {"pose": a.pose.duplicate(true), "world": a.location(), "scene": a.scene_version, "ack": a.processed_sequence, "moving": a.moving, "running": a.running, "seated": a.school().seated, "hiding": bool(a.watcher().hide["on"]), "dead": a.fate().dead}
	return data


func state_for(id: String) -> Dictionary:
	if not actors.has(id): return {}
	var a: CooperativeActor = actors[id]
	var data := a.capture()
	data["room"] = room.public_state()
	data["item_revision"] = inventory.revision
	data["items"] = inventory.owners.get(id, {}).duplicate()
	data["patrol_target"] = patrol.target if room.debug_run else ""
	data["qualified"] = gameplay.qualified.duplicate()
	data["time_offer"] = gameplay._time_offer.duplicate(true)
	data["driver"] = gameplay.driver
	data["boarding"] = gameplay.boarding.duplicate(true)
	var radio: BroadcastModule = shared[&"story.broadcast"]
	data["radio_live"] = {"held": radio.held, "progress": radio.progress}
	var observing := observed(id)
	if observing != "":
		data["observed"] = actor(observing).capture()
		data["observed"]["id"] = observing
	return data


func observed(id: String) -> String:
	if not actors.has(id) or not actor(id).fate().dead or actor(id).fate().wake_pending: return ""
	var alive := room.alive_ids()
	if alive.is_empty(): return ""
	var who := String(spectators.get(id, ""))
	if who not in alive: who = String(alive[0])
	spectators[id] = who
	return who


func capture() -> Dictionary:
	var people := {}
	for id: String in actors: people[id] = actors[id].capture()
	return {"format": "wdfz-godot-coop", "version": 1, "room": room.public_state(), "calendar": calendar.capture(), "actors": people,
		"items": inventory.capture(), "patrol": patrol.capture(), "gameplay": gameplay.capture(), "leases": leases.duplicate(), "seconds": _seconds}


## Caller validates the entire candidate before setup/restore; keep the new room epoch.
func restore(data: Dictionary) -> void:
	calendar.restore(data["calendar"])
	for id: String in actors:
		actors[id].restore(data["actors"][id])
		room.members[id]["seat"] = actors[id].own_seat
		physics.place(actors[id])
	inventory.restore(data["items"])
	patrol.restore(data["patrol"])
	patrol.synchronize(actors)
	leases = data["leases"].duplicate()
	gameplay.restore(data["gameplay"])
	_seconds = float(data.get("seconds", 0))
	room.tick = int(data["room"]["tick"])
	room.debug_run = bool(data["room"].get("debug", false))
	for a: CooperativeActor in actors.values(): inventory.reconcile(a)


func _exit_tree() -> void:
	for a: CooperativeActor in actors.values():
		for feature: FeatureModule in a.session.modules._modules.values():
			if feature.has_method("set_context"): feature.call("set_context", {})
			for property: Dictionary in feature.get_property_list():
				if int(property["type"]) == TYPE_CALLABLE: feature.set(property["name"], Callable())
		a.watcher().nav.door_open = Callable()
	for feature: FeatureModule in shared.values():
		if feature.has_method("set_context"): feature.call("set_context", {})
	if patrol.main != null:
		patrol.main.nav.door_open = Callable()
		patrol.main.zone_active = Callable()
		patrol.main.elevator = null
		patrol.main.camouflage = Callable()
	if gameplay != null:
		for engine: ElevatorModule in gameplay.lift_engines.values():
			engine.closed_hook = Callable()
			engine.unsafe_check = Callable()
		gameplay.lifts.closed_hook = Callable()
		gameplay.lifts.unsafe_check = Callable()
	actors.clear()
	shared.clear()
