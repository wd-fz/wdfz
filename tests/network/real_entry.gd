extends "res://tests/network/consistency.gd"
## Controlled locations/items, but every route is entered by interact/choice/item commands.
## Unlike the legacy authority fixtures, never calls _board_car or _offer_ending.
func run() -> void:
	await fresh()
	await car_entry()
	await fresh()
	whitelist_entry()
	await fresh()
	portal_entry()
	await fresh()
	cyber_entry()
	await fresh()
	dismissal_entry()
	await fresh()
	international_entry()
	sim.queue_free()
	await process_frame
	print("LAN REAL-ENTRY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func agree(action: String) -> void:
	for a: CooperativeActor in sim.active_actors(): command(a, action, {"accept": true})

func gather(world: String, at: Vector2) -> void:
	for a: CooperativeActor in sim.active_actors(): point(a, world, at)

func car_entry() -> void:
	var a := sim.actor("a")
	var garage := sim.shared[&"garage.world"] as GarageModule
	a.bag().add("key")
	var key := garage.car_right_cell().split(":")
	check(aim(a, "garage1", int(key[0]), int(key[1])), "car: real target vehicle")
	for id: String in ["b", "c"]: sim.travel(sim.actor(id), a.location(), a.pose)
	garage.roam.merge({"on": true, "stage": "wait", "waitT": 20.0, "x": -1e6, "y": -1e6}, true)
	command(a, "interact")
	check(a.choice.get("source") == "garage", "car: door opens real choice")
	command(a, "choice", {"index": 0})
	for i in 110:
		sim.tick(1.0 / 60.0)
		await physics_frame
	check(not sim.gameplay.boarding.is_empty() and not garage.driving(), "car: actual key task reaches boarding")
	agree("board_confirm")
	check(garage.driving() and sim.gameplay.passengers.size() == 3, "car: consent starts one chase")
	for i in 2400:
		if garage.chase == null: break
		var d: Dictionary = garage.chase
		var target := 2.0 if d["distance"] < 65 else (-1.5 if d["distance"] < 95 else (2.0 if d["distance"] < 220 else -2.0))
		sim.input(a.id, {"epoch": sim.room.epoch, "scene": a.scene_version, "seq": i, "x": clampf((target - float(d["x"])) * 2, -1, 1), "y": -1.0, "yaw": 0, "pitch": 0, "run": false})
		sim.tick(1.0 / 60.0)
	check(sim.gameplay.qualified.get("route") == "car", "car: steering and escape distance reach qualification")
	agree("ending_confirm")
	check(sim.room.ending == "car", "car: real route finishes through team confirmation")

func whitelist_entry() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	a.bag().add("usb")
	check(tile(a, "lab3", "D"), "whitelist: real management terminal reachable")
	command(a, "interact")
	var route := sim.shared[&"story.routes"] as RoutesModule
	check(route.hacked, "whitelist: real terminal writes whitelist")
	check(tile(b, "admin3", "D"), "whitelist: real data terminal reachable")
	command(b, "interact")
	check(route.data_synced, "whitelist: teammate completes synchronization")
	var gate: Dictionary = CampusData.campus()["gates"]["w"]
	gather("out", Vector2(float(gate["x"]), float(gate["y"])) * 2)
	command(a, "interact")
	for i in 3:
		if a.choice.is_empty(): break
		var q: Dictionary = RoutesModule.QUESTIONS[route.face_quiz["order"][int(route.face_quiz["done"])]]
		command(a, "choice", {"index": int(q["answer"])})
	command(a, "choice", {"index": 0})
	agree("ending_confirm")
	check(sim.room.ending == "face", "whitelist: physical gate quiz and consent finish route")

func portal_entry() -> void:
	var a := sim.actor("a")
	check(tile(a, "lab1", "K"), "portal: actual bench reachable")
	command(a, "interact")
	command(a, "choice", {"index": 0})
	check(a.location() == "portal_tunnel", "portal: actual bench enters tunnel")
	check(tile(a, "portal_tunnel", "u"), "portal: diary is physically reachable")
	command(a, "interact")
	var facility := sim.shared[&"campus.facilities"] as FacilitiesModule
	check(facility.portal["diary"], "portal: reading diary reveals blueprints")
	for row: Array in [["lab2", [1]], ["lab4", [2]], ["lab5", [1, 2, 0]]]:
		for answer: int in row[1]:
			check(tile(a, row[0], "K"), "portal: real blueprint bench " + row[0])
			command(a, "interact")
			command(a, "choice", {"index": answer})
	check(facility.portal["sketch"], "portal: physical benches complete all three blueprints")
	for item: String in FacilitiesModule.PORTAL_PARTS: a.bag().add(item) # Material acquisition is covered by inventory/uniqueness fixtures.
	tile(a, "lab1", "K")
	for id: String in ["b", "c"]: sim.travel(sim.actor(id), a.location(), a.pose)
	command(a, "interact")
	command(a, "choice", {"index": 0})
	check(facility.portal["open"], "portal: actual assembly consumes materials")
	# Return to the same built device via E, rather than invoking portal_ask directly.
	command(a, "interact")
	command(a, "choice", {"index": 0})
	agree("ending_confirm")
	check(sim.room.ending == "portal", "portal: actual device offers and completes escape")

func cyber_entry() -> void:
	var a := sim.actor("a")
	a.bag().add("phone")
	sim.inventory.reconcile(a)
	check(tile(a, "lab3", "n"), "cyber: real lab computer reachable")
	sim.gameplay.prepare(a)
	var phone := a.feature(&"phone.network") as PhoneModule
	phone.acquire()
	phone.device["network"] = true
	phone.device["wireless"] = {"status": "complete", "target": 240.0, "elapsed": 240.0}
	phone.device["download"] = {"status": "complete", "target": 60.0, "elapsed": 60.0}
	command(a, "interact")
	check(a.choice.get("menu") == "computer", "cyber: actual computer opens menu")
	command(a, "choice", {"index": 2})
	check(a.terminal and phone.terminal_open, "cyber: menu opens real server terminal")
	var helper := preload("res://tests/support/test_suite.gd").new(self)
	for line: String in helper._solve_lines(phone.puzzle): check(command(a, "terminal", {"line": line}).get("ok", false), "cyber: actual terminal command")
	check(phone.termination["status"] == "accepted", "cyber: submitted shutdown accepted")
	command(a, "cancel")
	# Long countdown uses the same authoritative shared scheduler as the running simulation.
	for i in 1200: sim.gameplay.shared_tick(.5)
	agree("ending_confirm")
	check(sim.room.ending == "cyber", "cyber: elapsed countdown and team consent complete")

func dismissal_entry() -> void:
	var a := sim.actor("a")
	var radio := sim.shared[&"story.broadcast"] as BroadcastModule
	for id: String in ["notice1", "notice2", "notice3", "notice4"]: a.bag().add(id)
	radio.b["book"] = true # Precollected pages/fuse; actual station interaction and reading remain mandatory.
	radio.b["fuse"] = true
	for person: CooperativeActor in sim.active_actors():
		person.school().day = 2
		person.school().tsec = 1100
	var room: Dictionary = CampusData.rooms()[BroadcastModule.ROOM]
	point(a, BroadcastModule.ROOM, CampusGeometry.tile_center(room, BroadcastModule.STATION[0], BroadcastModule.STATION[1]) + Vector2(0, 9))
	command(a, "interact")
	check(a.choice.get("source") == "broadcast", "dismissal: real broadcast station menu")
	command(a, "choice", {"index": 3})
	for page in 4:
		command(a, "mic", {"paper": "notice%d" % (page + 1), "held": true})
		for i in 32: sim.gameplay.shared_tick(.5)
	check(radio.b["phase"] == "bell", "dismissal: actual mic reads all four pages")
	for i in 65:
		var crowd := radio.crowd()
		if not crowd.is_empty(): gather("out", Vector2(float(crowd["x"]), float(crowd["y"])))
		sim.gameplay.shared_tick(1)
		if not sim.room.ending_offer.is_empty(): break
	agree("ending_confirm")
	check(sim.room.ending == "dismissal", "dismissal: following actual crowd qualifies entire team")

func international_entry() -> void:
	var a := sim.actor("a")
	var visit := sim.shared[&"story.exchange"] as ExchangeModule
	visit.s["hit"] = 1 # Controlled rare visitor spawn; no bypass of its dialogue/escort.
	for person: CooperativeActor in sim.active_actors():
		person.school().day = 2
		person.school().tsec = 600
	gather("out", Vector2(120, 222))
	sim.gameplay.shared_tick(.1)
	var lead: Vector2 = visit.members()[0]
	point(a, "out", lead)
	for lang: String in ["de", "fr"]:
		command(a, "interact")
		var labels: Array = a.choice.get("labels", [])
		var pick := -1
		for i in labels.size():
			if String(labels[i]).contains(ExchangeModule.EXAM[lang]["n"]): pick = i
		check(pick >= 0, "international: real visitor offers " + lang)
		command(a, "choice", {"index": pick})
		for i in ExchangeModule.QUESTIONS: command(a, "choice", {"index": int(visit._order(lang)[i])})
	check(visit.s["phase"] == "qualified", "international: both real exams passed")
	command(a, "interact")
	var tail: Vector2 = visit.members().back()
	gather("out", tail + Vector2(4, 0))
	point(sim.actor("b"), "out", Vector2(1600, 1300))
	sim.gameplay.shared_tick(ExchangeModule.GRACE + .1)
	check(sim.gameplay._escort_lost.get("b", false), "international: distant member is marked as lagging")
	tail = visit.members().back()
	point(sim.actor("b"), "out", tail + Vector2(4, 0))
	sim.gameplay.shared_tick(.1)
	check(not sim.gameplay._escort_lost.get("b", false), "international: catching up clears lagging and restores qualification")
	for i in 2000:
		tail = visit.members().back()
		gather("out", tail + Vector2(4, 0))
		sim.gameplay.shared_tick(.25)
		if not sim.room.ending_offer.is_empty(): break
	agree("ending_confirm")
	check(sim.room.ending == "international", "international: full escort path and consent finish")
