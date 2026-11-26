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
var lease_info: Dictionary = {}
var _lease_generation := 0
var _departed: Dictionary = {}
var _seconds := 0.0
var _last_save := 0.0
var timings: Dictionary = {}
var spectators: Dictionary = {}


func setup(state: CooperativeRoom, seed_value: int) -> void:
	room = state
	physics.name = "Physics"
	add_child(physics)
	room.assign_characters()
	var slot := 0
	for id: String in room.members:
		var a := CooperativeFactory.actor(id, slot, room.difficulty, String(room.members[id]["talent"]), seed_value, shared)
		a.session.character_id = String(room.members[id]["character"])
		actors[id] = a
		a.school().sanity_lost.connect(_report_sanity.bind(id))
		a.event("notice", {"text": OpeningStory.handover(a.session.character_id)})
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


func _report_sanity(id: String) -> void:
	var a := actor(id)
	if not is_participating(id) or not room.members[id]["connected"] or a.fate().over(): return
	var feet := a.point(CampusData.rooms())
	patrol.sense(a, a.watcher().sanity_report(a.location(), feet, a.school().active_seconds))


func is_participating(id: String) -> bool:
	return actors.has(id) and room.members.has(id) and room.members[id]["state"] != "departed"


func active_actors() -> Array:
	return actors.values().filter(func(a: CooperativeActor) -> bool: return is_participating(a.id))


func normalize_members() -> void:
	if room == null or room.phase != "playing": return
	for a: CooperativeActor in active_actors():
		room.members[a.id]["state"] = "dead" if a.fate().dead and not a.fate().wake_pending else "alive"
	if room.alive_ids().is_empty(): room.phase = "ended"


func lease(key: String, id: String) -> bool:
	if leases.has(key) and leases[key] != id: return false
	if not leases.has(key):
		_lease_generation += 1
		lease_info[key] = {"resource_id": key, "owner_member_id": id, "generation": _lease_generation, "operation_id": "%s:%d" % [room.epoch, _lease_generation], "expires": calendar.seconds + 120.0}
	leases[key] = id
	lease_info[key]["expires"] = calendar.seconds + 120.0
	return true


func lease_owner(source: String) -> String:
	for key: String in leases:
		if key == source or key.begins_with(source + "|"): return String(leases[key])
	return ""


func release_source(source: String, id: String) -> void:
	for key: String in leases.keys():
		if leases[key] == id and (key == source or key.begins_with(source + "|")):
			leases.erase(key)
			lease_info.erase(key)


func release(id: String, stop_movement: bool = true) -> void:
	for key: String in leases.keys():
		if leases[key] == id:
			leases.erase(key)
			lease_info.erase(key)
	inventory.release(id)
	if actors.has(id):
		actors[id].bag().cancel_search()
		if actors[id].choice.get("source") == "day":
			(actors[id].feature(&"school.days") as DayModule).answer(-1, CooperativeContext.base(actors[id]))
		actors[id].choice.clear()
		actors[id].terminal = false
		actors[id].mic = false
		if stop_movement: actors[id].clear_input()


func disconnect_member(id: String) -> void:
	gameplay.disconnected(id)


func departed(id: String) -> void:
	if not actors.has(id) or _departed.has(id): return
	_departed[id] = true
	var a: CooperativeActor = actors[id]
	gameplay.disconnected(id)
	gameplay.departed(id)
	release(id)
	inventory.recover(a)
	physics.remove_actor(id)


func exam_pending() -> bool:
	for a: CooperativeActor in actors.values():
		if room.members[a.id]["connected"] and is_participating(a.id) and a.entrance_exam().phase != "done": return true
	return false


func _grade_exam(a: CooperativeActor) -> void:
	var exam := a.entrance_exam()
	if not exam.submit(): return
	if a.talent().all_active():
		inventory.restore_phone(a)
		inventory.reconcile(a)
	checkpoint_requested.emit()


func _exam_command(a: CooperativeActor, data: Dictionary) -> Dictionary:
	var exam := a.entrance_exam()
	var now := Time.get_unix_time_from_system()
	if exam.phase == "writing" and now >= exam.deadline: _grade_exam(a)
	match String(data.get("action", "")):
		"exam_start":
			if exam.phase == "waiting":
				exam.start(now, RandomNumberGenerator.new())
				checkpoint_requested.emit()
		"exam_answer":
			if not SaveSchema.is_integer(data.get("index"), 0, EntranceExam.COUNT - 1) or not SaveSchema.is_integer(data.get("option"), 0, 3):
				return {"ok": false, "error": "无效的选项。"}
			if exam.answer(int(data.index), int(data.option), now): checkpoint_requested.emit()
		"exam_submit": _grade_exam(a)
		"exam_wake":
			if exam.phase == "graded":
				exam.wake()
				checkpoint_requested.emit()
		_: return {"ok": false, "error": "等全队收好试卷后再行动。"}
	return {"ok": true}


func tick(dt: float) -> void:
	normalize_members()
	if room == null or room.phase != "playing" or room.paused_left > 0.0: return
	if exam_pending():
		var now := Time.get_unix_time_from_system()
		for a: CooperativeActor in actors.values():
			var exam := a.entrance_exam()
			if exam.phase == "writing" and now >= exam.deadline: _grade_exam(a)
		return
	for i in 6 if gameplay.studying() else 1:
		if room.phase != "playing": break
		if i > 0 and not gameplay.studying(): break
		_step(dt, i == 0)


func _step(dt: float, physics_tick: bool = true) -> void:
	var started := Time.get_ticks_usec()
	for key: String in lease_info.keys():
		if not lease_info.has(key): continue
		var holder := String(lease_info[key]["owner_member_id"])
		var source := key.get_slice("|", 0)
		var working: bool = (source == "garage" and gameplay.garage_jobs.has(holder)) or (source == "broadcast" and (gameplay._radio_job.get("owner") == holder or (actor(holder).mic and (shared[&"story.broadcast"] as BroadcastModule).held))) or (source == "exchange" and (shared[&"story.exchange"] as ExchangeModule).s["phase"] == "escort")
		if working and is_participating(holder) and room.members[holder]["connected"]: lease_info[key]["expires"] = calendar.seconds + 120.0
		if float(lease_info[key]["expires"]) <= calendar.seconds:
			var owner := actor(String(lease_info[key]["owner_member_id"]))
			if owner != null:
				gameplay.cancel_actor_jobs(owner)
				owner.event("notice", {"text": "操作等待过久，已释放占用；可以重新使用。"})
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
		if physics_tick: a.consume_input()
		a.school().advance_game_time(minutes)
		a.session.clock.advance(dt)
		if a.school().seated and (absf(float(a.input["x"])) + absf(float(a.input["y"]))) > 0.08 and a.choice.is_empty():
			var stood := a.school().stand_up()
			if stood.has("pose"): a.pose = stood["pose"]
		physics.advance(a, dt)
		active.append(CooperativePhysics.instance_key(a))
		gameplay.personal(a, dt)
		if not CooperativePhysics.private_world(a.location()): contexts[id] = CooperativeContext.patrol(a)
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
			if not crossed.is_empty(): travel(a, String(crossed["world"]), crossed["pose"], true)
		for text: String in a.bag().take_notices(): a.event("notice", {"text": text})
		for text: String in a.school().take_notices(): a.event("notice", {"text": text})
	active.append(String(patrol.main.pat["room"]))
	physics.sync_doors(campus(), gameplay.lifts, gameplay.lift_engines)
	physics.maintain(dt, active)
	timings = {"personal_us": personal_end - started, "patrol_us": patrol_end - personal_end, "shared_us": shared_end - patrol_end, "finish_us": Time.get_ticks_usec() - shared_end}
	if _seconds - _last_save >= 30.0:
		_last_save = _seconds
		checkpoint_requested.emit()


func spawn(world: String) -> Dictionary:
	if world == "out": return {"position": [120.0, 0.05, 222.0], "yaw": 0.0, "pitch": 0.0}
	return campus().default_spawn(world)


func travel(a: CooperativeActor, world: String, pose: Dictionary, continuous: bool = false) -> void:
	if not campus().knows(world) or not pose.get("position") is Array or pose["position"].size() != 3 or not pose.has("yaw") or not pose.has("pitch"): return
	if world == "portal_tunnel" and a.location() != world:
		a.tunnel_return = {"world": a.location(), "pose": a.pose.duplicate(true)}
	elif a.location() == "portal_tunnel" and world == "lab1" and not a.tunnel_return.is_empty():
		world = String(a.tunnel_return["world"])
		pose = a.tunnel_return["pose"].duplicate(true)
		a.tunnel_return.clear()
	if a.id == patrol.target and CooperativePhysics.private_world(world):
		patrol.main.clear_chase()
		patrol.target = ""
	if a.id == patrol.target:
		patrol.main.set_context(CooperativeContext.patrol(a))
		patrol.main.left_scene(a.location(), world)
	var same_school := continuous and physics.space != null and physics.space.contains(a.location()) and physics.space.contains(world)
	gameplay.cancel_actor_jobs(a, not same_school)
	a.school().seated = false
	a.school().seat_id = ""
	if same_school:
		pose = physics.space.local_pose(world, physics.space.global_pose(a.location(), a.pose))
	a.travel(world, pose, same_school)
	physics.place(a,same_school)


func command(id: String, data: Dictionary) -> Dictionary:
	if not is_participating(id) or data.get("epoch") != room.epoch: return {"ok": false, "error": "会话已失效。"}
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
		result = _exam_command(a, data) if exam_pending() else gameplay.command(a, data)
	if result.get("ok", false) and data.get("action") in ["interact", "item", "pickup", "drop", "give", "camera_flash", "lift_close"]:
		a.gesture_until = room.tick + roundi(.5 * Engine.physics_ticks_per_second)
	room.remember(id, sequence, result)
	inventory.reconcile(a)
	return result


func input(id: String, data: Dictionary) -> void:
	if not is_participating(id) or room.phase != "playing" or room.paused_left > 0 or data.get("epoch") != room.epoch or not room.members[id]["connected"]: return
	if exam_pending(): return
	if data.has("frames"):
		actors[id].queue_inputs(LanProtocol.inputs(data), data.get("phone") == true and actor(id).bag().has("phone"))
	elif LanProtocol.input_valid(data):
		actors[id].accept_input(data)


func reachable(a: CooperativeActor, entry: Dictionary) -> bool:
	var entries := CooperativeGround.local_entries([entry], a.location(), physics.space)
	if entries.is_empty(): return false
	var e: Dictionary = entries[0]
	var local := Vector3(e["x"], e["y"], e["z"])
	var p: Array = a.pose["position"]
	if Vector2(local.x - p[0], local.z - p[2]).length() > InventoryModule.PICK_REACH or absf(local.y - p[1]) > InventoryModule.PICK_RISE: return false
	var target := physics.space.frame(a.location()) * local if physics.space.contains(a.location()) else local
	var query := PhysicsRayQueryParameters3D.create(physics.actor_position(a) + Vector3.UP * 1.1, target + Vector3.UP * 0.2, 3)
	return physics.zone(a.location()).find_world_3d().direct_space_state.intersect_ray(query).is_empty()


func motion(for_id: String) -> Dictionary:
	var data := {"epoch": room.epoch, "tick": room.tick, "players": {}}
	if not actors.has(for_id): return data
	var viewer: CooperativeActor = actors[for_id]
	var observing := observed(for_id)
	if observing != "": viewer = actor(observing)
	for id: String in actors:
		var a: CooperativeActor = actors[id]
		if room.members[id]["state"] == "departed": continue
		var common := physics.space != null and physics.space.contains(a.location()) and physics.space.contains(viewer.location())
		if id != viewer.id and (CooperativePhysics.private_world(a.location()) or CooperativePhysics.private_world(viewer.location())): continue
		if id != for_id and a.location() != viewer.location() and not common: continue
		if id != viewer.id and bool(a.watcher().hide["on"]): continue
		var school_pose := common and id != viewer.id
		var pose := physics.space.global_pose(a.location(), a.pose) if school_pose else a.pose
		data["players"][id] = {"pose": _motion_pose(pose), "school": school_pose, "world": a.location(), "scene": a.scene_version, "ack": a.processed_sequence, "moving": a.moving, "running": a.running, "seated": a.school().seated, "hiding": bool(a.watcher().hide["on"]), "dead": a.fate().dead}
		var state: Dictionary = data["players"][id]
		if a.seamless_from >= 0: state["seam"] = true
		var body := a.feature(&"body.injury") as BodyModule
		var act := ""
		if a.vehicle: act = "drive" if gameplay.driver == id else "ride"
		elif body.fall != null: act = "fall" if body.fall["kind"] == "roof" else "vault"
		elif body.treat != null: act = "bandage"
		elif a.bag().searching(): act = "search"
		elif a.terminal or a.activities.game == "snake": act = "type"
		elif a.mic: act = "speak"
		elif (a.feature(&"story.knife") as KnifeModule).captured(): act = "crouch"
		elif (a.feature(&"story.paper_plane") as PaperPlaneModule).phase() in ["read","flight"]: act = "read"
		elif a.gesture_until > room.tick: act = "interact"
		elif a.moving and not body.can_run(): act = "limp"
		var gear := int(a.bag().torch_on) + 2 * int(a.bag().brolly_up)
		if (a.held_phone or a.activities.game == "plane") and gear != 3:
			gear |= 4
			if act.is_empty() and not a.moving and not a.school().seated: act = "read"
		if not act.is_empty(): state["act"] = act
		if gear != 0: state["gear"] = gear
	return data


## Millimetre / 0.0001 rad presentation samples keep four-player motion below
## ENet's MTU. Authoritative state and saves retain their full precision.
static func _motion_pose(pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	return {"position":[snappedf(p[0],.001),snappedf(p[1],.001),snappedf(p[2],.001)],
		"yaw":snappedf(pose["yaw"],.0001),"pitch":snappedf(pose["pitch"],.0001)}


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
	data["car_job"] = gameplay.garage_jobs.get(id, {}).duplicate(true)
	data["operation_id"] = gameplay.operation_id(a)
	data["team"] = team_for(a)
	if exam_pending():
		data["exam_pending"] = true
		data["exam_left"] = clampf(a.entrance_exam().deadline - Time.get_unix_time_from_system(), 0, EntranceExam.SECONDS)
	var radio: BroadcastModule = shared[&"story.broadcast"]
	data["radio_live"] = {"held": radio.held, "progress": radio.progress}
	var observing := observed(id)
	if observing != "":
		data["observed"] = actor(observing).capture()
		data["observed"]["id"] = observing
	return data


## Small, reliable team summaries stay out of the MTU-limited motion stream.
func team_for(viewer: CooperativeActor) -> Dictionary:
	var team := {}
	for id: String in actors:
		if room.members[id]["state"] == "departed": continue
		var other := actor(id)
		var distance := physics.actor_distance(viewer, other)
		team[id] = {"seated": other.school().seated, "seat_id": other.school().seat_id, "place": other.school().place_name(other.location(), float(other.pose["position"][1])),
			"distance": snappedf(distance, .1) if is_finite(distance) else -1.0,
			"can_give": id != viewer.id and room.members[id]["connected"] and not viewer.fate().over() and not other.fate().over() and physics.can_exchange(viewer, other)}
	return team


func observed(id: String) -> String:
	if not actors.has(id) or not actor(id).fate().dead or actor(id).fate().wake_pending: return ""
	var alive := room.alive_ids()
	if alive.is_empty(): return ""
	var who := String(spectators.get(id, ""))
	if who not in alive: who = String(alive[0])
	spectators[id] = who
	return who


func capture() -> Dictionary:
	for a: CooperativeActor in actors.values(): inventory.reconcile(a)
	var people := {}
	for id: String in actors: people[id] = actors[id].capture()
	return {"format": "wdfz-godot-coop", "version": 1, "room": room.public_state(), "calendar": calendar.capture(), "actors": people,
		"items": inventory.capture(), "patrol": patrol.capture(), "gameplay": gameplay.capture(), "leases": leases.duplicate(), "lease_info": lease_info.duplicate(true), "seconds": _seconds}


## Caller validates the entire candidate before setup/restore; keep the new room epoch.
func restore(data: Dictionary) -> void:
	calendar.restore(data["calendar"])
	for id: String in actors:
		var member := actor(id)
		member.restore(data["actors"][id])
		member.pose = physics.space.resume_pose(member.location(), member.pose)
		member.session.character_id = room.members[id]["character"]
		room.members[id]["seat"] = member.own_seat
		if is_participating(id): physics.place(member)
		else: physics.remove_actor(id)
	inventory.restore(data["items"])
	for a: CooperativeActor in actors.values(): inventory.restore_phone(a)
	patrol.restore(data["patrol"])
	patrol.synchronize(actors)
	leases = data["leases"].duplicate()
	lease_info.clear()
	for key: String in leases.keys():
		var id := String(leases[key])
		leases.erase(key)
		if is_participating(id) and not actor(id).fate().over(): lease(key, id)
	gameplay.restore(data["gameplay"])
	for key: String in leases.keys():
		if not leases.has(key): continue
		var owner := actor(String(leases[key]))
		var source := key.get_slice("|", 0)
		var active: bool = owner.choice.get("source") == source or gameplay._time_offer.get("owner") == owner.id or (source == "terminal" and owner.terminal) or (source == "broadcast" and (owner.mic or gameplay._radio_job.get("owner") == owner.id)) or (source == "garage" and gameplay.garage_jobs.has(owner.id)) or (source == "exchange" and (shared[&"story.exchange"] as ExchangeModule).s["phase"] == "escort")
		var expired := float(data.get("lease_info", {}).get(key, {}).get("expires", calendar.seconds + 1)) <= calendar.seconds
		if not active or expired: release_source(source, owner.id)
	physics.sync_doors(campus(),gameplay.lifts,gameplay.lift_engines)
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
		gameplay.stories.game = null
		gameplay.stories.sim = null
		for engine: ElevatorModule in gameplay.lift_engines.values():
			engine.closed_hook = Callable()
			engine.unsafe_check = Callable()
		gameplay.lifts.closed_hook = Callable()
		gameplay.lifts.unsafe_check = Callable()
	actors.clear()
	shared.clear()
