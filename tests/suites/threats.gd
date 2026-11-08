extends "res://tests/support/test_suite.gd"


func _test_patrol_rules() -> void:
	var nav := CampusData.patrol_nav()
	var data := CampusData.patrol_data()
	check(not nav.grid("teach1").is_empty() and nav.nodes.size() == 121 and nav.edges.size() == 128, "patrol grids and the 121-node connection graph are exported")
	check(data["route"]["nodes"].size() == 128 and data["zones"].size() == 9, "route of 128 nodes and nine report zones")
	var a: Dictionary = nav.nodes["teach1:stairs"]
	var b: Dictionary = nav.nodes["teach1:east"]
	var way := nav.path(a, b)
	check(way.size() > 10 and nav.length(way) > 400.0, "A* connects the west stairs and the east end of teach1 (%d cells, %.0f units)" % [way.size(), nav.length(way)])
	var blocked := PatrolNav.point("teach1", 1000.0, 1760.0)
	var wall_edge := CampusGeometry.tile_center(CampusData.layout("teach1"), 31, 15)
	check(not nav.snap("teach1", PatrolNav.point("teach1", wall_edge.x, wall_edge.y)).is_empty(), "snap finds a free cell next to a wall point")
	check(nav.segment(a, way[2]) and not nav.segment(a, PatrolNav.point("teach1", 1000.0, 1760.0)), "a segment is clear along the corridor and blocked through walls")
	var hop := nav.shortest("admin1:stairs", "admin2:stairs")
	check(not hop.is_empty() and hop["nodes"].size() >= 2 and float(hop["weight"]) > 0.0, "RouteGraph finds admin1 -> admin2 through the stairs")
	# A patrol with nobody around walks the route and changes scenes.
	var pm := CampusData.make_patrol()
	pm.reset()
	pm.elevator = ElevatorModule.new(CampusData.rooms())
	check(pm.pat["room"] == "admin1" and pm.pat["state"] == "walk", "the patroller starts at the admin1 stairs")
	var far := _pctx("dorm1", CampusGeometry.tile_center(CampusData.layout("dorm1"), 10, 5), {"need_where": "自由"})
	_patrol_run(pm, far, 120.0)
	check(int(pm.pat["routeIndex"]) > 1 or pm.pat["room"] != "admin1", "after two minutes the patroller has walked on (node %d in %s)" % [pm.pat["routeIndex"], pm.pat["room"]])
	var moved := {}
	for _i in 6:
		_patrol_run(pm, far, 60.0)
		moved[pm.pat["room"]] = true
	check(moved.size() >= 2, "it crosses between scenes (%s)" % ", ".join(PackedStringArray(moved.keys())))
	# Chase: out of place in a classroom building during class.
	var t1: Dictionary = CampusData.layout("teach1")
	var me := CampusGeometry.tile_center(t1, 30, 17)
	var chaser := CampusData.make_patrol()
	chaser.reset()
	chaser.pat["room"] = "teach1"
	chaser.pat["x"] = me.x + 80.0
	chaser.pat["y"] = me.y
	chaser.pat["behavior"] = "patrol"
	chaser.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", chaser)
	chaser.pat["safety"] = 0.0
	chaser.elevator = pm.elevator
	var ctx := _pctx("teach1", me)
	check(chaser.eligible() == false or true, "context-free eligibility does not crash")
	chaser.set_context(ctx)
	check(chaser.eligible() and not chaser.exempt() and chaser.hunting(), "out of the seat in class inside a teaching building makes the player a target")
	var events := _patrol_run(chaser, ctx, 20.0, "kill")
	var kinds := events.map(func(e: Dictionary) -> String: return e["kind"])
	check(kinds.has("violation") and kinds.has("kill"), "it locks on (+8 violation once), chases and catches")
	check(events.size() > 0 and events[events.size() - 1].get("source") == "patrol" and events[events.size() - 1].get("fx") == "grip", "the catch is the patrol grip death")
	check(kinds.count("violation") == 1, "the citation is issued once")
	# Seated at the own seat: exempt.
	var calm := CampusData.make_patrol()
	calm.reset()
	calm.pat["room"] = "teach1"
	calm.pat["x"] = me.x + 80.0
	calm.pat["y"] = me.y
	calm.pat["safety"] = 0.0
	calm.pat["behavior"] = "patrol"
	calm.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", calm)
	calm.elevator = pm.elevator
	var seated_ctx := _pctx("teach1", me, {"seated": true, "at_seat": true})
	var quiet := _patrol_run(calm, seated_ctx, 15.0)
	check(quiet.is_empty() and not bool(calm.pat["locked"]), "sitting at the own seat in class is never hunted")
	# A seal burns instead of the lock.
	var sealed := CampusData.make_patrol()
	sealed.reset()
	sealed.pat["room"] = "teach1"
	sealed.pat["x"] = me.x + 80.0
	sealed.pat["y"] = me.y
	sealed.pat["safety"] = 0.0
	sealed.pat["behavior"] = "patrol"
	sealed.pat["routeIndex"] = _route_towards("teach1:east", "teach1:stairs", sealed)
	sealed.elevator = pm.elevator
	var sealed_events := _patrol_run(sealed, _pctx("teach1", me, {"has_seal": true}), 12.0, "remove_item")
	check(sealed_events.size() > 0 and sealed_events[sealed_events.size() - 1]["kind"] == "remove_item" and sealed.pat["state"] == "idle" and is_equal_approx(float(sealed.pat["respawn"]), 30.0),
		"the talisman burns at the lock and the patroller is banished for 30 s")
	# Night outside: hunted on the campus, left alone indoors.
	check(not _night_hunt("dorm1"), "at night inside a dorm the player is not eligible")
	check(_night_hunt("out"), "at night outside the player is eligible")
	# Hiding.
	var hider := CampusData.make_patrol()
	hider.reset()
	hider.elevator = pm.elevator
	hider.pat["room"] = "teach1"
	hider.pat["safety"] = 0.0
	var locker: Vector2i = Vector2i(12, 16)
	check(String(t1["grid"][16]).substr(12, 1) == "H", "teach1 has the exported locker cell (12, 16)")
	var near_locker := CampusGeometry.tile_center(t1, 12, 17)
	hider.pat["x"] = near_locker.x + 200.0
	hider.pat["y"] = near_locker.y
	hider.set_context(_pctx("teach1", near_locker))
	var spot := hider.hide_in(locker.x, locker.y)
	check(hider.hide["on"] and not hider.hide["seen"] and absf(spot["ang"] - PI * 0.5) < 0.001, "hiding in a locker unseen")
	var hide_events := _patrol_run(hider, _pctx("teach1", Vector2(spot["x"], spot["y"])), 10.0)
	check(not bool(hider.pat["locked"]), "an unseen locker is not searched")
	var out_spot := hider.hide_out()
	check(not hider.hide["on"] and out_spot.has("x"), "stepping out puts the body in front of the locker")
	# Registered absence makes the chase permanent.
	var abs_pm := CampusData.make_patrol()
	abs_pm.reset()
	abs_pm.registered_absence("1:0")
	check(abs_pm.pat["permanent"] and abs_pm.pat["behavior"] == "chase", "an unhonoured registration starts the permanent chase")
	abs_pm.rescued()
	check(not abs_pm.pat["permanent"] and is_equal_approx(float(abs_pm.pat["safety"]), 3.6), "rescue clears the permanent chase and grants 3.6 s")
	# Region report: standing in the network core queues an investigation.
	var zone_pm := CampusData.make_patrol()
	zone_pm.reset()
	zone_pm.elevator = pm.elevator
	var l3: Dictionary = CampusData.layout("lab3")
	_patrol_run(zone_pm, _pctx("lab3", CampusGeometry.tile_center(l3, 41, 5), {"need_where": "自由"}), 0.2)
	check(zone_pm.pat["lastRegion"] == "lab3:servers" and (zone_pm.pat["queue"] as Array).size() + (1 if zone_pm.pat["investigation"] != null else 0) == 1, "entering the server room is reported once")
	# Save round trip.
	var snap_data: Dictionary = JSON.parse_string(JSON.stringify(chaser.capture()))
	check(chaser.validate(snap_data).is_empty(), "patrol state survives JSON")
	var again := CampusData.make_patrol()
	again.reset()
	again.restore(snap_data)
	check(again.pat["room"] == chaser.pat["room"] and absf(float(again.pat["x"]) - float(chaser.pat["x"])) < 0.001, "patrol position restores")
	snap_data["pat"]["x"] = "far"
	check(not chaser.validate(snap_data).is_empty(), "garbage patrol numbers are refused")


## Route index whose previous node is `from` and next node is `to` (the patroller walks from -> to).


func _test_garage_rules() -> void:
	var g := CampusData.layout("garage1")
	var cars := GarageModule.new(g)
	cars.reset()
	cars.set_seed(5)
	var right := cars.car_right_cell()
	var all: Array = cars._cars()
	check(all.size() == 16 and all.has(right) and int(right.split(":")[0]) <= 24, "the right car is one of the 8 cars farthest from the entrance")
	check(cars.car_right_cell() == right, "the right car stays the same for the run")
	check(GarageModule.car_name(12, 4) == "鄂A·F" + str(3100 + 12 * 31 + 4), "plates follow carName")
	# The thing appears in the driveway and walks to you in the dark.
	var east := Vector2(float(g["ox"]) + 55.5 * 9.0, float(g["oy"]) + 13.5 * 9.0)
	cars.set_context(_gctx(east.x, east.y))
	cars.tick(0.1)
	check(bool(cars.roam["on"]) and cars.roam_visible(), "entering the garage puts the thing in the driveway")
	var start := Vector2(float(cars.roam["x"]), float(cars.roam["y"]))
	for _i in 120:
		cars.tick(0.1)
	check(Vector2(float(cars.roam["x"]), float(cars.roam["y"])).distance_to(east) < start.distance_to(east), "in the dark it comes closer")
	var e := cars.take_events()
	check(e.any(func(x: Dictionary) -> bool: return x["kind"] == "step"), "its steps are heard")
	# The torch held on it for 1.6 s sends it away.
	cars.roam["x"] = east.x - 120.0
	cars.roam["y"] = east.y
	cars.roam["stage"] = "approach"
	cars.set_context(_gctx(east.x, east.y, {"torch": true, "ang": PI}))
	for _i in 17:
		cars.tick(0.1)
	e = cars.take_events()
	check(cars.roam["stage"] == "wait" and not cars.roam_visible() and e.any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "torch"), "the torch held on it makes it vanish")
	check(_notices(e).has("我：光扫过去，它就没了。"), "and says so once")
	cars.roam["waitT"] = 0.05
	cars.set_context(_gctx(east.x, east.y))
	cars.tick(0.1)
	check(cars.roam["stage"] == "approach" and Vector2(float(cars.roam["x"]), float(cars.roam["y"])).distance_to(east) > 250.0, "it comes back far away")
	# Touching it in the dark kills.
	cars.roam["x"] = east.x - 10.0
	cars.roam["y"] = east.y
	cars.roam["litAcc"] = 0.0
	cars.take_events()
	cars.tick(0.05)
	e = cars.take_events()
	check(e.any(func(x: Dictionary) -> bool: return x["kind"] == "kill" and x["source"] == "garage"), "walking into it in the dark is the garage death")
	cars.set_context(_gctx(east.x, east.y, {"enter_cool": 0.5}))
	cars.tick(0.05)
	check(not cars.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "kill"), "not right after entering the room")
	# The coin lures it.
	var coin := GarageModule.new(g)
	coin.reset()
	coin.set_seed(5) # Throw angle and distance are random; this scenario must be reproducible.
	coin.set_context(_gctx(east.x, east.y, {"ang": PI}))
	coin.tick(0.1)
	check(coin.throw_coin() and coin.lure != null and float(coin.lure["x"]) < east.x - 50.0 and float(coin.lure["t"]) == 8.0,
		"the seeded coin rolls ahead and starts an eight-second lure")
	coin.tick(7.9)
	check(coin.lure != null, "the coin still attracts the shadow before eight seconds")
	coin.tick(0.2)
	check(coin.lure == null, "the coin lure expires after eight seconds")
	coin.set_context(_gctx(0, 0, {"scene": "canteen1"}))
	check(not coin.throw_coin() and _notices(coin.take_events()).has("我：要买饭就去打饭窗口，要买东西就去售货机。"), "outside the garage the coin is kept")
	# Trying cars: the thing nearby kills, a wrong car is remembered, the right one starts the drive.
	var drive := GarageModule.new(g)
	drive.reset()
	drive.set_seed(5)
	var rc := drive.car_right_cell().split(":")
	var wrong: String = all.filter(func(x: String) -> bool: return x != drive.car_right_cell())[0]
	drive.set_context(_gctx(east.x, east.y, {"has_key": false}))
	drive.use_car(int(rc[0]), int(rc[1]))
	check(_notices(drive.take_events()).has("我：车门锁着。"), "without the key the doors are locked")
	drive.roam["on"] = true
	drive.roam["stage"] = "approach"
	drive.roam["x"] = east.x - 50.0
	drive.roam["y"] = east.y
	drive.set_context(_gctx(east.x, east.y))
	drive.use_car(int(rc[0]), int(rc[1]))
	check(drive.take_events().any(func(x: Dictionary) -> bool: return x["kind"] == "kill" and x["source"] == "car_entry"), "opening a door with it close by is the back-seat death")
	drive.roam["stage"] = "wait"
	drive.roam["x"] = -1e6
	var wc := wrong.split(":")
	drive.inspect_car(int(wc[0]), int(wc[1]))
	var asked := drive.take_events()
	check(asked.back()["kind"] == "choice" and String(asked.back()["text"]).begins_with(GarageModule.car_name(int(wc[0]), int(wc[1]))), "looking at a car offers to try the key")
	drive.choose(0)
	check(drive.job != null and _notices(drive.take_events()).has("我：我把钥匙插进锁孔，慢慢地拧……"), "trying the key is a 1.6 s hold")
	drive.set_context(_gctx(east.x + 8.0, east.y))
	drive.tick(0.1)
	check(drive.job == null and _notices(drive.take_events()).has("我：手一松，钥匙从锁孔里滑了出来。"), "stepping away drops the key")
	drive.set_context(_gctx(east.x, east.y))
	drive.use_car(int(wc[0]), int(wc[1]))
	for _i in 17:
		drive.tick(0.1)
	check(drive.car_tried.has(wrong) and not drive.driving(), "the wrong car is remembered")
	drive.take_events()
	drive.use_car(int(wc[0]), int(wc[1]))
	check(_notices(drive.take_events()).has("我：这辆试过了。不是它。"), "a tried car is not tried again")
	drive.use_car(int(rc[0]), int(rc[1]))
	for _i in 17:
		drive.tick(0.1)
	var go := drive.take_events()
	check(drive.driving() and drive.car_used and go.any(func(x: Dictionary) -> bool: return x["kind"] == "drive") and go.any(func(x: Dictionary) -> bool: return x["kind"] == "fact" and x["what"] == "drive" and x["tried"] == 1), "the right car starts the drive")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(drive.capture()))
	var back := GarageModule.new(g)
	back.reset()
	check(back.validate(saved).is_empty(), "garage state survives JSON")
	back.restore(saved)
	check(back.driving() and back.car_tried.has(wrong) and back.car_right_cell() == drive.car_right_cell(), "and restores")
	saved["car_right"] = "1:1"
	check(not back.validate(saved).is_empty(), "a right car that is not a car is refused")
	# The drive itself (domain/car-chase.js).
	var d := CarChaseRules.new_state()
	var r := CarChaseRules.step(d, {"throttle": false}, 1.0)
	check(float(d["pursuit"]) == 3.0 and not r.has("failure"), "standing still lets the pursuit close in")
	d = CarChaseRules.new_state()
	d["distance"] = 44.0
	d["speed"] = 10.0
	r = CarChaseRules.step(d, {"throttle": true}, 0.2)
	check(int(d["hp"]) == 2 and r["events"][0]["type"] == "hit", "a barrier in the lane costs a life")
	d = CarChaseRules.new_state()
	d["distance"] = 149.0
	d["speed"] = 10.0
	d["nextObstacle"] = 3
	r = CarChaseRules.step(d, {"throttle": true}, 0.2)
	check(r.has("failure") and float(r["failure"]["checkpoint"]) == 120.0, "the wrong side at a fork leads back to school")
	CarChaseRules.reset_to(d, 120.0)
	check(int(d["hp"]) == 3 and int(d["nextObstacle"]) == 3 and int(d["nextFork"]) == 0, "a failure goes back to the checkpoint")
	d = CarChaseRules.new_state()
	d["distance"] = 319.0
	d["speed"] = 10.0
	d["x"] = -2.0
	d["nextObstacle"] = 6
	d["nextFork"] = 2
	check(CarChaseRules.step(d, {"throttle": true}, 0.2).get("won", false), "past 320 m with both forks right is out")


func _test_anomaly_rules() -> void:
	check(AnomalyModule.IDS.size() == 26 and AnomalyModule.DEFS.size() == 26, "all 26 anomalies are defined")
	for id: String in AnomalyModule.IDS:
		check(AnomalyModule.DEFS[id].has("msg") and AnomalyModule.DEFS[id].has("dfx"), "anomaly %s has its message and death scene" % id)
	var t1 := CampusData.layout("teach1")
	var seat_w := CampusGeometry.tile_center(t1, 40, 9)
	var class_ctx := _actx("teach1", seat_w, {"in_classroom": true, "tile": "d"})
	var am := CampusData.make_anomaly()
	am.reset()
	am.set_seed(5)
	am.begin_run("easy")
	check(is_equal_approx(float(am.an["next"]), 60.0), "the first anomaly is due after 60 s on 预知梦")
	var hard := CampusData.make_anomaly()
	hard.reset()
	hard.begin_run("hard")
	check(is_equal_approx(float(hard.an["next"]), 40.0), "and after 40 s on 梦魇")
	var evs := _an_run(am, class_ctx, 61.0, "notice")
	check(am.is_active() and am.active_id() == "chalk", "the first anomaly of a run is the blackboard foretelling (%s)" % am.active_id())
	check(evs.size() > 0 and evs[0]["text"] == AnomalyModule.DEFS["chalk"]["msg"], "its first line is the old message")
	_an_run(am, class_ctx, 20.0)
	check(not am.is_active() and float(am.an["next"]) >= 10.0 and am.hist == ["chalk"], "it ends after 16 s and the next one is paced (%.1f s)" % float(am.an["next"]))
	am.set_context(class_ctx)
	var iv := am._interval()
	check(iv >= 10.0 and iv <= 80.0, "intervals stay inside the old 40–64 s band, scaled by SAN, violation and pressure (%.1f)" % iv)
	# No lethal anomaly in the first-day dream; the same kind never runs twice in a row.
	var picks := {}
	var lethal_early := 0
	for i in 60:
		var pm := CampusData.make_anomaly()
		pm.reset()
		pm.set_seed(100 + i)
		pm.hist = ["turn"]
		pm.set_context(_actx("out", Vector2(1068, 1984), {"need_where": "自由"}))
		var pick := pm._pick()
		picks[pick] = true
		if pick != "" and AnomalyModule.DEFS[pick].get("late", false):
			lethal_early += 1
		if i == 0:
			check(pick != "turn", "the previous anomaly is not picked again")
	check(lethal_early == 0, "late anomalies stay out of the first-day dream")
	# Lethal ones.
	var field := Vector2(1068, 1984)
	var rain := CampusData.make_anomaly()
	rain.reset()
	rain.set_seed(1)
	var out_ctx := _actx("out", field, {"need_where": "自由"})
	rain.set_context(out_ctx)
	check(not rain.under_roof(), "the test spot is not under a roof")
	_an_force(rain, "rain", out_ctx)
	var got := _an_run(rain, out_ctx, 20.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "drown", "unsheltered in the rain you drown after 14 s")
	var sheltered := CampusData.make_anomaly()
	sheltered.reset()
	_an_force(sheltered, "rain", _actx("teach1", seat_w))
	check(not _kinds(_an_run(sheltered, _actx("teach1", seat_w), 25.0)).has("kill"), "indoors the rain never kills")
	var moth := CampusData.make_anomaly()
	moth.reset()
	_an_force(moth, "moth", out_ctx)
	got = _an_run(moth, out_ctx, 10.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "swarm", "staying by the moths kills in 6.5 s")
	var run_away := _an_run(moth, _actx("out", field + Vector2(400, 0), {"need_where": "自由"}), 3.0)
	check(not _kinds(run_away).has("kill"), "walking away from the swarm source stops it")
	var rite := CampusData.make_anomaly()
	rite.reset()
	var lab: Dictionary = CampusData.layout("lab2")
	var lab_ctx := _actx("lab2", CampusGeometry.tile_center(lab, 20, 10))
	_an_force(rite, "rite", lab_ctx)
	var circle: Dictionary = rite.an["data"]["c"]
	var stand := _actx("lab2", Vector2(circle["x"], circle["y"]))
	got = _an_run(rite, stand, 5.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "ring", "standing in the chalk circle kills in 2.2 s")
	var necker := CampusData.make_anomaly()
	necker.reset()
	var edge := _actx("out", Vector2((830.0 - 20.0) * 2.0, 1500.0), {"need_where": "自由", "day": 2})
	_an_force(necker, "necker", edge)
	got = _an_run(necker, edge, 6.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "neck", "next to the east wall the long-necked passer kills")
	var cup := CampusData.make_anomaly()
	cup.reset()
	var tb: Dictionary = {}
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == "teach":
			tb = o
	var below := Vector2((float(tb["x"]) + float(tb["w"]) / 2.0) * 2.0, float(tb["y"]) * 2.0 - 9.0)
	var cup_ctx := _actx("out", below, {"need_where": "自由"})
	cup.set_context(cup_ctx)
	check(cup._when("cup"), "next to a tall wall on the open side the cup can fall")
	_an_force(cup, "cup", cup_ctx)
	got = _an_run(cup, cup_ctx, 6.0, "kill")
	check(_kinds(got).has("kill") and got[got.size() - 1]["fx"] == "floor", "standing still under the window the cup lands on you")
	var dodge := CampusData.make_anomaly()
	dodge.reset()
	_an_force(dodge, "cup", cup_ctx)
	dodge._cola_owe() # anStart owes the can when a cup really starts; the forced start skips it
	var step_away := _actx("out", below + Vector2(60, 0), {"need_where": "自由"})
	var t_run := 0.0
	var killed := false
	while t_run < 6.0:
		var ctx_now := cup_ctx if t_run < 0.9 else step_away
		dodge.set_context(ctx_now)
		dodge.tick(0.1)
		killed = killed or _kinds(dodge.take_events()).has("kill")
		t_run += 0.1
	check(not killed, "moving away once it falls dodges the cup")
	check(dodge.cola_pending != null, "a cup that started owes one falling can")
	# Cola: at night, outside, after the settle time.
	var night_ctx := _actx("out", field, {"need_where": "宿舍", "night": true, "tsec": 1400.0})
	dodge.an["active"] = false
	dodge.an["id"] = ""
	dodge.an["next"] = 99.0
	_an_run(dodge, night_ctx, 2.0)
	check(not dodge.is_active(), "the can waits through the settle time")
	_an_run(dodge, night_ctx, 1.0)
	check(dodge.is_active() and dodge.active_id() == "cola" and dodge.cola_pending == null, "then the owed can starts")
	# Non-lethal rules.
	var broad := CampusData.make_anomaly()
	broad.reset()
	_an_force(broad, "broad", _actx("teach1", seat_w, {"moving": true}))
	got = _an_run(broad, _actx("teach1", seat_w, {"moving": true}), 3.0, "hurt")
	check(_kinds(got).has("hurt") and absf(float(got[got.size() - 1]["amount"]) - 18.0 * 0.9) < 0.001, "moving during the roll call costs 18 SAN (×0.9 on 预知梦)")
	var bell := CampusData.make_anomaly()
	bell.reset()
	_an_force(bell, "bell13", class_ctx)
	got = _an_run(bell, _actx("teach1", seat_w, {"seated": true}), 5.0)
	check(not bell.is_active() and _kinds(got).has("notice"), "sitting in teach1 during the bells ends it kindly")
	# The roster: ignoring it costs 18 violation when it ends.
	var roster := CampusData.make_anomaly()
	roster.reset()
	_an_force(roster, "roster", class_ctx)
	got = _an_run(roster, _actx("teach1", seat_w + Vector2(300, 0)), 20.0)
	check(_kinds(got).has("violation") and not roster.is_active(), "an ignored roster ends with +18 violation")
	var near_ctx := _actx("teach1", seat_w)
	roster.reset()
	_an_force(roster, "roster", near_ctx)
	check(roster.near_roster(), "standing by the roster allows the interaction")
	roster.use_roster(true)
	var written := roster.take_events()
	check(_kinds(written).has("san") and roster.an["data"]["done"], "writing the name back with a pen restores SAN and settles it")
	# A timed choice (turn): not turning round for 7.8 s is the good outcome.
	var turn := CampusData.make_anomaly()
	turn.reset()
	turn.set_seed(2)
	_an_force(turn, "turn", class_ctx)
	turn.an["data"]["smile"] = false
	var asked := _an_run(turn, class_ctx, 2.0, "choice")
	check(_kinds(asked).has("choice") and asked[asked.size() - 1]["labels"] == ["不回头", "回头看"], "the tap on the shoulder asks whether to look back")
	turn.choose("no")
	got = _an_run(turn, class_ctx, 9.0)
	check(_kinds(got).has("san") and not turn.is_active(), "not looking back ends it with +6 SAN")
	# Save round trip.
	var data: Dictionary = JSON.parse_string(JSON.stringify(rite.capture()))
	check(rite.validate(data).is_empty(), "anomaly state survives JSON")
	var again := CampusData.make_anomaly()
	again.reset()
	again.restore(data)
	check(again.hist == rite.hist and again.an["active"] == rite.an["active"], "anomaly state restores")
	data["an"]["id"] = "not-an-anomaly"
	check(not rite.validate(data).is_empty(), "unknown anomaly ids are refused")
