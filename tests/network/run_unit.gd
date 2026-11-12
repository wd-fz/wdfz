extends SceneTree
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)


func run() -> void:
	var room := CooperativeRoom.new()
	check(room.add_member("a", "同学", true).is_empty(), "create host")
	check(room.add_member("b", "同学").is_empty(), "duplicate nicknames have separate identities")
	check(not room.can_start(), "loading requires all ready")
	room.ready("a", true, "none")
	room.ready("b", true, "none")
	check(room.begin("test-epoch"), "ready room begins")
	room.loaded("a")
	check(room.phase == "loading", "host cannot run ahead of guest")
	room.loaded("b")
	check(room.phase == "playing", "all loaded releases barrier")
	var calendar := SchoolCalendar.new()
	var single := SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	single.reset()
	for i in 2000:
		calendar.advance(0.7)
		single.clock_tick(0.7)
	check(absf(single.tsec - calendar.tsec) < 0.0001 and single.day == calendar.day, "shared calendar matches full day and rollover")
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 421)
	await physics_frame
	await physics_frame
	var a := sim.actor("a")
	var b := sim.actor("b")
	check(a.own_seat != b.own_seat, "distinct seats")
	check(a.school().at_my_seat(a.location(), a.point(CampusData.rooms())), "host assigned seat is recognized")
	check(b.school().at_my_seat(b.location(), b.point(CampusData.rooms())), "guest assigned seat is recognized")
	a.school().san = 20.0
	check(b.school().san == 100.0, "personal SAN never aliases")
	a.bag().add("key")
	sim.inventory.reconcile(a)
	check(not b.bag().has("key"), "personal inventory")
	check(sim.inventory.drop(a, "key"), "drop unique instance")
	var uid: String = sim.inventory.ground[0]["uid"]
	b.pose = a.pose.duplicate(true)
	check(sim.inventory.pickup(b, uid, func(_actor: CooperativeActor, _entry: Dictionary) -> bool: return true), "guest picks shared item")
	check(not sim.inventory.pickup(a, uid, func(_actor: CooperativeActor, _entry: Dictionary) -> bool: return true), "second pickup rejected")
	check(b.bag().has("key") and not a.bag().has("key"), "unique possession")
	var baseline := sim.capture()
	check(CooperativeValidation.validate(baseline).is_empty(), "complete cooperative save validates: " + CooperativeValidation.validate(baseline))
	var chunks := LanChunks.split(baseline, "test")
	var assembler := LanChunks.new()
	var assembled := {}
	chunks.reverse()
	for chunk: Dictionary in chunks: assembled = assembler.accept(chunk, 0.0)
	check(not assembled.is_empty(), "fragmented baseline reassembles out of order")
	check(not LanProtocol.safe({"bad": INF}), "nonfinite wire data rejected")
	check(not LanProtocol.input_valid({"seq": 1, "scene": 1, "x": 9, "y": 0, "yaw": 0, "pitch": 0, "run": true}), "unbounded movement rejected")
	for i in 5:
		sim.tick(1.0 / 60.0)
		await physics_frame
	check(is_equal_approx(a.school().tsec, b.school().tsec), "two players share one calendar")
	check(room.pause("a", true), "host team pause")
	var before := sim.calendar.tsec
	sim.tick(1.0)
	check(sim.calendar.tsec == before, "paused room freezes simulation")
	check(room.pause("b", false), "guest can resume")
	room.disconnect_member("b")
	check(room.reconnect("b"), "original member reconnects")
	check(not room.reconnect("b"), "duplicate live member rejected")
	room.record_participation(2.0)
	var seconds: float = room.members["b"]["participation"]["seconds"]
	room.disconnect_member("b")
	room.record_participation(4.0)
	check(room.members["b"]["participation"]["seconds"] == seconds, "offline reservation cannot add participation credit")
	room.reconnect("b")
	room.death("b")
	room.record_participation(3.0)
	var record: Dictionary = room.members["b"]["participation"]
	check(is_equal_approx(record["seconds"] - record["alive_seconds"], 3.0), "spectator time is distinguished from living participation")
	check(CooperativeValidation.validate(sim.capture()).is_empty(), "participation persists in validated cooperative checkpoints")
	sim.queue_free()
	await process_frame
	var figures := RemoteStudents.new()
	root.add_child(figures)
	figures.set_process(false)
	var steps := {"count": 0}
	figures.stepped.connect(func(_at: Vector3, _running: bool) -> void: steps["count"] += 1)
	var remote := {"world": "teach1", "scene": 1, "dead": false, "hiding": false, "seated": false, "running": false, "moving": true, "pose": {"position": [1.0, 0.0, 2.0], "yaw": 0.0}}
	figures.receive({"players": {"b": remote}}, "a", "teach1", {"b": {"name": "队友"}})
	figures._process(0.1)
	check(figures.peers.size() == 1 and steps["count"] == 1, "same-room teammate gets a model and movement sound")
	figures._process(0.6)
	check(steps["count"] == 1, "stale motion cannot generate endless teammate footsteps")
	remote["world"] = "lab3"
	figures.receive({"players": {"b": remote}}, "a", "teach1", {})
	check(figures.peers.is_empty(), "different floors cannot leak remote avatars or sounds")
	remote["world"] = "teach1"
	remote["hiding"] = true
	figures.receive({"players": {"b": remote}}, "a", "teach1", {})
	check(figures.peers.is_empty(), "hidden teammate has no visible remote avatar")
	figures.queue_free()
	await process_frame
	print("LAN UNIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
