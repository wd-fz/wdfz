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
	sim.queue_free()
	await process_frame
	print("LAN UNIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
