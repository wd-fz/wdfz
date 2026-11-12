extends SceneTree
## Controlled rule fixtures. These exercise real feature adapters, not natural playthroughs.
var checks := 0
var failures := 0
var sim: CooperativeSimulation


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", message)


func fresh() -> void:
	if is_instance_valid(sim):
		sim.queue_free()
		await process_frame
	var room := CooperativeRoom.new()
	room.add_member("a", "房主", true)
	room.add_member("b", "队友")
	room.ready("a", true, "none")
	room.ready("b", true, "none")
	room.begin("authority-fixture")
	room.loaded("a")
	room.loaded("b")
	sim = CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 421)
	await physics_frame
	await physics_frame


func command(a: CooperativeActor, action: String, fields: Dictionary = {}) -> Dictionary:
	var packet := {"epoch": sim.room.epoch, "scene": a.scene_version, "seq": a.command_sequence + 1, "action": action}
	packet.merge(fields, true)
	return sim.command(a.id, packet)


func place(a: CooperativeActor, world: String, at: Vector2) -> void:
	var p := CampusGeometry.to_scene(CampusData.rooms().get(world), at)
	sim.travel(a, world, {"position": [p.x, 0.05, p.y], "yaw": 0.0, "pitch": 0.0})
	sim.gameplay.prepare(a)


func run() -> void:
	await fresh()
	transactions()
	transport_ordering()
	lobby_reconnect()
	await fresh()
	time_consent()
	await fresh()
	persistence()
	await fresh()
	patrol_responsibility()
	await fresh()
	anomaly_continuity()
	await fresh()
	await mobility()
	await fresh()
	whitelist()
	await fresh()
	portal()
	await fresh()
	car()
	await fresh()
	cyber()
	await fresh()
	dismissal()
	await fresh()
	international()
	sim.queue_free()
	await process_frame
	print("LAN AUTHORITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func transactions() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	b.pose = a.pose.duplicate(true)
	a.bag().add("pill")
	sim.inventory.reconcile(a)
	var packet := {"epoch": sim.room.epoch, "scene": a.scene_version, "seq": 20, "action": "give", "to": "b", "item": "pill", "member": "b"}
	check(sim.command("a", packet).get("ok", false), "verified sender can transfer its own item")
	check(sim.command("a", packet).get("ok", false), "duplicate transaction returns cached result")
	check(b.bag().has("pill") and not a.bag().has("pill"), "identity field cannot change actual sender or duplicate item")
	check(not command(b, "item", {"item": {"unexpected": true}}).get("ok", false), "malformed typed command rejected without exception")
	check(not command(b, "pickup", {"uid": []}).get("ok", false), "malformed ground ID rejected without exception")
	check(not command(b, "interact", {"scene": {}}).get("ok", false), "malformed scene version rejected before numeric conversion")
	check(not command(b, "debug_recover").get("ok", false) and not sim.room.debug_run, "guest cannot mutate debug state")
	check(not command(a, "ending_request").get("ok", false), "forged ending without qualification rejected")
	check(not command(a, "item", {"item": "pill", "epoch": "old"}).get("ok", false), "old room epoch rejected")
	check(not command(a, "item", {"item": "pill", "scene": 0}).get("ok", false), "stale scene command rejected")
	var input := {"epoch": sim.room.epoch, "seq": 100, "scene": a.scene_version, "x": 20, "y": 0, "yaw": 0, "pitch": 0, "run": true}
	sim.input(a.id, input)
	check(a.input_sequence < 100, "overspeed movement rejected")
	a.bag().add("key")
	sim.inventory.reconcile(a)
	var key: String = sim.inventory.owners[a.id]["key"]
	check(sim.inventory.drop(a, "key"), "key drops with unique ID")
	check(not sim.inventory.pickup(b, key, func(_p: CooperativeActor, _e: Dictionary) -> bool: return false), "occluded item cannot be picked up")
	for i in InventoryModule.GROUND_MAX - sim.inventory.ground.size():
		sim.inventory.serial += 1
		sim.inventory.ground.append({"uid": "item-%d" % sim.inventory.serial, "id": "coin", "world": "teach1", "x": 0.0, "y": 0.05, "z": 0.0})
	var held := b.bag().bag.duplicate()
	sim.inventory.recover(b)
	check(b.bag().bag.is_empty() and sim.inventory.stash.size() == held.size(), "departure preserves all items when ground is full")
	sim.inventory.ground.pop_back()
	sim.inventory.reconcile(a)
	check(sim.inventory.ground.size() == InventoryModule.GROUND_MAX and sim.inventory.stash.size() == held.size() - 1, "protected overflow returns when a slot opens")
	check(CooperativeValidation.validate(sim.capture()).is_empty(), "overflow ownership save validates")


func time_consent() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	a.school().san = 40.0
	var before := sim.calendar.tsec
	sim.gameplay.prepare(a)
	(sim.shared[&"campus.facilities"] as FacilitiesModule).rest("wash")
	check(a.school().san == 40.0 and sim.calendar.tsec == before, "rest proposal grants neither time nor healing")
	command(b, "time_confirm", {"accept": false})
	check(a.school().san == 40.0 and sim.calendar.tsec == before, "declined rest has no reward or cooldown")
	sim.gameplay.prepare(a)
	(sim.shared[&"campus.facilities"] as FacilitiesModule).rest("wash")
	command(b, "time_confirm", {"accept": true})
	check(a.school().san > 40 and sim.calendar.tsec == before + 4, "unanimous rest commits reward and time once")
	check(a.school().tsec == b.school().tsec, "jump advances all members together")
	a.bag().add("coin")
	var f := sim.shared[&"campus.facilities"] as FacilitiesModule
	f._pending = {"kind": "meal"}
	sim.gameplay._choice(a, "facilities", {"text": "吃饭", "labels": ["吃", "取消"]})
	var san := a.school().san
	command(a, "choice", {"index": 0})
	check(a.bag().has("coin") and a.school().san == san, "meal awaits consent before payment or healing")
	a.pose["position"][0] += 2
	command(b, "time_confirm", {"accept": true})
	check(a.bag().has("coin") and a.school().san == san and sim.gameplay._time_offer.is_empty(), "leaving the facility cancels pending meal transaction")


func persistence() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	place(a, "lab3", Vector2(500, 500))
	a.bag().add("phone")
	var phone := a.feature(&"phone.network") as PhoneModule
	phone.connection = {"x": 500.0, "y": 500.0}
	phone.terminal_open = true
	a.terminal = true
	sim.lease("terminal", a.id)
	sim.gameplay.termination_owner = a.id
	phone.termination = {"status": "accepted", "requestId": "%s:%d:shutdown" % [phone.run_seed, phone.attempt_id], "remaining": 532.0}
	sim.gameplay.prepare(b)
	(sim.shared[&"story.routes"] as RoutesModule).hacked = true
	(sim.shared[&"story.routes"] as RoutesModule).data_synced = true
	(sim.shared[&"story.routes"] as RoutesModule).face_open()
	sim.gameplay.drain(b, "routes")
	sim.patrol.report(a)
	for actor: CooperativeActor in sim.actors.values(): sim.inventory.reconcile(actor)
	var state: Dictionary = JSON.parse_string(JSON.stringify(sim.capture()))
	var why := CooperativeValidation.validate(state)
	check(why.is_empty(), "active terminal/quiz/report save validates: " + why)
	if not why.is_empty(): return
	var id := int(b.choice["id"])
	state["room"]["tick"] = 424
	var restored := CooperativeSimulation.new()
	root.add_child(restored)
	var reordered := CooperativeRoom.new()
	reordered.host_id = "a"
	reordered.phase = "playing"
	reordered.members = {"b": sim.room.members["b"].duplicate(true), "a": sim.room.members["a"].duplicate(true)}
	restored.setup(reordered, 99)
	restored.restore(state)
	check(restored.room.members["a"]["seat"] == a.own_seat and restored.room.members["b"]["seat"] == b.own_seat, "checkpoint seats belong to stable members regardless of dictionary order")
	check(restored.room.tick == 424, "saved participation keeps a continuous simulation timeline across new epochs")
	check(restored.actor("a").terminal and (restored.actor("a").feature(&"phone.network") as PhoneModule).connection != null, "terminal connection restores")
	check(restored.actor("b").choice["id"] == id and not (restored.shared[&"story.routes"] as RoutesModule)._pending.is_empty(), "pending quiz answer handler restores")
	check(restored.patrol.reports.size() == 1 and restored.gameplay.termination_owner == "a", "pending report and global countdown owner restore")
	restored.queue_free()
	var store := CooperativeStore.new()
	store.path = "user://lan-tests/slot.json"
	store.validator = CooperativeValidation.validate
	var credentials := {"a".sha256_text(): "a", "b".sha256_text(): "b"}
	check(store.write(state, credentials).is_empty(), "isolated cooperative slot writes")
	check(store.write(state, credentials).is_empty(), "second write retains backup")
	var broken := state.duplicate(true)
	broken["actors"]["a"]["runtime"]["phone.network"]["connection"] = {"x": "bad"}
	check(not CooperativeValidation.validate(broken).is_empty(), "corrupt pending phone connection rejected before restore")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	check(not store.read().has("error"), "truncated primary loads validated backup")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(store.path + suffix): DirAccess.remove_absolute(store.path + suffix)


func patrol_responsibility() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	sim.patrol.permanent[a.id] = "missed-inspection"
	sim.patrol.target = a.id
	sim.patrol.main.pat["locked"] = true
	sim.patrol.main.pat["lock"] = 0.8
	sim.patrol.synchronize(sim.actors)
	check(a.watcher().pat["permanent"] and not b.watcher().pat["permanent"], "absence responsibility is personal")
	check(a.watcher().pat["locked"] and not b.watcher().pat["locked"] and b.watcher().pat["lock"] == 0.0, "lock progression is not copied to unrelated member")
	place(b, "dorm1", Vector2(150, 150))
	b.school().tsec = 1350
	sim.gameplay.prepare(b)
	check(not b.watcher().eligible(), "ordinary night dorm entry is exempt")
	sim.patrol.report(b)
	var point: Dictionary = sim.patrol.reports.back()["signal"]["point"].duplicate()
	b.pose["position"][0] += 5
	check(sim.patrol.reports.back()["signal"]["point"] == point, "wireless report freezes observed coordinates")
	sim.patrol.lockers[a.id] = {"teach1:1:1": {"scene": "teach1", "c": 1, "r": 1, "ttl": 3.0}}
	sim.patrol.synchronize(sim.actors)
	check(b.watcher().pat["lockerMemory"].is_empty(), "another member's locker evidence is private to its target")


func mobility() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	place(a, "lab3", Vector2(500, 500))
	await physics_frame
	check(sim.physics.bodies[a.id].get_world_3d() != sim.physics.bodies[b.id].get_world_3d(), "overlapping room coordinates use independent collision spaces")
	a.input = {"x": 1.0, "y": 0.0, "yaw": 0.0, "pitch": 0.0, "run": true}
	a.input_age = 1.0
	sim.tick(1.0 / 60.0)
	check(a.input["x"] == 0.0 and not a.running, "lost movement packets cannot cause endless sprint")
	var body := a.feature(&"body.injury") as BodyModule
	body.fall = {"t": 0.1}
	a.input["x"] = 1
	var before := a.pose.duplicate(true)
	sim.physics.advance(a, 0.1)
	check(a.pose["position"] == before["position"], "vault animation blocks authoritative movement")
	body.fall = null
	sim.gameplay._choice(a, "day", {"text": "test", "labels": ["answer"]})
	var bbefore := b.school().active_seconds
	sim.tick(0.2)
	check(b.school().active_seconds > bbefore, "one personal modal never freezes teammate")


func whitelist() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	a.bag().add("usb")
	place(a, "lab3", Vector2(500, 500))
	sim.gameplay.apply_result(a, {"terminal": true})
	check((b.feature(&"story.routes") as RoutesModule).hacked, "host terminal writes shared whitelist")
	place(b, "admin3", Vector2(500, 500))
	sim.gameplay.apply_result(b, {"terminal": true})
	check((a.feature(&"story.routes") as RoutesModule).data_synced, "teammate can perform second shared route step")
	for p: CooperativeActor in [a, b]: place(p, "out", Vector2(401, 1250))
	sim.gameplay.apply_result(a, {"gate": "w"})
	var route := sim.shared[&"story.routes"] as RoutesModule
	for i in 3:
		var question: Dictionary = RoutesModule.QUESTIONS[route.face_quiz["order"][int(route.face_quiz["done"])]]
		check(command(a, "choice", {"index": int(question["answer"])}).get("ok", false), "shared gate answer %d" % i)
	command(a, "choice", {"index": 0})
	check(sim.room.phase == "playing" and not sim.room.ending_offer.is_empty(), "gate requires final teammate consent")
	place(b, "teach1", Vector2(500, 500))
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.phase == "playing" and sim.room.ending_offer.is_empty(), "departed teammate cannot accept old gate offer remotely")
	place(b, "out", Vector2(401, 1250))
	command(a, "ending_request")
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.ending == "face" and a.fate().ended == "face" and b.fate().ended == "face", "whitelist closes one shared ending for both")


func portal() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	var f := sim.shared[&"campus.facilities"] as FacilitiesModule
	f.portal["diary"] = true
	for row: Array in [["lab2", [1]], ["lab4", [2]], ["lab5", [1, 2, 0]]]:
		place(a, row[0], Vector2(500, 500))
		for answer: int in row[1]:
			sim.gameplay.apply_result(a, {"facility": ["K", 0, 0]})
			command(a, "choice", {"index": answer})
	check(f.portal["sketch"], "three floors' real blueprint questions produce shared sketch")
	for p: CooperativeActor in [a, b]: place(p, "lab1", Vector2(500, 500))
	for item: String in FacilitiesModule.PORTAL_PARTS:
		b.bag().add(item)
		sim.inventory.reconcile(b)
		check(command(b, "give", {"item": item, "to": "a"}).get("ok", false), "route material transfer " + item)
	sim.gameplay.prepare(a)
	sim.gameplay.apply_result(a, {"facility": ["K", 0, 0]})
	command(a, "choice", {"index": 0})
	check(f.portal["open"], "materials are atomically assembled")
	for item: String in FacilitiesModule.PORTAL_PARTS: check(not a.bag().has(item) and not b.bag().has(item), "material consumed once " + item)
	f.portal_ask()
	sim.gameplay.drain(a, "facilities")
	command(a, "choice", {"index": 0})
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.ending == "portal", "each gathered member consents to crossing portal")


func car() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	for p: CooperativeActor in [a, b]: place(p, "garage1", Vector2(500, 500))
	sim.gameplay._board_car(a)
	command(a, "board_confirm", {"accept": true})
	check(not a.vehicle and not b.vehicle, "driver cannot start before passenger accepts")
	command(b, "board_confirm", {"accept": true})
	var garage := sim.shared[&"garage.world"] as GarageModule
	check(a.vehicle and b.vehicle and garage.driving(), "both confirmed riders share one chase")
	for i in 2400:
		if garage.chase == null: break
		var d: Dictionary = garage.chase
		var target := 2.0 if d["distance"] < 65 else (-1.5 if d["distance"] < 95 else (2.0 if d["distance"] < 220 else -2.0))
		a.input["y"] = -1.0
		a.input["x"] = clampf((target - float(d["x"])) * 2, -1, 1)
		sim.gameplay._garage_tick(1.0 / 60.0)
	check(sim.gameplay.qualified.get("route") == "car", "real driving physics completes forks and escape distance")
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.ending == "car", "driver and passenger jointly finish car route")


func cyber() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	place(a, "lab3", Vector2(500, 500))
	a.bag().add("phone")
	sim.gameplay.prepare(a)
	var phone := a.feature(&"phone.network") as PhoneModule
	phone.acquire()
	phone.device["network"] = true
	phone.device["wireless"]["status"] = "complete"
	phone.device["download"] = {"status": "complete", "elapsed": 60.0, "target": 60.0}
	check(phone.open_terminal(500, 500), "prepared phone opens maintenance terminal")
	sim.gameplay.drain(a, "phone")
	var helper := preload("res://tests/support/test_suite.gd").new(self)
	for line: String in helper._solve_lines(phone.puzzle): command(a, "terminal", {"line": line})
	check(phone.termination["status"] == "accepted", "real terminal commands submit shutdown")
	a.fate().wakes = StoryModule.MAX_WAKES
	sim.gameplay.kill(a, "测试死亡", "vignette", "san")
	sim.gameplay.shared_tick(300)
	check(phone.termination["remaining"] == 300, "operator death does not freeze shared countdown")
	sim.gameplay.shared_tick(300)
	check(sim.room.ending == "cyber" and b.fate().ended == "cyber" and a.fate().dead, "surviving teammate finishes cyber while original death remains recorded")


func dismissal() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	var radio := sim.shared[&"story.broadcast"] as BroadcastModule
	var room := CampusData.rooms()["admin2"] as Dictionary
	var at := CampusGeometry.tile_center(room, BroadcastModule.STATION[0], BroadcastModule.STATION[1]) + Vector2(0, 9)
	place(a, "admin2", at)
	for id: String in ["notice1", "notice2", "notice3", "notice4"]: a.bag().add(id)
	for p: CooperativeActor in [a, b]:
		p.school().day = 2
		p.school().tsec = 1100
	radio.b["book"] = true
	radio.b["fuse"] = true
	sim.gameplay.prepare(a)
	sim.lease("broadcast", a.id)
	check(radio.use_here(), "shared broadcast station opens")
	sim.gameplay.drain(a, "broadcast")
	command(a, "choice", {"index": 3})
	for page in 4:
		command(a, "mic", {"paper": "notice%d" % (page + 1), "held": true})
		for step in 32: sim.gameplay._broadcast_tick(0.5)
	check(radio.b["phase"] == "bell", "one operator reads four real pages and starts shared bell")
	for i in 65:
		var crowd := radio.crowd()
		if not crowd.is_empty():
			for p: CooperativeActor in [a, b]: place(p, "out", Vector2(float(crowd["x"]), float(crowd["y"])))
		sim.gameplay._broadcast_tick(1)
		if not sim.room.ending_offer.is_empty(): break
	check(not sim.room.ending_offer.is_empty(), "following crowd qualifies both members individually")
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.ending == "dismissal", "shared broadcast route concludes")


func international() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	var visit := sim.shared[&"story.exchange"] as ExchangeModule
	visit.s["hit"] = 1
	for p: CooperativeActor in [a, b]:
		p.school().day = 2
		p.school().tsec = 600
		sim.travel(p, "out", sim.spawn("out"))
	sim.gameplay._exchange_tick(0.1)
	var lead: Vector2 = visit.members()[0]
	place(a, "out", lead)
	for lang: String in ["de", "fr"]:
		sim.gameplay.prepare(a)
		visit.use_here()
		sim.gameplay.drain(a, "exchange")
		var labels: Array = a.choice.get("labels", [])
		var pick := -1
		for i in labels.size():
			if String(labels[i]).contains(ExchangeModule.EXAM[lang]["n"]): pick = i
		command(a, "choice", {"index": pick})
		for i in ExchangeModule.QUESTIONS: command(a, "choice", {"index": int(visit._order(lang)[i])})
	check(visit.s["phase"] == "qualified", "both language examinations pass through cooperative commands")
	sim.gameplay.prepare(a)
	visit.use_here()
	sim.gameplay.drain(a, "exchange")
	for i in 2000:
		var tail: Vector2 = visit.members().back()
		for p: CooperativeActor in [a, b]: place(p, "out", tail + Vector2(4, 0))
		sim.gameplay._exchange_tick(0.25)
		if not sim.room.ending_offer.is_empty(): break
	check(not sim.room.ending_offer.is_empty(), "both members reach escort destination")
	command(b, "ending_confirm", {"accept": true})
	check(sim.room.ending == "international", "shared escort route concludes")


func transport_ordering() -> void:
	var net := LanSession.new()
	root.add_child(net)
	net.room = sim.room
	net.simulation = sim
	net.connections = {2: "b"}
	net._clock = 8.0
	var fragments := LanChunks.split(sim.state_for("b"), "pending-5")
	net._awaiting[2] = {"at": 0.0, "started": 0.0, "snapshot": 5, "chunks": fragments}
	net._send_state(2, "b")
	check(net._awaiting[2]["snapshot"] == 5 and net._awaiting[2]["chunks"] == fragments, "slow loading retries original baseline rather than abandoning acknowledgement ID")
	net.transport.serving = true
	net._control(2, {"kind": "state_ack", "snapshot": 4})
	check(net._awaiting.has(2), "older acknowledgement cannot release newer snapshot")
	net._control(2, {"kind": "state_ack", "snapshot": 5})
	check(net._awaiting.is_empty(), "matching delayed acknowledgement releases pending baseline")
	net.room.revision = 4
	var older := net.room.public_state()
	older["revision"] = 3
	older["phase"] = "loading"
	net._receive_room(older)
	check(net.room.phase == "playing", "cross-channel stale lobby cannot regress playing state")
	net.transport.serving = false
	net._clock = Time.get_ticks_msec() / 1000.0 - 80.0
	net._control(1, {"kind": "notice", "text": "loading complete"})
	check(Time.get_ticks_msec() / 1000.0 - net._last_heard < 0.1, "receipt uses current wall time even when scene loading blocked the prior frame")
	net._last_heard = net._clock
	net.transport.motion_received.emit({"epoch": net.room.epoch})
	check(Time.get_ticks_msec() / 1000.0 - net._last_heard < 0.1, "motion heartbeat cannot inherit a stale frame timestamp")
	net.simulation = null
	net.room = null
	net.queue_free()


func lobby_reconnect() -> void:
	var net := LanSession.new()
	root.add_child(net)
	net.transport.serving = true
	net.room = CooperativeRoom.new()
	net.room.add_member("a", "host", true)
	net.room.add_member("b", "guest")
	net.connections = {2: "b"}
	var token := "lobby-reconnect-fixture"
	net.credentials[token.sha256_text()] = "b"
	net._peer_left(2)
	check(not net.room.members.has("b") and not net.credentials.has(token.sha256_text()), "leaving fresh lobby releases obsolete identity and credential together")
	var hello := {"protocol": LanProtocol.VERSION, "rules": LanProtocol.RULES, "content": net._fingerprint, "name": "guest", "token": token}
	net._accept(3, hello)
	check(net.connections.has(3) and net.room.members.size() == 2, "invitation rejoin with an obsolete lobby token can create a new seat")
	net.room = CooperativeRoom.new()
	net.room.add_member("a", "host", true)
	net.room.add_member("b", "saved guest")
	net.connections = {4: "b"}
	net.credentials = {token.sha256_text(): "b"}
	net._resume = {"restored": true}
	net._peer_left(4)
	check(net.room.members.has("b") and not net.room.members["b"]["connected"], "restored lobby preserves a disconnected saved student")
	net._accept(5, hello)
	check(net.connections.get(5) == "b" and net.room.members["b"]["connected"], "restored lobby accepts the same credential after another disconnect")
	net.queue_free()


func anomaly_continuity() -> void:
	var a := sim.actor("a")
	var b := sim.actor("b")
	var first := a.feature(&"anomaly.world") as AnomalyModule
	var second := b.feature(&"anomaly.world") as AnomalyModule
	first.an.merge({"id": "rain", "active": true, "t": 10.0, "acc": 4.0, "data": {"scene": "out"}}, true)
	second.cola_pending = {"seq": 3, "day": 2}
	second.clues["private"] = true
	sim.gameplay._copy_anomaly_schedule(first, second)
	second.an["acc"] = 2.0
	check(second.cola_pending == {"seq": 3, "day": 2} and second.clues.has("private"), "shared weather cannot transfer personal debts or clues")
	sim.gameplay.anomaly_owner = a.id
	sim.gameplay.anomaly_participants = [a.id, b.id]
	a.fate().wakes = StoryModule.MAX_WAKES
	sim.gameplay.kill(a, "test", "vignette", "san")
	sim.gameplay._anomaly_tick(0.1)
	check(sim.gameplay.anomaly_owner == b.id and second.active_id() == "rain" and is_equal_approx(float(second.an["t"]), 10.1), "weather continues without restarting when its scheduler owner dies")
	check(float(second.an["acc"]) < 2.0, "successor keeps personal exposure instead of inheriting dead teammate damage")
	sim.gameplay._anomaly_tick(17.0)
	check(not second.is_active(), "shared weather expires normally after owner loss")
	check(CooperativeValidation.validate(sim.capture()).is_empty(), "weather succession survives cooperative save validation")
