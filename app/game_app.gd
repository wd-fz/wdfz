class_name GameApp
extends Node
## Composition root: creates rules and connects input, worlds, UI and storage.

## Web version start: teach1, the player's own seat (ClassroomLayout.ownSeat).
@export var initial_world := "teach1"
@onready var router: WorldRouter = %WorldRouter
@onready var player: PlayerController = %Player
@onready var ui: GameUI = %UI

var session: GameSession
var saves := SaveStore.new()
var _hint_cooldown := 0.0
var _choice_handler: Callable
var _death_hold := 0.0
var _death_wait := 0.0
## "" while alive, "fade" while the (not yet ported) death scene plays, "card" on the record card.
var _death_phase := ""
var _choice_left := 0.0
var _choice_count := 0
var audio: AudioFx
var _seen_anomaly := ""
var _seen_lock := false
var _bell_count := 0
var _seen_phase := 0
var _seen_day := 1
var _seen_hide := false
var _seen_lock_ach := false
var _ach_started := ""
var _enter_cool := 0.0
var _drive_view: CarChaseView


func _ready() -> void:
	audio = AudioFx.new()
	audio.name = "AudioFx"
	add_child(audio)
	ui.new_requested.connect(_pick_talent.bind("easy"))
	ui.new_hard_requested.connect(_pick_talent.bind("hard"))
	ui.achievements_requested.connect(_show_achievements)
	ui.archive_requested.connect(_show_archive)
	ui.terminal_command.connect(_terminal_command)
	ui.terminal_closed.connect(_terminal_closed)
	ui.sound_toggled.connect(func(on: bool) -> void: audio.muted = not on)
	ui.death_menu_requested.connect(return_to_menu)
	ui.load_requested.connect(load_game)
	ui.save_requested.connect(save_game)
	ui.menu_requested.connect(return_to_menu)
	ui.pause_requested.connect(pause_game)
	ui.resume_requested.connect(resume_game)
	ui.touch_move.connect(player.set_touch_move)
	ui.touch_look.connect(player.look_from_touch)
	ui.touch_sprint.connect(player.set_touch_sprint)
	ui.interact_requested.connect(player.request_interaction)
	player.focus_changed.connect(ui.show_prompt)
	player.interaction_requested.connect(_interact)
	player.free_interaction_requested.connect(_campus_interact)
	ui.choice_selected.connect(_choice_made)
	ui.lift_close_requested.connect(_lift_close)
	ui.item_use_requested.connect(_use_item)
	ui.item_hot_requested.connect(_set_hot)
	return_to_menu()


func _make_session() -> GameSession:
	var candidate := GameSession.new()
	for feature: FeatureModule in [DemoModule.new(), CampusData.make_module(), ElevatorModule.new(CampusData.rooms()),
			SchoolModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus()),
			InventoryModule.new(CampusData.rooms(), CampusData.campus()), StoryModule.new(), CampusData.make_patrol(), CampusData.make_anomaly(), RoutesModule.new(CampusData.campus()), AchievementsModule.new(AnomalyModule.IDS.size() - 1), GarageModule.new(CampusData.layout("garage1")), FacilitiesModule.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus()), BroadcastModule.new(CampusData.rooms(), CampusData.patrol_nav()), PhoneModule.new(), TalentModule.new(), FakeNormalModule.new()]:
		var error := candidate.modules.register(feature)
		if not error.is_empty():
			push_error(error)
			return null
	return candidate


func campus() -> CampusModule:
	return session.modules.get_module(&"campus.world") as CampusModule if session != null else null


func fake_normal() -> FakeNormalModule:
	return session.modules.get_module(&"story.fake_normal") as FakeNormalModule if session != null else null


func talent() -> TalentModule:
	return session.modules.get_module(&"story.talent") as TalentModule if session != null else null


func phone() -> PhoneModule:
	return session.modules.get_module(&"phone.network") as PhoneModule if session != null else null


func broadcast() -> BroadcastModule:
	return session.modules.get_module(&"story.broadcast") as BroadcastModule if session != null else null


func facilities() -> FacilitiesModule:
	return session.modules.get_module(&"campus.facilities") as FacilitiesModule if session != null else null


func garage() -> GarageModule:
	return session.modules.get_module(&"garage.world") as GarageModule if session != null else null


func achievements() -> AchievementsModule:
	return session.modules.get_module(&"profile.achievements") as AchievementsModule if session != null else null


func _profile_path() -> String:
	return saves.side_path("achievements.json")


func _load_profile(into: AchievementsModule) -> void:
	var path := _profile_path()
	if into != null and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and SaveSchema.is_json_value(parsed):
			into.load_profile(parsed)


func _save_profile(from: AchievementsModule) -> void:
	var path := _profile_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(from.profile()))
		file.close()


## Report one fact; unlocked entries are announced and the profile is stored.
func fact(f: Dictionary) -> void:
	var ach := achievements()
	if ach == null:
		return
	ach.fact(f)
	for e: Dictionary in ach.take_events():
		ui.show_notice("成就：%s" % e["name"])
		audio.cue("chime", -10.0)
		_save_profile(ach)


func _show_achievements() -> void:
	var view := achievements()
	if view == null:
		view = AchievementsModule.new(AnomalyModule.IDS.size() - 1)
		_load_profile(view)
	ui.show_achievements(view.entries(), view.points())


func _show_archive() -> void:
	var ends: Dictionary = {}
	var path := saves.side_path("ends.json")
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			ends = parsed
	var rows := DeathArchive.rows(_read_death_log(), ends)
	ui.show_archive(rows, DeathArchive.known(rows), rows.size())


func routes() -> RoutesModule:
	return session.modules.get_module(&"story.routes") as RoutesModule if session != null else null


func anomaly() -> AnomalyModule:
	return session.modules.get_module(&"anomaly.world") as AnomalyModule if session != null else null


func patrol() -> PatrolModule:
	return session.modules.get_module(&"patrol.world") as PatrolModule if session != null else null


func story() -> StoryModule:
	return session.modules.get_module(&"story.death") as StoryModule if session != null else null


func items() -> InventoryModule:
	return session.modules.get_module(&"items.bag") as InventoryModule if session != null else null


func school() -> SchoolModule:
	return session.modules.get_module(&"school.day") as SchoolModule if session != null else null


func elevator() -> ElevatorModule:
	return session.modules.get_module(&"campus.elevator") as ElevatorModule if session != null else null


## TalentPick: the new-game talent screen (seven cards and a random pick).
func _pick_talent(difficulty: String) -> void:
	var labels: Array = []
	for k: String in TalentModule.KEYS:
		var d: Dictionary = TalentModule.DEF[k]
		labels.append("%s — %s" % [d["n"], d["does"]])
	labels.append("随机一个天赋")
	_choice_count += 1
	var mine := _choice_count
	_choice_handler = func(index: int) -> void:
		if mine != _choice_count or index < 0:
			return
		var pick := String(TalentModule.KEYS[index]) if index < TalentModule.KEYS.size() else String(TalentModule.KEYS[randi() % TalentModule.KEYS.size()])
		start_new_game(difficulty, pick)
	ui.show_choice("%s · 选择天赋（每局一个；限制写在卡片上）" % ("梦魇" if difficulty == "hard" else "预知梦"), labels)


func start_new_game(difficulty: String = "easy", talent_id: String = "none") -> void:
	var candidate := _make_session()
	if candidate == null:
		return
	var error := router.switch_to(initial_world)
	if not error.is_empty():
		ui.show_notice(error)
		return
	candidate.start(initial_world)
	var fate := candidate.modules.get_module(&"story.death") as StoryModule
	if fate != null:
		fate.diff = difficulty if difficulty in StoryModule.DIFFICULTIES else "easy"
	var weirdness := candidate.modules.get_module(&"anomaly.world") as AnomalyModule
	if weirdness != null:
		weirdness.begin_run(fate.diff if fate != null else "easy")
	var gift := candidate.modules.get_module(&"story.talent") as TalentModule
	if gift != null:
		gift.pick(talent_id)
		var bag0 := candidate.modules.get_module(&"items.bag") as InventoryModule
		if gift.has("tech") and bag0 != null:
			bag0.add("phone")
			bag0.take_notices()
	var cars := candidate.modules.get_module(&"garage.world") as GarageModule
	if cars != null:
		cars.set_seed(int(Time.get_ticks_usec() % 2147483647))
	var fac := candidate.modules.get_module(&"campus.facilities") as FacilitiesModule
	if fac != null:
		fac.set_seed(int((Time.get_ticks_usec() * 7) % 2147483647))
	var radio := candidate.modules.get_module(&"story.broadcast") as BroadcastModule
	if radio != null:
		radio.set_seed(int((Time.get_ticks_usec() * 13) % 2147483647))
	var fnm := candidate.modules.get_module(&"story.fake_normal") as FakeNormalModule
	if fnm != null:
		fnm.set_seed(int((Time.get_ticks_usec() * 19) % 2147483647))
	var net := candidate.modules.get_module(&"phone.network") as PhoneModule
	if net != null:
		net.set_seed(int((Time.get_ticks_usec() * 17) % 2147483647))
	var rules := candidate.modules.get_module(&"campus.world") as CampusModule
	var pose := rules.start_pose() if rules != null and initial_world == rules.start_world() else router.current.spawn_pose()
	# Game.start: the run begins seated on the player's own seat in teach1.
	var day_rules := candidate.modules.get_module(&"school.day") as SchoolModule
	if day_rules != null and rules != null and initial_world == rules.start_world():
		var seated := day_rules.start_seated(initial_world)
		if not seated.is_empty():
			pose = seated
	_install_session(candidate, pose)
	if rules != null and rules.knows(initial_world):
		ui.show_notice(String(rules.room(initial_world)["name"]) if rules.room(initial_world) != null else "武大附中 · 校园")
	else:
		ui.show_notice("走到前方告示牌，按 E 或触屏交互。这里用于验证移植接口。")


## Break the callback links between the rule modules of a finished session (they reference
## each other through Callables; leaving them would keep the whole session alive).
func _unwire(old: GameSession) -> void:
	if old == null:
		return
	var lift := old.modules.get_module(&"campus.elevator") as ElevatorModule
	if lift != null:
		lift.unsafe_check = Callable()
		lift.closed_hook = Callable()
	var watcher := old.modules.get_module(&"patrol.world") as PatrolModule
	if watcher != null:
		watcher.elevator = null
		watcher.zone_active = func(_z: Dictionary) -> bool: return false
		watcher.camouflage = Callable()
		watcher.nav.door_open = func(_room: String, _c: int, _r: int) -> bool: return false
	var rules := old.modules.get_module(&"campus.world") as CampusModule
	if rules != null:
		rules.car_hint = Callable()
		var day_old := old.modules.get_module(&"school.day") as SchoolModule
		if day_old != null:
			day_old.danger_mul = Callable()
		var route_old := old.modules.get_module(&"story.routes") as RoutesModule
		if route_old != null:
			route_old.face_remedy = Callable()
		rules.facility_hint = Callable()
		rules.rest_out = Callable()
		rules.has_item = func(_id: String) -> bool: return false
		for connection: Dictionary in rules.door_changed.get_connections():
			rules.door_changed.disconnect(connection["callable"])


func _install_session(candidate: GameSession, pose: Dictionary) -> void:
	if session != null:
		_unwire(session)
		session.stop()
	session = candidate
	_load_profile(achievements())
	_fn_day = school().day if school() != null else 1
	_leave_drive()
	if campus() != null and garage() != null:
		campus().car_hint = garage().car_hint
	if campus() != null and facilities() != null:
		campus().facility_hint = facilities().hint
	var gift_now := talent()
	if gift_now != null:
		if school() != null:
			school().danger_mul = gift_now.danger_mul
		if routes() != null:
			routes().face_remedy = gift_now.face_remedy
		if patrol() != null:
			patrol().hear_mul = gift_now.hear_range()
		campus().rest_out = facilities().rest_out
	_seen_day = school().day if school() != null else 1
	_seen_hide = false
	_seen_lock_ach = false
	_ach_started = ""
	session.notice_requested.connect(ui.show_notice)
	var day_rules := school()
	player.seated = day_rules != null and day_rules.seated
	var lift_rules := elevator()
	var watcher := patrol()
	var radio_now := broadcast()
	if watcher != null and radio_now != null:
		watcher.zone_active = func(z: Dictionary) -> bool: return z.get("when") == "broadcast" and radio_now.zone_live()
		watcher.camouflage = radio_now.cover
	if lift_rules != null and day_rules != null:
		var weird := anomaly()
		lift_rules.unsafe_check = func() -> bool: return (weird != null and weird.is_active()) or day_rules.inspection_pending() or (watcher != null and watcher.local_chase())
		if watcher != null:
			lift_rules.closed_hook = watcher.elevator_closed
	if watcher != null:
		watcher.elevator = lift_rules
		var campus_rules := campus()
		watcher.nav.door_open = func(room_id: String, c: int, r: int) -> bool: return campus_rules != null and campus_rules.is_open("%s:%d:%d" % [room_id, c, r])
	player.hiding = watcher != null and bool(watcher.hide["on"])
	var rules := campus()
	if rules != null:
		rules.door_changed.connect(_door_changed)
	var bag := items()
	if rules != null and bag != null:
		rules.has_item = bag.has
	_sync_world()
	player.restore_pose(pose)
	player.show()
	ui.set_save_available(saves.exists())
	resume_game()


func _dead() -> bool:
	return story() != null and story().over()


func save_game() -> void:
	if session == null or not session.running or _dead():
		return
	var snapshot := session.capture(player.capture_pose())
	var error := session.validate(snapshot, router.known_ids())
	if error.is_empty():
		error = saves.write(snapshot)
	ui.show_notice("已保存测试进度。" if error.is_empty() else error)
	ui.set_save_available(saves.exists())


func load_game() -> void:
	var result := saves.read()
	if result.has("error"):
		ui.show_notice(result["error"])
		return
	var candidate := _make_session()
	if candidate == null:
		return
	var data: Dictionary = result["data"]
	var error := candidate.validate(data, router.known_ids())
	if not error.is_empty():
		ui.show_notice(error)
		return
	error = router.switch_to(data["world_id"])
	if not error.is_empty():
		ui.show_notice(error)
		return
	candidate.restore(data)
	_install_session(candidate, data["player"])
	if garage() != null and garage().driving():
		_enter_drive()
	ui.show_notice("已恢复测试进度；读档不会再次触发交互奖励。")


func pause_game() -> void:
	# Game.pause: no pause menu once dead (a death cannot be saved around).
	if session == null or not session.running or _dead():
		return
	player.enabled = false
	player.clear_input()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("pause")
	if talent() != null and session != null:
		ui.show_notice(talent().pause_text())


func resume_game() -> void:
	if session == null or not session.running or _dead():
		return
	get_tree().paused = false
	player.enabled = true
	player.clear_input()
	ui.set_mode("play")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func return_to_menu() -> void:
	_leave_drive()
	ui.hide_terminal()
	_mic_open = false
	_radio_job = null
	if is_instance_valid(_crowd_nodes):
		_crowd_nodes.queue_free()
	_crowd_nodes = null
	if audio != null:
		audio.stop_all()
	ui.hide_ending()
	ui.show_hiding(false)
	ui.hide_choice()
	ui.hide_death()
	_death_hold = 0.0
	_death_phase = ""
	ui.hide_bag()
	ui.reset_status()
	player.seated = false
	_choice_handler = Callable()
	if session != null:
		_unwire(session)
		session.stop()
	session = null
	player.enabled = false
	player.clear_input()
	player.hide()
	router.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("menu")
	ui.set_save_available(saves.exists())
	ui.show_notice("")


func _physics_process(delta: float) -> void:
	if _choice_left > 0.0 and ui.choice_open():
		_choice_left -= delta
		ui.show_choice_timer(maxf(0.0, _choice_left))
		if _choice_left <= 0.0:
			ui.choice_selected.emit(-2) # timed out: random pick
	if session != null and session.running and not get_tree().paused:
		session.advance(delta, router.current.advances_calendar)
		if school() == null or campus() == null or not campus().knows(session.world_id):
			ui.show_location(_location_name())
		ui.show_runtime(session.clock.active_seconds)
		_campus_step(delta)


# ---- formal campus (features/campus) ----

func _campus_world() -> CampusWorld:
	return router.get_child(0) as CampusWorld if router.get_child_count() > 0 else null


func _sync_world() -> void:
	var world := _campus_world()
	var rules := campus()
	if world != null and rules != null:
		world.apply_doors(rules.open_doors())
	var lift := elevator()
	if world != null and lift != null:
		world.set_lift_doors(lift.door_amount_in(session.world_id))


func _door_changed(key: String, open: bool) -> void:
	var world := _campus_world()
	if world != null:
		world.set_door_open(key, open)


func _campus_step(delta: float) -> void:
	var rules := campus()
	if rules == null or not rules.knows(session.world_id):
		return
	var fate := story()
	if fate != null and fate.ended != "":
		return
	if fate != null and fate.dead:
		_death_step(delta)
		return
	_school_step(delta, rules)
	_handle_deaths()
	if fate != null and fate.dead:
		return
	var lift := elevator()
	if lift != null:
		var stepped := lift.step(delta, session.world_id, player.capture_pose())
		_apply_result(stepped)
		for text: String in lift.take_notices():
			ui.show_notice(text)
		var world := _campus_world()
		if world != null:
			world.set_lift_doors(lift.door_amount_in(session.world_id))
		ui.set_lift_close(lift.show_close_button(session.world_id, player.capture_pose()) and not ui.choice_open())
		if player.enabled and Input.is_action_just_pressed("lift_close"):
			_lift_close()
	if not player.enabled:
		return
	var crossing := rules.crossing(session.world_id, player.capture_pose())
	if not crossing.is_empty():
		travel(crossing["world"], crossing["pose"], true)
	_hint_cooldown -= delta
	if _hint_cooldown <= 0.0 and not player.has_focus():
		_hint_cooldown = 0.1
		var radio_hint := broadcast().hint() if broadcast() != null else ""
		ui.show_prompt(radio_hint if radio_hint != "" else rules.hint(session.world_id, player.capture_pose()))


func _campus_interact() -> void:
	var rules := campus()
	if session == null or get_tree().paused or rules == null or not rules.knows(session.world_id):
		return
	var pose := player.capture_pose()
	var day_rules := school()
	if patrol() != null and bool(patrol().hide["on"]):
		_hide_out()
		return
	var weird := anomaly()
	if weird != null and weird.near_roster():
		var bag_here := items()
		weird.use_roster(bag_here != null and (bag_here.has("pen") or bag_here.has("chalk")))
		return
	# tryInteract: a seated player stands up first.
	if day_rules != null and day_rules.seated:
		_stand_up("我站了起来。")
		return
	var radio := broadcast()
	if radio != null:
		radio.set_context(_broadcast_context())
		if radio.use_here():
			_apply_broadcast_events()
			return
	var lift := elevator()
	var result: Dictionary
	var room: Variant = rules.room(session.world_id)
	var here := CampusGeometry.to_world(room, float(pose["position"][0]), float(pose["position"][2])) if room != null else Vector2.ZERO
	# elevator.js 'interact' hook first: inside a cabin (or a ride room) the panel answers.
	if lift != null and room != null and (session.world_id in ElevatorModule.RIDE_ROOMS or lift.in_cabin(session.world_id, here)):
		result = lift.use_at(session.world_id, here)
	else:
		result = rules.interact_at(session.world_id, pose)
		if result.get("elevator", false) and lift != null:
			result = lift.use_at(session.world_id, here)
	_apply_result(result)


func _apply_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	if result.has("door"):
		audio.cue("creak", -10.0)
	if result.has("choice"):
		_open_choice(result["choice"])
	var text := String(result.get("notice", ""))
	if result.has("toast"):
		text = (text + "\n" if not text.is_empty() else "") + String(result["toast"])
	if result.has("search") and items() != null:
		var room: Variant = campus().room(session.world_id)
		var p: Array = player.capture_pose()["position"]
		items().start_search(session.world_id, int(result["search"][0]), int(result["search"][1]), CampusGeometry.to_world(room, float(p[0]), float(p[2])))
	if result.has("podium") and items() != null:
		var said := items().podium(session.world_id, int(result["podium"][0]), int(result["podium"][1]))
		text = String(said.get("notice", text))
	if result.has("terminal") and routes() != null:
		var bag_t := items()
		var scene := session.world_id
		if scene == "admin3":
			routes().use_data(scene)
		else:
			routes().use_terminal(scene, (bag_t != null and bag_t.has("usb")) or (talent() != null and talent().has("code")), school().day)
		_apply_route_events(routes())
		return
	if result.has("gate") and routes() != null:
		routes().use_gate(String(result["gate"]), school().day)
		_apply_route_events(routes())
		return
	if result.has("facility") and phone() != null and session.world_id == "lab3" and String(result["facility"][0]) in ["n", "K"]:
		var lab: Dictionary = campus().room("lab3")
		var tile := CampusGeometry.tile_center(lab, int(result["facility"][1]), int(result["facility"][2]))
		phone().set_context(_phone_context())
		phone().computer_menu(tile.x, tile.y)
		_apply_phone_events()
		return
	if result.has("phone") and phone() != null:
		phone().set_context(_phone_context())
		phone().phone_menu()
		_apply_phone_events()
		return
	if result.has("facility") and facilities() != null:
		var fac := facilities()
		fac.set_context(_facility_context())
		fac.use(campus().room(session.world_id), String(result["facility"][0]), int(result["facility"][1]), int(result["facility"][2]))
		_apply_facility_events()
		return
	if result.has("rest") and facilities() != null:
		facilities().set_context(_facility_context())
		facilities().rest(String(result["rest"]))
		_apply_facility_events()
		return
	if result.has("facility_item") and facilities() != null:
		facilities().set_context(_facility_context())
		facilities().use_item(String(result["facility_item"]))
		_apply_facility_events()
		return
	if result.has("leave") and school() != null:
		if school().use_leave() and items() != null:
			items().remove("leave")
			ui.show_notice("请假 %d 分钟 · 不用待在规定的地方，巡察者也不管你" % int(SchoolModule.LEAVE_MIN))
		for line: String in school().take_notices():
			ui.show_notice(line)
		return
	if result.has("car") and garage() != null:
		garage().set_context(_garage_context())
		garage().inspect_car(int(result["car"][0]), int(result["car"][1]))
		_apply_garage_events()
		return
	if result.has("car_key") and garage() != null:
		ui.show_notice("我：钥匙环刻着「%s」。要去车位前核对。" % garage().key_label())
		return
	if result.has("coin") and garage() != null:
		garage().set_context(_garage_context())
		if garage().throw_coin() and items() != null:
			items().remove("coin")
		_apply_garage_events()
		return
	if result.has("trash") and routes() != null:
		routes().use_trash(session.world_id, school().day)
		_apply_route_events(routes())
		return
	if result.has("hide") and patrol() != null:
		_hide_in(int(result["hide"][0]), int(result["hide"][1]))
		return
	if result.has("seat") and school() != null:
		var sat := school().sit(session.world_id, int(result["seat"][0]), int(result["seat"][1]))
		if not sat.is_empty():
			player.restore_pose(sat["pose"])
			player.seated = true
			ui.show_notice(sat["notice"])
		return
	if result.has("san") and school() != null:
		school().change_san(float(result["san"]), 0.0)
	if result.has("travel"):
		travel(result["travel"]["world"], result["travel"]["pose"], bool(result["travel"].get("seamless", false)))
	if not text.is_empty():
		ui.show_notice(text)


func _stand_up(text: String = "") -> void:
	var day_rules := school()
	if day_rules == null:
		return
	var stood := day_rules.stand_up()
	player.seated = false
	if stood.has("pose"):
		var pose: Dictionary = stood["pose"]
		pose["yaw"] = player.capture_pose()["yaw"]
		pose["pitch"] = player.capture_pose()["pitch"]
		player.place(pose)
	if not text.is_empty():
		ui.show_notice(text)


func _school_step(delta: float, rules: CampusModule) -> void:
	var day_rules := school()
	if day_rules == null:
		return
	if driving():
		_drive_step(delta)
		return
	if day_rules.seated and player.wants_move():
		_stand_up()
	var watcher := patrol()
	var bag := items()
	var pill_san := 0.0
	var snack := false
	if bag != null:
		_item_keys(bag)
		pill_san = bag.step(delta)
		snack = bag.snack_active()
		var room_here: Variant = rules.room(session.world_id)
		var here: Array = player.capture_pose()["position"]
		bag.search_tick(delta, session.world_id, CampusGeometry.to_world(room_here, float(here[0]), float(here[2])))
		for text: String in bag.take_notices():
			ui.show_notice(text)
		ui.show_search(bag.search_progress())
		player.speed_multiplier = 1.5 if snack else 1.0
		player.camera.get_node("Torch").visible = bag.torch_on
		if talent() != null:
			talent().tick_watch(day_rules.day if day_rules != null else 1, school().tsec, SchoolClock.rate_at(school().tsec))
			for te: Dictionary in talent().take_events():
				ui.show_notice(String(te["text"]))
		ui.show_hot("1 · %s    2 · %s" % [bag.item_name(String(bag.hot[0])) if bag.hot[0] != null else "空", bag.item_name(String(bag.hot[1])) if bag.hot[1] != null else "空"])
	var pose := player.capture_pose()
	var room: Variant = rules.room(session.world_id)
	var p: Array = pose["position"]
	var hiding_now: bool = watcher != null and bool(watcher.hide["on"])
	player.hiding = hiding_now
	if watcher != null:
		watcher.set_context(_patrol_context(room, pose))
	var weird_now := anomaly()
	day_rules.step(delta, {"anomaly_active": weird_now != null and weird_now.is_active(), "hiding": hiding_now, "patrol_threat": watcher != null and watcher.local_threat(), "world_id": session.world_id, "w": CampusGeometry.to_world(room, float(p[0]), float(p[2])),
		"height": float(p[1]), "moving": player.moving, "running": player.sprinting, "calendar": router.current.advances_calendar,
		"ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "pitch": float(pose["pitch"]),
		"can_stand": _can_stand.bind(room, float(p[1])), "line_clear": _line_clear.bind(room), "snack": snack, "pill_san": pill_san})
	var world := _campus_world()
	if world != null:
		world.show_silhouettes(day_rules.inspection_points(), room, float(p[1]))
	player.can_sprint = day_rules.can_run(snack)
	_patrol_step(delta, watcher, day_rules, room, pose)
	if story().dead:
		return
	_routes_step(delta)
	if story().over():
		return
	_garage_step(delta, room, pose)
	if story().dead or story().over():
		return
	_facility_step()
	_broadcast_step(delta)
	if story().dead or story().over():
		return
	_phone_step(delta)
	if story().dead or story().over():
		return
	_fake_normal_step(delta)
	if story().dead or story().over():
		return
	_anomaly_step(delta, day_rules, room, pose)
	_audio_step(delta, watcher, day_rules, room, p)
	_progress_step(watcher, day_rules, weird_now)
	for text: String in day_rules.take_notices():
		ui.show_notice(text)
	var frozen := not router.current.advances_calendar
	var period := day_rules.period_text(frozen)
	if watcher != null and bool(watcher.pat["permanent"]) and not frozen:
		period += " · 持续追踪"
	ui.show_status(day_rules.place_name(session.world_id, float(p[1])), period, day_rules.period_class(frozen), day_rules.clock_text((bag != null and bag.has_clock()) or (talent() != null and talent().has("watch"))))
	if hiding_now:
		ui.show_prompt("出来")
	elif weird_now != null and weird_now.near_roster():
		ui.show_prompt("那张名单")
	elif day_rules.seated and not player.has_focus():
		ui.show_prompt("站起来")
	ui.show_stamina(day_rules.stam, day_rules.stamina_max(), day_rules.tired)
	var lit := _campus_world()
	if lit != null:
		var weird_light := anomaly()
		lit.update_lighting(delta, day_rules.tsec, player.camera, watcher.flick if watcher != null else 0.0, watcher.red if watcher != null else 0.0,
			weird_light != null and weird_light.blackout_now(), weird_light.overcast_target() if weird_light != null else 0.0)
		if watcher != null:
			var fig_scene := Vector2.ZERO
			if watcher.figure_visible():
				fig_scene = CampusGeometry.to_scene(room, Vector2(float(watcher.pat["x"]), float(watcher.pat["y"])))
			lit.show_patrol(watcher.figure_visible(), fig_scene, float(watcher.pat["fy"]), player.camera.global_position)
		if weird_light != null and lit.anomaly_fx != null:
			var cam_pos := player.camera.global_position
			var fwd := -player.camera.global_transform.basis.z
			lit.anomaly_fx.update(delta, weird_light.an, room, session.world_id, Vector3(cam_pos.x, float(p[1]), cam_pos.z), Vector2(fwd.x, fwd.z))


## canStand (world.js): is there room for the body (radius 3 units) at this old world point?
func _can_stand(w: Vector2, room: Variant, height: float) -> bool:
	var world := _campus_world()
	if world == null:
		return false
	var s := CampusGeometry.to_scene(room, w)
	var shape := SphereShape3D.new()
	shape.radius = CampusGeometry.PRAD * CampusGeometry.U2M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis(), Vector3(s.x, height + 0.9, s.y))
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## inspection.js lineClear: indoors walls and closed doors on the tile grid; outdoors solid obstacles.
func _line_clear(a: Vector2, b: Vector2, room: Variant) -> bool:
	var n := int(ceil(a.distance_to(b) / 3.0))
	var rules := campus()
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if room != null:
			var ch := CampusGeometry.tile_at(room, p)
			if ch == "#":
				return false
			if ch == "=":
				var c := int(floor((p.x - float(room["ox"])) / float(room["tw"])))
				var r := int(floor((p.y - float(room["oy"])) / float(room["th"])))
				if not rules.is_open(CampusGeometry.door_key(room, c, r)):
					return false
		elif not _can_stand_point(p):
			return false
	return true


func _can_stand_point(w: Vector2) -> bool:
	var world := _campus_world()
	if world == null:
		return true
	var s := CampusGeometry.to_scene(null, w)
	var query := PhysicsPointQueryParameters3D.new()
	query.position = Vector3(s.x, 1.0, s.y)
	query.collision_mask = 1
	return world.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


func _item_keys(bag: InventoryModule) -> void:
	if Input.is_action_just_pressed("bag"):
		if ui.bag_open():
			_close_bag()
		elif player.enabled:
			_open_bag()
	if not player.enabled:
		return
	var tsec := school().tsec if school() != null else 0.0
	if Input.is_action_just_pressed("torch"):
		if not bag.has("torch"):
			ui.show_notice("没有手电筒")
		else:
			_apply_result(bag.use("torch", tsec))
	for i in 2:
		if Input.is_action_just_pressed("hot_%d" % (i + 1)):
			_apply_result(bag.use_hot(i, tsec))


func _bag_entries() -> Array:
	var bag := items()
	var out: Array = []
	for id: String in bag.bag:
		out.append({"id": id, "name": bag.item_name(id), "text": bag.item_text(id)})
	return out


func _open_bag() -> void:
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_bag(_bag_entries())


func _close_bag() -> void:
	ui.hide_bag()
	if session != null and session.running and not get_tree().paused:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _use_item(id: String) -> void:
	var bag := items()
	if bag == null:
		return
	_close_bag()
	_apply_result(bag.use(id, school().tsec if school() != null else 0.0))


func _set_hot(index: int, id: String) -> void:
	var bag := items()
	if bag != null and bag.set_hot(index, id):
		ui.show_notice("「%s」放到快捷栏 %d" % [bag.item_name(id), index + 1])
		ui.show_bag(_bag_entries())


# ---- locker hiding (patrol.js hideIn / hideOut) ----

func _hide_in(c: int, r: int) -> void:
	var watcher := patrol()
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	watcher.set_context(_patrol_context(room, pose))
	var spot := watcher.hide_in(c, r)
	for e: Dictionary in watcher.take_events():
		ui.show_notice(String(e["text"]))
	var s := CampusGeometry.to_scene(room, Vector2(spot["x"], spot["y"]))
	player.restore_pose({"position": [s.x, float(pose["position"][1]), s.y], "yaw": CampusGeometry.yaw_from_ang(float(spot["ang"])), "pitch": 0.0})
	player.hiding = true
	ui.show_hiding(true)


func _hide_out() -> void:
	var watcher := patrol()
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	watcher.set_context(_patrol_context(room, pose))
	var spot := watcher.hide_out()
	for e: Dictionary in watcher.take_events():
		ui.show_notice(String(e["text"]))
	if spot.has("x"):
		var s := CampusGeometry.to_scene(room, Vector2(spot["x"], spot["y"]))
		player.place({"position": [s.x, float(pose["position"][1]), s.y], "yaw": pose["yaw"], "pitch": pose["pitch"]})
	player.hiding = false
	ui.show_hiding(false)


# ---- deaths (story.js kill / dreamWake) ----

func _handle_deaths() -> void:
	var day_rules := school()
	var fate := story()
	if day_rules == null or fate == null:
		return
	for req: Dictionary in day_rules.take_deaths():
		kill(String(req["msg"]), String(req["fx"]), String(req["source"]))
		if fate.dead:
			return


func kill(msg: String, fx: String, source: String) -> void:
	var fate := story()
	if fate == null or fate.dead:
		return
	var bag := items()
	var elixir := bag != null and bag.has("elixir")
	var immune := not elixir and not fate.dead and talent() != null and talent().prevent_death()
	var result := fate.kill(msg, fx, source, {"day": school().day if school() != null else 1, "has_elixir": elixir, "immune": immune})
	if result.has("protected"):
		if result["protected"] == "elixir":
			bag.remove("elixir")
		fact({"kind": "protect"})
		if garage() != null:
			garage().rescued()
		school().survive(source)
		if patrol() != null:
			patrol().rescued()
		if anomaly() != null:
			anomaly().end_now()
		_apply_result(result)
		return
	if not result.get("dead", false):
		return
	player.enabled = false
	player.clear_input()
	audio.stop_all()
	audio.cue("scare", -2.0)
	ui.hide_choice()
	ui.hide_bag()
	if bag != null:
		bag.cancel_search()
	if school() != null:
		school().cancel_inspection()
	if elevator() != null:
		elevator().cancel()
	ui.set_lift_close(false)
	ui.show_search(0.0)
	get_tree().paused = false
	_death_hold = float(result["hold"])
	_death_wait = 0.0
	_death_phase = "fade"
	ui.show_notice(msg)
	var updated := fate.log_death(_read_death_log(), school().day if school() != null else 1, session.world_id)
	_write_death_log(updated)
	if not result["wake"]:
		saves.clear()
		ui.set_save_available(saves.exists())


func _death_log_path() -> String:
	return saves.side_path("death_log.json")


func _read_death_log() -> Dictionary:
	var path := _death_log_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary and SaveSchema.is_json_value(parsed) else {}


func _write_death_log(record: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_death_log_path().get_base_dir())
	var file := FileAccess.open(_death_log_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record))
		file.close()


func _death_step(delta: float) -> void:
	if _death_phase != "fade":
		return
	_death_wait += delta
	ui.show_death_scene(story().death_fx, minf(1.0, _death_wait / maxf(0.2, _death_hold)))
	# story.js deathSkip: at least 0.6 s of the scene, then a key skips to the result.
	var skip := _death_wait >= 0.6 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"))
	if _death_wait >= _death_hold or skip:
		_finish_death()


func _finish_death() -> void:
	var fate := story()
	if fate.wake_pending:
		var left := fate.finish_wake()
		fact({"kind": "wake"})
		if phone() != null:
			phone().dream()
		ui.hide_terminal()
		if garage() != null:
			garage().cancel_chase()
		_leave_drive()
		_death_phase = ""
		school().dream_wake_reset()
		campus().close_all_doors()
		if patrol() != null:
			patrol().reset()
		if anomaly() != null:
			anomaly().dream_wake()
		player.hiding = false
		ui.show_hiding(false)
		if items() != null:
			items().snack_t = 0.0
		var seated := school().start_seated("teach1")
		travel("teach1", seated, false)
		player.seated = true
		player.enabled = true
		ui.hide_death()
		ui.show_notice("……我猛地抬起头，后背全是汗。我还坐在自己的位子上。\n刚才那些——是梦吗？可我记得每一条走廊。\n" +
			("预知梦 · 还能再醒 %d 次" % left if left > 0 else "预知梦 · 下一次，不会再醒了"))
		return
	_death_phase = "card"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_death_card(fate.death_msg, fate.epitaph(), fate.cause(), StoryModule.hints(_read_death_log()))


## Player state the patroller reads (old S / HIDE / Inspection state).
func _patrol_context(room: Variant, pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var day_rules := school()
	var bag := items()
	var tsec := day_rules.tsec if day_rules != null else 700.0
	var cur: Dictionary = day_rules.inspection.get("current", {}) if day_rules != null else {}
	var height := float(p[1])
	if room != null and campus() != null and not campus().is_stairwell(session.world_id) and session.world_id != "bell1":
		height = 0.0
	return {"scene": session.world_id, "x": w.x, "y": w.y, "fy": height, "seated": day_rules != null and day_rules.seated,
		"at_seat": day_rules != null and day_rules.at_my_seat(session.world_id, w), "excused": day_rules != null and day_rules.permit(),
		"on_leave": school() != null and school().on_leave(), "night": SchoolClock.is_night(tsec), "need_where": SchoolClock.need_where(tsec), "dead": story() != null and story().dead,
		"playing": true, "inspection_room": String(cur.get("room", "")) if not cur.is_empty() else "",
		"calm": float(day_rules.inspection.get("calm", 0.0)) if day_rules != null else 0.0, "calm_room": String(day_rules.inspection.get("calm_room", "")) if day_rules != null else "",
		"has_seal": bag != null and bag.has("seal"), "active_seconds": day_rules.active_seconds if day_rules != null else 0.0, "car_chase": false}


func _patrol_step(delta: float, watcher: PatrolModule, day_rules: SchoolModule, room: Variant, pose: Dictionary) -> void:
	if watcher == null:
		return
	for e: Dictionary in day_rules.take_events():
		if e["kind"] == "absence":
			watcher.registered_absence(String(e["id"]))
		elif e["kind"] == "exam":
			fact({"kind": "exam", "phase": e["phase"], "pass": e.get("pass", false), "day": e.get("day", 1)})
		elif e["kind"] == "inspection":
			fact({"kind": "inspection", "day": e["day"], "slot": e["slot"], "compliant": e["compliant"]})
	watcher.set_context(_patrol_context(room, pose))
	watcher.tick(delta)
	for e: Dictionary in watcher.take_events():
		match e["kind"]:
			"violation":
				day_rules.add_violation(float(e["amount"]))
			"remove_item":
				if items() != null:
					items().remove(String(e["id"]))
			"notice":
				ui.show_notice(String(e["text"]))
			"toast":
				ui.show_notice(String(e["text"]))
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return


## Facts for the achievements: transitions of the run, never the rules themselves.
func _progress_step(watcher: PatrolModule, day_rules: SchoolModule, weird: AnomalyModule) -> void:
	if achievements() == null or story().over():
		return
	if day_rules.day != _seen_day:
		_seen_day = day_rules.day
		fact({"kind": "day", "day": _seen_day})
	if not achievements().rooms.has(session.world_id):
		fact({"kind": "room", "id": session.world_id})
	if weird != null:
		var id := weird.active_id()
		if id != _ach_started:
			if id != "":
				fact({"kind": "anomaly", "phase": "start", "id": id, "public": id != "cola"})
			elif _ach_started != "":
				fact({"kind": "anomaly", "phase": "end", "id": _ach_started, "survived": not story().dead, "lethal": bool(AnomalyModule.DEFS[_ach_started].get("lethal", false))})
			_ach_started = id
	if watcher != null:
		var locked := bool(watcher.pat["locked"])
		var hid := bool(watcher.hide["on"])
		if _seen_lock_ach and not locked and not hid and not story().dead:
			fact({"kind": "patrol", "what": "lost"})
		if _seen_hide and not hid and _seen_lock_ach and not story().dead:
			fact({"kind": "patrol", "what": "locker"})
		_seen_lock_ach = locked
		_seen_hide = hid


## Sound layers and cues from the current state (AudioFx never changes a rule).
func _audio_step(delta: float, watcher: PatrolModule, day_rules: SchoolModule, room: Variant, p: Array) -> void:
	if audio == null or story().over():
		return
	var weird := anomaly()
	var an_id := weird.active_id() if weird != null else ""
	var near := 0.0
	var patrol_pos: Variant = null
	if watcher != null and watcher.figure_visible():
		var dist := watcher.distance()
		near = clampf(1.0 - dist / 360.0, 0.0, 1.0)
		var fs := CampusGeometry.to_scene(room, Vector2(float(watcher.pat["x"]), float(watcher.pat["y"])))
		patrol_pos = Vector3(fs.x, float(watcher.pat["fy"]) + 0.2, fs.y)
	audio.update(delta, {"moving": player.moving, "running": player.sprinting, "indoors": session.world_id != "out", "san": day_rules.san,
		"blackout": weird != null and weird.blackout_now(), "rain": an_id in ["rain", "raindots"] and session.world_id == "out", "hiding": player.hiding,
		"patrol_near": near, "patrol_pos": patrol_pos, "chase": watcher != null and bool(watcher.pat["locked"])})
	if watcher != null:
		var locked := bool(watcher.pat["locked"])
		if locked and not _seen_lock:
			audio.cue("scare", -6.0)
		_seen_lock = locked
	if an_id != _seen_anomaly:
		_seen_anomaly = an_id
		_bell_count = 0
		_seen_phase = 0
		if an_id != "":
			match an_id:
				"broad":
					audio.cue("static", -8.0)
				"leak", "raindots":
					audio.cue("drip", -8.0)
				"hand":
					audio.cue("creak", -8.0)
				_:
					audio.cue("sting", -10.0)
	if weird != null and an_id != "":
		var t := float(weird.an["t"])
		var data: Dictionary = weird.an["data"]
		match an_id:
			"bell13":
				if _bell_count < 13 and t >= float(_bell_count) * 1.4:
					_bell_count += 1
					audio.cue("bell", -6.0)
			"bells":
				if _bell_count < 9 and t >= float(_bell_count) * 0.25:
					_bell_count += 1
					audio.cue("ding", -10.0, 0.9 + 0.05 * float(_bell_count % 4))
			"leak":
				if fmod(t, 0.9) < delta:
					audio.cue("drip", -14.0, 0.9 + randf() * 0.3)
			"cup", "cola":
				var phase := int(data.get("phase", 0))
				if phase == 2 and _seen_phase != 2:
					audio.cue("thud", -2.0)
				_seen_phase = phase


# ---- facilities, rest and the portal (features/campus/facilities_module.gd) ----

func _facility_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var day_rules := school()
	var bag := items()
	var weird := anomaly()
	var meal := false
	for m: Array in CampusData.campus().get("meals", []):
		if day_rules.tsec >= float(m[0]) and day_rules.tsec < float(m[1]):
			meal = true
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "tsec": day_rules.tsec,
		"clock": day_rules.game_clock(), "meal": meal, "rest_mul": float(day_rules.pressure()["rest"]), "exam": day_rules.exam,
		"has": func(id: String) -> bool: return bag != null and bag.has(id),
		"add": func(id: String) -> bool: return _add_item(id),
		"remove": func(id: String) -> void:
			if bag != null:
				bag.remove(id),
		"anomaly": weird.pendulum_info() if weird != null else {},
		"busy": (weird != null and weird.is_active()) or day_rules.inspection_pending() or (patrol() != null and patrol().local_chase()),
		"gate_n_map": CampusData.campus().get("gates", {}).get("n", {"x": 514, "y": 95}), "bound_x1": float(CampusData.campus().get("bound_map", {}).get("x1", 830))}


## Inventory add with the old messages (a full bag says so).
func _add_item(id: String) -> bool:
	var bag := items()
	if bag == null:
		return false
	var ok := bag.add(id)
	for text: String in bag.take_notices():
		ui.show_notice(text)
	return ok


func _facility_step() -> void:
	var fac := facilities()
	if fac == null:
		return
	fac.set_context(_facility_context())
	fac.spot_tick()
	var world := _campus_world()
	if world != null:
		world.show_portal(bool(fac.portal["open"]))


func _apply_facility_events() -> void:
	var fac := facilities()
	if fac == null:
		return
	for e: Dictionary in fac.take_events():
		match e["kind"]:
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = clampf(school().san + float(e["amount"]), float(e.get("min", -INF)), float(e.get("max", INF)))
			"advance":
				school().advance_game_time(float(e["minutes"]))
			"stamina":
				school().stam = minf(school().stamina_max(), school().stam + float(e["amount"]))
			"skip":
				ui.show_notice("…%d 分钟过去了 · %s" % [int(e["minutes"]), e["name"]])
			"fact":
				fact({"kind": "rest", "key": String(e["key"])})
			"anomaly_lock":
				if anomaly() != null:
					anomaly().lock_forecast()
			"anomaly_end":
				if anomaly() != null:
					anomaly().end_now()
			"exam_start":
				audio.cue("bell", -2.0)
				if school().exam_start():
					ui.show_notice("考试模式 · 今天剩下的课都是考试，熄灯后结束")
			"bell":
				audio.cue("bell", -6.0)
			"save":
				save_game()
			"map":
				ui.show_list("地图 · 记下的地方", fac.spot_rows().map(func(r: Dictionary) -> Dictionary: return {"text": r["name"] if r["on"] else "？？？", "on": r["on"], "memo": ""}))
			"travel":
				_facility_travel(e)
				return
			"route_hint":
				_route_hint(String(e["route"]))
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"later":
				var run := session
				get_tree().create_timer(float(e["seconds"]), false).timeout.connect(func() -> void:
					if session == run and facilities() != null and not story().over() and not ui.choice_open():
						facilities().set_context(_facility_context())
						facilities().portal_ask()
						_apply_facility_events())
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var f := facilities()
					if f != null and mine == _choice_count:
						f.set_context(_facility_context())
						f.choose(index)
						_apply_facility_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])
			"ending":
				_reach_ending(String(e["id"]))
				return
	for text: String in school().take_notices():
		ui.show_notice(text)


func _facility_travel(e: Dictionary) -> void:
	var world := String(e["world"])
	var pose: Dictionary
	if e.has("x"):
		var s := CampusGeometry.to_scene(campus().room(world), Vector2(float(e["x"]), float(e["y"])))
		pose = {"position": [s.x, 0.05, s.y], "yaw": CampusGeometry.yaw_from_ang(float(e["ang"])), "pitch": 0.0}
	else:
		pose = campus().default_spawn(world)
	travel(world, pose, false)


# ---- the fake-normal day and the escape ideas ----

var _fn_day := 0


func _fake_normal_step(delta: float) -> void:
	var fnm := fake_normal()
	if fnm == null:
		return
	var day_rules := school()
	if day_rules.day == 1 and day_rules.tsec >= SchoolClock.LIGHTS_OUT:
		fnm.lights_out_note()
	if _fn_day != day_rules.day:
		if _fn_day == 1 and day_rules.day == 2:
			fnm.day_two()
		_fn_day = day_rules.day
	var room: Variant = campus().room(session.world_id)
	fnm.tick(delta, {"tag": FakeNormalModule.where_tag(session.world_id, String(room.get("host", "")) if room != null else ""),
		"busy": ui.choice_open() or day_rules.inspection_pending(), "dead": story().dead})
	_apply_fake_normal_events()


func _apply_fake_normal_events() -> void:
	var fnm := fake_normal()
	if fnm == null:
		return
	for e: Dictionary in fnm.take_events():
		match e["kind"]:
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"hurt":
				ui.flash_hurt(0.45)
			"fact":
				fact({"kind": "fakeNormal", "done": true, "laughs": int(e["laughs"])})
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var f := fake_normal()
					if f != null and mine == _choice_count:
						f.choose(index)
						_apply_fake_normal_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], false)
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return


## story.js tryFaceRoute / tryTrashRoute from the ideas list.
func _route_hint(route: String) -> void:
	var r := routes()
	if r == null:
		return
	if route == "face":
		if not r.hacked:
			ui.show_notice("我：得先进实验楼三楼机房里那间锁着的网络中心，再去行政楼三楼改数据。")
		elif not r.data_synced:
			ui.show_notice("我：白名单还没改完。")
		else:
			var pose := player.capture_pose()
			var w := CampusGeometry.to_world(null, float(pose["position"][0]), float(pose["position"][2]))
			if session.world_id != "out" or r.gate_at(w) != "w":
				ui.show_notice("我：还得去西小门的闸机前。")
			else:
				r.use_gate("w", school().day)
				_apply_route_events(r)
	elif route == "trash":
		if session.world_id != "trash1":
			ui.show_notice("我：得先进垃圾房。")
		else:
			r.use_trash("trash1", school().day)
			_apply_route_events(r)


# ---- the phone, the network and 《网安仙人》 (features/phone) ----

func _phone_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var own: Dictionary = CampusData.campus().get("own_seat", {})
	var classroom := session.world_id == String(own.get("room", "")) and school().in_classroom_here(session.world_id, w)
	return {"held": items() != null and items().has("phone"), "tech": talent() != null and talent().has("tech"), "classroom": classroom, "scene": session.world_id, "x": w.x, "y": w.y, "dead": story().dead}


func _phone_step(delta: float) -> void:
	var net := phone()
	if net == null:
		return
	net.set_context(_phone_context())
	net.tick(delta)
	if ui.terminal_open():
		if not net.terminal_open or Input.is_action_just_pressed("pause"):
			_terminal_closed()
		else:
			_paint_terminal()
	_apply_phone_events()


func _paint_terminal() -> void:
	var net := phone()
	ui.show_terminal("\n".join(PackedStringArray(net.puzzle["history"])), net.status_text())


func _terminal_command(line: String) -> void:
	var net := phone()
	if net == null:
		return
	net.set_context(_phone_context())
	net.run_line(line)
	_paint_terminal()
	_apply_phone_events()


func _terminal_closed() -> void:
	ui.hide_terminal()
	if phone() != null:
		phone().terminal_open = false
	if session != null and not story().over() and not story().dead:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not ui.touch_enabled() else Input.MOUSE_MODE_VISIBLE


func _apply_phone_events() -> void:
	var net := phone()
	if net == null:
		return
	for e: Dictionary in net.take_events():
		match e["kind"]:
			"toast", "notice":
				ui.show_notice(String(e["text"]))
			"save":
				if not story().dead:
					save_game()
			"reveal":
				if patrol() != null:
					patrol().set_context(_patrol_context(campus().room(session.world_id), player.capture_pose()))
					patrol().reveal_wireless()
			"location":
				ui.show_notice("巡察查询：" + (patrol().location_label() if patrol() != null and bool(net.device["network"]) else "尚未接入学校网络"))
			"sync":
				if routes() != null:
					routes().sync("phone")
					_apply_route_events(routes())
			"rest_pc":
				if facilities() != null:
					facilities().set_context(_facility_context())
					facilities().rest("pc")
					_apply_facility_events()
			"terminal":
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_paint_terminal()
			"choice":
				_choice_count += 1
				var mine := _choice_count
				var menu := String(e["menu"])
				var cx := float(e.get("x", 0.0))
				var cy := float(e.get("y", 0.0))
				_choice_handler = func(index: int) -> void:
					var n := phone()
					if n == null or mine != _choice_count:
						return
					n.set_context(_phone_context())
					if menu == "phone":
						n.phone_choose(index)
					else:
						n.computer_choose(index, cx, cy)
					_apply_phone_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])
			"ending":
				ui.hide_terminal()
				_reach_ending(String(e["id"]))
				return


# ---- the broadcast station and 《放学》 (features/story/broadcast_module.gd) ----

var _mic_open := false
var _radio_job: Variant = null   # {index, t, seconds, x, y, scene}
var _crowd_nodes: Node3D


func _broadcast_context() -> Dictionary:
	var ctx := _facility_context()
	var weird := anomaly()
	var gates: Dictionary = CampusData.campus().get("gates", {})
	var gn: Dictionary = gates.get("n", {"x": 514, "y": 95})
	ctx.merge({"day": school().day, "diff": story().diff, "dead": story().dead, "hiding": player.hiding, "night": SchoolClock.is_night(school().tsec),
		"anomaly_active": weird != null and weird.is_active(), "anomaly_id": weird.active_id() if weird != null else "",
		"inspection_pending": school().inspection_pending(), "inspection_quiet": school().inspection_pending(),
		"gate_n": Vector2(float(gn["x"]) * 2.0, float(gn["y"]) * 2.0)}, true)
	return ctx


func _broadcast_step(delta: float) -> void:
	var radio := broadcast()
	if radio == null:
		return
	radio.set_context(_broadcast_context())
	if _mic_open:
		if not radio.near_station() or Input.is_action_just_pressed("pause"):
			_close_mic()
		else:
			var want := Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept")
			if want and not radio.held:
				radio.hold(true)
			elif not want and radio.held:
				radio.hold(false)
			var why := radio.reason()
			ui.show_search(radio.progress / radio.reading_seconds() if radio.held else 0.0)
			ui.show_prompt("按住 E 朗读 · %s · 已播完 %d/4 段%s" % [radio.paper_text(String(radio.b["selected"])) if radio.papers().has(radio.b["selected"]) else "手里没有这一页", int(radio.b["completed"]), "" if why == "" else " · " + why])
	if _radio_job != null:
		var j: Dictionary = _radio_job
		var here := Vector2(float(radio._c["x"]), float(radio._c["y"]))
		if session.world_id != String(j["scene"]) or here.distance_to(Vector2(float(j["x"]), float(j["y"]))) > 5.0:
			_radio_job = null
			ui.show_search(0.0)
			ui.show_notice("我：手一松，没翻完。")
		else:
			j["t"] = float(j["t"]) + delta
			ui.show_search(float(j["t"]) / float(j["seconds"]))
			if float(j["t"]) >= float(j["seconds"]):
				_radio_job = null
				ui.show_search(0.0)
				radio.job_done(int(j["index"]))
	radio.tick(delta)
	_show_crowd(radio)
	_apply_broadcast_events()


func _show_crowd(radio: BroadcastModule) -> void:
	var p := radio.crowd()
	var show := not p.is_empty() and session.world_id == "out"
	if not show:
		if is_instance_valid(_crowd_nodes):
			_crowd_nodes.queue_free()
		_crowd_nodes = null
		return
	var world := _campus_world()
	if world == null:
		return
	if not is_instance_valid(_crowd_nodes):
		_crowd_nodes = Node3D.new()
		_crowd_nodes.name = "DismissalCrowd"
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.2, 0.26)
		var body := CapsuleMesh.new()
		body.radius = 0.22
		body.height = 1.65
		body.material = mat
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 26:
			var fig := MeshInstance3D.new()
			fig.mesh = body
			fig.position = Vector3(rng.randf_range(-2.6, 2.6), 0.825, rng.randf_range(-3.5, 3.5))
			_crowd_nodes.add_child(fig)
		world.add_child(_crowd_nodes)
	var s := CampusGeometry.to_scene(null, Vector2(float(p["x"]), float(p["y"])))
	_crowd_nodes.position = Vector3(s.x, 0.0, s.y)
	_crowd_nodes.rotation.y = -float(p["angle"]) - PI * 0.5


func _open_mic() -> void:
	var radio := broadcast()
	if radio == null:
		return
	var papers := radio.papers()
	if papers.is_empty():
		ui.show_notice("我：手里没有通知稿。")
		return
	_choice_count += 1
	var mine := _choice_count
	_choice_handler = func(index: int) -> void:
		if mine != _choice_count or index < 0 or index >= papers.size():
			return
		radio.select(String(papers[index]))
		_mic_open = true
		ui.show_notice("话筒：按住 E 朗读，松开会重读当前段；走开或按 Esc 离开。")
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var reason := radio.reason()
	ui.show_choice("广播站 · 话筒%s\n手中的稿纸：" % ("" if reason == "" else "（" + reason + "）"), papers.map(func(id: String) -> String: return radio.paper_text(id)))


func _close_mic() -> void:
	_mic_open = false
	if broadcast() != null:
		broadcast().hold(false)
	ui.show_search(0.0)


func _apply_broadcast_events() -> void:
	var radio := broadcast()
	if radio == null:
		return
	for e: Dictionary in radio.take_events():
		match e["kind"]:
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = maxf(school().san + float(e["amount"]), float(e.get("min", -INF)))
			"save":
				if not story().dead:
					save_game()
			"fact":
				fact({"kind": "broadcast", "what": e["what"], "real": e.get("real", true)})
			"job":
				var w := Vector2(float(radio._c["x"]), float(radio._c["y"]))
				_radio_job = {"index": int(e["index"]), "t": 0.0, "seconds": float(e["seconds"]), "x": w.x, "y": w.y, "scene": session.world_id}
			"guard":
				if facilities() != null:
					facilities().set_context(_facility_context())
					facilities()._guard()
					_apply_facility_events()
			"note":
				audio.cue("ding", -12.0, [1.0, 1.0, 1.12, 1.26, 1.0, 0.75][int(e["note"])])
			"radio":
				audio.cue("static", -6.0, 1.0 if bool(e["real"]) else 0.87)
			"bell_start":
				_close_mic()
				audio.loop("dismissal", true, -10.0)
			"bell_stop":
				audio.loop("dismissal", false)
			"mic":
				_open_mic()
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var r := broadcast()
					if r != null and mine == _choice_count:
						r.set_context(_broadcast_context())
						r.choose(index)
						_apply_broadcast_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])
			"kill":
				_close_mic()
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"ending":
				audio.loop("dismissal", false)
				_reach_ending(String(e["id"]))
				return


# ---- the garage and the drive (features/garage) ----

func _garage_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var weird := anomaly()
	var bag := items()
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "run": player.sprinting,
		"torch": bag != null and bag.torch_on, "has_key": bag != null and bag.has("key"), "hotwire": talent() != null and talent().has("drive"), "dead": story().dead, "enter_cool": _enter_cool,
		"busy": (weird != null and weird.is_active()) or (school() != null and school().inspection_pending()),
		"can_stand": _can_stand.bind(room, float(p[1]))}


func _garage_step(delta: float, room: Variant, pose: Dictionary) -> void:
	var cars := garage()
	if cars == null:
		return
	_enter_cool = maxf(0.0, _enter_cool - delta)
	cars.set_context(_garage_context())
	cars.tick(delta)
	if cars.job != null:
		ui.show_search(cars.job_progress())
	var world := _campus_world()
	if world != null:
		var shown := session.world_id == GarageModule.ROOM and cars.roam_visible()
		var at := Vector2.ZERO
		if shown:
			at = CampusGeometry.to_scene(room, Vector2(float(cars.roam["x"]), float(cars.roam["y"])))
		world.show_garage_shadow(shown, at, float(pose["position"][1]))
	_apply_garage_events()


func _apply_garage_events() -> void:
	var cars := garage()
	if cars == null:
		return
	for e: Dictionary in cars.take_events():
		match e["kind"]:
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = maxf(school().san + float(e["amount"]), float(e.get("min", -INF)))
			"step":
				var room: Variant = campus().room(session.world_id)
				var s := CampusGeometry.to_scene(room, Vector2(float(e["x"]), float(e["y"])))
				audio.cue_at("step_heavy", Vector3(s.x, float(player.capture_pose()["position"][1]) + 0.2, s.y), -2.0)
			"fact":
				fact({"kind": "garage", "what": e["what"], "tried": int(e.get("tried", 0))})
			"save":
				save_game()
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var g := garage()
					if g != null and mine == _choice_count:
						g.set_context(_garage_context())
						g.choose(index)
						_apply_garage_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])
			"drive":
				_enter_drive()
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"ending":
				_leave_drive()
				_reach_ending(String(e["id"]))
				return


## CarChase.start: out on the road north of the north gate, the campus hidden behind the drive.
func _enter_drive() -> void:
	var gates: Dictionary = CampusData.campus().get("gates", {})
	var gn: Dictionary = gates.get("n", {"x": 514, "y": 95})
	var at := CampusGeometry.to_scene(null, Vector2(float(gn["x"]) * 2.0, (float(gn["y"]) + 40.0) * 2.0))
	if session.world_id != "out":
		travel("out", {"position": [at.x, 0.05, at.y], "yaw": CampusGeometry.yaw_from_ang(-PI * 0.5), "pitch": 0.0}, false)
	if _drive_view == null:
		_drive_view = CarChaseView.new()
		_drive_view.name = "CarChaseView"
		_drive_view.position = Vector3(0, 400.0, 0)
		add_child(_drive_view)
	var world := _campus_world()
	if world != null:
		world.visible = false
	player.enabled = false
	player.clear_input()
	var night := Environment.new()
	night.background_mode = Environment.BG_COLOR
	night.background_color = Color(0.03, 0.035, 0.05)
	night.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	night.ambient_light_color = Color(0.25, 0.27, 0.3)
	night.fog_enabled = true
	night.fog_light_color = Color(0.04, 0.045, 0.06)
	night.fog_density = 0.02
	player.camera.environment = night
	audio.loop("engine", true, -14.0)


func _leave_drive() -> void:
	if _drive_view != null:
		_drive_view.queue_free()
		_drive_view = null
	var world := _campus_world()
	if world != null:
		world.visible = true
	if player != null and player.camera != null:
		player.camera.environment = null
	if audio != null:
		audio.loop("engine", false)


func driving() -> bool:
	return _drive_view != null and garage() != null and garage().driving()


func _drive_step(delta: float) -> void:
	var cars := garage()
	cars.set_context(_garage_context())
	var steer := Input.get_axis("move_left", "move_right")
	cars.chase_step(delta, {"throttle": Input.is_action_pressed("move_forward"), "braking": Input.is_action_pressed("move_back"), "steering": steer})
	if cars.chase != null:
		var d: Dictionary = cars.chase
		_drive_view.update(d)
		var eye := _drive_view.position + CarChaseView.eye(d)
		player.global_position = eye - Vector3(0, player.camera.position.y, 0)
		player.rotation.y = 0.0
		player.camera.rotation.x = -0.04
		ui.show_status("校外道路", "速度 %d · 车况 %d/3 · %d%%" % [roundi(float(d["speed"]) * 3.6), int(d["hp"]), roundi(float(d["distance"]) / CarChaseRules.DISTANCE * 100.0)], "warn" if float(d["pursuit"]) > 40.0 else "", "")
		if not story().dead:
			ui.show_death_scene("vignette", float(d["pursuit"]) / CarChaseRules.PURSUIT_LIMIT * 0.6)
	_apply_garage_events()


## Escape routes: delayed lines, terminals, gates, the face quiz and endings.
func _routes_step(delta: float) -> void:
	var route := routes()
	if route == null:
		return
	route.tick(delta)
	_apply_route_events(route)


func _apply_route_events(route: RoutesModule) -> void:
	for e: Dictionary in route.take_events():
		match e["kind"]:
			"notice":
				ui.show_notice(String(e["text"]))
			"toast":
				ui.show_notice(String(e["text"]))
			"san":
				var after := school().san + float(e["amount"])
				school().san = maxf(after, float(e.get("min", -INF)))
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var r := routes()
					if r != null and mine == _choice_count:
						r.choose(index, story().diff if story() != null else "easy")
						_apply_route_events(r)
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"ending":
				_reach_ending(String(e["id"]))
				return


## story.js triggerEnding: the run is over; the save is cleared; the ending is recorded.
func _reach_ending(id: String) -> void:
	var fate := story()
	var card := fate.trigger_ending(id) if fate != null else {}
	if card.is_empty():
		return
	player.enabled = false
	player.clear_input()
	audio.stop_all()
	audio.cue("chime", -4.0)
	ui.hide_choice()
	ui.hide_bag()
	if items() != null:
		items().cancel_search()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	saves.clear()
	ui.set_save_available(saves.exists())
	var path := saves.side_path("ends.json")
	var seen_ends: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			seen_ends = parsed
	seen_ends[id] = 1
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(seen_ends))
		file.close()
	if achievements() != null and routes() != null:
		achievements().face_wrong = maxi(0, routes().wrong_answers())
	fact({"kind": "ending", "id": id, "day": school().day, "diff": story().diff, "talent": talent().id if talent() != null else "none"})
	var meta := "第 %d 天" % school().day
	if (items() != null and items().has_clock()) or (talent() != null and talent().has("watch")):
		meta += " · " + SchoolClock.fmt_clock(school().tsec)
	ui.show_ending(String(card["title"]), String(card["tag"]), card["lines"], meta)


func _anomaly_context(room: Variant, pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var day_rules := school()
	var bag := items()
	var watcher := patrol()
	var item_names := {}
	if bag != null:
		for id: String in bag.bag:
			item_names[id] = bag.item_name(id)
	var tile := ""
	if room != null:
		tile = CampusGeometry.tile_at(room, w)
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "tsec": day_rules.tsec, "day": day_rules.day,
		"diff": story().diff if story() != null else "easy", "san": day_rules.san, "viol": day_rules.viol, "moving": player.moving, "running": player.sprinting,
		"seated": day_rules.seated, "night": SchoolClock.is_night(day_rules.tsec), "need_where": SchoolClock.need_where(day_rules.tsec), "tile": tile,
		"on_field": day_rules.on_field(session.world_id, w), "in_classroom": day_rules.in_classroom_here(session.world_id, w),
		"game_clock": day_rules.game_clock(), "pressure_anomaly": float(day_rules.pressure()["anomaly"]), "bag": bag.bag if bag != null else [],
		"item_names": item_names, "dead": story() != null and story().dead, "hiding": watcher != null and bool(watcher.hide["on"]),
		"patrol_chase": watcher != null and watcher.local_chase(), "choice_open": ui.choice_open(), "brolly": false,
		"inspection_quiet": day_rules.inspection_pending() or day_rules.inspection_upcoming() or float(day_rules.inspection.get("calm", 0.0)) > 0.0,
		"in_lift": session.world_id in ElevatorModule.RIDE_ROOMS, "can_stand": _can_stand.bind(room, float(p[1]))}


func _anomaly_step(delta: float, day_rules: SchoolModule, room: Variant, pose: Dictionary) -> void:
	var weird := anomaly()
	if weird == null:
		return
	var ctx := _anomaly_context(room, pose)
	weird.set_context(ctx)
	weird.warning_seen(false)
	weird.tick(delta)
	for e: Dictionary in weird.take_events():
		match e["kind"]:
			"notice":
				ui.show_notice(String(e["text"]))
			"hurt":
				day_rules.change_san(-float(e["amount"]), 0.0)
				ui.flash_hurt(0.4 if e.get("quiet", false) else 0.65)
				audio.cue("thud", -8.0 if e.get("quiet", false) else -3.0)
				ui.show_notice(String(e["msg"]))
			"san":
				var after := day_rules.san + float(e["amount"])
				if e.has("max"):
					after = minf(after, float(e["max"]))
				if e.has("min"):
					after = maxf(after, float(e["min"]))
				day_rules.san = after
			"violation":
				day_rules.add_violation(float(e["amount"]))
			"remove_item":
				if items() != null:
					items().remove(String(e["id"]))
			"advance_time":
				day_rules.advance_game_time(float(e["minutes"]))
			"turn":
				var cur := player.capture_pose()
				var turned: Dictionary = cur.duplicate(true)
				turned["yaw"] = wrapf(float(cur["yaw"]) + float(e["angle"]), -PI, PI)
				player.place(turned)
			"choice":
				_open_anomaly_choice(e)
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return


func _open_anomaly_choice(e: Dictionary) -> void:
	var ids: Array = e["ids"]
	_choice_count += 1
	var mine := _choice_count
	_choice_handler = func(index: int) -> void:
		var weird := anomaly()
		if weird == null or mine != _choice_count:
			return
		if index < 0:
			index = randi() % ids.size() # "算了" or the timeout: random like the old timed choice
		if index < ids.size():
			weird.choose(String(ids[index]))
	_choice_left = float(e["timeout"])
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_choice(String(e["text"]), e["labels"], false)
	ui.show_choice_timer(_choice_left)


func _open_choice(choice: Dictionary) -> void:
	var values: Array = choice["values"]
	_choice_handler = func(index: int) -> void:
		var lift := elevator()
		if index >= 0 and index < values.size() and lift != null:
			_apply_result(lift.press(values[index], session.world_id, player.capture_pose()))
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_choice(String(choice["text"]), choice["labels"])


func _choice_made(index: int) -> void:
	_choice_left = 0.0
	ui.hide_choice()
	if index == -2:
		index = -1
	var handler := _choice_handler
	_choice_handler = Callable()
	if session != null and session.running and not get_tree().paused:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED
	if handler.is_valid():
		handler.call(index)


func _lift_close() -> void:
	var lift := elevator()
	var room: Variant = campus().room(session.world_id) if campus() != null and session != null else null
	if lift == null or room == null:
		return
	var p: Array = player.capture_pose()["position"]
	lift.close_door(session.world_id, CampusGeometry.to_world(room, float(p[0]), float(p[2])))


## Switch scene inside the running session (old doEnterRoom / doExitRoom). Seamless moves keep input.
func travel(world_id: String, pose: Dictionary, seamless: bool) -> String:
	var error := router.switch_to(world_id)
	if not error.is_empty():
		ui.show_notice(error)
		return error
	var from_world := session.world_id
	if patrol() != null and from_world != world_id and school() != null:
		var pp: Array = player.capture_pose()["position"]
		var from_room: Variant = campus().room(from_world)
		patrol().set_context(_patrol_context(from_room, player.capture_pose()))
		patrol().left_scene(from_world, world_id)
	session.world_id = world_id
	_enter_cool = 0.0 if seamless else 0.9
	if seamless:
		player.place(pose)
	else:
		player.restore_pose(pose)
	_sync_world()
	_hint_cooldown = 0.0
	return ""


func _location_name() -> String:
	var rules := campus()
	if rules == null or session == null or not rules.knows(session.world_id):
		return "移植测试场景"
	return "武大附中 · 校园" if session.world_id == "out" else String(rules.room(session.world_id)["name"])


func _interact(id: StringName) -> void:
	if session != null and not get_tree().paused:
		session.interact(id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo() and session != null:
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_node_ready():
		pause_game()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_H and facilities() != null and player.enabled and not story().over():
		facilities().set_context(_facility_context())
		facilities().think()
		_apply_facility_events()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_M and audio != null:
		audio.muted = not audio.muted
		ui.show_notice("声音：关" if audio.muted else "声音：开")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if session != null:
		_unwire(session)
		session.stop()
	CampusData.clear_caches()
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
