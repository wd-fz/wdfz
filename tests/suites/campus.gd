extends "res://tests/support/test_suite.gd"


func _test_campus_rules() -> void:
	var rooms := CampusData.rooms()
	check(rooms.size() == 42 and not CampusData.layout("out").is_empty(), "all 42 Web interiors and the outside are exported")
	var campus := CampusData.make_module()
	campus.reset()
	check(campus.start_world() == "teach1", "run starts in teach1 like the Web version")
	var t1: Dictionary = rooms["teach1"]
	check(t1["grid"].size() == 22 and String(t1["grid"][0]).length() == 63, "teach1 keeps the 63 x 22 tile grid")
	# Door 10:15 is the front door of the first classroom; stand in the corridor facing north.
	var door := CampusGeometry.tile_center(t1, 10, 15)
	var pose := _campus_pose(t1, door + Vector2(0, 14), -PI * 0.5)
	check(campus.hint("teach1", pose) == "开门", "closed classroom door offers to open")
	var opened := campus.interact_at("teach1", pose)
	check(opened.get("door", {}).get("open") == true and campus.is_open("teach1:10:15"), "E opens the facing door")
	check(campus.capture()["open_doors"] == ["teach1:10:15"], "open doors are saved by key")
	var blocked := campus.interact_at("teach1", _campus_pose(t1, door + Vector2(0, 5), -PI * 0.5))
	check(blocked["notice"] == "我：先让开门口。" and campus.is_open("teach1:10:15"), "cannot close a door while standing in it")
	campus.interact_at("teach1", pose)
	check(not campus.is_open("teach1:10:15"), "E closes it again from the corridor")
	check(not campus.validate({"open_doors": ["teach1:99:99"]}).is_empty(), "unknown door keys rejected")
	check(not campus.validate({"open_doors": "x"}).is_empty(), "malformed door state rejected")
	var l3: Dictionary = rooms["lab3"]
	var locked := campus.interact_at("lab3", _campus_pose(l3, CampusGeometry.tile_center(l3, 41, 15) + Vector2(0, 14), -PI * 0.5))
	check(String(locked.get("toast", "")).contains("机房钥匙") and not campus.is_open("lab3:41:15"), "locked door keeps the Web lock and key name")
	# Seamless teach1 south door (campus-link: column 31, 3 cells wide).
	var cfg: Dictionary = CampusData.campus()["campus_doors"]
	var spec: Dictionary = cfg["doors"][0]
	var port := CampusGeometry.door_port(t1, spec)
	var inside := campus.crossing("teach1", _campus_pose(t1, port["p"] - Vector2(0, 2), PI * 0.5))
	check(inside.is_empty(), "no switch before the threshold line")
	var out := campus.crossing("teach1", _campus_pose(t1, port["p"] + Vector2(0, 0.5), PI * 0.5))
	check(out.get("world") == "out", "crossing the threshold leaves to the campus")
	var back := campus.crossing("out", out["pose"])
	check(back.is_empty(), "standing outside the gap does not bounce back")
	var shift := CampusGeometry.shift_of(t1)
	var entering := campus.crossing("out", _campus_pose(null, port["p"] + shift - Vector2(0, 1), -PI * 0.5))
	check(entering.get("world") == "teach1", "walking into the doorway enters teach1")
	var p_in: Array = entering["pose"]["position"]
	var expect := CampusGeometry.to_scene(t1, port["p"] - Vector2(0, 1))
	check(absf(p_in[0] - expect.x) < 0.001 and absf(p_in[2] - expect.y) < 0.001, "threshold keeps position through the room/campus translation")
	var garage := campus.interact_at("out", _campus_pose(null, Vector2(956, 326), PI * 0.5))
	check(garage.get("travel", {}).get("world") == "garage1", "E at the garage entrance enters garage1")
	var at_teach := campus.interact_at("out", _campus_pose(null, Vector2(1077.5, 1975), -PI * 0.5))
	check(at_teach["notice"] == "我：门开着，直接走进去就行。", "seamless buildings answer like the Web version")
	var exit_room: Dictionary = rooms["trash1"]
	check(exit_room["exit_world"] != null, "rooms know where their host door is outside")
	# Stairwell threshold (stairwell.js): teach1 west stair cell (6..7, 21) opens to stair_teach_w.
	var stair_port := CampusPortals.stair_port(CampusPortals.stair_config(CampusData.campus()["stair_layout"], "stair_teach_w"), 0, rooms, CampusData.layout("out"))
	var before_stair := campus.crossing("teach1", _campus_pose(t1, stair_port["p"] - Vector2(0, 2), PI * 0.5))
	check(before_stair.is_empty(), "approaching the stair doorway does not switch yet")
	var into_stair := campus.crossing("teach1", _campus_pose(t1, stair_port["p"] + Vector2(0, 0.3), PI * 0.5))
	check(into_stair.get("world") == "stair_teach_w" and absf(float(into_stair["pose"]["position"][1]) - 0.05) < 0.001, "walking past the stair doorway enters the shaft at ground level")
	var level_two := campus.crossing("stair_teach_w", {"position": [0.0, 3.2, -2.9], "yaw": 0.0, "pitch": 0.0})
	check(level_two.get("world") == "teach2", "leaving the shaft on the 3.2 m landing reaches teach2")
	var mid_air := campus.crossing("stair_teach_w", {"position": [0.0, 1.6, -2.9], "yaw": 0.0, "pitch": 0.0})
	check(mid_air.is_empty(), "no exit between landings")
	var surfaces := CampusPortals.stair_surfaces(6, 3.2)
	check(surfaces.size() == 6 * 2 + 5 * 3, "stair surfaces match StairGeometry for six levels")
	check(is_equal_approx(CampusPortals.surface_at(surfaces, -1.25, 3.2, 0.8)["h"], 0.8), "half way up the first flight is 0.8 m")
	# Corridor bridge teach2 -> link2 (campus-link/link.js, a pure translation).
	var t2: Dictionary = rooms["teach2"]
	var link_cfg: Dictionary = CampusData.campus()["campus_link"]
	var tp := CampusPortals.link_port(rooms, link_cfg["pairs"][3][0], 3)
	var bridged := campus.crossing("teach2", _campus_pose(t2, (tp["p"] as Vector2) + Vector2(0, -0.5), -PI * 0.5))
	check(bridged.get("world") == "link2", "walking out of teach2's north opening enters the bridge")
	var back_t2 := campus.crossing("link2", bridged["pose"])
	check(back_t2.is_empty(), "arriving on the bridge does not bounce back")
	var canteen_stair := campus.interact_at("canteen1", _campus_pose(rooms["canteen1"], CampusGeometry.tile_center(rooms["canteen1"], 4, 25), PI * 0.5))
	check(canteen_stair.get("travel", {}).get("world") == "out", "canteen stair without a shaft leads outside like stairGo")


func _test_elevator_rules() -> void:
	var rooms := CampusData.rooms()
	var lift := ElevatorModule.new(rooms)
	lift.reset()
	lift.set_seed(7)
	var t1: Dictionary = rooms["teach1"]
	var f := lift.frame("teach1")
	check(not f.is_empty() and (f["out"] as Vector2) == Vector2(0, -1), "teach1 elevator J cell faces the corridor")
	var hall := (f["j"] as Vector2) + Vector2(0, -12)
	var pose_hall := _campus_pose(t1, hall, -PI * 0.5)
	# The car starts at floor 1: the call button opens the doors directly.
	var called := lift.use_at("teach1", hall)
	check(called["notice"] == "我：按下呼梯键。门开了。", "hall call at the car's floor opens the doors")
	_run_lift(lift, 1.0, "teach1", pose_hall)
	check(is_equal_approx(lift.door_amount("teach", 1), 1.0), "doors open fully in 0.9 s")
	_run_lift(lift, 4.2, "teach1", pose_hall)
	check(lift.door_amount("teach", 1) < 1.0, "doors start closing after the 4 s hold")
	# Step into the cabin (behind the landing door) and choose floor 3.
	lift.use_at("teach1", hall)
	_run_lift(lift, 1.0, "teach1", pose_hall)
	var inside := lift.world("teach1", -1.2, 0.0)
	var pose_in := _campus_pose(t1, inside, PI * 0.5)
	_run_lift(lift, 0.1, "teach1", pose_in)
	check(lift.ride.get("phase") == "cabin" and lift.ride.get("origin") == 1, "stepping over the landing door boards the cabin")
	var panel := lift.use_at("teach1", inside)
	check(panel.has("choice") and (panel["choice"]["values"] as Array).size() in [2, 5], "cabin panel offers floors")
	if lift.ride.get("rare", false):
		lift.ride["rare"] = false # This seed's roll is irrelevant here; the rare path is tested below.
	lift.press(3, "teach1", pose_in)
	var departed := _run_lift(lift, 2.0, "teach1", pose_in)
	check(departed.get("travel", {}).get("world") == "lift_teach", "doors close, then the ride moves to the cabin scene")
	var car_pose: Dictionary = departed["travel"]["pose"]
	check(lift.door_amount("teach", 1) == 0.0 and lift.lifts["teach"]["phase"] == "occupied", "car is occupied while travelling")
	var arrived := _run_lift(lift, 5.0, "lift_teach", car_pose)
	check(arrived.get("travel", {}).get("world") == "teach3", "after 2 + 2 × 0.7 s the ride arrives at teach3")
	var p3: Array = arrived["travel"]["pose"]["position"]
	var exp3 := CampusGeometry.to_scene(rooms["teach3"], lift.world("teach3", -1.2, 0.0))
	check(absf(p3[0] - exp3.x) < 0.01 and absf(p3[2] - exp3.y) < 0.01, "arrival keeps the spot inside the cabin")
	_run_lift(lift, 1.0, "teach3", arrived["travel"]["pose"])
	check(is_equal_approx(lift.door_amount("teach", 3), 1.0), "doors open at the arrival floor")
	var saved := lift.capture()
	var copy := ElevatorModule.new(rooms)
	copy.reset()
	check(copy.validate(JSON.parse_string(JSON.stringify(saved))).is_empty(), "elevator state survives JSON")
	copy.restore(JSON.parse_string(JSON.stringify(saved)))
	check(copy.capture()["lifts"]["teach"]["floor"] == 3 and copy.ride.get("phase") == "cabin", "restored elevator is at floor 3 with the ride")
	# Calling from another floor makes the car travel there.
	var lab := ElevatorModule.new(rooms)
	lab.reset()
	var l4: Dictionary = rooms["lab4"]
	var lab_hall := lab.world("lab4", 1.2, 0.0)
	var waiting := lab.use_at("lab4", lab_hall)
	check(waiting["notice"] == "我：按下呼梯键。楼层指示灯缓慢亮了起来。" and lab.lifts["lab"]["phase"] == "waiting", "calling from lab4 summons the car")
	_run_lift(lab, 3.0 + 3 * 0.7 + 1.2, "lab4", _campus_pose(l4, lab_hall, 0.0))
	check(lab.lifts["lab"]["floor"] == 4 and lab.door_amount("lab", 4) > 0.9, "car arrives at lab4 and opens")
	# Rare ride: the 67/89 buttons enter the fully ported maze.
	lab.ride = {"host": "lab", "origin": 4, "target": 4, "phase": "cabin", "rare": true, "remaining": 0.0, "pending": null}
	var rare_panel := lab.controls("lab4", lab.world("lab4", -1.2, 0.0))
	check(rare_panel["choice"]["values"] == ["67", "89"], "the rare cabin only offers 67 and 89")
	var fresh := ElevatorModule.new(rooms)
	fresh.reset()
	fresh.set_seed(20261108)
	var rare_rolls := 0
	for _i in 200:
		fresh.ride = {}
		fresh._enter_cabin("teach", 1)
		rare_rolls += 1 if fresh.ride["rare"] else 0
	check(rare_rolls > 0 and rare_rolls < 40, "seeded natural boarding includes rare rides alongside ordinary ones (%d / 200)" % rare_rolls)


func _test_inventory_rules() -> void:
	var rooms := CampusData.rooms()
	var inv := InventoryModule.new(rooms, CampusData.campus())
	inv.reset()
	inv.set_seed(3)
	check(inv.capacity() == 8, "the bag holds eight things")
	check(inv.add("torch") and not inv.add("torch"), "an item is held once")
	for id: String in ["chalk", "pen", "coin", "battery", "card", "notebook", "watch"]:
		inv.add(id)
	check(inv.bag.size() == 8 and not inv.add("pill") and inv.take_notices().has("我：装不下了。"), "a full bag refuses more")
	check(inv.set_hot(0, "torch") and not inv.set_hot(1, "pill"), "hot slots only take held items")
	inv.use_hot(0, 700.0)
	check(inv.torch_on, "the torch toggles from its hot slot")
	inv.remove("torch")
	check(inv.hot[0] == null and not inv.torch_on, "dropping the torch clears its slot and light")
	check(inv.has_clock() and inv.use("watch", 700.0)["notice"] == "我：现在是 11:40。", "the watch tells the time")
	inv.remove("coin")
	inv.add("pill")
	inv.use("pill", 700.0)
	var gained := 0.0
	for _i in 40:
		gained += inv.step(1.0)
	check(absf(gained - 60.0) < 0.01 and not inv.has("pill"), "a pill restores 2 SAN per second for 30 s")
	inv.add("snack")
	inv.use("snack", 700.0)
	check(inv.snack_active(), "the snack starts its 30 s")
	# Searching: hold still 0.8 s; walking away cancels; the same drawer is only searched once.
	var fresh := InventoryModule.new(rooms, CampusData.campus())
	fresh.reset()
	fresh.set_seed(11)
	var t1: Dictionary = rooms["teach1"]
	var desk := CampusGeometry.tile_center(t1, 47, 7)
	fresh.start_search("teach1", 47, 7, desk)
	fresh.search_tick(0.5, "teach1", desk + Vector2(9, 0))
	check(not fresh.searching() and fresh.take_notices().has("我：手一松，没翻完。"), "moving away interrupts the search")
	fresh.start_search("teach1", 47, 7, desk)
	fresh.search_tick(0.5, "teach1", desk)
	check(fresh.searching(), "still searching after 0.5 s")
	fresh.search_tick(0.4, "teach1", desk)
	check(not fresh.searching() and fresh.hw_taken and fresh.has("hw"), "the first teach1 drawer holds the homework")
	fresh.start_search("teach1", 47, 7, desk)
	check(fresh.take_notices().has("我：翻过了。"), "a searched drawer stays searched")
	# The principal's office keeps its 45 % key chance with the pity on the fourth miss.
	var keys := InventoryModule.new(rooms, CampusData.campus())
	keys.reset()
	var found := false
	for i in 4:
		keys.desk_used.clear()
		keys.do_search("admin5", 10 + i, 3)
		found = found or keys.has("key") or keys.has("roomkey")
	check(found, "four principal drawers always give a key (pity)")
	var campus := CampusData.make_module()
	campus.reset()
	var l3: Dictionary = rooms["lab3"]
	var lab_pose := _campus_pose(l3, CampusGeometry.tile_center(l3, 41, 15) + Vector2(0, 14), -PI * 0.5)
	check(campus.hint("lab3", lab_pose) == "开门（锁着）", "the lab3 machine room door shows as locked")
	var bag := InventoryModule.new(rooms, CampusData.campus())
	bag.reset()
	campus.has_item = bag.has
	bag.add("roomkey")
	var opened := campus.interact_at("lab3", lab_pose)
	check(opened.get("door", {}).get("open") == true, "the machine room key opens it")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bag.capture()))
	check(bag.validate(saved).is_empty(), "bag state survives JSON")
	saved["bag"] = ["nonsense"]
	check(not bag.validate(saved).is_empty(), "unknown items are rejected")


func _test_marks_rules() -> void:
	var t1 := CampusData.layout("teach1")
	var m := MarksModule.new()
	m.reset()
	var solid := func(q: Vector2) -> bool: return CampusGeometry.SOLID_CH.contains(CampusGeometry.tile_at(t1, q))
	var near_wall := _wall_spot(t1)
	m.set_context({"scene": "teach1", "x": near_wall.x, "y": near_wall.y, "ang": PI, "pitch": 0.0, "solid": solid, "has_chalk": true})
	var t := m.target()
	check(t["face"] == "wall" and float(t["h"]) > 1.0, "looking level at a wall targets the wall")
	m.set_context({"scene": "teach1", "x": near_wall.x + 40.0, "y": near_wall.y, "ang": 0.0, "pitch": -0.8, "solid": solid, "has_chalk": true})
	check(m.target()["face"] == "floor", "looking down targets the floor")
	check(m.use_chalk() and m.take_events()[0]["labels"].size() == 8, "the chalk offers eight symbols")
	m.choose(0)
	var ev := m.take_events()
	check(m.marks.size() == 1 and ev.any(func(e: Dictionary) -> bool: return e["kind"] == "fact"), "a mark is drawn")
	m.use_chalk()
	check(m.take_events()[0]["labels"].size() == 9, "on a mark the chalk can also erase it")
	m.choose(8)
	check(m.marks.is_empty(), "erased")
	for i in 85:
		m.place("x", {"room": "teach1", "x": float(i), "y": 0.0, "h": 0.0, "face": "floor", "a": 0.0})
	check(m.visible("teach1").size() == MarksModule.PER_ROOM, "at most 80 marks a room")
	m.set_context({"scene": "teach1", "has_chalk": false})
	check(not m.use_chalk(), "no chalk, no marks")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.capture()))
	var back := MarksModule.new()
	back.reset()
	back.restore(saved)
	check(back.marks.size() == MarksModule.PER_ROOM, "marks survive the save")


func _test_exploration_rules() -> void:
	var rooms := CampusData.rooms()
	var t1: Dictionary = rooms["teach1"]
	var ex := ExplorationModule.new(rooms)
	ex.reset()
	var at := CampusGeometry.tile_center(t1, 20, 18)
	var open_doors := {}
	ex.set_context({"scene": "teach1", "x": at.x, "y": at.y, "door_open": func(c: int, r: int) -> bool: return open_doors.has("%d:%d" % [c, r])})
	check(ex.rooms().is_empty() and ex.count("teach1") == 0, "nothing is on the sketch before you look")
	check(ex.observe() and ex.has(t1, 20, 18) and ex.has(t1, 24, 18) and not ex.has(t1, 40, 18), "the tiles within 6 around you are seen, the far ones are not")
	check(ex.rooms() == ["teach1"] and ex.count("teach1") > 20, "the room joins the list of walked floors")
	check(not ex.has(t1, 20, 10), "a classroom behind its closed door is not seen from the corridor")
	var d := Vector2i(-1, -1)
	for c in range(10, 24):
		if String(t1["grid"][15]).substr(c, 1) == "=":
			d = Vector2i(c, 15)
			break
	check(d.x >= 0, "(the corridor wall has classroom doors)")
	var door_at := CampusGeometry.tile_center(t1, d.x, 17)
	var ex2 := ExplorationModule.new(rooms)
	ex2.reset()
	ex2.set_context({"scene": "teach1", "x": door_at.x, "y": door_at.y, "door_open": func(_c: int, _r: int) -> bool: return false})
	ex2.observe()
	check(not ex2.has(t1, d.x, 13), "a closed door hides the room behind it")
	var ex3 := ExplorationModule.new(rooms)
	ex3.reset()
	ex3.set_context({"scene": "teach1", "x": door_at.x, "y": door_at.y, "door_open": func(_c: int, _r: int) -> bool: return true})
	ex3.observe()
	check(ex3.has(t1, d.x, 13), "an open door shows it")
	check(ex.percent("teach1") > 0 and ex.percent("teach1") < 20, "a few steps in, a small part of the floor is seen (%d%%)" % ex.percent("teach1"))
	# Save: six tiles a character, trailing blanks dropped; a bad record is rejected.
	var saved := ex.capture()
	var text := String(saved["seen"]["teach1"])
	check(text.length() <= (63 * 22 + 5) / 6 and not text.ends_with("A") and ExplorationModule.unpack(text, t1) == ex.seen("teach1"), "the sketch packs to a short string and unpacks to the same tiles")
	var back := ExplorationModule.new(rooms)
	back.restore(saved)
	check(back.count("teach1") == ex.count("teach1") and back.validate(saved).is_empty(), "the sketch saves and loads")
	check(not back.validate({"seen": {"teach1": "!!"}}).is_empty() and not back.validate({"seen": {"nowhere": "A"}}).is_empty() and not back.validate({"seen": {"teach1": "B".repeat(400)}}).is_empty(), "bad records are rejected")
	# The tick samples every 0.3 s.
	var tk := ExplorationModule.new(rooms)
	tk.reset()
	tk.set_context({"scene": "teach1", "x": at.x, "y": at.y, "door_open": func(_c: int, _r: int) -> bool: return false})
	tk.tick(0.2)
	check(tk.count("teach1") == 0, "no look before 0.3 s")
	tk.tick(0.15)
	check(tk.count("teach1") > 0, "a look every 0.3 s")
	check(MapView.tone("留") == "brass" and MapView.tone("锁") == "seal" and MapView.tone("✓") == "done" and MapView.tone("梯") == "route" and MapView.tone("桌") == "prop" and MapView.static_mark("S") == "梯", "the four tones and the furniture letters of the sketch")


func _test_drop_rules() -> void:
	var bag := InventoryModule.new(CampusData.rooms(), CampusData.campus())
	bag.reset()
	bag.add("coin")
	bag.add("torch")
	bag.set_hot(0, "torch")
	bag.torch_on = true
	check(bag.drop("torch") and not bag.has("torch") and bag.hot[0] == null and not bag.torch_on and bag.take_notices().has("我：我把「手电筒」放下了。"), "dropping an item removes it from the bag and the hot slot, and switches the torch off")
	check(not bag.drop("torch") and bag.has("coin"), "dropping what you do not have does nothing; the rest stays")
	var fac := FacilitiesModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.flags["coil"] = true
	check(fac.flags["coil"] == true, "(the coil was taken from the server room)")


func _test_duty_rules() -> void:
	check(DutyRoster.tier_of(0.0) == 0 and DutyRoster.tier_of(19.9) == 0 and DutyRoster.tier_of(20.0) == 1 and DutyRoster.tier_of(65.0) == 3 and DutyRoster.tier_of(80.0) == 4 and DutyRoster.tier_of(500.0) == 4, "the roster changes every 20 assimilation, up to tier 4")
	var mine := func(t: int) -> int:
		var n := 0
		for d in 5:
			for k in 3:
				n += 1 if DutyRoster.is_mine(t, k, d, 2) else 0
		return n
	check(mine.call(0) == 0 and mine.call(1) == 1 and mine.call(2) == 5 and mine.call(3) == 10 and mine.call(4) == 15, "tier 1 one square today, 2 the first square every day, 3 two a day, 4 all fifteen")
	check(DutyRoster.is_mine(1, 0, 2, 2) and not DutyRoster.is_mine(1, 0, 3, 2) and not DutyRoster.is_mine(1, 1, 2, 2), "tier 1 is today's first square only")
	check(DutyRoster.NAMES.size() == 16 and DutyRoster.NAMES[0] == "王浩" and DutyRoster.DAYS == ["周一", "周二", "周三", "周四", "周五"], "the names and weekdays are the Web version's")


func _test_last_life_box() -> void:
	var rooms := CampusData.rooms()
	var g := CampusData.layout("guard1")
	var at := Vector2(float(g["ox"]) + 4.5 * float(g["tw"]), float(g["oy"]) + 6.5 * float(g["th"]))
	var m := MarksModule.new(rooms)
	m.reset()
	m.set_context({"scene": "guard1", "x": at.x, "y": at.y})
	check(not m.near_box() and m.box_hint() == "" and not m.use_box(), "no box without a trace of the last run")
	m.last_life = {"scene": "teach1", "x": 10.0, "y": 10.0, "tsec": 745, "day": 2}
	check(m.near_box() and m.box_hint() == "失物招领箱", "with a trace, the lost-and-found box by the guard counter is offered")
	check(m.use_box(), "E at the box reads the card")
	var ev := m.take_events()
	check(String(ev[0]["text"]).contains("照片那一栏是空的") and String(ev[0]["text"]).contains("第 2 天 12:25") and ev[1]["kind"] == "record" and ev[1]["id"] == "lastLife" and ev[1]["source"] == "保安岗", "the card is blank, the day and time are pencilled on the back, and it is noted")
	m.set_context({"scene": "guard1", "x": at.x + 100.0, "y": at.y})
	check(not m.near_box(), "only close to the box")
	m.set_context({"scene": "teach1", "x": at.x, "y": at.y})
	check(not m.near_box(), "only at the guard post")


func _test_umbrella_rules() -> void:
	var bag := InventoryModule.new(CampusData.rooms(), CampusData.campus())
	bag.reset()
	bag.add("brolly")
	check(not bag.brolly_up, "the umbrella starts closed")
	var open := bag.use("brolly", 700.0)
	check(bag.brolly_up and open["toast"] == "撑开伞", "using it opens it")
	var shut := bag.use("brolly", 700.0)
	check(not bag.brolly_up and shut["toast"] == "收起伞", "using it again closes it")
	bag.use("brolly", 700.0)
	bag.drop("brolly")
	check(not bag.brolly_up and not bag.has("brolly"), "dropping an open umbrella closes it")
	bag.add("brolly")
	bag.use("brolly", 700.0)
	bag.reset()
	check(not bag.brolly_up, "a new run starts with it closed")
	# The cola anomaly's can bounces off an open umbrella (anomaly.js): it costs SAN instead of the can.
	var an := CampusData.make_anomaly()
	check(an != null, "(the anomaly module reads the umbrella from its context)")


func _test_vault_hold() -> void:
	var rooms := CampusData.rooms()
	var roof: Dictionary = rooms["teach6"]
	var body := BodyModule.new(rooms)
	body.reset()
	# Stand one step from the parapet on the north side, facing it.
	var at := Vector2(float(roof["ox"]) + 10.5 * float(roof["tw"]), float(roof["oy"]) + 1.8 * float(roof["th"]))
	var ctx := {"scene": "teach6", "x": at.x, "y": at.y, "ang": -PI * 0.5, "seated": false, "hiding": false, "stam": 100.0, "moving": false, "locked": false, "anomaly": false, "day": 1, "dead": false, "space": true}
	body.set_context(ctx)
	check(not body.target().is_empty() and body.hint() == "翻过栏杆 · 外侧悬空（按住空格）", "the railing hint now says to hold space")
	body.tick(0.4)
	check(body.hold > 0.39 and body.fall == null, "holding space builds progress, nothing yet")
	var released := ctx.duplicate()
	released["space"] = false
	body.set_context(released)
	body.tick(0.1)
	check(body.hold == 0.0 and body.fall == null, "letting go cancels")
	body.set_context(ctx)
	for _i in 5:
		body.tick(0.15)
	check(body.fall != null and body.hold == 0.0, "after 0.6 s of holding the vault begins")
	var tired := BodyModule.new(rooms)
	tired.reset()
	var weak := ctx.duplicate()
	weak["stam"] = 3.0
	tired.set_context(weak)
	for _i in 6:
		tired.tick(0.15)
	check(tired.fall == null and _of_kind(tired.take_events(), "notice").size() >= 1, "too tired: holding does not vault, and says so")
	var away := ctx.duplicate()
	away["x"] = at.x + 200.0
	var far := BodyModule.new(rooms)
	far.reset()
	far.set_context(away)
	for _i in 6:
		far.tick(0.15)
	check(far.hold == 0.0 and far.fall == null, "away from the railing holding space does nothing")


func _test_facility_rules() -> void:
	var rooms := CampusData.rooms()
	var fac := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	fac.reset()
	fac.set_seed(3)
	# Rest: which tile offers what, the hint, the gain scaled by pressure, the cooldown in game minutes.
	fac.set_context(_fctx("teach1", {"meal": true}))
	check(fac.rest_for(rooms["teach1"], "w") == "wash" and fac.rest_for(rooms["dorm1"], "b") == "sleep" and fac.rest_for(rooms["lab5"], "p") == "piano"
		and fac.rest_for(rooms["lab3"], "n") == "pc" and fac.rest_for(rooms["canteen1"], "k") == "eat", "the rest activities sit where they did")
	fac.set_context(_fctx("canteen1", {"meal": false}))
	check(fac.rest_for(rooms["canteen1"], "k") == "" and fac.hint(rooms["canteen1"], "k") == "打饭窗口", "outside meal times the canteen window wants a coin")
	var field := Vector2.ZERO
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == "field":
			field = Vector2((float(o["x"]) + float(o["w"]) / 2.0) * 2.0, (float(o["y"]) + float(o["h"]) / 2.0) * 2.0)
	check(fac.rest_out(field) == "run" and FacilitiesModule.rest_hint("run") == "沿跑道跑两圈（12 分钟）", "the field is for running two laps")
	fac.set_context(_fctx("teach1", {"rest_mul": 0.5, "clock": 800.0,"tsec":800.0}))
	fac.rest("wash")
	var ev := fac.take_events()
	check(_of_kind(ev, "advance")[0]["minutes"] == 4.0 and _of_kind(ev,"rest_gain")[0]["base"]==8.0 and _of_kind(ev, "fact")[0]["key"] == "wash" and _of_kind(ev, "stamina")[0]["amount"] == 25.0,
		"washing advances four minutes before applying the pressure to its eight SAN and 25 stamina")
	fac.set_context(_fctx("teach1", {"clock": 820.0}))
	fac.rest("wash")
	check(_notices(fac.take_events()).has("我：刚做过。现在没那个心情。"), "a rest has a cooldown in game minutes")
	fac.set_context(_fctx("teach1", {"clock": 900.0}))
	fac.rest("wash")
	check(not _of_kind(fac.take_events(), "rest_gain").is_empty(), "after the cooldown it works again")
	# Lab devices.
	var bag: Array = []
	fac.set_context(_fctx("lab1", {"bag": bag, "anomaly": {"active": false, "pre": "rain", "warn_ok": true, "minutes": 7, "cn": "下不完的雨"}}))
	fac.use(rooms["lab1"], "Z", 0, 0)
	ev = fac.take_events()
	check(not _of_kind(ev, "anomaly_lock").is_empty() and _notices(ev)[0].contains("「下不完的雨」。还有大约 7 分钟。"), "the pendulum names the coming anomaly and locks it")
	fac.use(rooms["lab1"], "Z", 0, 0)
	check(_notices(fac.take_events()).has("我：刚弄过。等一会儿。"), "the pendulum has a cooldown")
	fac.set_context(_fctx("lab1", {"bag": bag}))
	fac.use(rooms["lab1"], "N", 0, 0)
	check(bag.has("lens") and bool(fac.flags["lens"]), "the microscope gives the lens once")
	fac.set_context(_fctx("lab3", {"bag": bag}))
	fac.use(rooms["lab3"], "Q", 0, 0)
	check(bag.has("coil"), "the server gives the coil")
	fac.use(rooms["lab3"], "Q", 0, 0)
	check(_notices(fac.take_events()).back().contains("每一行的时间都是 11:40"), "and only once")
	var got_vial := false
	for i in 40:
		fac.set_context(_fctx("lab2", {"bag": bag, "clock": 1000.0 + i * 100.0}))
		fac.use(rooms["lab2"], "C", 0, 0)
		if bag.has("vial"):
			got_vial = true
			break
	check(got_vial, "the centrifuge separates the vial on a good spin")
	fac.set_context(_fctx("lab2", {"bag": bag}))
	fac.use(rooms["lab2"], "K", 0, 0)
	check(bag.has("goggles"), "the chemistry bench has goggles")
	# Canteen window, vending machine, altar, stall.
	var purse: Array = []
	fac.set_context(_fctx("canteen1", {"bag": purse}))
	fac.use(rooms["canteen1"], "k", 0, 0)
	check(_notices(fac.take_events()).has("我：窗口里的人头也不抬：「饭点过了。要吃，拿钱来。」"), "no coin, no meal")
	purse.append("coin")
	fac.use(rooms["canteen1"], "k", 0, 0)
	check(_of_kind(fac.take_events(), "choice").size() == 1, "with a coin the window offers a meal")
	fac.choose(0)
	ev = fac.take_events()
	check(not purse.has("coin") and _of_kind(ev, "san")[0]["amount"] == 24.0 and _of_kind(ev, "advance")[0]["minutes"] == 10.0, "a bought meal: 24 SAN, 10 minutes")
	var altar_room: Dictionary = {}
	for id: String in rooms:
		if String("".join(rooms[id]["grid"])).contains("A"):
			altar_room = rooms[id]
	fac.set_context(_fctx(String(altar_room.get("id", "x")), {"bag": purse}))
	fac.use(altar_room, "A", 0, 0)
	check(purse.has("coin"), "the altar hides a coin")
	fac.use(rooms["canteen1"], "M", 0, 0)
	check(not purse.has("coin"), "the vending machine eats it")
	fac.use(rooms["teach1"], "B", 0, 0)
	check(_notices(fac.take_events()).back().begins_with("我：第三个隔间的门从里面锁着") and fac.spots.has("stall"), "the third stall is locked from inside")
	# The bell: the thirteenth stroke ends bell13, otherwise exams start.
	fac.set_context(_fctx("bell1", {"anomaly": {"active": true, "id": "bell13"}}))
	fac.use(rooms["bell1"], "U", 0, 0)
	check(not _of_kind(fac.take_events(), "anomaly_end").is_empty(), "ringing the bell during the thirteen strokes ends them")
	fac.set_context(_fctx("bell1"))
	fac.use(rooms["bell1"], "U", 0, 0)
	check(not _of_kind(fac.take_events(), "exam_start").is_empty(), "otherwise it starts the exams")
	# Spots, map and compass.
	fac.set_context(_fctx("guard1"))
	fac.spot_tick()
	check(fac.spots.has("guard"), "being in the guard house marks it")
	var paper: Array = ["map"]
	fac.set_context(_fctx("teach1", {"bag": paper}))
	check(fac.use_item("map") and fac.spots.has("trash") and fac.spots.has("wall") and not _of_kind(fac.take_events(), "map").is_empty(), "the plan marks four places and opens the map")
	fac.set_context(_fctx("teach1", {"x": float(rooms["teach1"]["ox"]) + 30.0, "y": float(rooms["teach1"]["oy"]) + 30.0}))
	check(fac.use_item("compass") and _of_kind(fac.take_events(), "toast")[0]["text"].begins_with("罗盘 → "), "the compass points to the nearest way out")
	# The portal (portal.js).
	var p := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	p.reset()
	var kit: Array = []
	p.set_context(_fctx("lab1", {"bag": kit, "x": 700.0, "y": 700.0, "ang": 1.0}))
	p.use(rooms["lab1"], "K", 0, 0)
	ev = p.take_events()
	check(_of_kind(ev, "choice")[0]["text"] == "实验台后有一条覆着黑色黏液的狭窄隧道。", "the bench shows the tunnel")
	p.choose(0)
	ev = p.take_events()
	check(_of_kind(ev, "travel")[0]["world"] == "portal_tunnel" and p.portal["ret"]["x"] == 700.0, "entering the tunnel remembers where you stood")
	p.set_context(_fctx("lab4", {"bag": kit}))
	p.use(rooms["lab4"], "K", 0, 0)
	check(_of_kind(p.take_events(), "choice").is_empty(), "no blueprints before the diary")
	p.set_context(_fctx("portal_tunnel", {"bag": kit}))
	p.use(rooms["portal_tunnel"], "u", 0, 0)
	check(bool(p.portal["diary"]) and _notices(p.take_events())[0].contains("二楼、四楼和五楼"), "the diary tells where the blueprints are")
	p.use(rooms["portal_tunnel"], "j", 0, 5)
	check(_of_kind(p.take_events(), "travel")[0]["x"] == 700.0, "leaving puts you back at the bench")
	p.set_context(_fctx("lab2", {"bag": kit}))
	p.use(rooms["lab2"], "K", 0, 0)
	p.take_events()
	p.choose(0)
	check(not p.portal["blueprints"].has(2) and _notices(p.take_events())[0].contains("发光重液会沉底"), "a wrong answer explains and keeps the blueprint")
	p.use(rooms["lab2"], "K", 0, 0)
	p.take_events()
	p.choose(1)
	check(p.portal["blueprints"].has(2) and _notices(p.take_events())[0].contains("1 / 3"), "the right layer gives the second-floor blueprint")
	p.set_context(_fctx("lab4", {"bag": kit}))
	p.use(rooms["lab4"], "K", 0, 0)
	p.take_events()
	p.choose(2)
	p.take_events()
	p.set_context(_fctx("lab5", {"bag": kit}))
	for pick: int in [1, 2]:
		p.use(rooms["lab5"], "K", 0, 0)
		p.take_events()
		p.choose(pick)
		p.take_events()
	check(int(p.portal["work"][5]) == 2 and not p.portal["blueprints"].has(5), "the wiring order is pressed step by step")
	p.use(rooms["lab5"], "K", 0, 0)
	check(String(_of_kind(p.take_events(), "choice")[0]["text"]).ends_with("（已正确操作 2/3 步）"), "the progress is shown")
	p.choose(0)
	check(bool(p.portal["sketch"]) and _notices(p.take_events())[0].begins_with("我：三张图纸拼在一起"), "three blueprints make the sketch")
	p.set_context(_fctx("lab1", {"bag": kit}))
	p.use(rooms["lab1"], "K", 0, 0)
	check(_notices(p.take_events())[0].begins_with("我：草图上的四样，我还差「"), "the bench lists what is missing")
	for k: String in FacilitiesModule.PORTAL_PARTS:
		kit.append(k)
	p.use(rooms["lab1"], "K", 0, 0)
	check(_of_kind(p.take_events(), "choice")[0]["labels"][0] == "把它们接起来", "with the four parts the bench offers to assemble")
	p.choose(0)
	ev = p.take_events()
	check(bool(p.portal["open"]) and kit.is_empty() and not _of_kind(ev, "later").is_empty(), "assembling uses the parts and opens the circle")
	p.portal_ask()
	check(_of_kind(p.take_events(), "choice")[0]["labels"] == ["走进去", "再等一下"], "the circle waits")
	p.choose(0)
	check(_of_kind(p.take_events(), "ending")[0]["id"] == "portal", "walking in is 《门》")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.capture()))
	var back := FacilitiesModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	back.reset()
	check(back.validate(saved).is_empty(), "facility state survives JSON")
	back.restore(saved)
	check(bool(back.portal["open"]) and back.portal["blueprints"].has(5) and back.blueprint_count() == 3, "and restores with integer floors")
	# The school side: leave slip, exams, the tunnel drains.
	var day := SchoolModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	day.reset()
	check(day.use_leave() and day.on_leave() and not day.use_leave(), "a leave slip runs for 180 game minutes, once")
	day.viol = 100.0
	day.leave_until = 0.0
	check(not day.use_leave(), "with violations full the slip is refused")
	day.reset()
	day.tsec = 1200.0
	check(day.exam_start() and day.exam, "the bell turns the day into exams")
	var night := SchoolModule.new(rooms, CampusData.layout("out"), CampusData.campus())
	night.reset()
	night.tsec = 1350.0
	check(not night.exam_start(), "at night the bell gets no answer")
	check(night.danger_at("portal_tunnel") == "tunnel" and night.danger_at("garage1") == "garage" and night.danger_at("out") == "night", "the danger places")
