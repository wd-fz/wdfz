extends SceneTree
## Behavioural fixtures for room recovery, physical item handoff and device-local history.
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)


func frames(count: int = 2) -> void:
	for i in count: await physics_frame


func room_fixture() -> CooperativeRoom:
	var room := CooperativeRoom.new()
	for id: String in ["a", "b", "c"]:
		room.add_member(id, "  " if id == "a" else "队友" + id, id == "a")
		room.ready(id, true, "none")
	room.begin("experience")
	room.loaded("a")
	room.loaded("b")
	return room


func run() -> void:
	var room := room_fixture()
	check(room.members.a.name == "同学", "blank nickname has a readable fallback")
	check(LanRoomView.summary(room.public_state()).contains("2/3"), "loading names and count describe the actual barrier")
	room.disconnect_member("c")
	room.elapsed(59)
	check(room.phase == "loading", "loading retains the disconnected member's reconnect window")
	check(LanRoomView.member_text("c", room.members.c, room.public_state(), "a").contains("1 秒"), "offline reservation countdown is visible")
	check(room.elapsed(1) == ["c"] and room.phase == "playing", "reservation expiry releases remaining ready players")
	check(LanRoomView.active_members(room.public_state()).size() == 2, "departed seats are not counted as connected teammates")
	var too_few := room_fixture()
	too_few.disconnect_member("b")
	too_few.disconnect_member("c")
	too_few.elapsed(60)
	check(too_few.phase == "loading" and LanRoomView.summary(too_few.public_state()).contains("人数不足"), "a lone fresh host gets an actionable message instead of a false all-ready promise")
	room.pause("a", true)
	check(LanRoomView.summary(room.public_state()).contains("120 秒"), "team pause reports automatic resume")
	history_checks()
	await handoff_checks(room)
	await avatar_checks()
	await discovery_refresh()
	var net := LanSession.new()
	root.add_child(net)
	net.set_process(false)
	net._clock = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	net._control(1, {"kind": "pong", "time": now - 0.1})
	check(net.rtt_ms >= 99 and net.rtt_ms < 500 and net.jitter_ms == 0, "first pong uses current wall time and does not invent jitter")
	net.stop()
	check(net.rtt_ms == 0 and net.jitter_ms == 0, "a new connection cannot inherit old latency")
	net.queue_free()
	await frames()
	print("LAN EXPERIENCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func history_checks() -> void:
	var path := "user://experience-%s/connection.json" % Time.get_ticks_usec()
	var recent := CooperativeConnectionHistory.new(path)
	var lan := {"name": "甲", "token": "fixture-lan", "address": "192.168.1.2:24560"}
	var remote := {"name": "乙", "token": "fixture-remote", "code": "U/fixture"}
	check(recent.remember("lan", lan).is_empty() and FileAccess.file_exists(path), "recent LAN room is saved atomically")
	for i in 40: recent.remember("lan", lan)
	check(not FileAccess.file_exists(path + ".bak"), "unchanged baselines never rewrite or rotate credentials")
	check(recent.remember("remote", remote).is_empty(), "remote mode has its own recent identity")
	var reloaded := CooperativeConnectionHistory.new(path)
	reloaded.load_file()
	check(reloaded.get_entry("lan").token == "fixture-lan" and reloaded.get_entry("remote").token == "fixture-remote", "switching modes preserves both original characters")
	var copy := reloaded.get_entry("lan")
	copy.token = "modified"
	check(reloaded.get_entry("lan").token == "fixture-lan", "UI copies cannot mutate stored credentials")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("incomplete")
	file.close()
	reloaded.load_file()
	check(reloaded.get_entry("lan").token == "fixture-lan", "an interrupted write recovers the last valid backup")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(lan))
	file.close()
	reloaded.load_file()
	check(reloaded.get_entry("lan").mode == "lan", "existing single-entry reconnect files remain readable")
	check(not recent.valid("lan", {"name": "甲", "token": "x", "address": "garbage"}), "invalid address cannot displace the working recent room")
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(path.get_base_dir())


func pose(p: Vector3) -> Dictionary:
	return {"position": [p.x, p.y, p.z], "yaw": 0.0, "pitch": 0.0}


func handoff_checks(room: CooperativeRoom) -> void:
	room.paused_left = 0
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room, 421)
	var a := sim.actor("a")
	var b := sim.actor("b")
	var map := CampusData.layout("teach1")
	var port := CampusGeometry.door_port(map, CampusData.campus().campus_doors.doors[0])
	var at := CampusGeometry.to_scene(map, port.p)
	var inside := pose(Vector3(at.x - port.n.x * 0.5, 0.05, at.y - port.n.y * 0.5))
	var outside := pose(Vector3(at.x + port.n.x * 0.5, 0.05, at.y + port.n.y * 0.5))
	sim.travel(a, "teach1", inside)
	sim.travel(b, "out", sim.physics.space.global_pose("teach1", outside))
	await frames()
	check(is_equal_approx(sim.physics.actor_distance(a, b), 1.0), "handoff distance uses one school coordinate system at an entrance")
	check(sim.physics.can_exchange(a, b), "nearby teammates can exchange across an ordinary region boundary")
	a.bag().add("key")
	sim.inventory.reconcile(a)
	var uid: String = sim.inventory.owners.a.key
	var command := {"epoch": room.epoch, "scene": a.scene_version, "seq": 10, "action": "give", "to": "b", "item": "key"}
	check(sim.command("a", command).get("ok", false), "authoritative command permits the boundary handoff")
	check(b.bag().has("key") and not a.bag().has("key") and sim.inventory.owners.b.key == uid, "handoff preserves a single unique item")
	var before := b.events.size()
	check(sim.command("a", command).get("ok", false) and b.events.size() == before, "retry acknowledges without duplicating the item or feedback")
	check(a.events.any(func(e: Dictionary) -> bool: return e.get("text", "").contains("交给")) and b.events.any(func(e: Dictionary) -> bool: return e.get("text", "").contains("交给你")), "both players receive named handoff feedback")
	var team: Dictionary = sim.state_for("a").team
	check(team.b.can_give and is_equal_approx(float(team.b.distance), 1.0) and not team.b.place.is_empty(), "team menu gets reliable place, distance and handoff availability")
	check(not sim.motion("a").has("team") and LanProtocol.encode(sim.motion("a")).size() < 1200, "team descriptions never enlarge the motion datagram")
	room.disconnect_member("b")
	check(not sim.state_for("a").team.b.can_give, "offline characters cannot receive gifts")
	room.reconnect("b")
	var door := CampusGeometry.to_scene(map, CampusGeometry.tile_center(map, 10, 15))
	sim.travel(a, "teach1", pose(Vector3(door.x, 0.05, door.y - 0.7)))
	sim.travel(b, "teach1", pose(Vector3(door.x, 0.05, door.y + 0.7)))
	await frames()
	check(not sim.physics.can_exchange(a, b), "a closed classroom door blocks nearby handoff")
	sim.campus().restore({"open_doors": ["teach1:10:15"]})
	sim.physics.sync_doors(sim.campus(), sim.gameplay.lifts)
	await frames()
	check(sim.physics.can_exchange(a, b), "opening the same door enables handoff")
	b.pose.position[1] += 3.2
	check(not sim.physics.can_exchange(a, b), "vertically separated floors cannot exchange")
	b.pose.position[1] -= 3.2
	sim.campus().restore({"open_doors": []})
	sim.physics.sync_doors(sim.campus(), sim.gameplay.lifts)
	sim.physics.sync_doors(sim.campus(), sim.gameplay.lifts)
	await frames()
	check(not sim.physics.can_exchange(a, b), "removing an open door from the state restores its collision")
	sim.campus().restore({"open_doors": ["teach1:10:15"]})
	sim.physics.sync_doors(sim.campus(), sim.gameplay.lifts)
	sim.physics.sync_doors(sim.campus(), sim.gameplay.lifts)
	await frames()
	check(sim.physics.can_exchange(a, b), "repeated unchanged door states leave the reopened doorway clear")
	sim.travel(b, "portal_tunnel", inside)
	check(not sim.physics.can_exchange(a, b) and sim.state_for("a").team.b.distance == -1, "special spaces stay isolated even with overlapping local coordinates")
	var saved := sim.capture()
	check(CooperativeValidation.validate(saved).is_empty(), "new room metadata remains save-valid")
	saved.room.erase("title")
	saved.room.erase("minimum_loaded")
	check(CooperativeValidation.validate(saved).is_empty(), "old checkpoints without room metadata still validate")
	sim.queue_free()
	await frames()


func avatar_checks() -> void:
	var figures := RemoteStudents.new()
	root.add_child(figures)
	figures.set_process(false)
	var steps: Array = []
	figures.stepped.connect(func(_at: Vector3, _running: bool, world: String) -> void: steps.append(world))
	var actor := {"world": "teach1", "scene": 1, "dead": false, "hiding": false, "seated": false, "running": false, "moving": true, "pose": pose(Vector3(8, 0, 7))}
	figures.receive({"players": {"b": actor}}, "a", "teach1", {"b": {"name": "队友", "connected": true}})
	check(figures.peers.b.position == Vector3(8, 0, 7), "first avatar frame starts at the received pose, never at origin")
	figures._process(0.1)
	check(steps == ["teach1"], "footstep source carries its own region for material selection")
	var position: Vector3 = figures.peers.b.get_child(0).position
	figures.frozen = true
	figures._process(1)
	check(steps.size() == 1 and figures.peers.b.get_child(0).position == position, "team pause freezes avatar animation and footsteps")
	figures.frozen = false
	figures._process(0.6)
	check(steps.size() == 1 and figures.peers.b.get_child(0).position.y == 0, "stale moving packets cannot leave a walking animation running")
	figures.receive({"players": {"b": actor}}, "a", "teach1", {"b": {"name": "改名", "connected": false}})
	check(figures.peers.b.get_meta("label").text == "改名（暂离）", "existing avatar label updates disconnected status")
	actor.scene = 2
	actor.pose = pose(Vector3(-6, 0, -5))
	figures.receive({"players": {"b": actor}}, "a", "teach1", {})
	check(figures.peers.b.position == Vector3(-6, 0, -5), "teleport does not interpolate through intervening walls")
	figures.queue_free()
	await frames()


func discovery_refresh() -> void:
	var discovery := LanDiscovery.new()
	root.add_child(discovery)
	discovery.set_process(false)
	discovery.discover()
	check(discovery.socket != null, "discovery socket opens for refresh fixture")
	var socket := discovery.socket
	discovery.rooms["fixture"] = {"seen": -100.0}
	var changes: Array = []
	discovery.found.connect(func(list: Array) -> void: changes.append(list))
	discovery.discover(true)
	check(discovery.socket == socket and discovery.rooms.has("fixture") and changes.is_empty(), "automatic refresh retains socket and pressed room rows")
	discovery._process(0)
	check(discovery.rooms.has("fixture"), "previous room gets a new probe grace period")
	discovery._refresh_at = -100.0
	discovery._process(0)
	check(discovery.rooms.is_empty() and changes.size() == 1, "unanswered rooms disappear after refresh grace")
	discovery.queue_free()
	await frames()
