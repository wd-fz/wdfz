extends "res://tests/network/consistency.gd"
## Controlled boundary fixtures: public commands for entry, explicit setup for rare states.

func run() -> void:
	await transactions()
	await garage_and_lockers()
	await games_and_dream()
	await records_and_input()
	await personal_name_cards()
	sim.queue_free()
	await process_frame
	print("LAN EDGES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func personal_name_cards() -> void:
	await fresh()
	var a := sim.actor("a")
	var b := sim.actor("b")
	check(command(a, "seat_card").get("ok", false) and a.choice.get("source") == "seat_card", "desk card opens from a real, assigned seat")
	var dialog := saved("open seat card")
	sim.restore(dialog)
	a = sim.actor("a")
	b = sim.actor("b")
	check(a.choice.get("source") == "seat_card", "an open desk dialog restores through the cooperative save validator")
	command(a, "choice", {"index":0})
	check(a.school().seat_card.armed == "1:0" and b.school().seat_card.armed.is_empty(), "a student's answer cannot spend a teammate's name")
	command(a, "interact")
	check(not command(a, "seat_card").get("ok", true), "standing away from the desk cannot arm the card")
	var stand := func(_p: Vector2) -> bool: return true
	for person: CooperativeActor in [a,b]:
		person.school().start_inspection({"day":1,"slot":0},person.location(),person.point(CampusData.rooms()),stand)
	check(a.school().inspection.current.proxy and not b.school().inspection.current.proxy, "the same team bell permits individual attendance outcomes")
	var during := saved("rollcall in two places")
	sim.restore(during)
	check(sim.actor("a").school().seat_card.outstanding(), "the outstanding counterfoil survives a team resume")
	a = sim.actor("a")
	b = sim.actor("b")
	check(tile(b, "guard1", "k"), "the teammate reaches the guard's real counter")
	command(b, "interact")
	check(a.school().seat_card.outstanding(), "a teammate reading the shared register cannot clear personal debt")
	check(tile(a, "guard1", "k"), "the borrower reaches the guard's real counter")
	command(a, "interact")
	check(a.school().seat_card.checked, "reading the same counter personally releases natural recovery")

func agree_time() -> void:
	for id: String in ["b", "c"]: command(sim.actor(id), "time_confirm", {"accept": true})

func transactions() -> void:
	await fresh()
	var a := sim.actor("a")
	a.terminal = true
	check(not command(a, "cancel", {"choice_id": 999}).get("ok", true) and a.terminal, "C05 stale dialog close cannot cancel a newer terminal")
	command(a, "cancel")
	check(not a.terminal, "C05 current terminal close still releases operation")
	check(tile(a, "teach1", "w"), "rest fixture reaches an actual sink")
	command(a, "interact")
	check(not sim.gameplay._time_offer.is_empty(), "C02 real sink proposes a team rest")
	check(not command(a, "cancel", {"operation_id": "previous"}).get("ok", true) and not sim.gameplay._time_offer.is_empty(), "C05 old operation close cannot cancel the current wait offer")
	check(not command(a, "think").get("ok", true), "C02 pending wait cannot overwrite its resource transaction")
	command(a, "cancel")
	check(sim.gameplay._time_offer.is_empty() and sim.leases.is_empty(), "C02 cancelling wait releases only live operation")
	a.bag().add("coil")
	sim.inventory.reconcile(a)
	command(a, "drop", {"item": "coil"})
	for person: CooperativeActor in sim.active_actors(): sim.inventory.reconcile(person)
	check((sim.shared[&"campus.facilities"] as FacilitiesModule).flags.get("coil", false), "C27 dropped unique material cannot respawn at source")
	var data := saved("C27 unique material")
	sim.restore(data)
	check(sim.inventory.ground.any(func(e: Dictionary) -> bool: return e["id"] == "coil"), "C27 material remains recoverable after restore")

func garage_and_lockers() -> void:
	await fresh()
	var a := sim.actor("a")
	var b := sim.actor("b")
	var g := sim.shared[&"garage.world"] as GarageModule
	var key := g.car_right_cell().split(":")
	check(aim(a, "garage1", int(key[0]), int(key[1])), "C14 normal car aisle is reachable")
	sim.travel(b, a.location(), a.pose)
	var at := a.point(CampusData.rooms())
	var ang := CampusGeometry.ang_from_yaw(a.pose["yaw"]) + PI
	var shadow := at + Vector2.from_angle(ang) * 20
	a.pose["yaw"] = CampusGeometry.yaw_from_ang(ang)
	b.pose["yaw"] = a.pose["yaw"]
	b.bag().add("torch")
	b.bag().torch_on = true
	a.enter_cool = 0
	b.enter_cool = 0
	g.roam.merge({"on": true, "stage": "approach", "cd": 10.0, "x": shadow.x, "y": shadow.y, "litAcc": 0.0}, true)
	sim.gameplay._garage_tick(.25)
	check(not a.fate().dead and not b.fate().dead and is_equal_approx(float(g.roam["litAcc"]), .25), "C14 one ally light protects both, monster clock advances once")
	check(sim.actor("c").school().san == 100, "C14 remote teammate receives no garage pressure")
	a.bag().add("elixir")
	sim.gameplay.kill(a, "garage contact", "grip", "garage")
	check(not a.fate().dead and g.roam["stage"] == "wait", "C01 protection repels shared shadow instead of repeated instant deaths")
	await fresh()
	a = sim.actor("a")
	a.watcher().hide.merge({"on": true, "c": 2, "r": 2}, true)
	a.watcher().pat.merge({"near": true, "room": "lab5", "state": "walk", "locked": false, "permanent": false}, true)
	a.locker.t = 44.95
	sim.gameplay.personal(a, .1)
	check(a.locker.stage == 1, "C20 another region's near flag cannot freeze this player's locker timer")
	var data := saved("C20 personal locker")
	sim.restore(data)
	check(a.locker.stage == 1 and a.locker.t >= 45, "C20 personal warning stage resumes without replay")
	a.watcher().pat["locked"] = true
	var before := a.locker.t
	sim.gameplay.personal(a, .1)
	check(a.locker.t == before, "C20 an actual chase pauses the locker threat")

func games_and_dream() -> void:
	await fresh()
	var a := sim.actor("a")
	check(tile(a, "lab3", "n"), "C22 real computer target exists")
	command(a, "interact")
	check(a.choice.get("menu") == "computer", "C22 real computer offers the minigame")
	command(a, "choice", {"index": 0})
	agree_time()
	check(a.activities.game == "snake" and sim.actor("b").activities.game.is_empty(), "C22 computer and team consent start only the operator's snake game")
	var token := a.activities.id
	check(not command(a, "game_input", {"game_id": token, "operation": "turn", "x": 1, "y": 1}).get("ok", true), "C22 invalid diagonal input cannot forge snake state")
	var data := saved("C22 snake round")
	sim.restore(data)
	check(a.activities.id == token and a.activities.snake.body.size() == 1, "C22 running snake round restores")
	command(a, "game_close", {"game_id": token})
	check(not command(a, "game_close", {"game_id": token}).get("ok", true), "C22 snake reward cannot be replayed")
	await fresh()
	a = sim.actor("a")
	a.bag().add("top")
	var dream := a.feature(&"story.inception") as InceptionModule
	dream.roll = func() -> float: return 0.0 # Control only the rare entry draw.
	check(tile(a, "dorm2", "b"), "C24 dormitory bed is a real interaction target")
	var origin := a.pose.duplicate(true)
	command(a, "interact")
	agree_time()
	check(a.location() == InceptionModule.ROOM and sim.actor("b").location() == "teach1", "C25 sleeping enters only the owner's dream")
	dream.roll = func() -> float: return 1.0 # The top falls: exit is a real ending.
	command(a, "item", {"item": "top"})
	point(a, InceptionModule.ROOM, CampusGeometry.tile_center(CampusData.rooms()[InceptionModule.ROOM], InceptionModule.EXIT.x, InceptionModule.EXIT.y))
	command(a, "interact")
	check(sim.room.ending_offer.get("route") == "inception" and sim.room.phase == "playing", "C24 hidden true ending still waits for teammates")
	sim.tick(1.0 / 60.0)
	check(a.location() == "dorm2" and absf(a.pose["position"][0] - origin["position"][0]) < .01 and absf(a.pose["position"][2] - origin["position"][2]) < .01, "C25 completed dream returns to its own entrance while the team decides")
	command(sim.actor("b"), "ending_confirm", {"accept": false})
	check(sim.room.ending_offer.is_empty() and sim.room.phase == "playing", "C24 declined dream ending leaves the team playing")
	command(a, "ending_request")
	check(sim.room.ending_offer.get("route") == "inception", "C24 completed personal route can be proposed again without replaying the dream")
	for id: String in ["b", "c"]: command(sim.actor(id), "ending_confirm", {"accept": true})
	check(sim.room.ending == "inception", "C24 hidden true ending settles only after full consent")

func records_and_input() -> void:
	await fresh()
	var a := sim.actor("a")
	var rules := a.feature(&"dlc.campus_rules") as RulesDlcModule
	rules.start(true, "fixture")
	rules.fact({"kind": "paper", "what": "returned"})
	sim.gameplay.stories.flush(a, "rules")
	var data := saved("C26 personal rule records")
	sim.restore(data)
	check(rules.records.has("rules.e.paper_return") and (sim.actor("b").feature(&"dlc.campus_rules") as RulesDlcModule).records.is_empty(), "C26 DLC achievements restore without leaking into teammate records")
	var malformed := data.duplicate(true)
	malformed["actors"]["a"]["runtime"]["story.paper_plane"]["s"]["ev"] = {"phase": "flight"}
	check(not CooperativeValidation.validate(malformed).is_empty(), "C28 malformed personal active events rejected before restore")
	var packet := {"epoch": sim.room.epoch, "seq": 10, "scene": a.scene_version, "x": 0, "y": 0, "yaw": 0, "pitch": 0, "run": false, "vault": true}
	sim.input(a.id, packet)
	check(CooperativeContext.base(a)["space"], "C19 held vault reaches authoritative body context")
	a.clear_input()
	check(not CooperativeContext.base(a)["space"], "C19 cleared input cannot keep vaulting after interruption")
	a.bag().add("coil")
	sim.inventory.reconcile(a)
	var material: String = sim.inventory.owners[a.id]["coil"]
	a.special_return = {"host": "lab", "origin": 3}
	sim.travel(a, MazeModule.ROOM, (a.feature(&"campus.maze") as MazeModule).enter())
	a.fate().wakes = StoryModule.MAX_WAKES # Final death, not the first-day dream rescue.
	sim.gameplay.kill(a, "private fall", "abyss", "maze_fall")
	check(sim.inventory.ground.any(func(e: Dictionary) -> bool: return e["uid"] == material and e["world"] == "lab3"), "C25 private-space death leaves team material at its campus entrance with the same UID")
	saved("C25 death recovery from private space")
