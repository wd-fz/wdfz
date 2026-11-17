extends SceneTree
## Regression scenarios use public commands; controlled positioning replaces travel time only.
var checks := 0
var failures := 0
var sim: CooperativeSimulation

func _initialize() -> void: call_deferred("run")
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
	for id: String in ["a", "b", "c"]:
		room.add_member(id, id, id == "a")
		room.ready(id, true, "none")
	room.begin("consistency")
	for id: String in room.members: room.loaded(id)
	sim = CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 421)
	await physics_frame
	await physics_frame

func command(a: CooperativeActor, action: String, fields: Dictionary = {}) -> Dictionary:
	if action in ["cancel", "terminal", "mic"] and not fields.has("operation_id"): fields["operation_id"] = sim.gameplay.operation_id(a)
	if action in ["choice", "cancel"] and not fields.has("choice_id"): fields["choice_id"] = a.choice.get("id", -1)
	if action in ["board_confirm", "time_confirm", "ending_confirm"] and not fields.has("offer_id"):
		var offer: Dictionary = sim.gameplay.boarding if action == "board_confirm" else sim.gameplay._time_offer if action == "time_confirm" else sim.room.ending_offer
		fields["offer_id"] = offer.get("id", "")
	var request := {"epoch": sim.room.epoch, "scene": a.scene_version, "seq": a.command_sequence + 1, "action": action}
	request.merge(fields, true)
	return sim.command(a.id, request)

func aim(a: CooperativeActor, world: String, c: int, r: int) -> bool:
	var map: Dictionary = CampusData.rooms()[world]
	var target := CampusGeometry.tile_center(map, c, r)
	for i in 16:
		var angle := float(i) * TAU / 16
		var at := target - Vector2.from_angle(angle) * float(map["tw"]) * 1.5
		var hit := CampusGeometry.near_tile(map, at, angle, CampusGeometry.NEAR_ROOM, sim.campus()._open_doors)
		if hit.get("c") != c or hit.get("r") != r: continue
		var p := CampusGeometry.to_scene(map, at)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.34
		shape.height = 1.75
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 3
		query.transform.origin = sim.physics.space.frame(world) * Vector3(p.x, 0.95, p.y)
		if not sim.physics.zone(world).find_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		sim.travel(a, world, {"position": [p.x, 0.05, p.y], "yaw": CampusGeometry.yaw_from_ang(angle), "pitch": 0.0})
		return true
	return false

func run() -> void:
	await fresh()
	var a := sim.actor("a")
	var b := sim.actor("b")
	command(a, "think")
	check(sim.leases.is_empty(), "C02 instant escape hint releases the facility seat")
	command(b, "think")
	check(not b.events.is_empty(), "C02 a second player can read an independent hint")
	await fresh()
	a = sim.actor("a")
	var garage: GarageModule = sim.shared[&"garage.world"]
	var key := garage.car_right_cell().split(":")
	check(aim(a, "garage1", int(key[0]), int(key[1])), "C01 real car tile can be targeted")
	for id: String in ["b", "c"]: sim.travel(sim.actor(id), a.location(), a.pose)
	a.bag().add("key")
	garage.roam.merge({"on": true, "stage": "wait", "waitT": 20.0, "x": -1e6, "y": -1e6}, true)
	check(command(a, "interact").get("ok", false) and a.choice.get("source") == "garage", "C01 interaction opens the car door menu")
	command(a, "choice", {"index": 0, "choice_id": a.choice.get("id", -1)})
	for i in 110:
		sim.tick(1.0 / 60.0)
		await physics_frame
	if sim.gameplay.boarding.is_empty(): print("CAR TRACE: ", a.pose, " / ", garage.job, " / ", a.events.slice(-6))
	check(not sim.gameplay.boarding.is_empty() and not garage.driving(), "C01 key job offers boarding before the chase starts")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	command(a, "lesson")
	var old_id: Variant = a.choice.get("id", -1)
	command(a, "cancel")
	command(a, "lesson")
	var next_id: Variant = a.choice.get("id", -1)
	var stale := command(a, "choice", {"index": 0, "choice_id": old_id})
	check(not stale.get("ok", true) and a.choice.get("id") == next_id, "C05 delayed answer cannot answer a new question")
	command(a, "cancel")
	var body := a.feature(&"body.injury") as BodyModule
	body.injury = 60
	a.bag().add("medkit")
	command(a, "item", {"item": "medkit"})
	command(a, "drop", {"item": "medkit"})
	for i in 250: sim.tick(1.0 / 60.0)
	check(body.injury >= 59 and body.treat == null, "C07 removing the treating medkit cancels healing")
	await fresh()
	a = sim.actor("a")
	check(aim(a, "teach2", 48, 11), "C12 another classroom can be reached")
	check(not CooperativeContext.base(a).classroom, "C12 another classroom is not the personal charging classroom")
	await extensions()
	sim.queue_free()
	await process_frame
	print("LAN CONSISTENCY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func point(a: CooperativeActor, world: String, at: Vector2) -> void:
	var p := CampusGeometry.to_scene(CampusData.rooms().get(world), at)
	sim.travel(a, world, {"position": [p.x, .05, p.y], "yaw": 0.0, "pitch": 0.0})

func tile(a: CooperativeActor, world: String, symbol: String) -> bool:
	var map: Dictionary = CampusData.rooms()[world]
	for r in map["grid"].size():
		for c in String(map["grid"][r]).length():
			if String(map["grid"][r]).substr(c, 1) == symbol and aim(a, world, c, r): return true
	return false

func saved(label: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(JSON.stringify(sim.capture()))
	var why := CooperativeValidation.validate(data)
	check(why.is_empty(), label + " save validates: " + why)
	return data

func extensions() -> void:
	await fresh()
	var a := sim.actor("a")
	var b := sim.actor("b")
	b.pose = a.pose.duplicate(true)
	a.bag().add("phone")
	sim.inventory.reconcile(a)
	var uid: String = sim.inventory.owners[a.id]["phone"]
	var phone := a.feature(&"phone.network") as PhoneModule
	sim.gameplay.prepare(a)
	phone.acquire()
	phone.device["battery"] = 37.0
	phone.device["wireless"].merge({"status": "complete", "target": 240.0, "elapsed": 240.0}, true)
	phone.device["network"] = true
	check(command(a, "give", {"item": "phone", "to": "b"}).get("ok", false), "C08 phone handed over through normal item command")
	var received := b.feature(&"phone.network") as PhoneModule
	check(received.device["battery"] == 37 and received.device["network"] and b.phone_uid == uid, "C08 device progress and identity travel together")
	check(command(b, "drop", {"item": "phone"}).get("ok", false), "C08 device can be dropped")
	await physics_frame
	check(command(a, "pickup", {"uid": uid}).get("ok", false), "C08 dropped phone picked up by same UID")
	check(phone.device["battery"] == 37 and phone.device["network"], "C08 pickup preserves network and charge")
	var data := saved("C08 phone transfer")
	var before := phone.device.duplicate(true)
	sim.restore(data)
	check(phone.device == before and a.phone_uid == uid, "C08 restore keeps the device, not previous owner's device")
	var invalid := data.duplicate(true)
	invalid["items"]["phones"][uid]["battery"] = -1
	check(not CooperativeValidation.validate(invalid).is_empty(), "C08 corrupted phone cache rejected")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	point(a, "lab1", Vector2(460, 500))
	point(b, "lab1", Vector2(510, 530))
	var origin_a := a.pose.duplicate(true)
	var origin_b := b.pose.duplicate(true)
	sim.travel(a, "portal_tunnel", sim.spawn("portal_tunnel"))
	sim.travel(b, "portal_tunnel", sim.spawn("portal_tunnel"))
	data = saved("C09 independent tunnel returns")
	sim.restore(data)
	sim.travel(b, "lab1", sim.spawn("lab1"))
	sim.travel(a, "lab1", sim.spawn("lab1"))
	check(same_pose(a.pose, origin_a) and same_pose(b.pose, origin_b), "C09 reverse-order exit uses each member's original position")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	var podium: Array = CampusData.campus()["own_podium"]
	check(aim(a, "teach1", int(podium[0]), int(podium[1])), "C10 actual transfer-note podium reachable")
	command(a, "interact")
	command(a, "choice", {"index": -1})
	var note := a.feature(&"story.investigation") as InvestigationModule
	if not note.visible("notice"): print("PODIUM TRACE: ", a.pose, " / ", sim.campus().interact_at(a.location(), a.pose), " / ", a.events.slice(-4))
	check(note.visible("notice"), "C10 podium records supply location")
	var supply_world := String(note.supply_site()["site"])
	check(tile(a, supply_world, "k" if supply_world == "guard1" else "M"), "C10 actual supply facility reachable")
	command(a, "interact")
	check(a.choice.get("pending", {}).get("kind") == "supply", "C10 normal facility offers supply")
	command(a, "choice", {"index": -1})
	check(not note.supply["taken"], "C10 cancelled supply remains available")
	a.bag().add("coin")
	command(a, "interact")
	command(a, "choice", {"index": 1})
	check(a.bag().has("pill") and not a.bag().has("coin") and note.supply["taken"], "C10 payment and supply award happen once")
	command(b, "think")
	check(not b.events.is_empty(), "C02 supply does not lock unrelated investigations")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	check(aim(a, "teach1", 49, 11), "C11 teammate seat can be aimed at")
	sim.gameplay.prepare(a)
	check(sim.campus().hint(a.location(), a.pose) == "座位有人", "C11 occupied teammate seat hint matches authority")
	command(a, "interact")
	check(not a.bag().searching() and not a.school().seated, "C11 cannot search an occupied player desk")
	command(b, "interact")
	command(a, "interact")
	check(a.school().seated and a.school().seat_id == b.own_seat, "C11 empty player seat uses sitting rather than searching")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	# A completed classroom question is a controlled precondition; waiting still goes through R and team consent.
	var day := a.feature(&"school.days") as DayModule
	var key := DayModule.lesson_key_of(a.school().day, a.school().tsec)
	day.lessons[key] = {"task": 0, "left": 0.0, "done": true}
	var note2 := a.feature(&"story.investigation") as InvestigationModule
	note2.record("desk", "fixture completed parking note")
	command(a, "lesson")
	if a.choice.get("source") == "investigation":
		command(a, "choice", {"index": -1})
		command(a, "lesson")
	check(a.choice.get("menu") == "wait", "C15 completed lesson opens real study choice")
	command(a, "choice", {"index": 0})
	for id: String in ["b", "c"]: command(sim.actor(id), "time_confirm", {"accept": true})
	var seconds := sim.calendar.seconds
	var active := b.session.clock.active_seconds
	sim.tick(.1)
	check(is_equal_approx(sim.calendar.seconds - seconds, .6) and is_equal_approx(b.session.clock.active_seconds - active, .6), "C15 six full simulation steps advance every member")
	command(a, "lesson")
	check(not sim.gameplay.studying(), "C15 pressing lesson again cancels acceleration")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	a.fate().wakes = StoryModule.MAX_WAKES
	sim.gameplay.kill(a, "fixture", "vignette", "san")
	sim.room.phase = "loading"
	sim.room.members[a.id]["state"] = "loading"
	sim.room.members[b.id]["state"] = "loading"
	sim.room.members["c"]["state"] = "loading"
	sim.room.loaded(a.id)
	sim.room.loaded(b.id)
	sim.room.remove("c")
	sim.room.check_loaded()
	sim.normalize_members()
	check(sim.room.phase == "playing" and sim.room.members[a.id]["state"] == "dead" and a.id not in sim.room.alive_ids(), "C06 removal releases loading barrier without resurrecting dead actor")
	sim.departed("c")
	var revision := sim.inventory.revision
	sim.departed("c")
	check(sim.active_actors().size() == 2 and sim.inventory.revision == revision and not sim.physics.bodies.has("c"), "C03 departure is idempotent and removes physical participant")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	a.bag().add("phone")
	sim.inventory.reconcile(a)
	sim.gameplay.prepare(a)
	(a.feature(&"phone.network") as PhoneModule).acquire()
	check(command(a, "game_start", {"game": "plane"}).get("ok", false), "C21 phone starts a signed individual game session")
	var game_id := a.activities.id
	check(not command(a, "game_input", {"game_id": "old", "operation": "flap", "score": 900}).get("ok", true), "C21 forged session and score cannot award rewards")
	check(command(a, "game_input", {"game_id": game_id, "operation": "flap"}).get("ok", false), "C21 authoritative flap accepted")
	active = b.session.clock.active_seconds
	for i in 30: sim.tick(1.0 / 60.0)
	check(b.session.clock.active_seconds > active and b.activities.game.is_empty(), "C21 friend's world continues during a personal game")
	data = saved("C21 active minigame")
	sim.restore(data)
	check(a.activities.id == game_id and a.activities.plane.st == data["actors"]["a"]["activities"]["plane"]["st"], "C21 minigame and cooldown restore together")
	command(a, "game_close", {"game_id": game_id})
	check(not command(a, "game_close", {"game_id": game_id}).get("ok", true), "C21 close/reward cannot be replayed")
	check(command(a, "camera_flash").get("ok", false) and not command(a, "camera_flash").get("ok", true), "C23 flash has authority cooldown")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	var maze_a := a.feature(&"campus.maze") as MazeModule
	var maze_b := b.feature(&"campus.maze") as MazeModule
	sim.travel(a, MazeModule.ROOM, maze_a.enter())
	sim.travel(b, MazeModule.ROOM, maze_b.enter())
	check(sim.physics.bodies[a.id].get_world_3d() != sim.physics.bodies[b.id].get_world_3d(), "C25 each member gets an isolated special-space physics world")
	check(not sim.motion(a.id)["players"].has(b.id) and not sim.physics.can_exchange(a, b), "C25 special-space instances cannot see or trade through each other")
	data = saved("C25 personal spaces")
	sim.restore(data)
	check(a.location() == MazeModule.ROOM and maze_a.active, "C25 special-space location and progress restore")
	await fresh()
	a = sim.actor("a")
	b = sim.actor("b")
	var knife := a.feature(&"story.knife") as KnifeModule
	point(a, KnifeModule.ROOM, CampusGeometry.tile_center(CampusData.rooms()[KnifeModule.ROOM], KnifeModule.CELL.x, KnifeModule.CELL.y) + Vector2(0, 9))
	command(a, "interact")
	check(a.bag().has("small_knife"), "C24 knife has a real drawer entry")
	sim.gameplay.kill(a, "caught", "grip", "patrol")
	check(knife.captured() and not a.fate().dead, "C24 actual patrol capture enters one-second window")
	command(a, "item", {"item": "small_knife"})
	command(a, "item", {"item": "small_knife"})
	check(a.hidden_history.get("knife", false) and a.location() == "teach1" and sim.room.phase == "playing" and b.fate().ended.is_empty(), "C24 fake ending wakes only its owner without ending team run")
	await fresh()
	a = sim.actor("a")
	var rules := a.feature(&"dlc.campus_rules") as RulesDlcModule
	rules.start(true, "fixture")
	var spot: Dictionary = rules.spots()[0]
	point(a, spot["p"]["room"], Vector2(spot["p"]["x"], spot["p"]["y"]))
	command(a, "interact")
	check(a.choice.get("source") == "rules" or not rules.state["read"].is_empty(), "C26 actual DLC prop is read through authority command")
	if not a.choice.is_empty(): command(a, "choice", {"index": 1})
	saved("C26 DLC personal rule progress")


func same_pose(a: Dictionary, b: Dictionary) -> bool:
	for i in 3:
		if not is_equal_approx(float(a["position"][i]), float(b["position"][i])): return false
	return is_equal_approx(float(a["yaw"]), float(b["yaw"])) and is_equal_approx(float(a["pitch"]), float(b["pitch"]))
