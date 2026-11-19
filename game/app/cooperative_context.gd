class_name CooperativeContext
extends RefCounted
## Application adapter: supplies explicit personal context to the existing pure rules.

static func base(a: CooperativeActor) -> Dictionary:
	var s := a.school()
	var w := a.point(CampusData.rooms())
	var weird := a.feature(&"anomaly.world") as AnomalyModule
	var room: Variant = CampusData.rooms().get(a.location())
	var clock := s.game_clock()
	var pressure := s.pressure()
	var in_classroom := s.in_classroom_here(a.location(), w)
	var inspection_pending := s.inspection_pending()
	var inspection_upcoming := s.inspection_upcoming()
	var patrol_chase := a.watcher().local_chase()
	var anomaly_active := weird.is_active()
	var meal := false
	for m: Array in CampusData.campus().get("meals", []):
		if s.tsec >= float(m[0]) and s.tsec < float(m[1]): meal = true
	var ctx := {"cooperative": true, "scene": a.location(), "world_id": a.location(), "x": w.x, "y": w.y, "w": w, "height": float(a.pose["position"][1]),
		"ang": CampusGeometry.ang_from_yaw(float(a.pose["yaw"])), "pitch": float(a.pose["pitch"]), "tsec": s.tsec, "day": s.day,
		"clock": clock, "game_clock": clock, "dead": a.fate().dead, "diff": a.fate().diff,
		"moving": a.moving, "running": a.running, "run": a.running, "seated": s.seated, "san": s.san, "viol": s.viol,
		"hiding": bool(a.watcher().hide["on"]), "night": SchoolClock.is_night(s.tsec), "need_where": SchoolClock.need_where(s.tsec),
		"meal": meal, "rollcall_claim": s.seat_card.outstanding(), "rest_mul": float(pressure["rest"]), "pressure_anomaly": float(pressure["anomaly"]), "exam": s.exam,
		"held": a.bag().has("phone"), "tech": a.talent().has("tech"), "classroom": a.location() == a.own_seat.get_slice(":", 0) and in_classroom,
		"has": a.bag().has, "add": a.bag().add, "remove": a.bag().remove,
		"busy": anomaly_active or inspection_pending or patrol_chase,
		"anomaly": weird.pendulum_info(), "anomaly_active": anomaly_active, "anomaly_id": weird.active_id(), "brolly": a.bag().brolly_up,
		"patrol_chase": patrol_chase, "choice_open": not a.choice.is_empty(), "inspection_pending": inspection_pending,
		"inspection_quiet": inspection_pending or inspection_upcoming or float(s.inspection.get("calm", 0)) > 0,
		"gate_n_map": CampusData.campus().get("gates", {}).get("n", {"x": 514, "y": 95}), "bound_x1": 830.0,
		"closed": [], "drain_mul": 1.0, "has_key": a.bag().has("key"), "torch": a.bag().torch_on, "hotwire": a.talent().has("drive"),
		"enter_cool": a.enter_cool, "tile": CampusGeometry.tile_at(room, w) if room != null else "",
		"on_field": s.on_field(a.location(), w), "in_classroom": in_classroom, "in_lift": a.location() in ElevatorModule.RIDE_ROOMS,
		"fence_x": float(CampusData.layout("out")["bound"]["x1"]) * 2 - 6, "bag": a.bag().bag, "item_names": {},
		"available": s.seated and s.at_my_seat(a.location(), w) and not inspection_pending and not inspection_upcoming and not anomaly_active,
		"quiet": inspection_pending or inspection_upcoming, "room": a.location(), "stam": s.stam, "space": bool(a.input.get("vault", false)),
		"locked": bool(a.watcher().pat["locked"])}
	for id: String in a.bag().bag: ctx["item_names"][id] = a.bag().item_name(id)
	var nav := a.watcher().nav
	ctx["can_stand"] = func(p: Vector2) -> bool:
		var cell := nav.cell(a.location(), PatrolNav.point(a.location(), p.x, p.y))
		return nav.is_free(a.location(), cell.x, cell.y)
	ctx["los"] = func(p: Vector2, q: Vector2) -> bool: return nav.los(PatrolNav.point(a.location(), p.x, p.y), PatrolNav.point(a.location(), q.x, q.y))
	ctx["line_clear"] = ctx["los"]
	var car := a.feature(&"garage.world") as GarageModule
	ctx["car_row"] = int(car.car_right.get_slice(":", 1)) + 1 if not car.car_right.is_empty() else 1
	var north: Dictionary = ctx["gate_n_map"]
	ctx["gate_n"] = Vector2(float(north["x"]) * 2, float(north["y"]) * 2)
	var days := a.feature(&"school.days") as DayModule
	ctx["drain_mul"] = days.drain_mul(s.day, s.tsec)
	ctx["closed"] = DayModule.CLOSED.duplicate() if days.today(s.day, s.tsec) == "occupied" else []
	ctx["piano_closed"] = days.closed("piano", s.day, s.tsec)
	ctx["dread_ok"] = false
	return ctx


static func patrol(a: CooperativeActor, common: Dictionary = {}) -> Dictionary:
	var c := base(a) if common.is_empty() else common.duplicate()
	var s := a.school()
	var cur: Dictionary = s.inspection.get("current", {})
	var room: Variant = CampusData.rooms().get(a.location())
	var height := float(a.pose["position"][1])
	if room != null and not CampusData.rules().is_stairwell(a.location()) and a.location() != "bell1": height = 0.0
	c.merge({"fy": height, "at_seat": s.at_my_seat(a.location(), c["w"]), "excused": s.permit(), "on_leave": s.on_leave(), "playing": not a.fate().over(),
		"inspection_room": String(cur.get("room", "")), "calm": float(s.inspection.get("calm", 0)), "calm_room": String(s.inspection.get("calm_room", "")),
		"has_seal": a.bag().has("seal"), "active_seconds": s.active_seconds, "car_chase": false}, true)
	return c


static func investigation(a: CooperativeActor, common: Dictionary = {}, reading: bool = false) -> Dictionary:
	var c := base(a) if common.is_empty() else common.duplicate()
	var f := a.feature(&"campus.facilities") as FacilitiesModule
	var r := a.feature(&"story.routes") as RoutesModule
	var p := a.feature(&"phone.network") as PhoneModule
	var g := a.feature(&"garage.world") as GarageModule
	var left: Array = []
	if reading:
		c["radio_goal"] = (a.feature(&"story.broadcast") as BroadcastModule).notebook_goal(a.bag().has, a.school().day)
		c["exchange_goal"] = (a.feature(&"story.exchange") as ExchangeModule).notebook_goal()
	for floor_id: int in FacilitiesModule.BLUEPRINT_FLOORS:
		if not f.portal["blueprints"].has(floor_id): left.append(floor_id)
	c.merge({"place": a.school().place_name(a.location(), float(a.pose["position"][1])), "has_phone": a.bag().has("phone"), "has_coin": a.bag().has("coin"), "has_pill": a.bag().has("pill"), "bag_full": a.bag().bag.size() >= a.bag().capacity(),
		"reader": a.own_seat,
		"car": a.talent().car(a.bag().has("key")), "car_tried": g.car_tried.size(), "car_used": g.car_used, "hacked": r.hacked, "data": r.data_synced,
		"face_done": int(r.face_quiz.get("done", -1)), "spot_comp": f.spots.has("comp"), "spot_data": f.spots.has("data"),
		"portal": {"diary": f.portal["diary"], "sketch": f.portal["sketch"], "open": f.portal["open"], "count": f.blueprint_count(), "floors_left": left, "need": f.portal_need_text()},
		"cyber": {"initialized": p.device["initialized"], "network": p.device["network"], "download": p.device["download"]["status"], "term": p.termination["status"]},
		"desk_ok": a.school().seated and a.school().at_my_seat(a.location(), c["w"]) and not c["busy"]}, true)
	return c
