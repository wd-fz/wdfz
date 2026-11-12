class_name CooperativeGameplay
extends RefCounted
## Commands and rule events share one authoritative application boundary.
const SOURCES := {"facilities": &"campus.facilities", "routes": &"story.routes", "garage": &"garage.world", "phone": &"phone.network", "broadcast": &"story.broadcast", "exchange": &"story.exchange", "investigation": &"story.investigation", "day": &"school.days", "body": &"body.injury", "anomaly": &"anomaly.world", "marks": &"campus.marks"}
var sim: CooperativeSimulation
var lifts: ElevatorModule
var lift_engines: Dictionary = {}
var lift_owners: Dictionary = {}
var lift_riders: Dictionary = {}
var driver := ""
var passengers: Array = []
var anomaly_owner := ""
var anomaly_round := 0
var anomaly_participants: Array = []
var termination_owner := ""
var _radio_job: Dictionary = {}
var _time_offer: Dictionary = {}
var qualified: Dictionary = {}
var _committing_time := false
var boarding: Dictionary = {}
var _escort_lag: Dictionary = {}
var _escort_lost: Dictionary = {}


func _init(authority: CooperativeSimulation) -> void:
	sim = authority


func setup(seed_value: int) -> void:
	lifts = ElevatorModule.new(CampusData.rooms())
	lifts.reset()
	lifts.set_seed(seed_value)
	lifts.closed_hook = sim.patrol.main.elevator_closed
	# Optional personal elevator fantasies remain a single-player entry until adapted.
	lifts.unsafe_check = func() -> bool: return true
	for host: String in ElevatorModule.HOSTS:
		var engine := ElevatorModule.new(CampusData.rooms())
		engine.reset()
		engine.set_seed(seed_value)
		engine.unsafe_check = func() -> bool: return true
		engine.closed_hook = sim.patrol.main.elevator_closed
		lift_engines[host] = engine
		lift_riders[host] = []
		lifts.lifts[host] = engine.lifts[host]
	for a: CooperativeActor in sim.actors.values():
		a.watcher().elevator = lifts
		a.watcher().camouflage = func() -> bool:
			var radio: BroadcastModule = sim.shared[&"story.broadcast"]
			var previous := radio._c
			var at := a.point(CampusData.rooms())
			radio.set_context({"scene": a.location(), "x": at.x, "y": at.y})
			var covered := radio.cover()
			radio.set_context(previous)
			return covered
		a.watcher().zone_active = func(z: Dictionary) -> bool: return z.get("when") == "broadcast" and (sim.shared[&"story.broadcast"] as BroadcastModule).zone_live()
		var phone := a.feature(&"phone.network") as PhoneModule
		phone.set_seed(seed_value)
	var exchange := sim.shared[&"story.exchange"] as ExchangeModule
	exchange.roll(seed_value)
	sim.patrol.main.elevator = lifts
	sim.patrol.main.zone_active = func(z: Dictionary) -> bool: return z.get("when") == "broadcast" and (sim.shared[&"story.broadcast"] as BroadcastModule).zone_live()


func prepare(a: CooperativeActor) -> Dictionary:
	var ctx := CooperativeContext.base(a)
	for source: String in SOURCES:
		var m := a.feature(SOURCES[source])
		if m.has_method("set_context"): m.call("set_context", CooperativeContext.investigation(a) if source == "investigation" else ctx)
	var body_ctx := ctx.duplicate()
	body_ctx["anomaly"] = bool(ctx["anomaly_active"])
	(a.feature(&"body.injury") as BodyModule).set_context(body_ctx)
	var marks_ctx := ctx.duplicate()
	marks_ctx.merge({"has_chalk": a.bag().has("chalk"), "floor": float(a.pose["position"][1]), "eye": 1.6, "solid": func(q: Vector2) -> bool: return not bool(ctx["can_stand"].call(q))}, true)
	(a.feature(&"campus.marks") as MarksModule).set_context(marks_ctx)
	sim.campus().has_item = a.bag().has
	sim.campus().car_hint = (a.feature(&"garage.world") as GarageModule).car_hint
	sim.campus().facility_hint = (a.feature(&"campus.facilities") as FacilitiesModule).hint
	sim.campus().rest_out = (a.feature(&"campus.facilities") as FacilitiesModule).rest_out
	(a.feature(&"story.routes") as RoutesModule).face_remedy = a.talent().face_remedy
	(a.feature(&"campus.facilities") as FacilitiesModule).rest_intercept = func(key: String) -> bool:
		if _committing_time: return false
		_offer_time(a, float(FacilitiesModule.SAN_ACTS[key]["min"]), {"kind": "rest", "key": key})
		return true
	a.watcher().set_context(CooperativeContext.patrol(a))
	return ctx


func _owner(source: String) -> CooperativeActor:
	var id := String(sim.leases.get(source, ""))
	if sim.actors.has(id) and not sim.actors[id].fate().over(): return sim.actors[id]
	for candidate: String in sim.room.alive_ids():
		if sim.actors.has(candidate): return sim.actors[candidate]
	return null


func personal(a: CooperativeActor, dt: float) -> void:
	if a.fate().dead:
		a.death_elapsed += dt
		if a.fate().wake_pending and a.death_elapsed >= StoryModule.duration(a.fate().death_fx):
			a.fate().finish_wake()
			a.school().dream_wake_reset()
			a.school().tsec = sim.calendar.tsec
			a.school().day = sim.calendar.day
			a.watcher().hide["on"] = false
			(a.feature(&"anomaly.world") as AnomalyModule).dream_wake()
			sim.travel(a, "teach1", a.school().start_seated("teach1"))
			a.school().start_seated("teach1")
			a.event("wake", {"text": "预知梦 · 我回到了自己的座位，队友仍在继续行动。"})
		return
	if a.fate().ended != "": return
	var ctx := prepare(a)
	if a.vehicle: return
	ctx["calendar"] = false
	ctx["snack"] = a.bag().snack_active()
	ctx["pill_san"] = a.bag().step(dt)
	ctx["patrol_threat"] = a.watcher().local_threat() and sim.patrol.target == a.id
	a.school().step(dt, ctx)
	sim.inventory.prepare_search(a)
	a.bag().search_tick(dt, a.location(), ctx["w"])
	sim.inventory.finish_search(a)
	for e: Dictionary in a.school().take_events():
		if e["kind"] == "absence": sim.patrol.permanent[a.id] = String(e["id"])
	var phone := a.feature(&"phone.network") as PhoneModule
	phone.tick(dt, false)
	a.terminal = phone.terminal_open
	drain(a, "phone")
	a.talent().tick_watch(a.school().day, a.school().tsec, SchoolClock.rate_at(a.school().tsec))
	for event: Dictionary in a.talent().take_events(): a.event("notice", event)
	var day := a.feature(&"school.days") as DayModule
	day.tick_day(a.school().day, a.school().tsec)
	drain(a, "day")
	var body := a.feature(&"body.injury") as BodyModule
	body.tick(dt)
	a.school().stam = clampf(a.school().stam, 0, maxf(0, a.school().stamina_max() - body.stamina_cap_drop()))
	drain(a, "body")
	var mates := a.feature(&"school.classmates") as ClassmatesModule
	mates.tick(a.location(), a.point(CampusData.rooms()), a.school().viol, false)
	for e: Dictionary in mates.take_events(): a.event("notice", e)
	if mates.state.get("blocking", false) and mates.state.get("door") is Dictionary:
		var door: Dictionary = mates.state["door"]
		sim.campus().force_close("%s:%d:%d" % [a.location(), int(door["c"]), int(door["r"])])
	if a.school().san > 1: a.school().san = maxf(1, a.school().san - mates.pressure(a.location(), a.school().viol) * dt)
	var exploration := a.feature(&"campus.exploration") as ExplorationModule
	if exploration != null:
		exploration.set_context({"scene": a.location(), "x": ctx["x"], "y": ctx["y"], "door_open": func(c: int, r: int) -> bool: return sim.campus().is_open("%s:%d:%d" % [a.location(), c, r])})
		exploration.tick(dt)
	(a.feature(&"campus.facilities") as FacilitiesModule).spot_tick()
	drain(a, "facilities")
	if not a.choice.is_empty() and a.choice.has("remaining"):
		a.choice["remaining"] = maxf(0.0, float(a.choice["remaining"]) - dt)
		if a.choice["remaining"] <= 0.0: choose(a, -1)
	for job: Dictionary in a.pending.duplicate():
		job["left"] = float(job["left"]) - dt
		if job["left"] <= 0.0:
			a.pending.erase(job)
			if job["kind"] == "portal_ask" and a.location() == job["world"]:
				(a.feature(&"campus.facilities") as FacilitiesModule).portal_ask()
				drain(a, "facilities")
	if float(a.pose["position"][1]) < -8.0: kill(a, "你跌出了有支撑的地方。", "abyss", "campus_fall")


func shared_tick(dt: float) -> void:
	if not _time_offer.is_empty() and sim.calendar.seconds > float(_time_offer.get("expires", 0)): _cancel_time()
	if not boarding.is_empty() and sim.calendar.seconds > float(boarding["expires"]):
		boarding.clear()
		(sim.shared[&"garage.world"] as GarageModule).car_used = false
	var a := _owner("routes")
	if a == null: return
	prepare(a)
	(a.feature(&"story.routes") as RoutesModule).tick(dt)
	drain(a, "routes")
	_lift_tick(dt)
	_garage_tick(dt)
	_broadcast_tick(dt)
	_exchange_tick(dt)
	_anomaly_tick(dt)
	var common_phone: PhoneModule
	if not termination_owner.is_empty() and sim.actors.has(termination_owner): common_phone = sim.actor(termination_owner).feature(&"phone.network") as PhoneModule
	if common_phone != null:
		# The server countdown belongs to the world, even if its first operator died.
		prepare(a)
		common_phone.set_context(CooperativeContext.base(a))
		common_phone.tick_termination(dt)
		for event: Dictionary in common_phone.take_events(): apply_event(a, "phone", event)
		for person: CooperativeActor in sim.actors.values():
			if person.id == termination_owner: continue
			var phone := person.feature(&"phone.network") as PhoneModule
			phone.run_seed = common_phone.run_seed
			phone.attempt_id = common_phone.attempt_id
			phone.puzzle = common_phone.puzzle.duplicate(true)
			phone.termination = common_phone.termination.duplicate(true)


func command(a: CooperativeActor, data: Dictionary) -> Dictionary:
	if int(data.get("scene", -1)) != a.scene_version: return {"ok": false, "error": "场景已经变化，请重试。"}
	if not data.get("action") is String: return {"ok": false, "error": "操作格式无效。"}
	for key: String in ["item", "to", "operation", "line", "paper", "route"]:
		if data.has(key) and (not data[key] is String or String(data[key]).length() > 256): return {"ok": false, "error": "操作参数无效。"}
	for key: String in ["accept", "held"]:
		if data.has(key) and not data[key] is bool: return {"ok": false, "error": "操作确认无效。"}
	var action := String(data.get("action", ""))
	var ctx := prepare(a)
	if not a.choice.is_empty() and action not in ["choice", "cancel", "ending_confirm", "time_confirm"]: return {"ok": false, "error": "请先完成当前选择。"}
	match action:
		"debug_recover", "debug_teleport":
			if a.id != sim.room.host_id: return {"ok": false, "error": "只有房主可执行影响玩法的调试操作。"}
			if action == "debug_teleport":
				var target := sim.actor(String(data.get("to", "")))
				if target == null or target.fate().over() or target.vehicle: return {"ok": false, "error": "传送目标无效。"}
				(a.feature(&"anomaly.world") as AnomalyModule).end_now()
				sim.travel(a, target.location(), target.pose)
			else:
				a.school().san = 100.0
				a.school().viol = 0.0
				a.school().stam = a.school().stamina_max()
			sim.room.debug_run = true
			for member: CooperativeActor in sim.actors.values(): member.event("notice", {"text": "房主使用了调试操作，本局已标记为调试合作。"})
		"interact": interact(a)
		"choice":
			if not SaveSchema.is_integer(data.get("index"), -1, 32): return {"ok": false, "error": "选项无效。"}
			choose(a, int(data["index"]))
		"cancel":
			if a.choice.get("source") == "day": (a.feature(&"school.days") as DayModule).answer(-1, ctx)
			a.choice.clear()
			a.terminal = false
			(a.feature(&"phone.network") as PhoneModule).terminal_open = false
			sim.release(a.id)
		"item": apply_result(a, a.bag().use(String(data.get("item", "")), a.school().tsec))
		"drop":
			if not sim.inventory.drop(a, String(data.get("item", ""))): return {"ok": false, "error": "物品无法丢弃，地面空间可能已满。"}
		"pickup":
			if not sim.inventory.pickup(a, String(data.get("uid", "")), sim.reachable): return {"ok": false, "error": "物品已被拿走、无法触及或背包已满。"}
		"give":
			var other := sim.actor(String(data.get("to", "")))
			if other == null or other.id not in sim.room.alive_ids() or not sim.room.members[other.id]["connected"] or not sim.reachable(a, {"x": other.pose["position"][0], "y": other.pose["position"][1], "z": other.pose["position"][2]}) or not sim.inventory.transfer(a, other, String(data.get("item", ""))): return {"ok": false, "error": "请靠近队友并确认对方背包有空位。"}
		"hot":
			if not SaveSchema.is_integer(data.get("index"), 0, 1): return {"ok": false, "error": "快捷栏无效。"}
			a.bag().set_hot(int(data["index"]), data.get("item"))
		"lesson":
			if sim.lease("investigation", a.id) and (a.feature(&"story.investigation") as InvestigationModule).open_desk(): drain(a, "investigation")
			else:
				(a.feature(&"school.days") as DayModule).press(ctx)
				drain(a, "day")
		"think":
			if sim.lease("facilities", a.id):
				(a.feature(&"campus.facilities") as FacilitiesModule).think()
				drain(a, "facilities")
		"notes_focus":
			(a.feature(&"story.investigation") as InvestigationModule).set_focus(String(data.get("route", "")))
		"desk":
			if sim.lease("investigation", a.id):
				(a.feature(&"story.investigation") as InvestigationModule).open_desk()
				drain(a, "investigation")
		"phone":
			var phone := a.feature(&"phone.network") as PhoneModule
			match String(data.get("operation", "")):
				"wireless": phone.toggle_wireless()
				"download": phone.toggle_download()
				"sync":
					if phone.available() and phone.device["network"]: (a.feature(&"story.routes") as RoutesModule).sync("phone")
				_: return {"ok": false, "error": "手机操作无效。"}
			drain(a, "phone")
			drain(a, "routes")
		"terminal":
			if not a.terminal or not sim.lease("terminal", a.id): return {"ok": false, "error": "终端已被其他玩家占用。"}
			var text := String(data.get("line", "")).left(256)
			var phone := a.feature(&"phone.network") as PhoneModule
			phone.run_line(text)
			termination_owner = a.id
			drain(a, "phone")
		"mic":
			if sim.leases.get("broadcast") != a.id: return {"ok": false, "error": "请先走到广播台。"}
			if data.has("paper"): (a.feature(&"story.broadcast") as BroadcastModule).select(String(data["paper"]))
			(a.feature(&"story.broadcast") as BroadcastModule).hold(bool(data.get("held", false)))
		"ending_request":
			if qualified.is_empty(): return {"ok": false, "error": "尚未达成路线条件。"}
			_offer_ending(a, String(qualified["route"]))
		"lift_close": _lift_for(a).close_door(a.location(), ctx["w"])
		"ending_confirm":
			_confirm_ending(a, bool(data.get("accept", false)))
		"board_confirm": _confirm_board(a, bool(data.get("accept", false)))
		"time_confirm": _confirm_time(a, bool(data.get("accept", false)))
		_: return {"ok": false, "error": "未知联机操作。"}
	for text: String in a.bag().take_notices(): a.event("notice", {"text": text})
	return {"ok": true}


func interact(a: CooperativeActor) -> void:
	var weird := a.feature(&"anomaly.world") as AnomalyModule
	if weird.near_roster():
		weird.use_roster(a.bag().has("pen") or a.bag().has("chalk"))
		drain(a, "anomaly")
		return
	if bool(a.watcher().hide["on"]):
		apply_result(a, a.watcher().hide_out())
		return
	if a.school().seated:
		apply_result(a, a.school().stand_up())
		return
	var body := a.feature(&"body.injury") as BodyModule
	if body.ask_vault() or body.use_clinic():
		drain(a, "body")
		return
	var p: Array = a.pose["position"]
	var feet := Vector3(p[0], p[1], p[2])
	var look := Basis.from_euler(Vector3(float(a.pose["pitch"]), float(a.pose["yaw"]), 0)) * Vector3.FORWARD
	var pick := a.bag().ground_target(a.location(), feet, feet + Vector3.UP * 1.6, look)
	if pick >= 0 and pick < sim.inventory.ground.size():
		sim.inventory.pickup(a, String(sim.inventory.ground[pick]["uid"]), sim.reachable)
		return
	var radio := a.feature(&"story.broadcast") as BroadcastModule
	if sim.lease("broadcast", a.id):
		if radio.use_here():
			drain(a, "broadcast")
			return
		if not radio.held: sim.leases.erase("broadcast")
	var visit := a.feature(&"story.exchange") as ExchangeModule
	if sim.lease("exchange", a.id):
		if visit.use_here():
			drain(a, "exchange")
			return
		if visit.s["phase"] not in ["escort", "qualified"]: sim.leases.erase("exchange")
	var here := a.point(CampusData.rooms())
	var engine := _lift_for(a)
	if a.location() in ElevatorModule.RIDE_ROOMS or engine.in_cabin(a.location(), here):
		var host := _lift_host(a)
		if String(lift_owners.get(host, "")).is_empty() or lift_owners[host] == a.id:
			lift_owners[host] = a.id
			apply_result(a, engine.use_at(a.location(), here))
		else: a.event("notice", {"text": "队友正在操作电梯面板。"})
		return
	apply_result(a, sim.campus().interact_at(a.location(), a.pose))


func apply_result(a: CooperativeActor, result: Dictionary) -> void:
	if result.is_empty(): return
	for key: String in ["notice", "toast"]:
		if result.has(key): a.event("notice", {"text": result[key]})
	if result.has("pose"): a.pose = result["pose"].duplicate(true)
	if result.has("x") and result.has("y"):
		var at := CampusGeometry.to_scene(CampusData.rooms().get(a.location()), Vector2(float(result["x"]), float(result["y"])))
		a.pose["position"] = [at.x, a.pose["position"][1], at.y]
		if result.has("ang"):
			a.pose["yaw"] = CampusGeometry.yaw_from_ang(float(result["ang"]))
			a.input["yaw"] = a.pose["yaw"]
	if result.has("travel"): sim.travel(a, String(result["travel"]["world"]), result["travel"]["pose"])
	if result.has("choice"): _choice(a, "lift", result["choice"])
	if result.has("seat"):
		var seat: Array = result["seat"]
		var id := "%s:%d:%d" % [a.location(), int(seat[0]), int(seat[1])]
		for other: CooperativeActor in sim.actors.values():
			if other.id != a.id and other.school().seated and other.school().seat_id == id:
				a.event("notice", {"text": "这个座位已经有人了。"})
				return
		apply_result(a, a.school().sit(a.location(), int(seat[0]), int(seat[1])))
	if result.has("search"):
		var seat_id := "%s:%d:%d" % [a.location(), int(result["search"][0]), int(result["search"][1])]
		if seat_id == a.own_seat:
			apply_result(a, {"seat": result["search"]})
			return
		var reserved := false
		for person: CooperativeActor in sim.actors.values(): reserved = reserved or person.own_seat == seat_id
		if not reserved and (a.feature(&"school.classmates") as ClassmatesModule).occupied(a.location(), int(result["search"][0]), int(result["search"][1])):
			a.event("notice", {"text": "这个座位坐着同学。"})
			return
		if not sim.inventory.search(a, a.location(), int(result["search"][0]), int(result["search"][1]), a.point(CampusData.rooms())): a.event("notice", {"text": "队友正在翻找这里。"})
	if result.has("hide"):
		for other: CooperativeActor in sim.actors.values():
			if other.id != a.id and other.location() == a.location() and bool(other.watcher().hide["on"]) and [other.watcher().hide["c"], other.watcher().hide["r"]] == result["hide"]: return
		apply_result(a, a.watcher().hide_in(int(result["hide"][0]), int(result["hide"][1])))
		sim.patrol.lockers[a.id] = a.watcher().pat["lockerMemory"].duplicate(true)
		if sim.patrol.target == a.id:
			sim.patrol.main.pat["lastSeen"] = a.watcher().pat["lastSeen"]
		for e: Dictionary in a.watcher().take_events(): apply_event(a, "patrol", e)
	if result.has("elevator"): apply_result(a, _lift_for(a).use_at(a.location(), a.point(CampusData.rooms())))
	var routes := a.feature(&"story.routes") as RoutesModule
	if result.has("terminal"):
		if a.location() == "admin3": routes.use_data(a.location())
		else: routes.use_terminal(a.location(), a.bag().has("usb") or a.talent().has("code"), a.school().day)
		drain(a, "routes")
	if result.has("gate") and sim.lease("routes", a.id):
		routes.use_gate(String(result["gate"]), a.school().day)
		drain(a, "routes")
	if result.has("trash"):
		routes.use_trash(a.location(), a.school().day)
		drain(a, "routes")
	if result.has("facility"):
		var f: Array = result["facility"]
		if not _committing_time and String(f[0]) in ["Z", "C"]:
			if sim.lease("facilities", a.id): _offer_time(a, 3.0 if f[0] == "Z" else 5.0, {"kind": "facility", "value": f.duplicate()})
			return
		if a.location() == "lab3" and String(f[0]) in ["n", "K"]:
			if sim.lease("terminal", a.id):
				var at := CampusGeometry.tile_center(CampusData.rooms()["lab3"], int(f[1]), int(f[2]))
				(a.feature(&"phone.network") as PhoneModule).computer_menu(at.x, at.y)
				drain(a, "phone")
		elif sim.lease("facilities", a.id):
			(a.feature(&"campus.facilities") as FacilitiesModule).use(CampusData.rooms().get(a.location()), String(f[0]), int(f[1]), int(f[2]))
			drain(a, "facilities")
	if result.has("podium") and sim.lease("investigation", a.id):
		if a.location() == "teach1" and result["podium"] == CampusData.campus().get("own_podium", []):
			(a.feature(&"story.investigation") as InvestigationModule).notice()
			drain(a, "investigation")
		else:
			sim.inventory.prepare_search(a)
			apply_result(a, a.bag().podium(a.location(), int(result["podium"][0]), int(result["podium"][1])))
			sim.inventory.finish_search(a)
	if result.has("facility_item") and sim.lease("facilities", a.id):
		(a.feature(&"campus.facilities") as FacilitiesModule).use_item(String(result["facility_item"]))
		drain(a, "facilities")
	if result.has("rest") and sim.lease("facilities", a.id):
		(a.feature(&"campus.facilities") as FacilitiesModule).rest(String(result["rest"]))
		drain(a, "facilities")
	if result.has("leave") and a.school().use_leave(): a.bag().remove("leave")
	if result.has("phone"): a.event("phone")
	if result.has("chalk") and sim.lease("marks", a.id):
		(a.feature(&"campus.marks") as MarksModule).use_chalk()
		drain(a, "marks")
	if result.has("medkit"):
		(a.feature(&"body.injury") as BodyModule).use_medkit()
		drain(a, "body")
	if result.has("car") and sim.lease("garage", a.id):
		(a.feature(&"garage.world") as GarageModule).inspect_car(int(result["car"][0]), int(result["car"][1]))
		drain(a, "garage")
	if result.has("car_key"): a.event("notice", {"text": "钥匙车牌：" + (a.feature(&"garage.world") as GarageModule).key_label()})
	if result.has("coin"):
		if (a.feature(&"garage.world") as GarageModule).throw_coin(): a.bag().remove("coin")
		drain(a, "garage")
	if result.has("san"): a.school().change_san(float(result["san"]), 0.0)
	if result.has("maze_enter"): a.event("notice", {"text": "这个隐藏空间暂未开放合作入口。"})


func _choice(a: CooperativeActor, source: String, e: Dictionary) -> void:
	var data := e.duplicate(true)
	data["source"] = source
	data["id"] = a.event_sequence + 1
	if e.has("timer") or e.has("timeout"): data["remaining"] = float(e.get("timer", e.get("timeout", 0)))
	a.choice = data
	a.clear_input()
	a.event("choice", {"id": data["id"]})


func choose(a: CooperativeActor, index: int) -> void:
	if a.choice.is_empty(): return
	var choice := a.choice.duplicate(true)
	var source := String(choice["source"])
	if index >= (choice.get("labels", []) as Array).size(): return
	a.choice.clear()
	var ctx := prepare(a)
	if not _committing_time and index == 0 and source == "facilities" and (a.feature(&"campus.facilities") as FacilitiesModule)._pending.get("kind") == "meal":
		_offer_time(a, 10.0, {"kind": "meal"})
		return
	if not _committing_time and index == 0 and source == "investigation" and (a.feature(&"story.investigation") as InvestigationModule)._pending.get("kind") == "supply":
		_offer_time(a, 6.0, {"kind": "supply"})
		return
	match source:
		"body":
			if index == 0: (a.feature(&"body.injury") as BodyModule).vault()
		"lift":
			if index >= 0 and index < choice.get("values", []).size():
				var engine := _lift_for(a)
				var before := a.location()
				var result := engine.press(choice["values"][index], a.location(), a.pose)
				_lift_result(engine, _lift_host(a), a, before, result)
		"routes": (a.feature(&"story.routes") as RoutesModule).choose(index, a.fate().diff)
		"phone":
			var phone := a.feature(&"phone.network") as PhoneModule
			if choice.get("menu") == "phone": phone.phone_choose(index)
			else: phone.computer_choose(index, float(choice.get("x", 0)), float(choice.get("y", 0)))
		"day":
			if choice.get("menu") == "lesson": (a.feature(&"school.days") as DayModule).answer(index, ctx)
			elif index == 1: apply_result(a, a.school().stand_up())
			elif index == 0:
				var until := float(SchoolClock.period_at(a.school().tsec)[1])
				_offer_time(a, maxf(0.0, until - a.school().tsec), {"kind": "lesson", "key": DayModule.lesson_key_of(a.school().day, a.school().tsec)})
		"anomaly":
			var ids: Array = choice.get("ids", [])
			if not ids.is_empty(): (a.feature(&"anomaly.world") as AnomalyModule).choose(String(ids[index if index >= 0 else 0]))
		_:
			if SOURCES.has(source): a.feature(SOURCES[source]).call("choose", index)
	if SOURCES.has(source): drain(a, source)
	if a.choice.is_empty() and source not in ["garage", "broadcast", "exchange", "phone"]: sim.leases.erase(source)


func drain(a: CooperativeActor, source: String) -> void:
	if not SOURCES.has(source): return
	var m := a.feature(SOURCES[source])
	for e: Dictionary in m.call("take_events"): apply_event(a, source, e)


func apply_event(a: CooperativeActor, source: String, e: Dictionary) -> void:
	match String(e["kind"]):
		"notice", "toast", "say": a.event("notice", {"text": String(e.get("text", ""))})
		"san", "rest_gain", "hurt":
			var amount := float(e.get("amount", 0.0))
			if e["kind"] == "hurt": amount = -amount
			if e["kind"] == "rest_gain": amount = snappedf(float(e["base"]) * float(a.school().pressure()["rest"]), 0.1)
			a.school().san = clampf(a.school().san + amount, float(e.get("min", 0.0)), float(e.get("max", 100.0)))
		"stamina": a.school().stam = minf(a.school().stamina_max(), a.school().stam + float(e["amount"]))
		"violation": a.school().add_violation(float(e["amount"]))
		"remove_item", "remove": a.bag().remove(String(e["id"]))
		"give":
			if a.bag().add(String(e["id"])) and source == "body":
				(a.feature(&"body.injury") as BodyModule).gave_medkit(String(e["day"]))
		"land":
			var outside := CampusData.layout("out")
			var room: Dictionary = CampusData.rooms()[e["room"]]
			var target := Vector2(1000, 1000)
			for object: Dictionary in outside["objects"]:
				if object["id"] != room.get("host"): continue
				var side := int(e["side"])
				var cx := (float(object["x"]) + float(object["w"]) / 2.0) * 2.0
				var cy := (float(object["y"]) + float(object["h"]) / 2.0) * 2.0
				var offset := (float(object["w"]) / 2.0 + 5.0) * 2.0 * (side if side != 0 else 1)
				target = Vector2(cx + offset, cy)
				for k in 12:
					var p := Vector2(cx + offset + float(k % 3 - 1) * 6.0, cy + (floor(k / 3.0) - 1.5) * 10.0)
					var cell := sim.patrol.main.nav.cell("out", PatrolNav.point("out", p.x, p.y))
					if sim.patrol.main.nav.is_free("out", cell.x, cell.y):
						target = p
						break
			var at := CampusGeometry.to_scene(null, target)
			sim.travel(a, "out", {"position": [at.x, 0.05, at.y], "yaw": a.pose["yaw"], "pitch": 0.0})
		"choice": _choice(a, source, e)
		"kill": kill(a, String(e["msg"]), String(e["fx"]), String(e["source"]))
		"save": sim.checkpoint_requested.emit()
		"record":
			var notebook := a.feature(&"story.investigation") as InvestigationModule
			notebook.set_context(CooperativeContext.investigation(a))
			notebook.record(String(e["id"]), String(e["text"]), "事实", String(e.get("source", "")))
		"ending": _offer_ending(a, String(e["id"]))
		"travel":
			var world := String(e["world"])
			var pose := sim.spawn(world)
			if e.has("x"):
				var at := CampusGeometry.to_scene(CampusData.rooms().get(world), Vector2(float(e["x"]), float(e["y"])))
				pose = {"position": [at.x, 0.05, at.y], "yaw": CampusGeometry.yaw_from_ang(float(e.get("ang", 0))), "pitch": 0.0}
			sim.travel(a, world, pose)
		"advance", "advance_time":
			if _committing_time: _advance_time(float(e["minutes"]))
			else: _offer_time(a, float(e["minutes"]))
		"permit": a.school().leave_until = maxf(a.school().leave_until, float(e["until"]))
		"outing": a.school().grant_outing(false)
		"chalk": a.bag().add("chalk")
		"supply":
			if a.bag().add("pill") and e.get("pay", false): a.bag().remove("coin")
		"spots":
			for name: String in e["names"]: (a.feature(&"campus.facilities") as FacilitiesModule).spots[name] = true
		"anomaly_lock": (a.feature(&"anomaly.world") as AnomalyModule).lock_forecast()
		"anomaly_end": (a.feature(&"anomaly.world") as AnomalyModule).end_now()
		"exam_start":
			for other: CooperativeActor in sim.actors.values(): other.school().exam_start()
		"later": a.pending.append({"kind": "portal_ask", "world": a.location(), "left": float(e["seconds"])})
		"reveal": sim.patrol.report(a)
		"sync":
			(a.feature(&"story.routes") as RoutesModule).sync("phone")
			drain(a, "routes")
		"terminal": a.terminal = true
		"rest_pc":
			(a.feature(&"campus.facilities") as FacilitiesModule).rest("pc")
			drain(a, "facilities")
		"drive": _board_car(a)
		"mic": a.event("mic")
		"job": _radio_job = {"owner": a.id, "index": int(e["index"]), "left": float(e["seconds"]), "world": a.location(), "pose": a.pose.duplicate(true)}
		"guard":
			(a.feature(&"campus.facilities") as FacilitiesModule)._guard()
			drain(a, "facilities")
		"turn":
			a.pose["yaw"] = wrapf(float(a.pose["yaw"]) + float(e["angle"]), -PI, PI)
			a.input["yaw"] = a.pose["yaw"]
		_: pass # Presentation-only sounds/facts do not mutate cooperative authority.


func kill(a: CooperativeActor, message: String, fx: String, source: String) -> void:
	if a.fate().over(): return
	var elixir := a.bag().has("elixir")
	var immune := not elixir and a.talent().prevent_death()
	var result := a.fate().kill(message, fx, source, {"day": a.school().day, "has_elixir": elixir, "immune": immune})
	if result.has("protected"):
		if elixir: a.bag().remove("elixir")
		a.school().survive(source)
		if sim.patrol.target == a.id: sim.patrol.main.rescued()
		(a.feature(&"anomaly.world") as AnomalyModule).end_now()
		a.event("notice", {"text": result["notice"]})
		return
	a.death_elapsed = 0.0
	cancel_actor_jobs(a)
	a.event("death", {"fx": fx, "source": source, "text": message})
	if not a.fate().wake_pending:
		sim.room.death(a.id)
		sim.inventory.recover(a)


func _offer_time(a: CooperativeActor, minutes: float, operation: Dictionary = {}) -> void:
	if not _time_offer.is_empty():
		a.event("notice", {"text": "已有一项全队等待提议，请先处理。"})
		return
	_time_offer = {"id": "%d:%d" % [sim.room.tick, a.event_sequence], "minutes": minutes, "confirmed": [a.id], "owner": a.id, "scene": a.scene_version, "position": a.pose["position"].duplicate(), "expires": sim.calendar.seconds + 30.0, "operation": operation}
	for other: CooperativeActor in sim.actors.values():
		if not other.fate().over(): other.event("time_offer", {"minutes": minutes})
	if sim.room.alive_ids().size() == 1: _confirm_time(a, true)


func _cancel_time() -> void:
	var owner := String(_time_offer.get("owner", ""))
	_time_offer.clear()
	sim.release(owner)


func _confirm_time(a: CooperativeActor, accept: bool) -> void:
	if _time_offer.is_empty(): return
	var owner := sim.actor(String(_time_offer.get("owner", "")))
	if not accept or owner == null or owner.fate().over() or owner.scene_version != _time_offer["scene"] or sim.calendar.seconds > float(_time_offer["expires"]):
		_cancel_time()
		return
	var start: Array = _time_offer["position"]
	var now: Array = owner.pose["position"]
	if Vector3(start[0], start[1], start[2]).distance_to(Vector3(now[0], now[1], now[2])) > 0.6:
		_cancel_time()
		return
	if a.id not in _time_offer["confirmed"]: _time_offer["confirmed"].append(a.id)
	for id: String in sim.room.alive_ids():
		var p := sim.actor(id)
		if id not in _time_offer["confirmed"] or not sim.room.members[id]["connected"]: return
		if p.fate().over() or p.watcher().local_threat() or p.school().inspection_pending() or (p.feature(&"anomaly.world") as AnomalyModule).is_active() or p.bag().searching() or not p.choice.is_empty() or p.terminal or p.vehicle:
			a.event("notice", {"text": "队友当前遇险或仍有操作未结束，等待已取消。"})
			_cancel_time()
			return
	var offer := _time_offer.duplicate(true)
	_time_offer.clear()
	_committing_time = true
	prepare(owner)
	var operation: Dictionary = offer["operation"]
	match String(operation.get("kind", "")):
		"rest":
			(owner.feature(&"campus.facilities") as FacilitiesModule).rest(String(operation["key"]))
			drain(owner, "facilities")
		"facility": apply_result(owner, {"facility": operation["value"]})
		"meal":
			var facility := owner.feature(&"campus.facilities") as FacilitiesModule
			facility._pending = {"kind": "meal"}
			facility.choose(0)
			drain(owner, "facilities")
		"supply":
			var notebook := owner.feature(&"story.investigation") as InvestigationModule
			if not notebook.supply["taken"] and not owner.bag().has("pill") and owner.bag().bag.size() < owner.bag().capacity():
				notebook._pending = {"kind": "supply"}
				notebook.choose(0)
				drain(owner, "investigation")
				_advance_time(float(offer["minutes"]))
		"lesson":
			var day := owner.feature(&"school.days") as DayModule
			if operation["key"] == DayModule.lesson_key_of(owner.school().day, owner.school().tsec) and day.lessons.has(operation["key"]) and not day.lessons[operation["key"]].get("waitUsed", false):
				day.lessons[operation["key"]]["waitUsed"] = true
				_advance_time(maxf(0, float(SchoolClock.period_at(owner.school().tsec)[1]) - owner.school().tsec))
		_: _advance_time(float(offer["minutes"]))
	_committing_time = false
	sim.release(owner.id)
	sim.checkpoint_requested.emit()


func _advance_time(minutes: float) -> void:
	for p: CooperativeActor in sim.actors.values(): p.school().advance_game_time(minutes)
	var first: SchoolModule = sim.actors.values()[0].school()
	sim.calendar.tsec = first.tsec
	sim.calendar.day = first.day


func _ending_participants() -> Array:
	var participants: Array = []
	if qualified.is_empty(): return participants
	var route := String(qualified["route"])
	var anchor := Vector2(float(qualified["x"]), float(qualified["y"]))
	for id: String in sim.room.alive_ids():
		var other := sim.actor(id)
		if other.fate().over(): continue
		if route == "car" and id in passengers and other.vehicle: participants.append(id)
		elif route == "cyber": participants.append(id)
		elif other.location() == qualified["world"] and other.point(CampusData.rooms()).distance_to(anchor) <= (36.0 if route == "portal" else 90.0):
			prepare(other)
			if route == "dismissal" and not (other.feature(&"story.broadcast") as BroadcastModule).cover(): continue
			if route == "international" and (_escort_lost.get(id, false) or (other.feature(&"story.exchange") as ExchangeModule).tail_dist() > ExchangeModule.FOLLOW): continue
			participants.append(id)
	return participants


func _offer_ending(a: CooperativeActor, route: String) -> void:
	if route not in CooperativeRoom.ENDINGS:
		a.event("notice", {"text": "这条隐藏路线暂未开放合作结算。"})
		return
	if qualified.get("route") != route:
		var at := a.point(CampusData.rooms())
		qualified = {"owner": a.id, "route": route, "world": a.location(), "x": at.x, "y": at.y}
	if sim.room.ending_offer.get("route") == route: return
	var participants := _ending_participants()
	if not sim.room.offer_ending(a.id, route, participants):
		a.event("notice", {"text": "路线条件已达成。请让所有存活队友集合，再从队伍窗口发起逃离。"})
		return
	sim.room.ending_offer["id"] = "%d:%d" % [sim.room.tick, a.event_sequence]
	for id: String in participants: sim.actor(id).event("ending_offer", {"route": route})
	_confirm_ending(a, true)


func _confirm_ending(a: CooperativeActor, accept: bool) -> void:
	if sim.room.ending_offer.is_empty(): return
	var participants := _ending_participants()
	for id: String in sim.room.alive_ids():
		if id not in participants or not sim.room.members[id]["connected"]:
			sim.room.ending_offer.clear()
			a.event("notice", {"text": "成员位置或状态已变化，请重新集合后发起逃离。"})
			return
	if sim.room.confirm_ending(a.id, accept): _finish_ending()


func _finish_ending() -> void:
	for a: CooperativeActor in sim.actors.values():
		a.fate().ended = sim.room.ending
		a.event("ending", {"route": sim.room.ending})
	sim.checkpoint_requested.emit()


func disconnected(id: String) -> void:
	if sim.actors.has(id): cancel_actor_jobs(sim.actor(id))
	if driver == id:
		for other: String in passengers:
			if other != id and sim.room.members[other]["connected"] and not sim.actor(other).fate().dead:
				driver = other
				break
	for host: String in lift_owners.keys():
		if lift_owners[host] == id: lift_owners.erase(host)
	_cancel_time()


func cancel_actor_jobs(a: CooperativeActor) -> void:
	if _radio_job.get("owner") == a.id: _radio_job.clear()
	if sim.leases.get("broadcast") == a.id: (sim.shared[&"story.broadcast"] as BroadcastModule).hold(false)
	if sim.leases.get("garage") == a.id: (sim.shared[&"garage.world"] as GarageModule).job = null
	(a.feature(&"phone.network") as PhoneModule).terminal_open = false
	a.terminal = false
	sim.release(a.id)


func _lift_host(a: CooperativeActor) -> String:
	return "lab" if a.location().begins_with("lab") or a.location() == "lift_lab" else "teach"


func _lift_for(a: CooperativeActor) -> ElevatorModule:
	return lift_engines[_lift_host(a)]


func _lift_result(engine: ElevatorModule, host: String, a: CooperativeActor, from: String, result: Dictionary) -> void:
	if not result.has("travel"):
		apply_result(a, result)
		return
	var destination := String(result["travel"]["world"])
	var riders: Array = []
	for other: CooperativeActor in sim.actors.values():
		if other.location() != from or other.fate().over(): continue
		if from == "lift_" + host or engine.in_cabin(from, other.point(CampusData.rooms())): riders.append(other.id)
	lift_riders[host] = riders
	for id: String in riders:
		var other := sim.actor(id)
		var local: Variant = engine.local(from, other.point(CampusData.rooms()))
		if local == null: local = Vector2(-1.1, 0)
		var w := engine.world(destination, clampf(local.x, -1.61, -0.84), clampf(local.y, -0.41, 0.41))
		var ang := engine._turn(from, destination, CampusGeometry.ang_from_yaw(float(other.pose["yaw"])))
		sim.travel(other, destination, engine._pose(destination, w, ang, float(other.pose["pitch"])))


func _lift_tick(dt: float) -> void:
	for host: String in ElevatorModule.HOSTS:
		var engine: ElevatorModule = lift_engines[host]
		var car: Dictionary = engine.lifts[host]
		for person: CooperativeActor in sim.actors.values():
			if person.fate().over(): continue
			var floor_id := host + str(int(car["floor"]))
			if person.location() == floor_id and engine._in_doorway(floor_id, person.point(CampusData.rooms())):
				car["dir"] = 1
				car["hold"] = maxf(1, float(car["hold"]))
		var pilot: CooperativeActor
		var owner := String(lift_owners.get(host, ""))
		if sim.actors.has(owner) and not sim.actor(owner).fate().over(): pilot = sim.actor(owner)
		if pilot == null:
			for a: CooperativeActor in sim.actors.values():
				if a.fate().over() or _lift_host(a) != host: continue
				if a.location() == "lift_" + host or engine.in_cabin(a.location(), a.point(CampusData.rooms())):
					pilot = a
					break
		if pilot != null:
			var from := pilot.location()
			_lift_result(engine, host, pilot, from, engine.step(dt, from, pilot.pose))
			if not engine.ride.is_empty(): engine.ride["rare"] = false
			if not engine.in_cabin(pilot.location(), pilot.point(CampusData.rooms())) and pilot.location() != "lift_" + host: lift_owners.erase(host)
		else: engine.step(dt, "", {})
		lifts.lifts[host] = engine.lifts[host]
	for a: CooperativeActor in sim.actors.values():
		var view := a.feature(&"campus.elevator") as ElevatorModule
		view.lifts = lifts.lifts
		view.ride = _lift_for(a).ride if a.location() == "lift_" + _lift_host(a) or _lift_for(a).in_cabin(a.location(), a.point(CampusData.rooms())) else {}


func _board_car(a: CooperativeActor) -> void:
	var garage := a.feature(&"garage.world") as GarageModule
	var board: Array = []
	for id: String in sim.room.alive_ids():
		var other := sim.actor(id)
		if other.location() == a.location() and other.point(CampusData.rooms()).distance_to(a.point(CampusData.rooms())) <= 50.0: board.append(id)
	if board.size() != sim.room.alive_ids().size():
		garage.cancel_chase()
		garage.car_used = false
		a.event("notice", {"text": "车门已经打开。请让存活队友靠近车辆后一起上车。"})
		return
	if garage.driving() or not boarding.is_empty(): return
	boarding = {"driver": a.id, "members": board, "confirmed": [], "expires": sim.calendar.seconds + 30.0}
	for id: String in board: sim.actor(id).event("board_offer")


func _confirm_board(a: CooperativeActor, accept: bool) -> void:
	if boarding.is_empty() or a.id not in boarding["members"]: return
	var garage: GarageModule = sim.shared[&"garage.world"]
	if not accept or sim.calendar.seconds > float(boarding["expires"]):
		boarding.clear()
		garage.car_used = false
		return
	if a.id not in boarding["confirmed"]: boarding["confirmed"].append(a.id)
	var pilot := sim.actor(boarding["driver"])
	for id: String in sim.room.alive_ids():
		var p := sim.actor(id)
		if id not in boarding["confirmed"] or not sim.room.members[id]["connected"] or p.location() != pilot.location() or p.point(CampusData.rooms()).distance_to(pilot.point(CampusData.rooms())) > 50.0: return
	driver = pilot.id
	passengers = sim.room.alive_ids()
	boarding.clear()
	garage.start_chase()
	for id: String in passengers:
		sim.actor(id).vehicle = true
		sim.actor(id).event("drive", {"driver": driver})


func _garage_tick(dt: float) -> void:
	var a := _owner("garage")
	if a == null: return
	var garage := a.feature(&"garage.world") as GarageModule
	if not driver.is_empty() and sim.actors.has(driver) and garage.driving():
		a = sim.actor(driver)
		prepare(a)
		var online := bool(sim.room.members[driver]["connected"])
		garage.chase_step(dt, {"throttle": online and float(a.input["y"]) < -0.08, "braking": not online or float(a.input["y"]) > 0.08, "steering": float(a.input["x"]) if online else 0.0})
		for e: Dictionary in garage.take_events():
			if e["kind"] == "kill":
				for id: String in passengers:
					sim.actor(id).vehicle = false
					apply_event(sim.actor(id), "garage", e)
				passengers.clear()
				driver = ""
			elif e["kind"] != "drive": apply_event(a, "garage", e)
		return
	if garage.job == null:
		var nearest := INF
		for other: CooperativeActor in sim.actors.values():
			if other.location() != "garage1" or other.fate().over(): continue
			var d := other.point(CampusData.rooms()).distance_to(Vector2(float(garage.roam["x"]), float(garage.roam["y"])))
			if d < nearest:
				nearest = d
				a = other
	prepare(a)
	garage.tick(dt)
	drain(a, "garage")


func _broadcast_tick(dt: float) -> void:
	var a := _owner("broadcast")
	if a == null: return
	prepare(a)
	var radio := a.feature(&"story.broadcast") as BroadcastModule
	if not _radio_job.is_empty() and sim.actors.has(_radio_job["owner"]):
		var worker := sim.actor(_radio_job["owner"])
		var before: Array = _radio_job["pose"]["position"]
		var now: Array = worker.pose["position"]
		if worker.location() != _radio_job["world"] or Vector3(before[0], before[1], before[2]).distance_to(Vector3(now[0], now[1], now[2])) > 0.55:
			_radio_job.clear()
		else:
			_radio_job["left"] = float(_radio_job["left"]) - dt
			if _radio_job["left"] <= 0:
				prepare(worker)
				radio.job_done(int(_radio_job["index"]))
				drain(worker, "broadcast")
				_radio_job.clear()
	prepare(a)
	radio.tick(dt)
	drain(a, "broadcast")
	if radio.b["phase"] == "bell":
		for other: CooperativeActor in sim.actors.values():
			if other.fate().over(): continue
			prepare(other)
			radio.try_exit()
			drain(other, "broadcast")


func _exchange_tick(dt: float) -> void:
	var a := _owner("exchange")
	if a == null: return
	prepare(a)
	var visit := a.feature(&"story.exchange") as ExchangeModule
	if visit.s["phase"] != "escort":
		visit.tick(dt)
		drain(a, "exchange")
		return
	var advance := false
	var near := false
	var danger: CooperativeActor
	var nearest := INF
	for id: String in sim.room.alive_ids():
		var p := sim.actor(id)
		prepare(p)
		var distance := visit.tail_dist()
		if distance <= ExchangeModule.WARN:
			_escort_lag[id] = 0.0
			advance = advance or not _escort_lost.get(id, false)
			near = near or distance <= ExchangeModule.FOLLOW
		else:
			_escort_lag[id] = float(_escort_lag.get(id, 0)) + dt
			if float(_escort_lag[id]) >= ExchangeModule.GRACE and not _escort_lost.get(id, false):
				_escort_lost[id] = true
				p.event("notice", {"text": "我掉队了。队友的接待任务仍在继续。"})
		if p.location() == "out" and distance > ExchangeModule.FOLLOW:
			for hunter: Dictionary in visit.s["search"]:
				var hp := Vector2(float(hunter["x"]), float(hunter["y"]))
				var dist := hp.distance_to(p.point(CampusData.rooms())) * CampusGeometry.U2M
				if dist <= ExchangeModule.SEE_RANGE and dist < nearest and sim.patrol.main.nav.los(PatrolNav.point("out", hp.x, hp.y), PatrolNav.point("out", p.point(CampusData.rooms()).x, p.point(CampusData.rooms()).y)):
					danger = p
					nearest = dist
	if advance: visit.s["prog"] = minf(float(visit._route()["len"]), float(visit.s["prog"]) + ExchangeModule.LEAD * 21.0 * dt * (1.0 if near else ExchangeModule.SLOW))
	if danger != null:
		prepare(danger)
		visit._search_tick(dt, false)
		drain(danger, "exchange")
	else:
		prepare(a)
		visit._search_tick(dt, true)
	if float(visit.s["prog"]) >= float(visit._route()["len"]):
		for id: String in sim.room.alive_ids():
			if _escort_lost.get(id, false): continue
			prepare(sim.actor(id))
			if visit.tail_dist() <= ExchangeModule.FOLLOW:
				_offer_ending(sim.actor(id), "international")
				break


func _anomaly_tick(dt: float) -> void:
	var alive := sim.room.alive_ids().filter(func(id: String) -> bool: return not sim.actor(id).fate().over())
	if alive.is_empty(): return
	if anomaly_owner not in alive:
		var previous := sim.actor(anomaly_owner) if sim.actors.has(anomaly_owner) else null
		var continuing := alive.filter(func(id: String) -> bool: return id in anomaly_participants and (sim.actor(id).feature(&"anomaly.world") as AnomalyModule).is_active())
		anomaly_owner = String(continuing[0] if not continuing.is_empty() else alive[anomaly_round % alive.size()])
		if continuing.is_empty() and previous != null:
			var old_effect := previous.feature(&"anomaly.world") as AnomalyModule
			prepare(previous)
			old_effect.end_now()
			old_effect.take_events() # An expired personal event cannot punish its successor.
			_copy_anomaly_schedule(old_effect, sim.actor(anomaly_owner).feature(&"anomaly.world") as AnomalyModule)
			anomaly_participants.clear()
	var a := sim.actor(anomaly_owner)
	prepare(a)
	var weird := a.feature(&"anomaly.world") as AnomalyModule
	var was := weird.is_active()
	weird.tick(dt)
	if not was and weird.is_active():
		anomaly_participants = [a.id]
		if weird.active_id() in ["rain", "blackout", "moth", "exercise"]:
			for id: String in alive:
				if id == a.id: continue
				var other := sim.actor(id)
				if weird.active_id() in ["rain", "blackout"] or other.location() == a.location():
					_copy_anomaly_schedule(weird, other.feature(&"anomaly.world") as AnomalyModule)
					anomaly_participants.append(id)
	drain(a, "anomaly")
	for id: String in anomaly_participants:
		if id == a.id or id not in alive: continue
		var other := sim.actor(id)
		prepare(other)
		var effect := other.feature(&"anomaly.world") as AnomalyModule
		if effect.is_active(): effect.tick(dt)
		drain(other, "anomaly")
	if was and not weird.is_active():
		# Protection can end one member's exposure before the shared event expires.
		var continuing := alive.filter(func(id: String) -> bool: return id in anomaly_participants and (sim.actor(id).feature(&"anomaly.world") as AnomalyModule).is_active())
		if not continuing.is_empty():
			anomaly_owner = String(continuing[0])
		else:
			anomaly_participants.clear()
			anomaly_round += 1
			anomaly_owner = String(alive[anomaly_round % alive.size()])
			_copy_anomaly_schedule(weird, sim.actor(anomaly_owner).feature(&"anomaly.world") as AnomalyModule)


func _copy_anomaly_schedule(source: AnomalyModule, target: AnomalyModule) -> void:
	if source == target: return
	# Only the shared event/scheduler moves. Personal cola debt, clues and traces stay
	# with their owner; copying the module save would silently transfer those too.
	target.an = source.an.duplicate(true)
	if not target.is_active(): target.an["data"] = {}
	target.hist = source.hist.duplicate()
	target.seen = source.seen.duplicate()
	target._rng.seed = source._rng.seed
	target._rng.state = source._rng.state
	target.pre_told = false


func capture() -> Dictionary:
	var pending := {}
	for key: StringName in sim.shared:
		var m: FeatureModule = sim.shared[key]
		if "_pending" in m: pending[String(key)] = m.get("_pending")
	var engines := {}
	for host: String in lift_engines: engines[host] = lift_engines[host].capture()
	var radio: BroadcastModule = sim.shared[&"story.broadcast"]
	var extra := {"radio": {"held": radio.held, "progress": radio.progress, "origin": radio.origin}, "garage_job": (sim.shared[&"garage.world"] as GarageModule).job, "qualified": qualified, "boarding": boarding, "escort_lag": _escort_lag, "escort_lost": _escort_lost}
	return {"lifts": lifts.capture(), "lift_engines": engines, "lift_owners": lift_owners.duplicate(), "lift_riders": lift_riders.duplicate(true), "driver": driver, "passengers": passengers.duplicate(), "anomaly_owner": anomaly_owner, "anomaly_round": anomaly_round, "anomaly_participants": anomaly_participants.duplicate(), "termination_owner": termination_owner, "radio_job": _radio_job.duplicate(true), "pending": pending.duplicate(true), "time_offer": _time_offer.duplicate(true), "extra": extra.duplicate(true)}


func restore(data: Dictionary) -> void:
	lifts.restore(data["lifts"])
	for host: String in lift_engines:
		lift_engines[host].restore(data["lift_engines"][host])
		lifts.lifts[host] = lift_engines[host].lifts[host]
	lift_owners = data["lift_owners"].duplicate()
	lift_riders = data["lift_riders"].duplicate(true)
	driver = String(data["driver"])
	passengers = data["passengers"].duplicate()
	anomaly_owner = String(data["anomaly_owner"])
	anomaly_round = int(data["anomaly_round"])
	anomaly_participants = data["anomaly_participants"].duplicate()
	termination_owner = String(data["termination_owner"])
	_radio_job = data["radio_job"].duplicate(true)
	_time_offer = data["time_offer"].duplicate(true)
	if not _time_offer.is_empty(): _time_offer["scene"] = sim.actor(_time_offer["owner"]).scene_version
	var extra: Dictionary = data["extra"]
	var radio: BroadcastModule = sim.shared[&"story.broadcast"]
	radio.held = bool(extra["radio"]["held"])
	radio.progress = float(extra["radio"]["progress"])
	radio.origin = extra["radio"]["origin"]
	(sim.shared[&"garage.world"] as GarageModule).job = extra["garage_job"]
	qualified = extra["qualified"].duplicate(true)
	boarding = extra["boarding"].duplicate(true)
	_escort_lag = extra["escort_lag"].duplicate()
	_escort_lost = extra["escort_lost"].duplicate()
	for key: String in data["pending"]:
		if sim.shared.has(StringName(key)): sim.shared[StringName(key)].set("_pending", data["pending"][key])
