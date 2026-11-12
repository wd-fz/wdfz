class_name CooperativeFactory
extends RefCounted
## Only world features are shared; personal modules are never aliased between members.
const SHARED := [&"campus.world", &"campus.facilities", &"story.routes", &"garage.world", &"story.broadcast", &"story.exchange", &"story.investigation", &"campus.marks"]


static func actor(id: String, slot: int, difficulty: String, gift: String, seed_value: int, shared: Dictionary) -> CooperativeActor:
	var a := CooperativeActor.new()
	a.id = id
	a.session = SessionFactory.create()
	a.session.start("teach1")
	for key: StringName in SHARED:
		if shared.has(key): a.session.modules.share(shared[key])
		else: shared[key] = a.feature(key)
	var own := String(CampusData.campus()["own_seat"]["seatId"])
	var selected := own
	if slot > 0:
		selected = "teach1:%d:11" % (48 + slot)
	a.own_seat = selected
	a.school().assign_own_seat(selected)
	a.pose = a.school().start_seated("teach1")
	a.input["yaw"] = a.pose["yaw"]
	a.fate().diff = difficulty
	a.talent().pick(gift)
	if gift == "tech": a.bag().add("phone")
	a.bag().set_seed(seed_value)
	a.school().danger_mul = func(kind: String) -> float: return a.talent().danger_mul(kind) * (a.feature(&"school.days") as DayModule).drain_mul(a.school().day, a.school().tsec)
	for key: StringName in a.session.modules._modules:
		var m := a.feature(key)
		if m.has_method("set_seed") and (key not in SHARED or slot == 0):
			m.call("set_seed", str(seed_value) if key in [&"school.classmates", &"story.atmos"] else seed_value)
	(a.feature(&"anomaly.world") as AnomalyModule).begin_run(difficulty)
	a.watcher().hear_mul = a.talent().hear_range()
	return a
