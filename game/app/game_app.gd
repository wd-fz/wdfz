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
var settings := GameSettings.new()
var _hint_cooldown := 0.0
var _choice_handler: Callable
var _death_hold := 0.0
var _death_wait := 0.0
## "" while alive, "fade" while the (not yet ported) death scene plays, "card" on the record card.
var _death_phase := ""
var _choice_left := 0.0
var _choice_count := 0
var speedrun := Speedrun.new()
var audio: AudioFx
var _seen_anomaly := ""
var _seen_lock := false
var _seen_phase := 0
var _seen_day := 1
var _seen_hide := false
var _seen_lock_ach := false
var _ach_started := ""
var _enter_cool := 0.0
var _audio_period := ""
var _bolt_next := 6.0
var _drive_view: CarChaseView
var playtest := Playtest.new()
var debug_panel: DebugPanel
var debug_flow: DebugFlow
var maze_flow: MazeFlow
var knife_flow: KnifeFlow
var inception_flow: InceptionFlow
var rules_dlc_flow: RulesDlcFlow
var wuda_roll: Callable = func() -> float: return randf()
var _school_taps: Array = []


func _ready() -> void:
	audio = AudioFx.new()
	audio.name = "AudioFx"
	add_child(audio)
	maze_flow = MazeFlow.new()
	add_child(maze_flow)
	maze_flow.setup(self)
	knife_flow=KnifeFlow.new()
	knife_flow.app=self
	add_child(knife_flow)
	inception_flow=InceptionFlow.new()
	inception_flow.app=self
	add_child(inception_flow)
	debug_flow=DebugFlow.new()
	debug_flow.app=self
	add_child(debug_flow)
	rules_dlc_flow=RulesDlcFlow.new()
	rules_dlc_flow.app=self
	add_child(rules_dlc_flow)
	settings.load_file(DisplayServer.is_touchscreen_available())
	ui.set_wuda_armed(settings.wuda_armed)
	ui.school_tapped.connect(_school_tapped)
	ui.ending_wake_requested.connect(knife_flow.wake)
	ui.settings_requested.connect(func() -> void: ui.show_settings(settings.values))
	ui.setting_changed.connect(_setting_changed)
	ui.touch_layout_changed.connect(func(layout: Dictionary) -> void:
		settings.touch_layout = TouchLayout.normalize(layout)
		settings.save_file()
		ui.apply_touch_scale(settings.get_int("touch_size"),settings.touch_layout))
	ui.manual_requested.connect(_open_manual)
	ui.torch_requested.connect(_touch_torch)
	ui.hot_requested.connect(_touch_hot)
	ui.bag_closed.connect(_close_bag)
	ui.debug_requested.connect(_toggle_debug)
	ui.dlc_requested.connect(rules_dlc_flow.menu)
	ui.fullscreen_requested.connect(func() -> void: _setting_changed("full_screen", 1 - settings.get_int("full_screen")))
	ui.notes_requested.connect(_show_notes)
	ui.results_requested.connect(_open_results)
	ui.records_requested.connect(_open_records)
	ui.legacy_import_requested.connect(func(text: String) -> void:
		var why := import_legacy_save(text)
		ui.show_import_result(why))
	ui.grade_sound.connect(func(b: String) -> void: audio.play("ui.grade." + b))
	ui.map_requested.connect(_show_map)
	ui.notes_focus_requested.connect(_notes_focus)
	_apply_settings()
	# ui.click on every button press (audio.js click), including buttons made later (choices).
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton and n.is_inside_tree() and ui.is_ancestor_of(n):
			(n as BaseButton).pressed.connect(func() -> void: audio.play("ui.click")))
	for b: Node in ui.find_children("*", "BaseButton", true, false):
		(b as BaseButton).pressed.connect(func() -> void: audio.play("ui.click"))
	ui.new_requested.connect(_pick_talent.bind("easy", false))
	ui.new_hard_requested.connect(_pick_talent.bind("hard", false))
	ui.speedrun_requested.connect(_speedrun_menu)
	ui.achievements_requested.connect(_show_achievements)
	ui.archive_requested.connect(_show_archive)
	ui.terminal_command.connect(_terminal_command)
	ui.opening_finished.connect(_opening_done)
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
	ui.item_drop_requested.connect(_drop_item)
	return_to_menu()


func _make_session() -> GameSession:
	return SessionFactory.create()

func campus() -> CampusModule:
	return session.modules.get_module(&"campus.world") as CampusModule if session != null else null


func maze() -> MazeModule:
	return session.modules.get_module(&"campus.maze") as MazeModule if session != null else null


func dread() -> DreadModule:
	return session.modules.get_module(&"story.dread") as DreadModule if session != null else null


func runscore() -> RunScoreModule:
	return session.modules.get_module(&"progress.score") as RunScoreModule if session != null else null


func camera() -> CameraModule:
	return session.modules.get_module(&"phone.camera") as CameraModule if session != null else null


func exploration() -> ExplorationModule:
	return session.modules.get_module(&"campus.exploration") as ExplorationModule if session != null else null


func investigation() -> InvestigationModule:
	return session.modules.get_module(&"story.investigation") as InvestigationModule if session != null else null


func mono() -> MonoModule:
	return session.modules.get_module(&"story.mono") as MonoModule if session != null else null


func atmos() -> AtmosModule:
	return session.modules.get_module(&"story.atmos") as AtmosModule if session != null else null


func classmates() -> ClassmatesModule:
	return session.modules.get_module(&"school.classmates") as ClassmatesModule if session != null else null


func marks() -> MarksModule:
	return session.modules.get_module(&"campus.marks") as MarksModule if session != null else null


func paper() -> PaperPlaneModule:
	return session.modules.get_module(&"story.paper_plane") as PaperPlaneModule if session != null else null


func gaze() -> WindowGazeModule:
	return session.modules.get_module(&"story.window_gaze") as WindowGazeModule if session != null else null


func tales() -> TalesModule:
	return session.modules.get_module(&"campus.tales") as TalesModule if session != null else null


func days() -> DayModule:
	return session.modules.get_module(&"school.days") as DayModule if session != null else null


## Per-second SAN drains of today (the anniversary halves them).
func _drain_mul() -> float:
	return days().drain_mul(school().day, school().tsec) if days() != null and school() != null else 1.0


func exchange() -> ExchangeModule:
	return session.modules.get_module(&"story.exchange") as ExchangeModule if session != null else null


func body() -> BodyModule:
	return session.modules.get_module(&"body.injury") as BodyModule if session != null else null


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
	_score_fact(f)
	playtest.event("事实", String(f.get("kind", "")), _playtest_state())
	rules_dlc_flow.fact(f)
	ach.fact(f, runscore() != null and runscore().trusted and not rules_dlc_flow.module().active())
	for e: Dictionary in ach.take_events():
		ui.show_notice("成就：%s" % e["name"])
		audio.achieve(String(e.get("tier", "n")))
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


func knife() -> KnifeModule:
	return session.modules.get_module(&"story.knife") as KnifeModule if session != null else null


func wuda_kid() -> WudaKidModule:
	return session.modules.get_module(&"story.wuda_kid") as WudaKidModule if session != null else null


func inception() -> InceptionModule:
	return session.modules.get_module(&"story.inception") as InceptionModule if session!=null else null


func _school_tapped(now_ms: float = -1.0) -> void:
	if not ui.menu.visible: return
	if not WudaKidModule.tap(_school_taps,Time.get_ticks_msec() if now_ms<0 else now_ms): return
	settings.wuda_armed=not settings.wuda_armed
	settings.save_file()
	ui.set_wuda_armed(settings.wuda_armed,true)
	audio.play("ui.blink")


func items() -> InventoryModule:
	return session.modules.get_module(&"items.bag") as InventoryModule if session != null else null


func school() -> SchoolModule:
	return session.modules.get_module(&"school.day") as SchoolModule if session != null else null


func elevator() -> ElevatorModule:
	return session.modules.get_module(&"campus.elevator") as ElevatorModule if session != null else null


func lift_crowd() -> LiftCrowdModule:
	return session.modules.get_module(&"campus.lift_crowd") as LiftCrowdModule if session != null else null


var _lift_crowd_fx: LiftCrowdFx


## The prologue: the game waits (paused) until the pages are read or skipped.
var _opening_cut: OpeningCut
var _ending_cut: EndingCut


## The opening scene is on (the live cutscene, or the text pages that stand in for it).
func opening_busy() -> bool:
	return ui.opening_on() or (_opening_cut != null and _opening_cut.on)


func _play_opening() -> void:
	if session == null:
		return
	player.enabled = false
	get_tree().paused = true
	var world := _campus_world()
	var room: Variant = campus().room(session.world_id) if campus() != null else null
	if world != null and room != null and session.world_id == "teach1" and DisplayServer.get_name() != "headless":
		var seen := saves.side_path("opening_seen")
		if _opening_cut != null and is_instance_valid(_opening_cut):
			_opening_cut.queue_free()
		_opening_cut = OpeningCut.new()
		_opening_cut.name = "OpeningCut"
		add_child(_opening_cut)
		_opening_cut.finished.connect(func(skipped: bool) -> void:
			DirAccess.make_dir_recursive_absolute(seen.get_base_dir())
			var f := FileAccess.open(seen, FileAccess.WRITE)
			if f != null:
				f.store_string("1")
				f.close()
			_opening_done(skipped))
		_opening_cut.audio = audio
		_opening_cut.begin(world, room, player, ui, FileAccess.file_exists(seen))
		return
	ui.show_opening()


func _opening_done(_skipped: bool) -> void:
	get_tree().paused = false
	if session == null:
		return
	player.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED
	ui.show_notice("我：第四节。我坐在自己的位子上——至少，名牌上写的是我的名字。")
	speedrun.start()
	fact({"kind": "opening"})


## TalentPick: the new-game talent screen (seven cards and a random pick).
func _speedrun_path() -> String:
	return saves.side_path("speedrun.json")


func _read_speedrun() -> Dictionary:
	var path := _speedrun_path()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	return {"version": 1, "recent": [], "best": {}}


func _write_speedrun(record: Dictionary) -> void:
	var path := _speedrun_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record))
		file.close()


## A speedrun result: stored, reported as a fact; returns the summary line.
func _speedrun_result(res: Dictionary, record: Dictionary) -> String:
	if res.is_empty():
		return ""
	_write_speedrun(record)
	var rec: Dictionary = res["rec"]
	fact({"kind": "speedrun", "status": rec["status"], "route": rec["route"], "ms": rec["ms"], "diff": rec["diff"]})
	var suffix := "（个人最佳）" if bool(res["pb"]) else ""
	if rec["status"] == "invalid":
		suffix = "（无效：%s）" % Speedrun.reason_text(String(rec.get("reason", "")))
	return "速通 %s%s" % [Speedrun.fmt(int(rec["ms"])), suffix]


func _speedrun_menu() -> void:
	_choice_count += 1
	var mine := _choice_count
	_choice_handler = func(index: int) -> void:
		if mine != _choice_count:
			return
		match index:
			0, 1:
				_pick_talent("easy" if index == 0 else "hard", true)
			2:
				ui.show_list("速通记录（规则版本 %d · 本机）" % Speedrun.RULES, Speedrun.rows(_read_speedrun()))
	ui.show_choice("速通：从第一次能操作起计时，到真结局停表；暂停也照常计时。速通不写普通存档，也不能读档接着跑。", ["预知梦 · 速通", "梦魇 · 速通", "速通记录"])


func _pick_talent(difficulty: String, speed: bool = false) -> void:
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
		if speed:
			speedrun.arm(difficulty)
		else:
			speedrun.disarm()
		start_new_game(difficulty, pick)
		_play_opening()
	ui.show_choice("%s · 选择天赋（每局一个；限制写在卡片上）" % ("梦魇" if difficulty == "hard" else "预知梦"), labels)


## Carry what can be carried of an old Web save into a new run (game/features/compatibility/legacy_save.gd). Returns "" or why not.
func import_legacy_save(text: String) -> String:
	var parser := JSON.new()
	if parser.parse(text.strip_edges()) != OK:
		return "不是有效的 JSON 存档"
	var p := LegacySave.plan(parser.data, CampusData.rooms(), CampusData.campus().get("items", {}), TalentModule.KEYS)
	if not String(p["error"]).is_empty():
		return String(p["error"])
	var candidate := _make_session()
	if candidate == null:
		return "无法创建存档会话"
	candidate.start(String(p["world"]))
	var base := candidate.capture({"position":[0.0,0.01,0.0],"yaw":0.0,"pitch":0.0})
	var converted := LegacyState.new().convert(p, base, CampusData.rooms(), CampusData.campus(), CampusData.maze_geometry())
	if not String(converted["error"]).is_empty():
		return String(converted["error"])
	var snapshot: Dictionary = converted["snapshot"]
	var why := candidate.validate(snapshot, router.known_ids())
	if not why.is_empty():
		return "旧存档无法恢复：" + why
	why = router.switch_to(String(snapshot["world_id"]))
	if not why.is_empty():
		return why
	# All parsing, conversion and validation finish before touching the current run or sidecars.
	speedrun.disarm()
	ui.speedrun_text = ""
	candidate.restore(snapshot)
	_install_session(candidate, snapshot["player"])
	_restore_loaded_world()
	var note := "已恢复旧版进度：路线、背包、时钟、巡察和异象状态已接续。"
	if not (p["dropped"] as Array).is_empty():
		note += "\n未识别物品保留在导入原文中：" + "、".join(p["dropped"])
	ui.show_notice(note)
	return ""


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
	var kid := candidate.modules.get_module(&"story.wuda_kid") as WudaKidModule
	if kid.start(settings.wuda_armed,float(wuda_roll.call()) if not settings.wuda_armed and speedrun.run.is_empty() else 1.0,not speedrun.run.is_empty()):
		var bag0 := candidate.modules.get_module(&"items.bag") as InventoryModule
		if bag0.add("torch") and bag0.hot[0]==null: bag0.set_hot(0,"torch")
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
	var mk := candidate.modules.get_module(&"campus.marks") as MarksModule
	if mk != null:
		mk.last_life = _read_side("last_life.json")
	var pp := candidate.modules.get_module(&"story.paper_plane") as PaperPlaneModule
	if pp != null:
		pp.roll(int((Time.get_ticks_usec() * 37) % 2147483647))
	var wg := candidate.modules.get_module(&"story.window_gaze") as WindowGazeModule
	if wg != null:
		wg.set_seed(int((Time.get_ticks_usec() * 31) % 2147483647))
	var dm := candidate.modules.get_module(&"school.days") as DayModule
	if dm != null:
		dm.set_seed(int((Time.get_ticks_usec() * 29) % 4294967295))
	var visit := candidate.modules.get_module(&"story.exchange") as ExchangeModule
	if visit != null:
		visit.roll(int((Time.get_ticks_usec() * 23) % 2147483647))
	var fnm := candidate.modules.get_module(&"story.fake_normal") as FakeNormalModule
	if fnm != null:
		fnm.set_seed(int((Time.get_ticks_usec() * 19) % 2147483647))
	var net := candidate.modules.get_module(&"phone.network") as PhoneModule
	if net != null:
		net.set_seed(int((Time.get_ticks_usec() * 17) % 2147483647))
		var mates := candidate.modules.get_module(&"school.classmates") as ClassmatesModule
		if mates != null:
			mates.set_seed(net.run_seed)
		var mood := candidate.modules.get_module(&"story.atmos") as AtmosModule
		if mood != null:
			mood.set_seed(net.run_seed)
	var scoring := candidate.modules.get_module(&"progress.score") as RunScoreModule
	var dlc:=candidate.modules.get_module(&"dlc.campus_rules") as RulesDlcModule
	dlc.start(settings.rules_armed,net.run_seed)
	if scoring != null:
		scoring.begin("s%d%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000])
		_write_side("runlog_cur.json", null)
		_runlog.begin(scoring.run)
	var rules := candidate.modules.get_module(&"campus.world") as CampusModule
	var pose := rules.start_pose() if rules != null and initial_world == rules.start_world() else router.current.spawn_pose()
	# Game.start: the run begins seated on the player's own seat in teach1.
	var day_rules := candidate.modules.get_module(&"school.day") as SchoolModule
	if day_rules != null and rules != null and initial_world == rules.start_world():
		var seated := day_rules.start_seated(initial_world)
		if not seated.is_empty():
			pose = seated
	_install_session(candidate, pose)
	if dread() != null:
		dread().set_context(_dread_context())
		dread().enter(session.world_id)
	if atmos() != null:
		atmos().enter(session.world_id)
	if rules != null and rules.knows(initial_world):
		ui.show_notice(String(rules.room(initial_world)["name"]) if rules.room(initial_world) != null else "武大附中 · 校园")
	else:
		ui.show_notice("走到前方告示牌，按 E 或触屏交互。这里用于验证移植接口。")


## Break the callback links between the rule modules of a finished session (they reference
## each other through Callables; leaving them would keep the whole session alive).
func _unwire(old: GameSession) -> void:
	if old == null:
		return
	var old_paper:=old.modules.get_module(&"story.paper_plane") as PaperPlaneModule
	if old_paper!=null: old_paper.text_override=Callable()
	var fac := old.modules.get_module(&"campus.facilities") as FacilitiesModule
	if fac!=null: fac.rest_intercept=Callable()
	var lift := old.modules.get_module(&"campus.elevator") as ElevatorModule
	if lift != null:
		lift.unsafe_check = Callable()
		lift.closed_hook = Callable()
		lift.crowd = null
	var watcher := old.modules.get_module(&"patrol.world") as PatrolModule
	if watcher != null:
		watcher.elevator = null
		watcher.zone_active = func(_z: Dictionary) -> bool: return false
		watcher.camouflage = Callable()
		watcher.nav.door_open = func(_room: String, _c: int, _r: int) -> bool: return false
	var rules := old.modules.get_module(&"campus.world") as CampusModule
	if rules != null:
		rules.car_hint = Callable()
		rules.door_blocked = Callable()
		rules.desk_taken = Callable()
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
	_cancel_cinematics()
	_reset_sensory()
	if session != null:
		_unwire(session)
		session.stop()
	session = candidate
	_load_profile(achievements())
	_fn_day = school().day if school() != null else 1
	_leave_drive()
	if campus() != null and garage() != null:
		campus().car_hint = garage().car_hint
	if campus() != null and classmates() != null:
		campus().door_blocked = classmates().blocked
		campus().desk_taken = classmates().occupied
	if campus() != null and facilities() != null:
		campus().facility_hint = facilities().hint
		facilities().rest_intercept=inception_flow.rest
	var gift_now := talent()
	if gift_now != null:
		if school() != null:
			school().danger_mul = func(kind: String) -> float: return gift_now.danger_mul(kind) * _drain_mul()
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
	if lift_rules != null:
		lift_rules.crowd = lift_crowd()
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
	debug_flow.session_started()
	rules_dlc_flow.install()
	maze_flow.changed_world(true)
	inception_flow.changed_world()
	player.show()
	ui.set_save_available(saves.exists())
	resume_game()


func _dead() -> bool:
	return story() != null and story().over()


func save_game(quiet: bool = false) -> void:
	if session == null or not session.running or _dead() or not speedrun.run.is_empty():
		return
	var snapshot := session.capture(player.capture_pose())
	var error := session.validate(snapshot, router.known_ids())
	if error.is_empty():
		error = saves.write(snapshot)
	if not quiet or not error.is_empty():
		ui.show_notice("已保存测试进度。" if error.is_empty() else error)
	ui.set_save_available(saves.exists())


func load_game() -> void:
	speedrun.disarm()
	ui.speedrun_text = ""
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
	_restore_loaded_world()
	ui.show_notice("已恢复进度；读档不会再次触发交互奖励。")


func _restore_loaded_world() -> void:
	if atmos() != null and phone() != null:
		atmos().set_seed(phone().run_seed)
	if runscore() != null:
		_runlog.restore(runscore().run, _read_side("runlog_cur.json"))
	if dread() != null:
		dread().set_context(_dread_context())
		dread().enter(session.world_id, true)
		_apply_dread_events()
	if atmos() != null:
		atmos().enter(session.world_id)
	if garage() != null and garage().driving():
		_enter_drive()


func pause_game() -> void:
	if opening_busy() or is_instance_valid(maze_flow.cut):
		return
	# Game.pause: no pause menu once dead (a death cannot be saved around).
	if session == null or not session.running or _dead():
		return
	player.enabled = false
	player.clear_input()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.set_mode("pause")
	if talent() != null and session != null:
		ui.show_pause_detail(talent().pause_text())


func resume_game() -> void:
	if session == null or not session.running or _dead():
		return
	get_tree().paused = false
	player.enabled = not knife_flow.captured()
	player.clear_input()
	ui.set_mode("play")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _cancel_cinematics() -> void:
	if is_instance_valid(rules_dlc_flow): rules_dlc_flow.cancel()
	if is_instance_valid(debug_flow): debug_flow.cancel()
	if is_instance_valid(inception_flow): inception_flow.cancel()
	if is_instance_valid(_lift_crowd_fx):
		_lift_crowd_fx.clear()
	if is_instance_valid(maze_flow):
		maze_flow.cancel()
	if is_instance_valid(debug_panel):
		debug_panel.stop_audition()
	if is_instance_valid(_opening_cut):
		_opening_cut.cancel()
		_opening_cut.queue_free()
	_opening_cut = null
	if is_instance_valid(_ending_cut):
		_ending_cut.cancel()
		_ending_cut.queue_free()
	_ending_cut = null


func return_to_menu() -> void:
	_cancel_cinematics()
	_last_result = {}
	_fake_people_clear()
	_stop_snake(true)
	_close_phone()
	_audio_period = ""
	_reset_sensory()
	if is_instance_valid(_mates_nodes):
		_mates_nodes.queue_free()
	_mates_nodes = null
	_mates_key = ""
	if is_instance_valid(_marks_nodes):
		_marks_nodes.queue_free()
	_marks_nodes = null
	_marks_key = ""
	if is_instance_valid(_plane_nodes):
		_plane_nodes.queue_free()
	_plane_nodes = null
	_plane_pose = null
	if is_instance_valid(_gaze_nodes):
		_gaze_nodes.queue_free()
	_gaze_nodes = null
	if speedrun.active():
		var rec_a := _read_speedrun()
		_speedrun_result(speedrun.fail("abandoned", rec_a), rec_a)
	speedrun.disarm()
	ui.speedrun_text = ""
	_leave_drive()
	if is_instance_valid(_visit_nodes):
		_visit_nodes.queue_free()
	_visit_nodes = null
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
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	if _choice_left > 0.0 and ui.choice_open():
		_choice_left -= delta
		ui.show_choice_timer(maxf(0.0, _choice_left))
		if _choice_left <= 0.0:
			ui.choice_selected.emit(-2) # timed out: random pick
	if session != null and session.running and not get_tree().paused:
		session.advance(delta, router.current.advances_calendar)
		if school() == null or campus() == null or not campus().knows(session.world_id):
			ui.show_location(_location_name())
		ui.speedrun_text = ("无效 · " if speedrun.run.get("reason", "") != "" else "") + Speedrun.fmt(speedrun.elapsed()) if speedrun.active() and speedrun.run["status"] == "running" else ""
		ui.show_runtime(session.clock.active_seconds)
		_campus_step(delta)
		if days() != null and days().waiting != null:
			_study_fast_forward(delta)
	elif audio != null and ui.menu.visible:
		audio.update(delta, {"menu": true})


# ---- formal campus (features/campus) ----

func _campus_world() -> CampusWorld:
	return router.get_child(0) as CampusWorld if router.get_child_count() > 0 else null


func _sync_world() -> void:
	var world := _campus_world()
	var rules := campus()
	if world != null and rules != null:
		world.apply_doors(rules.open_doors())
		world.set_player_scene(player.position)
	var lift := elevator()
	if world != null and lift != null:
		world.apply_lift_doors(lift)
	if world != null and world.broadcast_props != null and broadcast() != null:
		world.broadcast_props.set_fuse(bool(broadcast().b["fuse"]))
	if world != null and world.banner != null and days() != null and school() != null:
		var want := days().today(school().day, school().tsec) == "anniversary"
		if want != world.banner.is_on():
			world.banner.set_on(want)


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
	maze_flow.step(delta)
	if _dead():
		return
	# The original module tick resolves a dream before SAN/death settlement. A wake's
	# 90-minute advance must not also receive a frame of ordinary calendar time.
	var calendar_before:=router.current.advances_calendar
	inception_flow.step(delta)
	if _dead(): return
	_school_step(delta, rules, calendar_before)
	knife_flow.step(delta)
	rules_dlc_flow.step(delta)
	_handle_deaths()
	if _dead():
		return
	var lift := elevator()
	if lift != null:
		var stepped := lift.step(delta, session.world_id, player.capture_pose())
		_apply_result(stepped)
		for text: String in lift.take_notices():
			ui.show_notice(text)
		var world := _campus_world()
		if world != null:
			world.apply_lift_doors(lift)
		ui.set_lift_close(lift.show_close_button(session.world_id, player.capture_pose()) and not ui.choice_open())
		if player.enabled and Input.is_action_just_pressed("lift_close"):
			_lift_close()
	_lift_crowd_step(delta)
	if not player.enabled:
		return
	var crossing := rules.crossing(session.world_id, player.capture_pose())
	if not crossing.is_empty():
		travel(crossing["world"], crossing["pose"], true)
	_hint_cooldown -= delta
	if _hint_cooldown <= 0.0 and not player.has_focus():
		_hint_cooldown = 0.1
		if maze_flow.here():
			ui.show_prompt(maze_flow.hint())
			return
		var radio_hint := rules_dlc_flow.hint()
		if radio_hint=="": radio_hint=knife_flow.hint()
		if radio_hint=="": radio_hint=inception_flow.hint()
		if radio_hint=="" and broadcast()!=null: radio_hint=broadcast().hint()
		if radio_hint == "" and marks() != null:
			marks().set_context(_marks_context())
			radio_hint = marks().box_hint()
		if radio_hint == "" and body() != null:
			body().set_context(_body_context())
			radio_hint = body().hint()
		if radio_hint == "" and paper() != null:
			paper().set_context(_paper_context())
			radio_hint = paper().hint()
		if radio_hint == "" and tales() != null:
			tales().set_context(_tales_context())
			radio_hint = tales().hint()
		if radio_hint == "" and exchange() != null:
			exchange().set_context(_exchange_context())
			radio_hint = exchange().hint()
		ui.show_prompt(radio_hint if radio_hint != "" else rules.hint(session.world_id, player.capture_pose()))


func _lift_crowd_step(delta: float) -> void:
	var crowd := lift_crowd()
	var lift := elevator()
	if crowd == null or lift == null:
		return
	_lift_crowd_events()
	if _dead():
		return
	var p: Array = player.capture_pose()["position"]
	var room: Variant = campus().room(session.world_id)
	var w := CampusGeometry.to_world(room,float(p[0]),float(p[2]))
	var here := not crowd.state.is_empty() and session.world_id == String(crowd.state["host"])+str(int(crowd.state["floor"]))
	crowd.tick(delta,lift.lifts,lift.ride,here and lift.in_cabin(session.world_id,w),session.world_id)
	_lift_crowd_events()
	if not is_instance_valid(_lift_crowd_fx):
		_lift_crowd_fx = LiftCrowdFx.new()
		add_child(_lift_crowd_fx)
	_lift_crowd_fx.update(delta,crowd.state,session.world_id,_campus_world(),lift,audio,_dead(),settings.get_int("reduce_flash")==1)


func _lift_crowd_events() -> void:
	var crowd := lift_crowd()
	for event: Dictionary in crowd.take_events():
		match event["kind"]:
			"notice": ui.show_notice(event["text"])
			"fact": fact(event["fact"])
			"kill":
				kill(event["text"],event["fx"],event["source"])
				if not _dead():
					fact({"kind":"anomaly","phase":"end","id":"crowd","name":"满员","survived":false,"saved":true,"public":false})


func _campus_interact() -> void:
	var rules := campus()
	if session == null or get_tree().paused or rules == null or not rules.knows(session.world_id):
		return
	if rules_dlc_flow.interact(): return
	if knife_flow.captured() or knife_flow.interact() or inception_flow.interact():
		return
	if maze_flow.here():
		maze_flow.interact()
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
	var keepsakes := marks()
	if keepsakes != null:
		keepsakes.set_context(_marks_context())
		if keepsakes.use_box():
			_apply_marks_events()
			return
	var limbs := body()
	if limbs != null:
		limbs.set_context(_body_context())
		if limbs.ask_vault() or limbs.use_clinic():
			_apply_body_events()
			return
	var plane := paper()
	if plane != null:
		plane.set_context(_paper_context())
		if plane.use_here():
			_apply_paper_events()
			return
	var tale := tales()
	if tale != null:
		tale.set_context(_tales_context())
		if tale.use_here():
			_apply_tales_events()
			return
	var visit := exchange()
	if visit != null:
		visit.set_context(_exchange_context())
		if visit.use_here():
			_apply_exchange_events()
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
		audio.play("foley.door")
		var dk := String(result["door"]["key"]).rsplit(":", true, 2)
		if atmos() != null and dk.size() == 3:
			atmos().set_context(_atmos_context())
			atmos().door_action(dk[0], int(dk[1]), int(dk[2]), bool(result["door"]["open"]))
	if result.has("choice"):
		_open_choice(result["choice"])
	var text := String(result.get("notice", ""))
	if result.has("toast"):
		text = (text + "\n" if not text.is_empty() else "") + String(result["toast"])
	if result.has("search") and items() != null:
		var room: Variant = campus().room(session.world_id)
		var p: Array = player.capture_pose()["position"]
		items().start_search(session.world_id, int(result["search"][0]), int(result["search"][1]), CampusGeometry.to_world(room, float(p[0]), float(p[2])))
	if result.has("podium") and investigation() != null and CampusData.campus().get("own_podium", []) == [int(result["podium"][0]), int(result["podium"][1])] and session.world_id == "teach1":
		_invest_do(func(inv: InvestigationModule) -> void: inv.notice())
		return
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
		_open_phone()
		return
	if result.has("facility") and facilities() != null:
		if String(result["facility"][0]) in ["B","G"] and routes().open_stall(session.world_id):
			facilities().spots["stall"] = true
			_apply_route_events(routes())
			return
		var fac := facilities()
		var use_here := func() -> void:
			fac.set_context(_facility_context())
			fac.use(campus().room(session.world_id), String(result["facility"][0]), int(result["facility"][1]), int(result["facility"][2]))
			_apply_facility_events()
		var ch := String(result["facility"][0])
		var inv2 := investigation()
		if inv2 != null and ch == "M":
			inv2.set_context(_invest_context())
			if inv2.supply_offer(session.world_id):
				_supply_after = use_here
				_apply_invest_events()
				return
		use_here.call()
		if inv2 != null and ch == "k" and session.world_id == "guard1":
			inv2.set_context(_invest_context())
			if inv2.supply_offer(session.world_id):
				_apply_invest_events()
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
	if result.has("chalk") and marks() != null:
		marks().set_context(_marks_context())
		marks().use_chalk()
		_apply_marks_events()
		return
	if result.has("medkit") and body() != null:
		body().set_context(_body_context())
		body().use_medkit()
		_apply_body_events()
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
		_record({"id": "carKey", "text": "钥匙环刻着车牌「%s」。在车位前看车牌，再试钥匙。" % garage().key_label(), "kind": "事实", "source": "车钥匙"})
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
	if result.has("maze_enter"):
		maze_flow.begin_entry()
		return
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


func _school_step(delta: float, rules: CampusModule, advance_calendar: bool = true) -> void:
	var day_rules := school()
	if day_rules == null:
		return
	var kid_line := wuda_kid().tick(delta)
	if kid_line!="": ui.show_notice(kid_line)
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
		bag.search_tick(60.0 if debug_flow.instant_search else delta, session.world_id, CampusGeometry.to_world(room_here, float(here[0]), float(here[2])))
		for text: String in bag.take_notices():
			ui.show_notice(text)
		ui.show_search(bag.search_progress())
		player.speed_multiplier = (1.5 if snack else 1.0) * (body().speed_mul() if body() != null else 1.0) * (2.6 if debug_flow.fast else 1.0)
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
		"height": float(p[1]), "moving": player.moving, "running": player.sprinting, "calendar": router.current.advances_calendar and advance_calendar,
		"ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "pitch": float(pose["pitch"]),
		"can_stand": _can_stand.bind(room, float(p[1])), "line_clear": _line_clear.bind(room), "snack": snack, "pill_san": pill_san})
	var world := _campus_world()
	if world != null:
		world.set_player_scene(Vector3(float(p[0]), float(p[1]), float(p[2])))
		world.show_silhouettes(day_rules.inspection_points(), room, float(p[1]))
	player.can_sprint = day_rules.can_run(snack) and (body() == null or body().can_run())
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
	_body_step(delta)
	if story().dead or story().over():
		return
	_exchange_step(delta)
	if story().dead or story().over():
		return
	_day_step(delta)
	if story().dead or story().over():
		return
	_tales_step(delta)
	if story().dead or story().over():
		return
	_gaze_step(delta)
	if story().dead or story().over():
		return
	_paper_step(delta)
	_show_marks()
	_classmates_step(delta)
	_sensory_step(delta)
	_dread_step(delta)
	_atmos_step(delta)
	_mono_step(delta)
	_explore_step(delta)
	_score_step(delta)
	_anomaly_step(delta, day_rules, room, pose)
	_audio_step(delta, watcher, day_rules, room, p)
	_progress_step(watcher, day_rules, weird_now)
	for text: String in day_rules.take_notices():
		ui.show_notice(text)
	var frozen := not router.current.advances_calendar
	var period := day_rules.period_text(frozen)
	var tale_now := tales()
	if tale_now != null and not frozen and not day_rules.inspection_active() and not day_rules.inspection_upcoming() and tale_now.checkup_period() != "":
		period = tale_now.checkup_period()
	if watcher != null and bool(watcher.pat["permanent"]) and not frozen:
		period += " · 持续追踪"
	ui.show_status(day_rules.place_name(session.world_id, float(p[1])), period, day_rules.period_class(frozen), "??:??" if inception_flow.here() else ("???" if maze_flow.here() else day_rules.clock_text((bag != null and bag.has_clock()) or (talent() != null and talent().has("watch")))))
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
		if lit.lighting != null:
			lit.lighting.reduce_flash = settings.get_int("reduce_flash") == 1
			lit.lighting.brightness = float(settings.get_int("bright")) / 100.0
			lit.lighting.world_normal = ui.scene_post().world_normal
			lit.lighting.fake_normal = ui.scene_post().fake_normal
			lit.lighting.gaze = ui.scene_post().gaze_level
			lit.lighting.crowd_state = lift_crowd().state if lift_crowd() != null else {}
		lit.update_lighting(delta, day_rules.tsec, player.camera, watcher.flick if watcher != null else 0.0, watcher.red if watcher != null else 0.0,
			weird_light != null and weird_light.blackout_now(), weird_light.overcast_target() if weird_light != null else 0.0)
		if lit.lighting != null:
			ui.scene_post().parameter("exposure",lit.lighting.post_exposure)
		if watcher != null:
			var fig_scene := Vector2.ZERO
			if watcher.figure_visible():
				fig_scene = CampusGeometry.to_scene(room, Vector2(float(watcher.pat["x"]), float(watcher.pat["y"])))
			lit.show_patrol(watcher.figure_visible(), fig_scene, float(watcher.pat["fy"]), player.camera.global_position)
		if weird_light != null and lit.anomaly_fx != null:
			var cam_pos := player.camera.global_position
			var fwd := -player.camera.global_transform.basis.z
			lit.anomaly_fx.update(delta, weird_light.an, room, session.world_id, Vector3(cam_pos.x, float(p[1]), cam_pos.z), Vector2(fwd.x, fwd.z), cam_pos, story().diff == "hard")


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
	if player.editing_text():
		return
	if Input.is_action_just_pressed("bag"):
		if ui.bag_open():
			_close_bag()
		elif player.enabled or knife_flow.captured():
			_open_bag()
	if not player.enabled and not knife_flow.captured():
		return
	var tsec := school().tsec if school() != null else 0.0
	if Input.is_action_just_pressed("torch"):
		if not bag.has("torch"):
			ui.show_notice("没有手电筒")
		else:
			_apply_result(bag.use("torch", tsec))
	for i in 2:
		if Input.is_action_just_pressed("hot_%d" % (i + 1)):
			if bag.hot[i]!=null and knife_flow.use(String(bag.hot[i]),"hot"): continue
			if bag.hot[i]!=null and inception_flow.use(String(bag.hot[i])): continue
			if bag.hot[i] == null or not maze_flow.intercept_item(String(bag.hot[i])):
				_apply_result(bag.use_hot(i, tsec))


func _bag_entries() -> Array:
	var bag := items()
	var out: Array = []
	for id: String in bag.bag:
		out.append({"id": id, "name": bag.item_name(id) + (" · 撑开着" if id == "brolly" and bag.brolly_up else ""), "text": bag.item_text(id)})
	return out


func _touch_torch() -> void:
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	if session == null or not player.enabled or story().over():
		return
	if not items().has("torch"):
		ui.show_notice("没有手电筒")
	else:
		_apply_result(items().use("torch",school().tsec))


func _touch_hot(index: int) -> void:
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	if session==null or get_tree().paused or story().over() or (not player.enabled and not knife_flow.captured()):
		return
	if index in [0,1] and items().hot[index]!=null and knife_flow.use(String(items().hot[index]),"hot"):
		return
	if index in [0,1] and items().hot[index]!=null and inception_flow.use(String(items().hot[index])): return
	if session != null and player.enabled and not story().over():
		_apply_result(items().use_hot(index,school().tsec))


func _open_manual() -> void:
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	if knife_flow.captured() and not story().over():
		_open_bag()
		return
	if session == null or not player.enabled or story().over() or opening_busy():
		return
	player.enabled = false
	player.clear_input()
	ui.clear_touch()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_choice_handler = func(index: int) -> void:
		match index:
			0: _open_bag()
			1: _show_notes("")
			2: _show_map("")
			3: _lesson_press()
			4:
				facilities().set_context(_facility_context())
				facilities().think()
				_apply_facility_events()
	ui.show_choice("手册",["背包","笔记","地图","课堂互动","逃生思路"])


func _open_bag() -> void:
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	player.enabled = false
	player.clear_input()
	ui.clear_touch()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ui.show_bag(_bag_entries())


func _close_bag() -> void:
	ui.hide_bag()
	if session != null and session.running and not get_tree().paused:
		player.enabled = not knife_flow.captured()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _use_item(id: String) -> void:
	var bag := items()
	if bag == null:
		return
	if knife_flow.use(id):
		if ui.bag_open(): ui.show_bag(_bag_entries())
		return
	_close_bag()
	if maze_flow.intercept_item(id) or inception_flow.use(id):
		return
	_apply_result(bag.use(id, school().tsec if school() != null else 0.0))


func _drop_item(id: String) -> void:
	var bag := items()
	if bag == null or _dead() or not bag.drop(id):
		return
	if id in ["coil", "lens", "vial"] and facilities() != null:
		facilities().flags[id] = false     # the unique portal materials can be taken again where they were found
	for line: String in bag.take_notices():
		ui.show_notice(line)
	ui.show_bag(_bag_entries())
	var p: Array = player.capture_pose()["position"]
	var room: Variant = campus().room(session.world_id)
	if routes().offer_item(room, CampusGeometry.to_world(room,p[0],p[2]),school().tsec,school().day):
		_apply_route_events(routes())


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
	if is_instance_valid(debug_flow) and debug_flow.god:
		ui.show_notice("【Dev】无敌挡下了死亡。")
		return
	var bag := items()
	var elixir := bag != null and bag.has("elixir")
	var immune := not elixir and not fate.dead and talent() != null and talent().prevent_death()
	var result := fate.kill(msg, fx, source, {"day": school().day if school() != null else 1, "has_elixir": elixir, "immune": immune})
	if result.has("protected"):
		if result["protected"] == "elixir":
			bag.remove("elixir")
		fact({"kind": "protect", "by": String(result["protected"])})
		if garage() != null:
			garage().rescued()
		school().survive(source)
		if patrol() != null:
			patrol().rescued()
		if anomaly() != null:
			anomaly().end_now()
		_apply_result(result)
		if source == "campus_fall" and _fall_back is Dictionary:
			var room_b: Variant = campus().room(session.world_id)
			var sb := CampusGeometry.to_scene(room_b, Vector2(float(_fall_back["x"]), float(_fall_back["y"])))
			player.restore_pose({"position": [sb.x, float(player.capture_pose()["position"][1]), sb.y], "yaw": CampusGeometry.yaw_from_ang(float(_fall_back["ang"]) + PI), "pitch": 0.0})
		_fall_back = null
		return
	if not result.get("dead", false):
		return
	debug_flow.before_death()
	fact({"kind": "death", "source": source, "fx": fx, "wake": bool(result["wake"])})
	rules_dlc_flow.cancel()
	if not bool(result["wake"]):
		_score_death()
	if not result["wake"] and not (session.world_id in ["lift_dream", "portal_tunnel"]):
		var lp: Array = player.capture_pose()["position"]
		var lw := CampusGeometry.to_world(campus().room(session.world_id), float(lp[0]), float(lp[2]))
		_write_side("last_life.json", {"v": 1, "scene": session.world_id, "x": lw.x, "y": lw.y, "tsec": roundi(school().tsec), "day": school().day})
	player.enabled = false
	player.clear_input()
	audio.stop_all()
	if is_instance_valid(_lift_crowd_fx):
		_lift_crowd_fx.clear()
	audio.death(fx)
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
	_start_death_cg(source if DeathCG.has(source) else fx)
	_death_hold = DeathCG.duration(source if DeathCG.has(source) else fx, _death_hold) if _death_cg != null and is_instance_valid(_death_cg) and _death_cg.on else _death_hold
	ui.show_notice(msg)
	var updated := fate.log_death(_read_death_log(), school().day if school() != null else 1, session.world_id)
	_write_death_log(updated)
	if not fate.cause().is_empty():
		_record({"id": "failure:" + fate.death_source, "text": fate.cause(), "kind": "验证", "source": "刚才的经历"})
	if not result["wake"]:
		if speedrun.run.is_empty():
			saves.clear()
			ui.set_save_available(saves.exists())
		else:
			var rec_d := _read_speedrun()
			ui.show_notice(msg + "\n" + _speedrun_result(speedrun.fail("failed", rec_d), rec_d))


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


var _death_cg: DeathCG


## The cause's own scene (death_cg.gd), when it has one and there is a picture to draw on; else the fade effect only.
func _start_death_cg(fx: String) -> void:
	_stop_death_cg()
	var world := _campus_world()
	if world == null or not DeathCG.has(fx) or DisplayServer.get_name() == "headless":
		return
	_death_cg = DeathCG.new()
	_death_cg.name = "DeathCG"
	add_child(_death_cg)
	_death_cg.audio = audio
	_death_cg.begin(fx, player, world, ui, DeathCG.duration(fx, StoryModule.duration(fx)), settings.get_int("reduce_flash") == 1)


func _stop_death_cg() -> void:
	if _death_cg != null and is_instance_valid(_death_cg):
		_death_cg.finish()
		_death_cg.queue_free()
	_death_cg = null


func _death_step(delta: float) -> void:
	if _death_phase != "fade":
		return
	_death_wait += delta
	if _death_cg != null and is_instance_valid(_death_cg) and _death_cg.on:
		_death_cg.tick(delta)
	else:
		ui.show_death_scene(story().death_fx, minf(1.0, _death_wait / maxf(0.2, _death_hold)))
	# story.js deathSkip: at least 0.6 s of the scene, then a key skips to the result.
	var skip := _death_wait >= 0.6 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"))
	if _death_wait >= _death_hold or skip:
		_finish_death()


func _finish_death() -> void:
	_stop_death_cg()
	var fate := story()
	if fate.wake_pending:
		var left := fate.finish_wake()
		fact({"kind": "wake"})
		audio.play("foley.wake")
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
	ui.show_death_card(fate.death_msg, fate.epitaph(), fate.cause(), StoryModule.hints(_read_death_log()), achievements().run_new_labels() if achievements() != null else PackedStringArray(), _death_score_line())


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
			fact({"kind": "patrol", "what": "permanent"})
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
				if e["source"]!="patrol" or e["fx"]!="grip" or not knife_flow.catch_player(String(e["msg"])):
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
		if locked and not _seen_lock_ach and not story().dead:
			fact({"kind": "patrol", "what": "locked", "permanent": bool(watcher.pat["permanent"])})
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
	var scene := session.world_id
	var w_here := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var out_room := CampusData.layout("out")
	var cw := _campus_world()
	var night := 0.0
	if cw != null and cw.lighting != null:
		night = 1.0 - float(cw.lighting.sun_at(day_rules.tsec / 60.0)["day"])
	var behind := false
	if patrol_pos is Vector3:
		var to_p: Vector3 = (patrol_pos as Vector3) - player.camera.global_position
		behind = (-player.camera.global_basis.z).dot(to_p.normalized()) < -0.2
	var big := false
	if room is Dictionary and (room as Dictionary).has("cols"):
		big = int(room["cols"]) * int(room["rows"]) > 900
	audio.update(delta, {"scene": scene, "out": scene == "out", "night": night, "dead": story().dead,
		"surface": AudioFx.surface(scene, scene == "bell1" and float(p[1]) > 0.4, w_here, out_room.get("objects", []), float(out_room.get("SC", 1.0))),
		"san": day_rules.san, "viol": day_rules.viol, "anomaly": an_id, "shelter": weird != null and weird.under_roof(), "brolly": items() != null and items().brolly_up, "moving": player.moving, "running": player.sprinting,
		"hiding": player.hiding, "body": maxf(0.0, _sense_body), "bpm": float(_sense_view.get("bpm", 0.0)),
		"chase": watcher != null and bool(watcher.pat["locked"]), "threat": watcher != null and watcher.local_threat(),
		"patrol_pos": patrol_pos, "patrol_behind": behind, "big": big, "blackout": weird != null and weird.blackout_now(),
		"moth_near": cw.anomaly_fx.moth_nearness() if cw != null and cw.anomaly_fx != null and an_id == "moth" else 0.0,
		"busy": ui.terminal_open() or (days() != null and days().waiting != null), "echo": dread() != null and dread().echo})
	ui.show_captions(audio.captions.lines() if audio.captions.enabled(audio.volume, audio.muted) else PackedStringArray())
	# fx/weather.js: in the rain a bolt every 6–14 s, the screen whitens twice and the thunder comes late.
	if an_id in ["rain", "raindots"]:
		_bolt_next -= delta
		if _bolt_next <= 0.0:
			_bolt_next = 6.0 + randf() * 8.0
			var near_b := randf()
			ui.flash_light(0.45 + 0.3 * (1.0 - near_b))
			get_tree().create_timer(0.09 + randf() * 0.08).timeout.connect(func() -> void: ui.flash_light(0.35))
			audio.thunder(0.4 + near_b * 2.0, 1.0 - near_b * 0.6, scene != "out")
	else:
		_bolt_next = 6.0
	if cw != null and cw.lighting != null:
		cw.lighting.crackle_from = player.camera
		for c: Dictionary in cw.lighting.crackles:
			if float(c["k"]) >= 0.05:
				audio.play("world.crackle", {"k": float(c["k"]), "pan": float(c["pan"])})
		cw.lighting.crackles.clear()
	# tickSchoolBell: the bell when the period changes (outdoors quieter and muffled).
	var period := String(SchoolClock.period_at(day_rules.tsec)[2])
	if _audio_period != "" and period != _audio_period and not story().dead and session.world_id != "lift_dream":
		var bell_kind := "start" if SchoolClock.period_at(day_rules.tsec)[3] == "教室" else "end"
		audio.school_bell(bell_kind, session.world_id == "out", atmos().bell_tune(bell_kind, day_rules.tsec) if atmos() != null else {})
	_audio_period = period
	if watcher != null:
		var locked := bool(watcher.pat["locked"])
		if locked and not _seen_lock:
			audio.play("threat.sting")
		_seen_lock = locked
	if an_id != _seen_anomaly:
		if an_id != "":
			audio.anomaly_start(an_id)
		elif _seen_anomaly != "":
			audio.play("anomaly.end")
		_seen_anomaly = an_id
		_seen_phase = 0
	if weird != null and an_id in ["cup", "cola"]:
		# cupFall / colaFall while it drops, cupHit / colaHit on landing (audio.js).
		var phase := int((weird.an["data"] as Dictionary).get("phase", 0))
		if phase != _seen_phase:
			if phase == 1:
				audio.play("foley.%sFall" % an_id)
			elif phase == 2:
				audio.play("foley.%sHit" % an_id)
		_seen_phase = phase


# ---- facilities, rest and the portal (game/features/campus/facilities_module.gd) ----

func _facility_context() -> Dictionary:
	var ctx := _facility_context_base()
	var cars := garage()
	ctx["car_row"] = int(cars.car_right.split(":")[1]) + 1 if cars != null and not cars.car_right.is_empty() else 1
	return ctx


func _facility_context_base() -> Dictionary:
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
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "tsec": day_rules.tsec,"day":day_rules.day,
		"clock": day_rules.game_clock(), "meal": meal, "rest_mul": float(day_rules.pressure()["rest"]), "exam": day_rules.exam,
		"has": func(id: String) -> bool: return bag != null and bag.has(id),
		"add": func(id: String) -> bool: return _add_item(id),
		"remove": func(id: String) -> void:
			if bag != null:
				bag.remove(id),
		"anomaly": weird.pendulum_info() if weird != null else {},
		"busy": (weird != null and weird.is_active()) or day_rules.inspection_pending() or (patrol() != null and patrol().local_chase()),
		"gate_n_map": CampusData.campus().get("gates", {}).get("n", {"x": 514, "y": 95}), "bound_x1": float(CampusData.campus().get("bound_map", {}).get("x1", 830)),
		"closed": DayModule.CLOSED if days() != null and days().today(day_rules.day, day_rules.tsec) == "occupied" else [], "drain_mul": _drain_mul()}


## Inventory add with the old messages (a full bag says so).
func _add_item(id: String) -> bool:
	var bag := items()
	if bag == null:
		return false
	var ok := bag.add(id)
	if ok:
		audio.play("ui.pickup")
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
		world.show_portal(bool(fac.portal["open"]), bool(fac.portal["sketch"]))


func _apply_facility_events() -> void:
	var fac := facilities()
	if fac == null:
		return
	for e: Dictionary in fac.take_events():
		match e["kind"]:
			"clue":
				if runscore() != null:
					runscore().add_clue(String(e["id"]), school().day)
			"record":
				_record(e)
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = clampf(school().san + float(e["amount"]), float(e.get("min", -INF)), float(e.get("max", INF)))
			"rest_gain":
				school().san=minf(100,school().san+snappedf(float(e["base"])*float(school().pressure()["rest"]),.1))
			"advance":
				school().advance_game_time(float(e["minutes"]))
			"stamina":
				school().stam = minf(school().stamina_max(), school().stam + float(e["amount"]))
			"skip":
				ui.show_notice("…%d 分钟过去了 · %s" % [int(e["minutes"]), e["name"]])
			"fact":
				fact({"kind": "rest", "key": String(e["key"])})
				if String(e["key"]) == "pc":
					_start_snake()
			"anomaly_lock":
				if anomaly() != null:
					anomaly().lock_forecast()
			"anomaly_end":
				if anomaly() != null:
					anomaly().end_now()
			"exam_start":
				audio.play("event.bigBell", {"k": 1.0})
				if school().exam_start():
					ui.show_notice("考试模式 · 今天剩下的课都是考试，熄灯后结束")
			"bell":
				audio.play("event.bigBell")
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


# ---- the low-SAN picture (game/features/school/sensory_rules.gd) ----

var _sense_body := -1.0
var _sense_view: Dictionary = {}
var _sense_t := 0.0
var _blink_plan: Array = []
var _blink_t := 0.0
var _blink_next := 0.0
var _sense_rng := RandomNumberGenerator.new()
var _ghost_t := 9.0
var _ghost_dur := 1.0
var _ghost_next := 8.0
var _ghost_a := 0.0
var _ghost_spin := 0.0


func _reset_sensory() -> void:
	ui.reset_post()
	_sense_body = -1.0
	_sense_t = 0.0
	_sense_view = {}
	_blink_plan = []
	_blink_t = 0.0
	_blink_next = 0.0
	_ghost_t = 9.0
	_ghost_next = 0.0
	_ghost_a = 0.0
	_ghost_spin = 0.0


func _sensory_step(delta: float) -> void:
	_sense_t += delta
	_sense_body = SensoryRules.step(_sense_body, school().san, delta)
	var watcher := patrol()
	var v := SensoryRules.view(_sense_body, {"time": _sense_t, "distortion": settings.get_int("distortion"), "reduce_flash": settings.get_int("reduce_flash") == 1, "threat": watcher != null and watcher.local_threat(),
		"takeover": driving() or ui.terminal_open(), "chase": watcher != null and bool(watcher.pat["locked"])})
	_sense_view = v
	# The picture follows the body's sounds (modules/sensory): the view tightens as the heart beats and
	# presses in as the breath is taken, from the moment the sound starts (muted or not).
	v["pulse_env"] = float(v["pulse"]) * exp(-audio.pulse_t / 0.18)
	var it := audio.inhale_t
	v["inhale"] = sin(PI / 2.0 * it / 0.55) if it < 0.55 else (cos(PI / 2.0 * (it - 0.55) / 1.05) if it < 1.6 else 0.0)
	# Ghosting: now and then a faint offset copy drifts for 0.8–1.6 s; the lower the SAN, the oftener.
	_ghost_t += delta
	if float(v["ghost"]) > 0.0:
		_ghost_next -= delta
		if _ghost_next <= 0.0 and _ghost_t >= _ghost_dur:
			_ghost_t = 0.0
			_ghost_dur = 0.8 + 0.8 * _sense_rng.randf()
			_ghost_a = _sense_rng.randf() * TAU
			_ghost_spin = (_sense_rng.randf() - 0.5) * 1.6
			_ghost_next = (11.0 - 7.0 * minf(1.0, (_sense_body - 0.45) / 0.45)) * (0.75 + 0.5 * _sense_rng.randf())
	else:
		_ghost_next = maxf(_ghost_next, 2.0)
	v["ghost_env"] = float(v["ghost"]) * sin(PI * _ghost_t / _ghost_dur) if _ghost_t < _ghost_dur else 0.0
	var ga := _ghost_a + _ghost_spin * minf(_ghost_t, _ghost_dur)
	v["ghost_dir"] = [cos(ga), sin(ga)]
	var blink := 0.0
	if float(v["flicker"]) > 0.0:
		if _blink_plan.is_empty():
			_blink_next -= delta
			if _blink_next <= 0.0:
				_blink_plan = SensoryRules.blink_plan(_sense_body, _sense_rng)
				_blink_t = 0.0
		else:
			_blink_t += delta
			blink = SensoryRules.blink_at(_blink_plan, _blink_t) * float(v["flicker"])
			if _blink_t >= SensoryRules.blink_end(_blink_plan):
				_blink_plan = []
				_blink_next = float(v["flicker_gap"]) * (0.7 + 0.6 * _sense_rng.randf())
	else:
		_blink_plan = []
	ui.show_sensory(v, blink, _sense_t)
	var post := ui.scene_post()
	var fnm := fake_normal()
	post.step(delta,fnm != null and fnm.active() and float(fnm.fn["v"])<72.0,school().san)
	post.parameter("brightness",float(settings.get_int("bright"))/100.0)
	post.parameter("red",watcher.red if watcher != null else 0.0)
	var a: Dictionary = anomaly().an if anomaly() != null else {}
	var gaze_target := 0.0
	if a.get("active",false) and a.get("id")=="stare":
		gaze_target=.35+.45*clampf(float(a.get("acc",0.0))/1.8,0,1)+(.2 if a.get("data",{}).get("hit",false) else 0.0)
	post.gaze_level += (gaze_target-post.gaze_level)*minf(1.0,delta*2.4)
	post.parameter("gaze",post.gaze_level)
	post.quality = settings.get_int("quality")


# ---- atmosphere (game/features/story/dread_module.gd) ----

func _dread_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var weird := anomaly()
	var watcher := patrol()
	var day_rules := school()
	var cw := _campus_world()
	var night := 0.0
	if cw != null and cw.lighting != null:
		night = 1.0 - float(cw.lighting.sun_at(day_rules.tsec / 60.0)["day"])
	var busy := story().dead or get_tree().paused or ui.choice_open() or ui.terminal_open() or driving() or phone_open() or snake_open() \
		or (weird != null and bool(weird.an["active"])) or (watcher != null and watcher.local_chase()) or day_rules.inspection_active() \
		or (days() != null and days().waiting != null) or session.world_id in ElevatorModule.RIDE_ROOMS or session.world_id == "portal_tunnel" \
		or (fake_normal() != null and fake_normal().active())
	var rid := session.world_id
	return {"scene": rid, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "san": day_rules.san, "viol": day_rules.viol,
		"night": night, "day": day_rules.day, "busy": busy, "an_active": weird != null and bool(weird.an["active"]),
		"an_next": float(weird.an["next"]) if weird != null else -1.0, "an_next0": int(weird.an["next0"]) if weird != null else 0,
		"ear": talent() != null and talent().has("ear"),
		"door_open": func(c: int, r: int) -> bool: return campus().is_open(CampusGeometry.door_key(campus().room(rid), c, r))}


func _dread_step(delta: float) -> void:
	var d := dread()
	if d == null:
		return
	d.set_context(_dread_context())
	d.tick(delta)
	_apply_dread_events()


func _apply_dread_events() -> void:
	var d := dread()
	if d == null:
		return
	var cw := _campus_world()
	for e: Dictionary in d.take_events():
		match e["kind"]:
			"dread":
				var pl: Dictionary = e["place"]
				audio.play("dread." + String(e["cue"]), {"pan": float(pl["pan"]), "k": float(pl["k"]),
					"lp": (0.35 if bool(pl["muffled"]) else 1.0) * (0.7 if bool(pl["behind"]) else 1.0), "place": pl})
			"duck":
				audio.duck(float(e["sec"]))
			"precursor":
				audio.play("threat.precursor", {"k": clampf(float(e["k"]), 0.2, 1.0)})
			"visit":
				if cw != null:
					if e["fx"] == "lamp" and cw.lighting != null:
						cw.lighting.dread_lamp = int(e["i"])
					elif e["fx"] == "note":
						cw.show_dread_note(String(e["text"]), float(e["seed"]), player.capture_pose())
			"clear":
				if cw != null:
					cw.show_dread_note("", 0.0, {})
					if cw.lighting != null:
						cw.lighting.dread_lamp = -1


# ---- settings (game/infrastructure/settings/game_settings.gd) ----

func _setting_changed(key: String, value: int) -> void:
	if key == "clear_last_life":
		_write_side("last_life.json", null)
		if marks() != null:
			marks().last_life = null
		_marks_key = ""
		ui.show_notice("已清除上一局的痕迹")
		return
	if key == "reset_comfort":
		settings.reset_comfort()
		ui.show_settings(settings.values)
		ui.show_notice("操作与文字设置已恢复默认")
	else:
		settings.set_value(key, value)
		if key == "quality":
			ui.show_notice("画质：" + String(GameSettings.QUALITY_LABELS[settings.get_int("quality")]))
	settings.save_file()
	_apply_settings()


## Push every stored setting to where it takes effect (presentation and comfort only).
func _apply_settings() -> void:
	audio.volume = float(settings.get_int("vol")) / 100.0
	audio.ambience = settings.get_int("amb") == 1
	audio.captions.mode = settings.get_int("captions")
	ui.apply_caption_scale(float(GameSettings.SUB_MULT[settings.get_int("sub")]))
	ui.apply_text_scale(settings.get_int("text"))
	ui.apply_touch_scale(settings.get_int("touch_size"), settings.touch_layout)
	ui.set_grain(settings.get_int("grain") == 1)
	ui.scene_post().quality=settings.get_int("quality")
	ui.scene_post().parameter("brightness",float(settings.get_int("bright"))/100.0)
	player.mouse_sensitivity = 0.0025 * float(settings.get_int("mouse")) / 100.0
	player.touch_sensitivity = 0.004 * float(settings.get_int("touch")) / 100.0
	player.view_motion.shake_enabled = settings.get_int("shake") == 1
	var q := settings.get_int("quality")
	CampusData.tier = q if CampusData.tiers_available().has(q) else CampusData.DEFAULT_TIER   # models of the chosen tier, if exported
	var vp := get_viewport()
	vp.scaling_3d_scale = float(GameSettings.QUALITY_SCALE[q])
	vp.msaa_3d = int(GameSettings.QUALITY_MSAA[q]) as Viewport.MSAA
	CampusLighting.shadows_on = bool(GameSettings.QUALITY_SHADOW[q])
	var cw := _campus_world()
	if cw != null and cw.visual_tier != CampusData.tier:
		cw.reload_models(player.position)
		_sync_world()
	if cw != null and cw.lighting != null:
		cw.lighting.sun_light.shadow_enabled = CampusLighting.shadows_on
	if DisplayServer.is_touchscreen_available():
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if settings.get_int("auto_land") == 1 else DisplayServer.SCREEN_SENSOR)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.get_int("full_screen") == 1 else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(want)


# ---- global atmosphere A1–A7 (game/features/story/atmos_module.gd, game/presentation/world/campus/atmos_fx.gd) ----

func _atmos_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var dc := _dread_context()
	var cw := _campus_world()
	var fx: AtmosFx = cw.atmos_fx if cw != null else null
	var watcher := patrol()
	_atmos_busy = bool(dc["busy"])
	var ctx := {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])),
		"day": school().day, "tsec": school().tsec, "viol": school().viol, "busy": bool(dc["busy"]), "an_active": dc["an_active"],
		"an_next": dc["an_next"], "an_next0": dc["an_next0"], "age": dread().t if dread() != null else 0.0, "dread": dread(),
		"prop": null, "prop_ok": false, "sees_shifted": false, "stage": int(school().pressure()["stage"]), "lamps": []}
	if watcher != null:
		ctx["pat"] = {"room": String(watcher.pat["room"]), "walk": watcher.pat["state"] == "walk", "x": float(watcher.pat["x"]), "y": float(watcher.pat["y"])}
	if cw != null and cw.lighting != null and room != null:
		var lamp_points: Array = []
		for l: OmniLight3D in cw.lighting.room_lights:
			lamp_points.append(CampusGeometry.to_world(room, l.position.x, l.position.z))
		ctx["lamps"] = lamp_points
	if fx != null and player.camera != null:
		ctx["prop"] = fx.prop_world()
		ctx["prop_ok"] = fx.can_shift(player.camera)
		ctx["sees_shifted"] = fx.sees_shifted(player.camera)
	return ctx


func _atmos_step(delta: float) -> void:
	var a := atmos()
	if a == null or story().dead:
		return
	a.set_context(_atmos_context())
	a.tick(delta)
	_apply_atmos_events()
	var cw := _campus_world()
	if cw == null:
		return
	if cw.lighting != null:
		cw.lighting.atmos_mods = AtmosModule.light_mods(school().day, school().tsec)
		cw.lighting.lamp_mul = a.lamp_mul()
	if cw.duty != null:
		cw.duty.update(DutyRoster.tier_of(school().tt), (school().day - 1) % 5)
	var fx: AtmosFx = cw.atmos_fx
	if fx == null or player.camera == null:
		return
	var r := a.floor_room()
	if not r.is_empty():
		var key := "%d:%s" % [school().day, r["id"]]
		var rec := str(a.shift.get(key, ""))
		var kind: Variant = rec if (rec == "push" or rec == "face") else null
		if kind != fx.shifted:
			fx.apply_shift(kind, a.shift_pose.get(key, {}))
		fx.face_camera(player.camera)
	a.window_look = fx.show_window(a.window, player.camera)


func _apply_atmos_events() -> void:
	var a := atmos()
	if a == null:
		return
	for e: Dictionary in a.take_events():
		match e["kind"]:
			"campus":
				audio.play("campus." + String(e["cue"]), {"pan": float(e["pan"]), "k": float(e["k"]), "lp": float(e["lp"])})
			"duck":
				audio.duck(float(e["sec"]))
				audio.note_caption("world.silence")
			"dread":
				var pl: Dictionary = e["place"]
				audio.play("dread." + String(e["cue"]), {"pan": float(pl["pan"]), "k": float(pl["k"]), "lp": 0.7 if bool(pl["behind"]) else 1.0, "place": pl})
			"say":
				ui.show_notice(String(e["text"]))


# ---- the investigation notebook (game/features/story/investigation_module.gd) ----

var _supply_after: Callable


func _invest_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var bag := items()
	var fac := facilities()
	var rt := routes()
	var ph := phone()
	var cars := garage()
	var has_key := bag != null and bag.has("key")
	var portal: Dictionary = {}
	if fac != null:
		var floors_left: Array = []
		for f: int in FacilitiesModule.BLUEPRINT_FLOORS:
			if not (fac.portal["blueprints"] as Dictionary).has(f):
				floors_left.append(f)
		portal = {"diary": fac.portal["diary"], "sketch": fac.portal["sketch"], "open": fac.portal["open"], "count": fac.blueprint_count(), "floors_left": floors_left, "need": fac.portal_need_text()}
	var cy: Dictionary = {}
	if ph != null:
		cy = {"initialized": ph.device["initialized"], "network": ph.device["network"], "download": ph.device["download"]["status"], "term": ph.termination["status"]}
	var seat: Dictionary = CampusData.campus().get("own_seat", {})
	var near_seat := false
	if session.world_id == "teach1" and not seat.is_empty() and room != null:
		near_seat = CampusGeometry.tile_center(room, int(seat["col"]), int(seat["row"])).distance_to(w) < 24.0
	var weird_now := anomaly()
	var watcher := patrol()
	var idle := not (story().dead or get_tree().paused or ui.choice_open() or ui.terminal_open() or driving() or player.hiding \
		or (weird_now != null and bool(weird_now.an["active"])) or (watcher != null and watcher.local_chase()) or school().inspection_active())
	var row := 1
	if cars != null and not cars.car_right.is_empty():
		row = int(cars.car_right.split(":")[1]) + 1
	return {"day": school().day, "place": school().place_name(session.world_id, float(p[1])), "has_key": has_key, "has_phone": bag != null and bag.has("phone"),
		"has_coin": bag != null and bag.has("coin"), "has_pill": bag != null and bag.has("pill"), "bag_full": bag != null and bag.bag.size() >= 8,
		"car": talent().car(has_key) if talent() != null else {"ok": has_key, "via": "key" if has_key else ""}, "car_tried": cars.car_tried.size() if cars != null else 0,
		"car_used": cars != null and cars.car_used, "hacked": rt != null and rt.hacked, "data": rt != null and rt.data_synced,
		"face_done": int(rt.face_quiz.get("done", -1)) if rt != null and not rt.face_quiz.is_empty() else -1,
		"spot_comp": fac != null and fac.spots.has("comp"), "spot_data": fac != null and fac.spots.has("data"), "portal": portal, "cyber": cy,
		"desk_ok": idle and near_seat, "car_row": row}


func _record(e: Dictionary) -> void:
	var inv := investigation()
	if inv == null:
		return
	inv.set_context(_invest_context())
	inv.record(String(e["id"]), String(e["text"]), String(e.get("kind", "事实")), String(e.get("source", "")))


func _invest_do(action: Callable) -> void:
	var inv := investigation()
	if inv == null:
		return
	inv.set_context(_invest_context())
	action.call(inv)
	_apply_invest_events()


func _apply_invest_events() -> void:
	var inv := investigation()
	if inv == null:
		return
	for e: Dictionary in inv.take_events():
		match e["kind"]:
			"say":
				ui.show_notice(String(e["text"]))
			"save":
				save_game()
			"spots":
				if facilities() != null:
					for n: String in e["names"]:
						facilities().spots[n] = true
			"outing":
				school().grant_outing(false)
				for line: String in school().take_notices():
					ui.show_notice(line)
			"chalk":
				if items() != null and not items().has("chalk"):
					items().add("chalk")
			"supply":
				if items() != null and items().add("pill"):
					if bool(e["pay"]):
						items().remove("coin")
					else:
						school().advance_game_time(6.0)
			"continue":
				if _supply_after.is_valid():
					var after := _supply_after
					_supply_after = Callable()
					after.call()
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var i2 := investigation()
					if i2 != null and mine == _choice_count:
						i2.set_context(_invest_context())
						i2.choose(index)
						_apply_invest_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], false)


func _show_notes(query: String = "") -> void:
	var inv := investigation()
	if inv == null:
		return
	inv.set_context(_invest_context())
	var routes := inv.routes()
	var focus := inv.current_focus()
	if not routes.any(func(r: Array) -> bool: return r[0] == focus):
		focus = "car" if routes.any(func(r: Array) -> bool: return r[0] == "car") else ""
	var listing := inv.list(query)
	ui.show_notes({"goal": inv.goal(), "focus": focus, "routes": routes, "recent": listing["recent"], "groups": listing["groups"],
		"progress": inv.progress(), "found": listing["found"], "query": query})


func _notes_focus(route: String) -> void:
	var inv := investigation()
	if inv != null and inv.set_focus(route):
		save_game()
		_show_notes(ui._notes_search.text if ui._notes_search != null else "")


# ---- the map page (game/features/campus/exploration_module.gd, game/presentation/ui/map_view.gd) ----

func _explore_step(delta: float) -> void:
	var ex := exploration()
	var room: Variant = campus().room(session.world_id)
	if ex == null or room == null or story().dead or get_tree().paused:
		return
	var p: Array = player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var rid := session.world_id
	ex.set_context({"scene": rid, "x": w.x, "y": w.y, "door_open": func(c: int, r: int) -> bool: return campus().is_open(CampusGeometry.door_key(campus().room(rid), c, r))})
	ex.tick(delta)


## The mark of a tile on a sketch (exploration-map.js label): what was left behind, searched, locked, tried.
func _map_label(r: Dictionary, c: int, row: int) -> String:
	var key := "%s:%d:%d" % [r["id"], c, row]
	var ch := String(r["grid"][row]).substr(c, 1)
	var bag := items()
	if bag != null and bag.pending_loot.has(key):
		return "留"
	if bag != null and bag.desk_used.has(key):
		return "✓"
	if ch == "=":
		if campus().is_open(key):
			return "开"
		return "锁" if CampusData.campus().get("door_locks", {}).has(key) else "门"
	if ch == "V":
		return "×" if garage() != null and garage().car_tried.has("%d:%d" % [c, row]) else "车"
	if ch == "K" and r.get("host") == "lab" and facilities() != null and (facilities().portal["blueprints"] as Dictionary).has(int(r.get("floor", 0))):
		return "✓"
	return MapView.static_mark(ch)


func _show_map(selected: String = "") -> void:
	if inception_flow.here():
		ui.show_notice("我：这里没有地图。走廊一直在变。")
		return
	if maze_flow.here():
		ui.show_notice("我：打开地图，纸上什么也没有。这里不在任何一张图上。")
		return
	var ex := exploration()
	if ex == null:
		return
	var here_room: Variant = campus().room(session.world_id)
	if here_room != null:
		var p0: Array = player.capture_pose()["position"]
		var w0 := CampusGeometry.to_world(here_room, float(p0[0]), float(p0[2]))
		var rid0 := session.world_id
		ex.set_context({"scene": rid0, "x": w0.x, "y": w0.y, "door_open": func(c: int, r: int) -> bool: return campus().is_open(CampusGeometry.door_key(campus().room(rid0), c, r))})
		ex.observe()
	var ids := ex.rooms()
	if selected.is_empty():
		selected = session.world_id if session.world_id in ids else "campus"
	if selected != "campus" and not ids.has(selected):
		selected = "campus"
	var options: Array = [["campus", "校园总图"]]
	for id: String in ids:
		options.append([id, String(campus().room(id)["name"]) + ("　· 你在这里" if id == session.world_id else "")])
	var pose := player.capture_pose()
	var yaw_ang := CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	if selected == "campus":
		var view := ui.open_map(options, selected, "走过 %d 处室内" % ids.size(), "")
		var out: Dictionary = CampusData.layout("out")
		var cam: Dictionary = CampusData.campus()
		var bm: Dictionary = cam["bound_map"]
		var objects: Array = out["objects"]
		var me := Vector2.ZERO
		var p: Array = pose["position"]
		var sc := float(out.get("SC", 2.0))
		if here_room != null:
			for o: Dictionary in objects:
				if o["id"] == here_room.get("host"):
					me = Vector2(float(o["x"]) + float(o["w"]) / 2.0, float(o["y"]) + float(o["h"]) / 2.0)
		else:
			var w1 := CampusGeometry.to_world(null, float(p[0]), float(p[2]))
			me = w1 / sc
		var gates: Array = []
		var gate_names := {"n": "北门", "w": "西小门", "s": "南门"}
		for g: String in ["n", "w", "s"]:
			gates.append([gate_names[g], float(cam["gates"][g]["x"]), float(cam["gates"][g]["y"])])
		view.show_plan({"bound": {"x0": bm["x0"], "y0": bm["y0"], "x1": bm["x1"], "y1": bm["y1"]}, "objects": objects, "gates": gates, "me": me, "ang": yaw_ang})
		return
	var r: Dictionary = campus().room(selected)
	var hereb := selected == session.world_id
	var view2 := ui.open_map(options, selected, "%s　北 ↑　%s已看清 %d%%" % [r["name"], "你在这一层　" if hereb else "", ex.percent(selected)],
		"空白处还没看到过。桌、柜、架等字表示看到过，不代表搜过。\n梯 楼梯　电 电梯　廊 连廊　出 出口　锁 门锁着　✓ 已解决　留 有东西没拿　× 钥匙不匹配")
	var me2 := Vector2.ZERO
	if hereb:
		var p2: Array = pose["position"]
		me2 = CampusGeometry.to_world(r, float(p2[0]), float(p2[2]))
	view2.show_floor(r, ex.seen(selected), _map_label, me2, yaw_ang, hereb)


# ---- the phone shell (game/presentation/ui/phone_panel.gd, game/features/phone/plane_game.gd) ----

var _phone_panel: PhonePanel
var _phone_random := RandomNumberGenerator.new()


func phone_open() -> bool:
	return _phone_panel != null and _phone_panel.visible


func _ensure_phone_panel() -> void:
	if _phone_panel != null:
		return
	_phone_panel = PhonePanel.new()
	_phone_panel.app_selected.connect(_phone_select)
	_phone_panel.action_pressed.connect(_phone_action)
	_phone_panel.flap.connect(_phone_flap)
	_phone_panel.closed.connect(_close_phone)
	_phone_panel.shoot_pressed.connect(_shoot)
	_phone_panel.flash_pressed.connect(func() -> void:
		if camera() != null:
			camera().toggle_flash()
			_phone_paint())
	ui.get_node("Root").add_child(_phone_panel)


func _open_phone() -> void:
	var net := phone()
	if net == null or phone_open():
		return
	net.set_context(_phone_context())
	if not net.available():
		ui.show_notice("手机已断电 · 充到 5% 后自动开机" if items() != null and items().has("phone") else "没有手机")
		return
	_ensure_phone_panel()
	ui.hide_bag()
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	net.plane.reset()
	_phone_panel.screen.game = net.plane
	_phone_panel.hint.text = ("点屏幕往上飘" if ui.touch_enabled() else "空格 / W 往上飘") + " · " + ("点「收起」" if ui.touch_enabled() else "Esc 收起")
	_phone_panel.visible = true
	audio.play("ui.click")
	_phone_select(net.page)


func _close_phone(dark: bool = false) -> void:
	if not phone_open():
		return
	_phone_panel.visible = false
	if dark and not story().dead:
		ui.show_notice("我：屏幕一下子黑了。我抬起头。")
	if session != null and session.running and not get_tree().paused and not story().dead and not ui.choice_open() and not ui.terminal_open():
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _phone_danger() -> bool:
	var weird := anomaly()
	var watcher := patrol()
	return (weird != null and bool(weird.an["active"])) or (watcher != null and watcher.local_chase())


func _phone_select(app: String) -> void:
	var net := phone()
	if app == "plane" and _phone_danger():
		ui.show_notice("遇险时不能玩纸飞机")
		app = "home"
	net.page = app
	_phone_paint()


func _phone_action(action: String) -> void:
	var net := phone()
	net.set_context(_phone_context())
	match action:
		"wireless":
			net.toggle_wireless()
		"download":
			net.toggle_download()
		"sync":
			net.set_context(_phone_context())
			if not net.available() or not bool(net.device["network"]):
				ui.show_notice("手机需要电量与学校网络连接")
			elif routes() != null:
				routes().sync("phone")
				_apply_route_events(routes())
	_apply_phone_events()
	_phone_paint()


var _studio: PhotoStudio
var _shooting := false


func _camera_context() -> Dictionary:
	var weird := anomaly()
	var bag := items()
	return {"an": String(weird.an["id"]) if weird != null and bool(weird.an["active"]) else "", "gaze": gaze() != null and not gaze().current().is_empty(),
		"crowd": lift_crowd() != null and lift_crowd().active(), "day": school().day, "tsec": school().tsec, "place": school().place_name(session.world_id, float(player.capture_pose()["position"][1])),
		"clock": (bag != null and bag.has_clock()) or (talent() != null and talent().has("watch"))}


## camera.js shoot: the lens image without the interface, the flash, the extra layer, then the album.
func _shoot() -> void:
	var cam := camera()
	if cam == null or _shooting or not phone_open() or story().dead:
		return
	_shooting = true
	cam.set_context(_camera_context())
	var plan := cam.plan()
	var root_ui: CanvasItem = ui.get_node("Root")
	root_ui.visible = false
	await RenderingServer.frame_post_draw
	var lens: Image = get_viewport().get_texture().get_image()
	root_ui.visible = true
	if _studio == null:
		_studio = PhotoStudio.new()
		add_child(_studio)
	var photo: Image = await _studio.compose(lens, plan)
	_shooting = false
	if cam == null or session == null or camera() != cam or story().dead:
		return
	var b64 := ""
	if photo != null and not photo.is_empty():
		b64 = Marshalls.raw_to_base64(photo.save_jpg_to_buffer(0.6))
	var seen := false
	if bool(plan["flash"]):
		ui.flash_screen(settings.get_int("reduce_flash") == 1)
		if patrol() != null:
			patrol().set_context(_patrol_context(campus().room(session.world_id), player.capture_pose()))
			seen = patrol().camera_flash(CameraModule.FLASH_SEE, CameraModule.FLASH_LOCK)
			for e: Dictionary in patrol().take_events():
				ui.show_notice(String(e["text"]))
	cam.set_context(_camera_context())
	cam.add_photo(plan, b64, seen)
	audio.play("ui.click")
	for e: Dictionary in cam.take_events():
		match e["kind"]:
			"say":
				ui.show_notice(String(e["text"]))
			"record":
				_record(e)
			"fact":
				fact({"kind": "photo", "an": e["an"], "flash": e["flash"], "seen": e["seen"]})
	_phone_paint()


func _phone_flap() -> void:
	var net := phone()
	if net != null and phone_open() and net.page == "plane":
		if net.plane.flap():
			pass
		audio.play("ui.click")


func _phone_copy() -> String:
	var net := phone()
	var d: Dictionary = net.device
	var w: Dictionary = d["wireless"]
	var copy := ""
	match net.page:
		"home":
			copy = "工具查看时不能移动，世界仍在运行。收起手机后，后台任务继续。原教室无渗透时，从空电充满：普通约 5 分钟，科技党约 10 分钟。机房接线只抵普通基础耗电；科技党仍每分钟净掉 10 点。"
		"wireless":
			if w["status"] == "complete":
				copy = "无线接入完成。定位与门禁同步已解锁；不再暴露新位置，已发出的情报不会撤回。"
			elif w["status"] == "idle":
				copy = "接入学校无线网络需要 180—600 运行秒，执行期间耗电翻倍。"
			else:
				copy = ("已暂停" if w["status"] == "paused" else "正在接入") + " · %d%% · 剩余 %d 秒" % [floori(float(w["elapsed"]) / float(w["target"]) * 100.0), ceili(float(w["target"]) - float(w["elapsed"]))]
			if w["status"] != "complete":
				copy += "\n\n破解每累计 15 运行秒暴露一次当时的位置，巡察者会来搜查；坐下、假条和外出登记不能豁免。"
				if w["status"] == "running":
					copy += "\n下次暴露：%d 秒；收起手机仍会继续。" % ceili(PhoneEnergy.next_signal_in(w))
				if w["status"] == "paused":
					copy += "\n暴露计时已暂停，已发出的位置信息不会撤回。"
			if talent() != null and talent().has("tech") and w["status"] != "complete":
				copy += " 科技党执行渗透时，即使在原教室也会净掉电。"
		"location":
			copy = "巡察查询：" + (patrol().location_label() if patrol() != null and bool(d["network"]) else "尚未接入学校网络")
		"sync":
			copy = "门禁数据已经同步。" if routes() != null and routes().data_synced else ("仍需先在网络中心写入白名单；联网手机可以完成同步。" if bool(d["network"]) else "先接入学校网络。")
		"container":
			var dl: Dictionary = d["download"]
			if dl["status"] == "complete":
				copy = "模拟 Kali Linux 容器已就绪，可在机房电脑旁打开终端。"
			elif dl["status"] == "idle":
				copy = "无线接入完成后，自动安装容器。"
			else:
				copy = ("安装已暂停 " if dl["status"] == "paused" else "容器安装 ") + "%d%% · 剩余 %d 秒" % [floori(float(dl["elapsed"]) / 60.0 * 100.0), ceili(60.0 - float(dl["elapsed"]))]
			if net.termination["status"] == "accepted":
				copy += "\n服务器停机剩余 %d 运行秒。" % ceili(float(net.termination["remaining"]))
	return copy


func _phone_paint() -> void:
	var net := phone()
	if net == null or not phone_open():
		return
	var d: Dictionary = net.device
	_phone_panel.status.text = "电量 %d%% · %s%s" % [floori(float(d["battery"])), "学校网络已连接" if d["network"] else "尚未联网", " · 耗电 ×2" if talent() != null and talent().has("tech") else ""]
	_phone_panel.copy.text = _phone_copy() if net.page != "plane" else ""
	var action := ""
	var label := ""
	var disabled := false
	match net.page:
		"wireless":
			var ws := String(d["wireless"]["status"])
			action = "wireless"
			disabled = ws == "complete"
			label = "暂停任务" if ws == "running" else ("开始接入" if ws == "idle" else ("已连接" if ws == "complete" else "继续任务"))
		"container":
			var ds := String(d["download"]["status"])
			action = "download"
			disabled = not ["running", "paused"].has(ds)
			label = "暂停下载" if ds == "running" else ("继续下载" if ds == "paused" else ("已安装" if ds == "complete" else "等待联网"))
		"sync":
			action = "sync"
			label = "同步门禁数据"
	if net.page == "camera" and camera() != null:
		_phone_panel.copy.text = camera().copy_text()
		_phone_panel.show_album(camera().photos, camera().flash)
	_phone_panel.select(net.page, action, label, disabled)
	_phone_panel.screen.queue_redraw()


func _phone_shell_step(delta: float) -> void:
	var net := phone()
	var ends := net.plane.tick(delta, float(school().pressure()["rest"]), func() -> float: return _phone_random.randf())
	for e: Dictionary in ends:
		if float(e["gain"]) > 0.0:
			school().san = minf(100.0, school().san + float(e["gain"]))
			ui.show_notice("纸飞机 · 得分 %d" % int(e["score"]))
		audio.play("ui.click")
	if not phone_open():
		return
	var danger := net.page == "plane" and _phone_danger()
	if story().dead or danger or ui.choice_open() or ui.terminal_open() or school().inspection_active() or not net.available():
		_close_phone(danger and not story().dead)
		return
	_phone_paint()


# ---- the snake game at the lab computer (game/features/phone/snake_game.gd, game/presentation/ui/snake_panel.gd) ----

var _snake := SnakeGame.new()
var _snake_panel: SnakePanel
var _snake_random := RandomNumberGenerator.new()


func snake_open() -> bool:
	return _snake.on


func _start_snake() -> void:
	if _snake_panel == null:
		_snake_panel = SnakePanel.new()
		_snake_panel.turned.connect(func(d: Vector2i) -> void: _snake.turn(d))
		_snake_panel.closed.connect(_stop_snake)
		ui.get_node("Root").add_child(_snake_panel)
		_snake_panel.board.game = _snake
		_snake_panel.game = _snake
	_snake.start(func() -> float: return _snake_random.randf())
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_snake_panel.hint.text = ("方向键或在画面上滑动转向 · 点「离开」退出" if ui.touch_enabled() else "WASD / 方向键转向 · Esc 退出") + " · 玩一会儿，缓口气"
	_snake_panel.visible = true
	audio.play("ui.click")


## Leaving the game (Esc, the exit button): the score earns rest. cancelled: a session end, no reward.
func _stop_snake(cancelled: bool = false) -> void:
	if not _snake.on:
		return
	var gain := _snake.gain(float(school().pressure()["rest"])) if not cancelled and school() != null else 0.0
	var score := _snake.score
	_snake.cancel()
	if _snake_panel != null:
		_snake_panel.visible = false
	if cancelled:
		return
	fact({"kind": "snake", "score": score})
	if gain > 0.0:
		school().san = minf(100.0, school().san + gain)
		ui.show_notice("游戏结束 · 得分 %d" % score)
	if session != null and session.running and not get_tree().paused and not story().dead:
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _snake_step(delta: float) -> void:
	if not _snake.on:
		return
	if story().dead:
		_stop_snake(true)
		return
	var key := Vector2i.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		key = Vector2i(0, -1)
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		key = Vector2i(0, 1)
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		key = Vector2i(-1, 0)
	elif Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		key = Vector2i(1, 0)
	_snake.tick(delta, key, func() -> float: return _snake_random.randf())
	if _snake_panel != null:
		_snake_panel.board.queue_redraw()


# ---- score, grade and clear records (game/features/progress/run_score_module.gd, run_log.gd, run_records.gd) ----

var _runlog := RunLog.new(CampusData.rooms())
var _last_result: Dictionary = {}
var _runs_store: RunRecords
var _runs_path := ""
var _ach_logged := 0


## The clear records of this device (next to the saves).
func runs() -> RunRecords:
	var dir := saves.side_path("records")
	if _runs_store == null or _runs_path != dir:
		_runs_store = RunRecords.new(dir)
		_runs_path = dir
	return _runs_store


func _score_fact(f: Dictionary) -> void:
	var sm := runscore()
	if sm == null:
		return
	sm.fact(f)
	match String(f["kind"]):
		"lesson":
			if bool(f.get("correct", false)):
				sm.add_clue("lesson", school().day)
		"ending":
			_runlog.point(true)
			if not bool(f.get("fake", false)):
				_runlog.event("ending", "结局" + String(f["id"]), 0)
		"death":
			_runlog.event("death", "死去，又在座位上惊醒" if bool(f.get("wake", false)) else "死亡", 0)
		"rest":
			_runlog.event("rest", String(FacilitiesModule.SAN_ACTS.get(String(f["key"]), {}).get("n", "休息")), 0)
		"garage":
			_runlog.event("garage", "手电照退了车库里的东西" if f.get("what") == "torch" else "开走了车", 0)
		"specialDay":
			_runlog.event("day", "特殊的上学日", 0)
		"day":
			_runlog.event("day", "第 %d 天" % int(f["day"]), 0)


func _runlog_room(id: String) -> void:
	var r: Variant = campus().room(id)
	_runlog.scene = id
	_runlog.point(true)
	_runlog.event("room", "进入 " + (String(r.get("name", id)) if r != null else id), 0)


func _score_step(delta: float) -> void:
	var sm := runscore()
	if sm == null or story().dead:
		return
	sm.observe_san(school().san)
	if items() != null:
		if items().has("roomkey"):
			sm.add_clue("roomkey", school().day)
		if items().has("atlas"):
			sm.add_clue("atlas", school().day)
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	sm.zone_tick(delta, session.world_id, w if room == null else Vector2(-1e9, -1e9))
	if not sm.on_event.is_valid():
		sm.on_event = func(kind: String, text: String, pts: int) -> void: _runlog.event(kind, text, pts)
	var watcher := patrol()
	_runlog.now_s = session.clock.active_seconds
	_runlog.scene = session.world_id
	_runlog.pos = w
	_runlog.ang = CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	_runlog.day = school().day
	_runlog.tsec = school().tsec
	var fresh: Array = []
	var ach := achievements()
	if ach != null:
		for id: String in ach.run_new:
			fresh.append(String(AchievementsModule.LIST[id][1]))
	var pstate := {}
	if watcher != null:
		pstate = {"walk": watcher.pat["state"] == "walk", "room": String(watcher.pat["room"]), "x": float(watcher.pat["x"]), "y": float(watcher.pat["y"])}
	if _runlog.tick(delta, pstate, fresh):
		_write_side("runlog_cur.json", _runlog.pack())


## Everything the ending's score needs from the other modules.
func _score_context() -> Dictionary:
	var sm := runscore()
	var ach := achievements()
	var run_ach: Array = []
	var new_ach: Array = []
	var ach_rows: Array = []
	if ach != null:
		for id: String in ach.run_new:
			run_ach.append(id)
			new_ach.append(id)
			if not AchievementsModule.SCORELESS.has(id):
				ach_rows.append({"name": "%s · %s" % [AchievementsModule.TIERS[AchievementsModule.LIST[id][0]]["name"], AchievementsModule.LIST[id][1]], "pts": int(AchievementsModule.TIERS[AchievementsModule.LIST[id][0]]["pts"])})
	var extra: Array = []
	if anomaly() != null:
		extra.append_array(anomaly().clues.keys())
	if routes() != null:
		extra.append_array(routes().clues.keys())
	var rta := 0.0
	var mode := "normal"
	if not speedrun.run.is_empty() and speedrun.run.get("ms") != null:
		mode = "speedrun"
		rta = float(speedrun.run["ms"]) / 1000.0
	return {"achievements": ach_rows, "san": school().san, "explore": sm.explore(exploration(), extra), "diff": story().diff, "talent": talent().id if talent() != null else "none",
		"day": school().day, "clock": school().tsec, "active": session.clock.active_seconds, "rta": rta, "mode": mode, "run_ach": run_ach, "new_ach": new_ach, "version": "godot"}


## At a clear: the score, the time score and the grade; a rated run goes into the records with its replay.
func _score_ending(id: String, title: String) -> Dictionary:
	var sm := runscore()
	if sm == null:
		return {}
	var ctx := _score_context()
	ctx["route_name"] = title.replace(" ", "")
	var res := sm.finish({"id": id, "legit": true}, ctx)
	var dlc:=rules_dlc_flow.module()
	if dlc.active():
		dlc.set_context(rules_dlc_flow.context())
		res["rated"]=bool(res["rated"]) and not bool(dlc.state["tainted"])
		res["debug"]=not bool(res["rated"])
		if res["rated"]:
			res.merge({"variant":RulesDlcModule.VARIANT,"variantName":"规则怪谈","variantGroup":dlc.state["bundle"]})
	if bool(res.get("rated", false)):
		var pack := _runlog.finish()
		if exploration() != null:
			pack["sketch"] = exploration().capture().get("seen", {})
		res["id"] = runs().add(res, pack)
		_write_side("runlog_cur.json", null)
	return res


func _score_death() -> void:
	var sm := runscore()
	if sm == null:
		return
	sm.death_line(_score_context())
	_runlog.discard()
	_write_side("runlog_cur.json", null)


## The result page after a clear (ending card → 结算).
func _open_results() -> void:
	if _last_result.is_empty():
		return
	var m := _last_result
	var rec := runs().get_record(String(m.get("id", ""))) if String(m.get("id", "")) != "" else {}
	ui.show_results(rec if not rec.is_empty() else m, {"replay": runs().replay(String(m.get("id", ""))) if String(m.get("id", "")) != "" else {},
		"back_label": "回到主菜单"})
	_wire_results(_results_back)


var _results_back_to: Callable


## The main menu's 通关记录: the list; a row opens the result page, whose 回放 / 足迹图 open the viewer.
func _open_records() -> void:
	var panel := ui.show_records(runs(), CampusData.rooms())
	if not panel.detail_requested.is_connected(_record_detail):
		panel.detail_requested.connect(_record_detail)
		panel.sample_requested.connect(func(g: String) -> void:
			var m := ScoreRules.sample_meta(g, "car")
			m["source"] = "archive"
			panel.visible = false
			ui.show_results(m, {"back_label": "返回记录", "silent": true})
			_wire_results(func() -> void:
				ui.hide_results()
				panel.reopen()))


func _record_detail(id: String) -> void:
	var rec := runs().get_record(id)
	if rec.is_empty():
		return
	ui.records_panel.visible = false
	ui.show_results(rec, {"replay": runs().replay(id), "back_label": "返回记录", "silent": true})
	_wire_results(func() -> void:
		ui.hide_results()
		ui.records_panel.reopen())


## The result page's buttons: back (where to go), and the viewers of the record.
func _wire_results(back: Callable) -> void:
	var rp := ui.results_panel
	for sig: Signal in [rp.back_pressed, rp.footprint_pressed, rp.replay_pressed]:
		for c in sig.get_connections():
			sig.disconnect(c["callable"])
	rp.back_pressed.connect(back)
	var panel := ui.ensure_records(runs(), CampusData.rooms())
	rp.footprint_pressed.connect(func(rid: String) -> void:
		ui.hide_results()
		panel.open_view(rid, true))
	rp.replay_pressed.connect(func(rid: String) -> void:
		ui.hide_results()
		panel.open_view(rid, false))


func _results_back() -> void:
	ui.hide_results()
	if _results_back_to.is_valid():
		var f := _results_back_to
		_results_back_to = Callable()
		f.call()
	else:
		return_to_menu()


func _death_score_line() -> String:
	var dl := runscore().last_death_line() if runscore() != null else {}
	if dl.is_empty() or not dl.has("total"):
		return ""
	return "调试局 · 不计分" if bool(dl.get("debug", false)) else "本局积分 %d · 探索度 %d%%" % [int(dl["total"]), int(dl["explore"])]


# ---- the protagonist's muttering (game/features/story/mono_module.gd) ----

func _mono_step(delta: float) -> void:
	var m := mono()
	if m == null or story().dead:
		return
	var room: Variant = campus().room(session.world_id)
	var p: Array = player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var day_rules := school()
	m.set_context({"scene": session.world_id, "x": w.x, "y": w.y, "tile": CampusGeometry.tile_at(room, w) if room != null else "", "san": day_rules.san,
		"night": SchoolClock.is_night(day_rules.tsec), "busy": bool(_dread_context()["busy"]),
		"seated_class": day_rules.seated and SchoolClock.need_where(day_rules.tsec) == "教室"})
	m.tick(delta)
	for e: Dictionary in m.take_events():
		ui.show_notice(String(e["text"]))


# ---- classmates (game/features/school/classmates_module.gd) ----

var _mates_nodes: Node3D
var _mates_key := ""
var _atmos_busy := false


func _classmates_step(delta: float) -> void:
	var mates := classmates()
	if mates == null:
		return
	var room: Variant = campus().room(session.world_id)
	var p: Array = player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var day_rules := school()
	mates.tick(session.world_id, w, day_rules.viol, story().dead)
	for e: Dictionary in mates.take_events():
		ui.show_notice(String(e["text"]))
	var d: Variant = mates.state.get("door")
	if bool(mates.state.get("blocking", false)) and d is Dictionary and room != null:
		campus().force_close(CampusGeometry.door_key(room, int(d["c"]), int(d["r"])))
	var drain := mates.pressure(session.world_id, day_rules.viol)
	if drain > 0.0 and not story().dead and day_rules.san > 1.0:
		day_rules.san = maxf(1.0, day_rules.san - drain * delta)
	_show_classmates(mates, room, w, day_rules.viol >= 70.0)


## Seated classmates (placeholder figures on the chairs), facing the board or, at 70+, the player.
func _show_classmates(mates: ClassmatesModule, room: Variant, me: Vector2, staring: bool) -> void:
	var world := _campus_world()
	if world == null or room == null or not ClassmatesModule.eligible(room):
		if is_instance_valid(_mates_nodes):
			_mates_nodes.queue_free()
		_mates_nodes = null
		_mates_key = ""
		return
	var key := session.world_id
	if key != _mates_key or not is_instance_valid(_mates_nodes) or _mates_nodes.get_parent() != world:
		_mates_key = key
		if is_instance_valid(_mates_nodes):
			_mates_nodes.queue_free()
		_mates_nodes = Node3D.new()
		_mates_nodes.name = "Classmates"
		world.add_child(_mates_nodes)
		for t: Vector2i in mates.layout(session.world_id)["seats"]:
			var k := ClassmatesModule.DESK_ROWS.find(t.y)
			var shift := (0.11 if k % 2 == 0 else -0.11) if k >= 0 else 0.0
			var wp := Vector2(float(room["ox"]) + (t.x + 0.8) * float(room["tw"]), float(room["oy"]) + (t.y + 0.5 + shift) * float(room["th"]))
			var sp := CampusGeometry.to_scene(room, wp)
			var fig := FigureModel.make("sit", Color(0.32, 0.34, 0.4))
			fig.position = Vector3(sp.x, 0.0, sp.y)
			fig.set_meta("w", wp)
			fig.set_meta("cls", "%s:%d" % [key, AtmosModule.class_index(t.x, t.y)])
			_mates_nodes.add_child(fig)
	# A3 (atmos_module.gd): a class turns to you and back; after a return one more seat is empty.
	var mood := atmos()
	var turn := 0.0
	var turning := ""
	var day_i := school().day
	if mood != null and not mood.stare.is_empty() and mood.stare["room"] == key:
		var tt := float(mood.stare["t"])
		var tm: float = AtmosModule.CFG["stare_turn"]
		var th: float = AtmosModule.CFG["stare_hold"]
		var kk := tt / tm if tt < tm else (1.0 if tt < tm + th else maxf(0.0, 1.0 - (tt - tm - th) / tm))
		turn = kk * kk * (3.0 - 2.0 * kk)
		turning = String(mood.stare["cls"])
	var by_class := {}
	for fig: Node in _mates_nodes.get_children():
		var f := fig as Node3D
		var wp: Vector2 = f.get_meta("w")
		var target := me if staring else wp + Vector2(-10, 0)
		var base := -atan2(target.y - wp.y, target.x - wp.x) - PI * 0.5
		var cls: String = f.get_meta("cls")
		if turn > 0.0 and cls == turning:
			var want := -atan2(me.y - wp.y, me.x - wp.x) - PI * 0.5
			base += wrapf(want - base, -PI, PI) * turn * 0.85
		f.rotation.y = base
		var list: Array = by_class.get(cls, [])
		list.append(f)
		by_class[cls] = list
	for cls: String in by_class:
		var gone := int(mood.seats.get("%d:%s" % [day_i, cls], 0)) if mood != null and not _atmos_busy and school().viol < 35.0 else 0
		var list: Array = by_class[cls]
		for i in list.size():
			(list[i] as Node3D).visible = not (gone > 0 and i == gone % list.size())


# ---- chalk marks and the last life (game/features/campus/marks_module.gd) ----

var _marks_nodes: Node3D
var _marks_key := ""


func _read_side(name: String) -> Variant:
	var path := saves.side_path(name)
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	return null


func _write_side(name: String, data: Variant) -> void:
	var path := saves.side_path(name)
	if data == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func _marks_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var solid := func(q: Vector2) -> bool:
		if maze_flow.here():
			var scene := CampusGeometry.to_scene(room, q)
			return maze().geometry.depth_at(scene.x, scene.y, 0.00001, float(p[1])) > 0.0
		if room != null:
			return CampusGeometry.SOLID_CH.contains(CampusGeometry.tile_at(room, q))
		return not _can_stand(q, null, 0.0)
	var floor_at := func(q: Vector2) -> Variant:
		if not maze_flow.here():
			return float(p[1])
		var scene := CampusGeometry.to_scene(room, q)
		var height := maze().geometry.ground_at(scene.x, scene.y, float(p[1]) + 0.42)
		return height if is_finite(height) and height >= float(p[1]) - 1.5 else null
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "pitch": float(pose["pitch"]),
		"solid": solid, "floor": float(p[1]), "eye": player.camera.position.y, "floor_at": floor_at, "has_chalk": items() != null and items().has("chalk")}


func _apply_marks_events() -> void:
	var mk := marks()
	if mk == null:
		return
	for e: Dictionary in mk.take_events():
		match e["kind"]:
			"record":
				_record(e)
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"save":
				save_game()
			"changed":
				_marks_key = ""
			"fact":
				fact({"kind": "chalk", "sym": e["sym"]})
				audio.play("foley.chalk")
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var m := marks()
					if m != null and mine == _choice_count:
						m.choose(index)
						_apply_marks_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"])


## Chalk marks of this scene (and last run's ×) as flat labels on the wall or the floor.
func _show_marks() -> void:
	var mk := marks()
	var world := _campus_world()
	if mk == null or world == null:
		return
	var key := "%s:%d:%d" % [session.world_id, mk.serial, mk.marks.size()]
	if key == _marks_key and is_instance_valid(_marks_nodes) and _marks_nodes.get_parent() == world:
		return
	_marks_key = key
	if is_instance_valid(_marks_nodes):
		_marks_nodes.queue_free()
	_marks_nodes = Node3D.new()
	_marks_nodes.name = "ChalkMarks"
	world.add_child(_marks_nodes)
	var room: Variant = campus().room(session.world_id)
	var list: Array = mk.visible(session.world_id).duplicate()
	if maze_flow.here():
		list.append_array(maze_flow.chalk_presets())
	if mk.last_life is Dictionary and String(mk.last_life.get("scene", "")) == session.world_id:
		list.append({"x": mk.last_life["x"], "y": mk.last_life["y"], "h": 0.0, "face": "floor", "a": 0.0, "text": "× " + SchoolClock.fmt_clock(float(mk.last_life.get("tsec", 700))), "old": true})
	for m: Dictionary in list:
		var sp := CampusGeometry.to_scene(room, Vector2(float(m["x"]), float(m["y"])))
		if not m.has("text") and ChalkTexture.SYMBOLS.has(String(m.get("s", ""))):
			# The hand-drawn chalk picture (game/presentation/world/campus/chalk_texture.gd), lit by the scene.
			var sym := String(m["s"])
			var old := bool(m.get("old", false))
			var jj := fposmod(sin(float(absi(int(m.get("n", 0))) * 3 + 1) * 12.9898 + float(sym.length() * 7) * 78.233) * 43758.5453, 1.0)
			var quad := MeshInstance3D.new()
			var qm := QuadMesh.new()
			quad.mesh = qm
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = ChalkTexture.texture(sym)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.84, 0.8, 0.71, 0.5) if old else Color(1, 1, 1, 0.92)
			mat.roughness = 1.0
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.render_priority = 2
			quad.material_override = mat
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			quad.rotation_order = EULER_ORDER_YXZ
			if m["face"] == "floor":
				var sz := 0.8 * (0.92 + 0.16 * jj)
				qm.size = Vector2(sz, sz)
				quad.position = Vector3(sp.x, float(m["h"]) + 0.012, sp.y)
				quad.rotation = Vector3(-PI * 0.5, -float(m["a"]) - PI * 0.5 + (jj - 0.5) * 0.16, 0.0)
			else:
				var sw := 0.6 * (0.92 + 0.16 * jj)
				qm.size = Vector2(sw, sw)
				quad.position = Vector3(sp.x + cos(float(m["a"])) * 0.012, float(m["h"]) + float(m.get("f", 0.0)), sp.y + sin(float(m["a"])) * 0.012)
				quad.rotation = Vector3(0.0, -float(m["a"]) + PI * 0.5, (jj - 0.5) * 0.14)
			_marks_nodes.add_child(quad)
			continue
		var label := Label3D.new()
		label.text = String(m.get("text", MarksModule._sym(String(m.get("s", "x")))))
		label.font_size = 96
		label.pixel_size = 0.004
		label.modulate = Color(0.92, 0.91, 0.86, 0.55 if m.get("old", false) else 0.9)
		label.shaded = false
		label.double_sided = true
		if m["face"] == "floor":
			label.position = Vector3(sp.x, float(m["h"]) + 0.012, sp.y)
			label.rotation = Vector3(-PI * 0.5, -float(m["a"]) - PI * 0.5, 0.0)
		else:
			label.position = Vector3(sp.x, float(m["h"]) + float(m.get("f", 0.0)), sp.y)
			label.rotation.y = -float(m["a"]) + PI * 0.5
		_marks_nodes.add_child(label)


# ---- paper planes (game/features/story/paper_plane_module.gd) ----

var _plane_nodes: Node3D
var _plane_pose: Variant = null


func _paper_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var weird := anomaly()
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "now": session.clock.active_seconds,
		"dead": story().dead, "can_stand": _can_stand.bind(room, float(p[1])),
		"busy": (weird != null and weird.is_active()) or player.hiding or school().seated or school().inspection_pending() or school().inspection_upcoming()
			or (patrol() != null and patrol().local_chase()) or (gaze() != null and not gaze().current().is_empty()),
		"steer": {"l": Input.get_action_strength("move_left"), "r": Input.get_action_strength("move_right"), "u": Input.get_action_strength("move_forward"), "d": Input.get_action_strength("move_back")}}


func _paper_step(delta: float) -> void:
	var plane := paper()
	if plane == null:
		return
	plane.set_context(_paper_context())
	plane.tick(delta)
	_show_plane(plane)
	_apply_paper_events()


func _show_plane(plane: PaperPlaneModule) -> void:
	var e: Variant = plane.s["ev"]
	var here: bool = e != null and session.world_id == String(e["room"]) and e["phase"] != "hunt"
	if not here:
		if is_instance_valid(_plane_nodes):
			_plane_nodes.queue_free()
		_plane_nodes = null
		if _plane_pose != null:
			player.restore_pose(_plane_pose)
			_plane_pose = null
			player.enabled = true
		return
	var world := _campus_world()
	if world == null:
		return
	if not is_instance_valid(_plane_nodes):
		_plane_nodes = Node3D.new()
		_plane_nodes.name = "PaperPlane"
		var body := MeshInstance3D.new()
		body.name = "Plane"
		var prism := PrismMesh.new()
		prism.size = Vector3(0.22, 0.04, 0.34)
		body.mesh = prism
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.95, 0.93, 0.88)
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		body.material_override = white
		_plane_nodes.add_child(body)
		var hand := MeshInstance3D.new()
		hand.name = "Hand"
		var palm := BoxMesh.new()
		palm.size = Vector3(0.09, 0.16, 0.03)
		hand.mesh = palm
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.8, 0.74, 0.65)
		skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hand.material_override = skin
		_plane_nodes.add_child(hand)
		world.add_child(_plane_nodes)
	var room: Variant = campus().room(session.world_id)
	var w := plane.window_of(e)
	var body_n := _plane_nodes.get_node("Plane") as Node3D
	var hand_n := _plane_nodes.get_node("Hand") as Node3D
	if w.is_empty():
		return
	var wp := CampusGeometry.to_scene(room, w["p"])
	var lp := CampusGeometry.to_scene(room, Vector2(float(e["lx"]), float(e["ly"])))
	hand_n.visible = e["kind"] == "danger" and e["phase"] != "ground"
	hand_n.position = Vector3(wp.x + 0.3, 1.55, wp.y + float(w["nz"]) * 0.14)
	var ph := String(e["phase"])
	body_n.visible = ph in ["fly", "ground", "wait", "flight"]
	if ph == "fly":
		var k := minf(1.0, float(e["t"]) / PaperPlaneModule.FLY_IN)
		body_n.position = Vector3(lerpf(wp.x, lp.x, k), 1.7 - 1.67 * k + 0.3 * sin(k * PI), lerpf(wp.y, lp.y, k))
	elif ph == "ground" or ph == "wait":
		body_n.position = Vector3(lp.x, 0.03, lp.y)
	elif ph == "flight":
		var f: Dictionary = e["f"]
		var fp := CampusGeometry.to_scene(room, Vector2(float(f["x"]), float(f["y"])))
		body_n.position = Vector3(fp.x, float(f["h"]), fp.y)
		body_n.rotation = Vector3(-float(f["pitch"]), -float(f["yaw"]) - PI * 0.5, 0.0)
		if _plane_pose == null:
			_plane_pose = player.capture_pose()
		player.enabled = false
		var back := Vector2(cos(float(f["yaw"])), sin(float(f["yaw"]))) * 0.9
		player.place({"position": [fp.x - back.x, float(f["h"]) + 0.28 - player.camera.position.y, fp.y - back.y], "yaw": CampusGeometry.yaw_from_ang(float(f["yaw"])), "pitch": float(f["pitch"]) - 0.12})


func _apply_paper_events() -> void:
	var plane := paper()
	if plane == null:
		return
	for e: Dictionary in plane.take_events():
		match e["kind"]:
			"record":
				_record(e)
			"notice":
				ui.show_notice(String(e["text"]))
			"fact":
				fact({"kind": "paper", "what": e["what"], "clean": e.get("clean", false)})
			"give":
				plane.gave(_add_item(String(e["id"])))
				_apply_paper_events()
			"steps":
				ui.hide_choice()
				audio.play("dread.steps", {"k": 1.0})
			"read":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var pl := paper()
					if pl == null or mine != _choice_count:
						return
					pl.set_context(_paper_context())
					if index == 0:
						pl.fold()
					else:
						pl.fail("drop")
					_apply_paper_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice("纸上的字：\n" + String(e["text"]), ["折好投回（E）", "扔掉"], false)
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return


# ---- the gaze behind a window (game/features/story/window_gaze_module.gd) ----

var _gaze_nodes: Node3D


func _gaze_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var weird := anomaly()
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "pitch": float(pose["pitch"]), "eye": 1.65,
		"now": session.clock.active_seconds, "san": school().san, "drain_mul": _drain_mul(), "dead": story().dead,
		"busy": (weird != null and weird.is_active()) or player.hiding or school().inspection_pending() or school().inspection_upcoming() or (patrol() != null and patrol().local_chase())
			or (paper() != null and paper().calm(session.clock.active_seconds))}


func _gaze_step(delta: float) -> void:
	var g := gaze()
	if g == null:
		return
	g.set_context(_gaze_context())
	g.tick(delta)
	_show_gaze(g)
	_apply_gaze_events()


func _show_gaze(g: WindowGazeModule) -> void:
	var cur := g.current()
	if cur.is_empty():
		if is_instance_valid(_gaze_nodes):
			_gaze_nodes.queue_free()
		_gaze_nodes = null
		return
	var world := _campus_world()
	if world == null:
		return
	var room: Variant = campus().room(session.world_id)
	var win: Dictionary = cur["w"]
	var sp := CampusGeometry.to_scene(room, win["p"])
	var nz := float(win["nz"])
	if not is_instance_valid(_gaze_nodes):
		_gaze_nodes = Node3D.new()
		_gaze_nodes.name = "WindowGaze"
		var body := FigureModel.make("person", Color(0.04, 0.05, 0.06), true, 0.92)
		body.position = Vector3(0, -0.05, -nz * 0.35)
		_gaze_nodes.add_child(body)
		for dx: float in [-0.045, 0.045]:
			var eye := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.016
			ball.height = 0.02
			eye.mesh = ball
			var white := StandardMaterial3D.new()
			white.albedo_color = Color(0.91, 0.89, 0.83)
			white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			eye.material_override = white
			eye.position = Vector3(dx, WindowGazeModule.EYE, nz * 0.16)
			_gaze_nodes.add_child(eye)
		world.add_child(_gaze_nodes)
	_gaze_nodes.position = Vector3(sp.x, 0.0, sp.y)


func _apply_gaze_events() -> void:
	var g := gaze()
	if g == null:
		return
	for e: Dictionary in g.take_events():
		match e["kind"]:
			"notice":
				ui.show_notice(String(e["text"]))
			"breath":
				var room: Variant = campus().room(session.world_id)
				var bp := CampusGeometry.to_scene(room, e["p"])
				audio.play("threat.breath", {"pos": Vector3(bp.x, 1.6, bp.y)})
				ui.show_notice("（窗后 · 呼吸声）")
			"fact":
				fact({"kind": "gaze", "what": e["what"]})
			"pull":
				var pose := player.capture_pose()
				var ang := CampusGeometry.ang_from_yaw(float(pose["yaw"])) + float(e["yaw"])
				pose["yaw"] = CampusGeometry.yaw_from_ang(ang)
				pose["pitch"] = clampf(float(pose["pitch"]) + float(e["pitch"]), -1.4, 1.4)
				player.place(pose)
			"san":
				school().san = maxf(0.0, school().san + float(e["amount"]))
			"san_zero":
				school().san = 0.0
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				g.after_kill(story().dead)
				return


# ---- campus tales: the midnight canteen and the late mirror ----

func _tales_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "tsec": school().tsec,
		"clock": school().game_clock(), "san": school().san, "tt": school().tt, "dead": story().dead, "day": school().day,
		"special": days().today(school().day, school().tsec) if days() != null else "none", "on_leave": school().on_leave(),
		"seed": phone().run_seed if phone() != null else ""}


func _tales_step(delta: float) -> void:
	var tale := tales()
	if tale == null:
		return
	tale.set_context(_tales_context())
	tale.tick(delta)
	_apply_tales_events()
	var cw := _campus_world()
	if cw != null:
		cw.show_checkup(tale.checkup_today() and session.world_id == TalesModule.CHECKUP["room"], tale.queue_on(), tale.chart_line())


func _apply_tales_events() -> void:
	var tale := tales()
	if tale == null:
		return
	for e: Dictionary in tale.take_events():
		match e["kind"]:
			"clue":
				if e.has("text"):
					_record({"id": e["id"], "text": e["text"], "kind": "线索", "source": String(e.get("source", ""))})
			"record":
				_record(e)
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"advance":
				school().advance_game_time(float(e["minutes"]))
			"san":
				school().san = clampf(school().san + float(e["amount"]), float(e.get("min", -INF)), float(e.get("max", 100.0)))
			"viol":
				school().add_violation(float(e["amount"]))
			"saved":
				save_game()
			"tt":
				school().tt = minf(float(e["cap"]), school().tt + float(e["amount"]))
			"hold":
				school().tt_hold_until = float(e["until"])
			"stamina":
				school().stam = minf(school().stamina_max(), school().stam + float(e["amount"]))
			"fact":
				fact({"kind": "midnightMeal", "n": int(e["n"])})
				save_game()
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var t := tales()
					if t != null and mine == _choice_count:
						t.set_context(_tales_context())
						t.choose(index)
						_apply_tales_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], false)
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return


# ---- special days and desk lessons (game/features/school/day_module.gd) ----

func _lesson_context() -> Dictionary:
	var day_rules := school()
	var room: Variant = campus().room(session.world_id)
	var p: Array = player.capture_pose()["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var weird := anomaly()
	var ok: bool = day_rules.seated and day_rules.at_my_seat(session.world_id, w) and SchoolClock.need_where(day_rules.tsec) == "教室" \
		and not player.hiding and not (weird != null and weird.is_active()) and not (patrol() != null and patrol().local_chase()) \
		and not day_rules.inspection_pending() and not day_rules.inspection_upcoming() and not story().dead
	return {"available": ok, "day": day_rules.day, "tsec": day_rules.tsec, "room": session.world_id, "exam": day_rules.exam_now(),
		"quiet": day_rules.inspection_pending() or day_rules.inspection_upcoming()}


func _day_step(_delta: float) -> void:
	var dm := days()
	if dm == null:
		return
	dm.tick_day(school().day, school().tsec)
	if dm.waiting != null and not dm.wait_allowed(_lesson_context()):
		dm.waiting = null
	_apply_day_events()


func _lesson_press() -> void:
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	var dm := days()
	if dm == null or ui.choice_open():
		return
	var inv := investigation()
	if inv != null:
		inv.set_context(_invest_context())
		if inv.open_desk():
			_apply_invest_events()
			return
	dm.press(_lesson_context())
	_apply_day_events()


## LESSON.fastForward: studying runs extra full simulation steps (6× in all), never a jump.
func _study_fast_forward(delta: float) -> void:
	var dm := days()
	for _i in 5:
		if dm == null or dm.waiting == null or story().over() or story().dead:
			return
		if not dm.wait_allowed(_lesson_context()):
			dm.waiting = null
			return
		session.advance(delta, router.current.advances_calendar)
		_campus_step(delta)


func _apply_day_events() -> void:
	var dm := days()
	if dm == null:
		return
	for e: Dictionary in dm.take_events():
		match e["kind"]:
			"record":
				_record(e)
			"notice":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = minf(float(e.get("max", 100.0)), school().san + float(e["amount"]))
			"save":
				save_game()
			"fact":
				if e["what"] == "specialDay":
					fact({"kind": "specialDay", "id": e["id"]})
				else:
					fact({"kind": "lesson", "task": e["task"], "correct": e["correct"]})
			"choice":
				_choice_count += 1
				var mine := _choice_count
				var menu := String(e["menu"])
				_choice_handler = func(index: int) -> void:
					var d := days()
					if d == null or mine != _choice_count:
						return
					if menu == "lesson":
						d.answer(index, _lesson_context())
					elif index == 0:
						d.start_wait(school().day, school().tsec, session.world_id)
					elif index == 1:
						_stand_up()
					_apply_day_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], menu != "lesson")
				if e.has("timer"):
					_choice_left = float(e["timer"])


# ---- the exchange visit and 《外国语学生》 (game/features/story/exchange_module.gd) ----

var _visit_nodes: Node3D


func _exchange_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var nav := CampusData.patrol_nav()
	return {"scene": session.world_id, "x": w.x, "y": w.y, "day": school().day, "tsec": school().tsec, "dead": story().dead,
		"busy": (anomaly() != null and anomaly().is_active()) or school().inspection_pending(),
		"los": func(a: Vector2, b: Vector2) -> bool: return nav.los(PatrolNav.point("out", a.x, a.y), PatrolNav.point("out", b.x, b.y))}


func _exchange_step(delta: float) -> void:
	var visit := exchange()
	if visit == null:
		return
	visit.set_context(_exchange_context())
	visit.tick(delta)
	_show_visit(visit)
	_apply_exchange_events()


func _show_visit(visit: ExchangeModule) -> void:
	var show := visit.visible() and session.world_id == "out"
	if not show:
		if is_instance_valid(_visit_nodes):
			_visit_nodes.queue_free()
		_visit_nodes = null
		return
	var world := _campus_world()
	if world == null:
		return
	if not is_instance_valid(_visit_nodes):
		_visit_nodes = Node3D.new()
		_visit_nodes.name = "ExchangeVisit"
		world.add_child(_visit_nodes)
		for i in 7:
			var fig := FigureModel.make("person", Color(0.2, 0.25, 0.4) if i == 0 else (Color(0.7, 0.62, 0.5) if i < 4 else Color(0.03, 0.03, 0.04)), i >= 4, 0.93)
			_visit_nodes.add_child(fig)
		# The bilingual reception sign outside the north gate of the administration building (exchange-fx.js sign()).
		var gp: Vector2 = visit.members()[0]
		var sp := CampusGeometry.to_scene(null, Vector2(gp.x + 30.0, gp.y + 4.0))
		var plate := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(1.2, 0.75)
		plate.mesh = pq
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color("#eef0ea")
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pm.emission_enabled = true
		pm.emission = Color(0.33, 0.33, 0.33)
		plate.material_override = pm
		plate.position = Vector3(sp.x, 1.2, sp.y)
		_visit_nodes.add_child(plate)
		var lines := [["国际交流 · 接待登记", 0.13, 0.22], ["Austausch · Anmeldung", 0.085, 0.0], ["Échange · Inscription", 0.085, -0.17]]
		for ln: Array in lines:
			var tl := Label3D.new()
			tl.text = String(ln[0])
			tl.font_size = 48
			tl.pixel_size = float(ln[1]) / 48.0 * 0.9
			tl.modulate = Color("#22324a")
			tl.shaded = false
			tl.double_sided = true
			tl.position = Vector3(0, float(ln[2]), 0.003)
			plate.add_child(tl)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.06, 1.2, 0.06)
		leg.mesh = lm
		var legm := StandardMaterial3D.new()
		legm.albedo_color = Color("#555b5e")
		leg.material_override = legm
		leg.position = Vector3(sp.x, 0.6, sp.y + 0.02)
		_visit_nodes.add_child(leg)
	var spots: Array = visit.members()
	for h: Dictionary in visit.s.get("search", []):
		spots.append(Vector2(float(h["x"]), float(h["y"])))
	for i in 7:
		var fig := _visit_nodes.get_child(i) as Node3D
		fig.visible = i < spots.size()
		if fig.visible:
			var sp := CampusGeometry.to_scene(null, spots[i])
			fig.position = Vector3(sp.x, 0.0, sp.y)


func _apply_exchange_events() -> void:
	var visit := exchange()
	if visit == null:
		return
	for e: Dictionary in visit.take_events():
		match e["kind"]:
			"notice":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = maxf(school().san + float(e["amount"]), float(e.get("min", -INF)))
			"permit":
				school().leave_until = maxf(school().leave_until, float(e["until"]))
			"fact":
				var f: Dictionary = e.duplicate()
				f["kind"] = "exchange"
				fact(f)
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var v := exchange()
					if v != null and mine == _choice_count:
						v.set_context(_exchange_context())
						v.choose(index)
						_apply_exchange_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], not bool(e.get("locked", false)))
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"ending":
				_reach_ending(String(e["id"]))
				return


# ---- vaulting, injury and the clinic (features/body) ----

var _fall_back: Variant = null


func _body_context() -> Dictionary:
	var room: Variant = campus().room(session.world_id)
	var pose := player.capture_pose()
	var p: Array = pose["position"]
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	return {"scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "seated": school().seated,
		"hiding": player.hiding, "stam": school().stam, "moving": player.moving, "locked": patrol() != null and bool(patrol().pat["locked"]),
		"anomaly": anomaly() != null and anomaly().is_active(), "day": school().day, "dead": story().dead,
		"space": player.enabled and Input.is_key_pressed(KEY_SPACE) and not ui.choice_open()}


func _body_step(delta: float) -> void:
	var limbs := body()
	if limbs == null:
		return
	limbs.set_context(_body_context())
	limbs.tick(delta)
	if limbs.hold > 0.0:
		ui.show_search(limbs.hold / BodyModule.VAULT_HOLD)
	player.update_view(delta, limbs.eye_drop()+(inception().eye_drop() if inception_flow.here() else 0.0))
	if limbs.fall != null:
		player.enabled = false
	var cap := school().stamina_max() - limbs.stamina_cap_drop()
	if school().stam > cap:
		school().stam = maxf(0.0, cap)
	_apply_body_events()


func _apply_body_events() -> void:
	var limbs := body()
	if limbs == null:
		return
	for e: Dictionary in limbs.take_events():
		match e["kind"]:
			"notice":
				ui.show_notice(String(e["text"]))
			"hurt_fx":
				ui.flash_hurt(0.5)
			"stamina":
				school().stam = maxf(0.0, school().stam + float(e["amount"]))
			"fact":
				if e["what"] == "landed":
					fact({"kind": "vault", "what": "landed"})
				elif e["what"] == "treated":
					fact({"kind": "treated"})
			"give":
				if _add_item(String(e["id"])):
					limbs.gave_medkit(String(e["day"]))
					_apply_body_events()
			"remove":
				if items() != null:
					items().remove(String(e["id"]))
			"land":
				_land_outside(String(e["room"]), int(e["side"]))
				player.enabled = true
			"choice":
				_choice_count += 1
				var mine := _choice_count
				_choice_handler = func(index: int) -> void:
					var b := body()
					if b != null and mine == _choice_count and index == 0:
						b.set_context(_body_context())
						b.vault()
						_apply_body_events()
				player.enabled = false
				player.clear_input()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				ui.show_choice(String(e["text"]), e["labels"], false)
			"kill":
				_fall_back = e.get("back")
				player.reset_view()
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				if not story().dead:
					player.enabled = true
				return


## landOutside: next to the bridge's own footprint outside, on the side the player went over.
func _land_outside(room_id: String, side: int) -> void:
	var r: Variant = campus().room(room_id)
	var host := String(r.get("host", "")) if r != null else ""
	var target := Vector2(1000, 1000)
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == host:
			var cx := (float(o["x"]) + float(o["w"]) / 2.0) * 2.0
			var cy := (float(o["y"]) + float(o["h"]) / 2.0) * 2.0
			var off := (float(o["w"]) / 2.0 + 5.0) * 2.0 * float(side if side != 0 else 1)
			target = Vector2(cx + off, cy)
			for k in 12:
				var tp := Vector2(cx + off + float(k % 3 - 1) * 6.0, cy + (floor(k / 3.0) - 1.5) * 10.0)
				if _can_stand(tp, null, 0.0):
					target = tp
					break
	var s := CampusGeometry.to_scene(null, target)
	travel("out", {"position": [s.x, 0.05, s.y], "yaw": player.capture_pose()["yaw"], "pitch": 0.0}, false)


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
	_fake_people_step(fnm, room)


# ---- the "normal people" of the fake-normal day (engine/presentation.js fnPeopleBuild) ----

var _fake_people: Node3D
var _fake_people_room := ""
var _fake_people_random := RandomNumberGenerator.new()


func _fake_people_clear() -> void:
	if is_instance_valid(_fake_people):
		_fake_people.queue_free()
	_fake_people = null
	_fake_people_room = ""


## While the fake-normal day is on (laughs below 72) four dull figures stand in a room facing you, 2.2–7.5 m
## away on open tiles; they are rebuilt when you change room and gone when it ends.
func _fake_people_step(fnm: FakeNormalModule, room: Variant) -> void:
	var on := fnm.active() and float(fnm.fn["v"]) < 72.0 and room != null and not story().dead
	if not on:
		if _fake_people != null:
			_fake_people_clear()
		return
	var world := _campus_world()
	if world == null or (is_instance_valid(_fake_people) and _fake_people_room == session.world_id and _fake_people.get_parent() == world):
		return
	_fake_people_clear()
	_fake_people_room = session.world_id
	_fake_people = Node3D.new()
	_fake_people.name = "FakeNormalPeople"
	world.add_child(_fake_people)
	var p: Array = player.capture_pose()["position"]
	var me := Vector2(float(p[0]), float(p[2]))
	var grid: Array = room["grid"]
	var made := 0
	var tries := 0
	while made < 4 and tries < 160:
		tries += 1
		var c := 1 + _fake_people_random.randi() % maxi(1, int(room["cols"]) - 2)
		var r := 1 + _fake_people_random.randi() % maxi(1, int(room["rows"]) - 2)
		var ch := String(grid[r]).substr(c, 1)
		if ch in ["#", "=", "O", "S", "L"]:
			continue
		var s := CampusGeometry.to_scene(room, Vector2(float(room["ox"]) + (c + 0.5) * float(room["tw"]), float(room["oy"]) + (r + 0.5) * float(room["th"])))
		var d := s.distance_to(me)
		if d < 2.2 or d > 7.5:
			continue
		var fig := FigureModel.make("person", Color("#41505c"), true, 0.92)
		fig.position = Vector3(s.x, 0.0, s.y)
		fig.rotation.y = atan2(s.x - me.x, s.y - me.y)
		_fake_people.add_child(fig)
		made += 1


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
			"fact_laugh":
				fact({"kind": "fakeNormal", "laugh": bool(e["laugh"])})
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
	elif route == "beast":
		var room: Variant = campus().room(session.world_id)
		var p: Array = player.capture_pose()["position"]
		if session.world_id != "teach1" or not RoutesModule.in_stall(room,CampusGeometry.to_world(room,p[0],p[2])):
			ui.show_notice("我：得在教学楼一楼的厕所里，第三个隔间门口。")
		elif r.open_stall(session.world_id):
			facilities().spots["stall"] = true
			_apply_route_events(r)
		else:
			facilities()._stall(session.world_id)
			_apply_facility_events()


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
	_phone_shell_step(delta)
	_snake_step(delta)
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
			"record":
				_record(e)
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


# ---- the broadcast station and 《放学》 (game/features/story/broadcast_module.gd) ----

var _mic_open := false
var _mic_panel: MicPanel
var _mic_hold_button := false
var _radio_job: Variant = null   # {index, t, seconds, x, y, scene}
var _crowd_nodes: Node3D


func _broadcast_context() -> Dictionary:
	var ctx := _facility_context()
	var weird := anomaly()
	var gates: Dictionary = CampusData.campus().get("gates", {})
	var gn: Dictionary = gates.get("n", {"x": 514, "y": 95})
	var scare := dread()
	ctx.merge({"dread_ok": scare != null and not bool(_dread_context()["busy"]) and scare.allow(1),
		"day": school().day, "diff": story().diff, "dead": story().dead, "hiding": player.hiding, "night": SchoolClock.is_night(school().tsec),
		"anomaly_active": weird != null and weird.is_active(), "anomaly_id": weird.active_id() if weird != null else "",
		"inspection_pending": school().inspection_pending(), "inspection_quiet": school().inspection_pending(),
		"gate_n": Vector2(float(gn["x"]) * 2.0, float(gn["y"]) * 2.0),
		"piano_closed": days() != null and days().closed("piano", school().day, school().tsec)}, true)
	return ctx


func _broadcast_step(delta: float) -> void:
	var radio := broadcast()
	if radio == null:
		return
	radio.set_context(_broadcast_context())
	if _mic_open:
		if not radio.near_station() or story().dead or Input.is_action_just_pressed("pause") or radio.b["phase"] == "bell":
			_close_mic()
		else:
			var want := _mic_hold_button or Input.is_key_pressed(KEY_SPACE) or Input.is_action_pressed("interact")
			if want and not radio.held:
				radio.hold(true)
			elif not want and radio.held:
				radio.hold(false)
			var why := radio.reason()
			var names: Array = radio.papers().map(func(id: String) -> Array: return [id, "%s · %s" % [items().item_name(id), "红笔／第 0 天" if id == "notice_fake" else "蓝黑墨水"]])
			var cur := String(radio.b["selected"])
			var st := "长铃已响，跟随同学从北门离校。" if radio.b["phase"] == "bell" else (why if why != "" else "已播完 %d/4 段 · %s" % [int(radio.b["completed"]), "正在播音，门禁已报告这个房间。" if radio.held else "从当前这一段开始，松开会重读。"])
			_mic_panel.paint(names, cur, radio.paper_text(cur) if radio.papers().has(cur) else "手里没有这一页", st, radio.progress, radio.reading_seconds(), radio.held, why == "" and not radio.papers().is_empty())
			ui.show_search(radio.progress / radio.reading_seconds() if radio.held else 0.0)
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
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 26:
			var fig := FigureModel.make("person", Color(0.18, 0.2, 0.26), false, 0.9)
			fig.rotation.y = rng.randf() * TAU
			fig.position = Vector3(rng.randf_range(-2.6, 2.6), 0.0, rng.randf_range(-3.5, 3.5))
			_crowd_nodes.add_child(fig)
		world.add_child(_crowd_nodes)
	var s := CampusGeometry.to_scene(null, Vector2(float(p["x"]), float(p["y"])))
	_crowd_nodes.position = Vector3(s.x, 0.0, s.y)
	_crowd_nodes.rotation.y = -float(p["angle"]) - PI * 0.5


func _open_mic() -> void:
	var radio := broadcast()
	if radio == null:
		return
	if radio.papers().is_empty():
		ui.show_notice("我：手里没有通知稿。")
		return
	if _mic_panel == null:
		_mic_panel = MicPanel.new()
		_mic_panel.paper_selected.connect(func(id: String) -> void:
			if broadcast() != null:
				broadcast().select(id))
		_mic_panel.hold_changed.connect(func(on: bool) -> void: _mic_hold_button = on)
		_mic_panel.closed.connect(_close_mic)
		ui.get_node("Root").add_child(_mic_panel)
	if not radio.papers().has(String(radio.b["selected"])):
		radio.b["selected"] = radio.papers()[0]
	_mic_open = true
	_mic_hold_button = false
	player.enabled = false
	player.clear_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mic_panel.visible = true


func _close_mic() -> void:
	var was := _mic_open
	_mic_open = false
	_mic_hold_button = false
	if _mic_panel != null:
		_mic_panel.visible = false
	if broadcast() != null:
		broadcast().hold(false)
	ui.show_search(0.0)
	if was and session != null and session.running and not get_tree().paused and not story().dead and not ui.choice_open():
		player.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if ui.touch_enabled() else Input.MOUSE_MODE_CAPTURED


func _apply_broadcast_events() -> void:
	var radio := broadcast()
	if radio == null:
		return
	for e: Dictionary in radio.take_events():
		match e["kind"]:
			"dread_note":
				if dread() != null:
					dread().note(String(e["what"]), 1)
			"record":
				_record(e)
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
				audio.play("music.piano", {"pitch": [1.0, 1.0, 1.12, 1.26, 1.0, 0.75][int(e["note"])]})
			"radio":
				audio.play("dread.radio", {"pitch": 1.0 if bool(e["real"]) else 0.87})
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
		"can_stand": _can_stand.bind(room, float(p[1])), "drain_mul": _drain_mul()}


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
			"record":
				_record(e)
			"notice", "toast":
				ui.show_notice(String(e["text"]))
			"san":
				school().san = maxf(school().san + float(e["amount"]), float(e.get("min", -INF)))
			"step":
				var room: Variant = campus().room(session.world_id)
				var s := CampusGeometry.to_scene(room, Vector2(float(e["x"]), float(e["y"])))
				audio.step_on("garage", 1.1, {"pos": Vector3(s.x, float(player.capture_pose()["position"][1]) + 0.2, s.y)})
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
				_play_car_intro()
			"kill":
				kill(String(e["msg"]), String(e["fx"]), String(e["source"]))
				return
			"ending":
				_leave_drive()
				_reach_ending(String(e["id"]))
				return


## CarChase.start: out on the road north of the north gate, the campus hidden behind the drive.
## The opening of the drive (cutscene.js car): headlights in the garage, then the gate seen from outside; then the real drive.
func _play_car_intro() -> void:
	var world := _campus_world()
	if world == null or session == null or DisplayServer.get_name() == "headless":
		_enter_drive()
		return
	if _ending_cut != null and is_instance_valid(_ending_cut):
		_ending_cut.queue_free()
	_ending_cut = EndingCut.new()
	_ending_cut.name = "CarIntro"
	add_child(_ending_cut)
	var was_paused := get_tree().paused
	player.enabled = false
	get_tree().paused = true
	_ending_cut.finished.connect(func(_skipped: bool) -> void:
		get_tree().paused = was_paused
		_enter_drive())
	_ending_cut.audio = audio
	var gate := EndingCut.gate_scene(CampusData.campus(), "n")
	var switch_out := func() -> Node3D:
		# Out of the garage and through the north gate: the real outdoors, in front of the gate (cutscene.js car, beginOutsideStage).
		travel("out", {"position": [gate.x, 0.05, gate.z - 4.0], "yaw": 0.0, "pitch": 0.0}, false)
		return _campus_world()
	_ending_cut.begin("car", world, CampusData.campus(), player, ui, Callable(), {"switch": switch_out, "tsec": school().tsec if school() != null else 0.0})


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
	audio.play("scene.engine")


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
		audio.stop("scene")


func driving() -> bool:
	return _drive_view != null and garage() != null and garage().driving()


func _drive_step(delta: float) -> void:
	var cars := garage()
	cars.set_context(_garage_context())
	cars.chase_step(delta, _drive_input())
	if cars.chase != null:
		var d: Dictionary = cars.chase
		_drive_view.update(d)
		var eye := _drive_view.position + CarChaseView.eye(d)
		player.global_position = eye - Vector3(0, player.camera.position.y, 0)
		player.rotation.y = 0.0
		player.set_pitch(-0.04)
		ui.show_status("校外道路", "速度 %d · 车况 %d/3 · %d%%" % [roundi(float(d["speed"]) * 3.6), int(d["hp"]), roundi(float(d["distance"]) / CarChaseRules.DISTANCE * 100.0)], "warn" if float(d["pursuit"]) > 40.0 else "", "")
		if not story().dead:
			ui.show_death_scene("vignette", float(d["pursuit"]) / CarChaseRules.PURSUIT_LIMIT * 0.6)
	_apply_garage_events()


func _drive_input() -> Dictionary:
	# car-chase.js: the same joystick controls the car, including reverse pull to brake.
	if player.editing_text():
		return {"throttle":false,"braking":false,"steering":0.0}
	var touch := ui.movement_touch()
	return {"throttle":Input.is_action_pressed("move_forward") or touch.y < -.25,
		"braking":Input.is_action_pressed("move_back") or touch.y > .3,
		"steering":clampf(Input.get_axis("move_left","move_right")+touch.x,-1,1)}


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
			"save":
				save_game(true)
			"fact_face":
				fact({"kind": "face", "correct": bool(e["correct"])})
			"record":
				_record(e)
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
	var fake := bool(card.get("fake",false))
	player.enabled = false
	player.clear_input()
	audio.stop_all()
	audio.play("ui.achieve.epic")
	ui.hide_choice()
	ui.hide_bag()
	if items() != null:
		items().cancel_search()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var run_line := ""
	if fake:
		pass # A false ending resumes this same run; neither save nor timer is finished.
	elif speedrun.run.is_empty():
		saves.clear()
		ui.set_save_available(saves.exists())
	else:
		var rec_e := _read_speedrun()
		run_line = _speedrun_result(speedrun.finish(id, rec_e), rec_e)
		ui.speedrun_text = ""
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
	if not fake: _write_side("last_life.json", null)
	fact({"kind": "ending", "id": id, "fake":fake, "legit":not fake, "day": school().day, "diff": story().diff, "talent": talent().id if talent() != null else "none"})
	_last_result = {} if fake else _score_ending(id, String(card["title"]))
	var meta := "第 %d 天" % school().day
	if (items() != null and items().has_clock()) or (talent() != null and talent().has("watch")):
		meta += " · " + SchoolClock.fmt_clock(school().tsec)
	if run_line != "":
		meta += "\n" + run_line
	var ending_session := session
	var show_card := func() -> void:
		if session != ending_session:
			return
		ui.show_ending(String(card["title"]), String(card["tag"]), card["lines"], meta, achievements().run_new_labels() if achievements() != null else PackedStringArray(),
			"rated" if bool(_last_result.get("rated", false)) else ("debug" if bool(_last_result.get("debug", false)) else ""))
		ui.set_ending_wake(fake)
	var world := _campus_world()
	if (id == "dismissal" or id == "cyber") and session != null and session.world_id != "out" and DisplayServer.get_name() != "headless":
		# The last stage of the dismissal is the real campus at the north gate: take the player outside first, then play (Engine.beginOutsideStage).
		var gate := EndingCut.gate_scene(CampusData.campus(), "n")
		travel("out", {"position": [gate.x, 0.05, gate.z - 4.0], "yaw": 0.0, "pitch": 0.0}, false)
		await get_tree().process_frame
		await get_tree().process_frame
		if session != ending_session:
			return
		world = _campus_world()
	if EndingCut.has(id) and world != null and session != null and (session.world_id == "out" or not EndingCut.needs_outdoor(id)) and DisplayServer.get_name() != "headless":
		if _ending_cut != null and is_instance_valid(_ending_cut):
			_ending_cut.queue_free()
		_ending_cut = EndingCut.new()
		_ending_cut.name = "EndingCut"
		add_child(_ending_cut)
		var was_paused := get_tree().paused
		get_tree().paused = true
		_ending_cut.finished.connect(func(_skipped: bool) -> void:
			get_tree().paused = was_paused
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			show_card.call())
		_ending_cut.audio = audio
		_ending_cut.begin(id, world, CampusData.campus(), player, ui, func() -> void: audio.play("ui.click"), {"how": String(exchange().s.get("how", "exam")) if exchange() != null else "exam","tsec":school().tsec})
		return
	show_card.call()


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
	return {"fence_x": float(CampusData.layout("out")["bound"]["x1"]) * 2.0 - 6.0, "scene": session.world_id, "x": w.x, "y": w.y, "ang": CampusGeometry.ang_from_yaw(float(pose["yaw"])), "tsec": day_rules.tsec, "day": day_rules.day,
		"diff": story().diff if story() != null else "easy", "san": day_rules.san, "viol": day_rules.viol, "moving": player.moving, "running": player.sprinting,
		"seated": day_rules.seated, "night": SchoolClock.is_night(day_rules.tsec), "need_where": SchoolClock.need_where(day_rules.tsec), "tile": tile,
		"on_field": day_rules.on_field(session.world_id, w), "in_classroom": day_rules.in_classroom_here(session.world_id, w),
		"game_clock": day_rules.game_clock(), "pressure_anomaly": float(day_rules.pressure()["anomaly"]), "bag": bag.bag if bag != null else [],
		"item_names": item_names, "dead": story() != null and story().dead, "hiding": watcher != null and bool(watcher.hide["on"]),
		"patrol_chase": watcher != null and watcher.local_chase(), "choice_open": ui.choice_open(), "brolly": items() != null and items().brolly_up,
		"inspection_quiet": day_rules.inspection_pending() or day_rules.inspection_upcoming() or float(day_rules.inspection.get("calm", 0.0)) > 0.0,
		"in_lift": session.world_id in ElevatorModule.RIDE_ROOMS, "can_stand": _can_stand.bind(room, float(p[1])), "drain_mul": _drain_mul()}


## The chalk writing (game/presentation/world/campus/chalk_notes.gd): the forecast of the next anomaly and the truancy warnings.
var _skip_on := false


func _chalk_step(delta: float, weird: AnomalyModule, day_rules: SchoolModule, room: Variant, pose: Dictionary) -> bool:
	var world := _campus_world()
	if world == null or world.chalk == null:
		return false
	var p: Array = pose["position"]
	var yaw := float(pose["yaw"])
	var rd: Dictionary = room if room is Dictionary else {}
	var w := CampusGeometry.to_world(room, float(p[0]), float(p[2]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var here := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var playing := not story().dead and not get_tree().paused and not opening_busy()
	var shown := false
	if playing and weird.warning_visible():
		var text := SchoolClock.fmt_clock(roundf(day_rules.tsec + float(weird.an["next"]) * SchoolClock.rate_at(day_rules.tsec) / 60.0))
		shown = world.chalk.update_forecast(true, text, rd, w, fwd, here, delta)
	else:
		world.chalk.clear_forecast()
	_skip_on = ChalkNotes.skip_active(day_rules.wrong, day_rules.viol, _skip_on) and playing and not day_rules.inspection_active()
	world.chalk.update_skip(delta, _skip_on, day_rules.viol, rd, here)
	return shown


## The seen-but-harmless things (game/presentation/world/campus/phantoms.gd): the low-SAN figure at the edge of the view, the far figure, the smile.
func _phantom_step(delta: float, day_rules: SchoolModule, room: Variant, pose: Dictionary, weird: AnomalyModule) -> void:
	var world := _campus_world()
	if world == null or world.phantoms == null:
		return
	var ph := world.phantoms
	var p: Array = pose["position"]
	var cam := player.camera.global_position
	var ang := CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	var h := float(p[1])
	var playing := not story().dead and not get_tree().paused and not opening_busy() and not ui.choice_open() and not ui.terminal_open() and not phone_open() and not driving()
	var stand := func(w: Vector2) -> bool: return _can_stand(w, room, h)
	var busy_anomaly := weird != null and weird.is_active()
	ph.hallucinate(delta, playing and not busy_anomaly, day_rules.san, cam, ang, room, h, stand)
	var watcher := patrol()
	var dark: bool = room != null or SchoolClock.is_night(day_rules.tsec)
	var calm := playing and not busy_anomaly and not (watcher != null and watcher.local_chase()) and not player.hiding
	var inv := items()
	ph.apparition(delta, calm, dark, inv != null and inv.torch_on, day_rules.san, cam, ang, room, h, stand, _line_clear.bind(room))
	ph.tick_smile(delta, cam)
	var tl := tales()
	if world.canteen_view != null and tl != null:
		var csc := CampusGeometry.to_scene(room, CampusGeometry.to_world(room, float(p[0]), float(p[2])))
		world.canteen_view.update(session.world_id == CanteenView.ROOM and tl.canteen_open(), csc, tl.ate())
	if world.mirror_view != null and tl != null:
		if world.mirror_view.count() == 0:
			world.mirror_view.build(room if room is Dictionary else {}, tl.mirrors(session.world_id))
		world.mirror_view.update(delta, CampusGeometry.to_world(room, float(p[0]), float(p[2])), ang, day_rules.san, tl.raise, playing)


func _anomaly_step(delta: float, day_rules: SchoolModule, room: Variant, pose: Dictionary) -> void:
	var weird := anomaly()
	if weird == null:
		return
	var ctx := _anomaly_context(room, pose)
	weird.set_context(ctx)
	weird.warning_seen(_chalk_step(delta, weird, day_rules, room, pose))
	CampusWorld.pending_traces = weird.traces
	var tw := _campus_world()
	if tw != null:
		tw.sync_traces(weird.traces)
		if campus() != null and campus().is_stairwell(session.world_id):
			tw.update_shaft_previews(float(pose["position"][1]))
	_phantom_step(delta, day_rules, room, pose, weird)
	weird.tick(delta)
	for e: Dictionary in weird.take_events():
		match e["kind"]:
			"clue":
				if runscore() != null:
					runscore().add_clue(String(e["id"]), school().day)
			"notice":
				ui.show_notice(String(e["text"]))
			"smile":
				var sw := _campus_world()
				if sw != null and sw.phantoms != null:
					var cp := player.camera.global_position
					sw.phantoms.show_smile(String(e["mode"]), cp, CampusGeometry.ang_from_yaw(player.rotation.y))
					if e["mode"] == "jump":
						ui.flash_hurt(0.6)
				# SFX.smile: behind you a held-in giggle; in your face a scream at the ear.
				if e["mode"] == "jump":
					audio.play("threat.smileJump")
				else:
					audio.play("threat.smileBack", {"pan": 0.3, "lp": 0.8})
			"hurt":
				if anomaly() != null and anomaly().active_id() != "":
					fact({"kind": "anomaly", "phase": "hurt", "id": anomaly().active_id()})
				day_rules.change_san(-float(e["amount"]), 0.0)
				ui.flash_hurt(0.4 if e.get("quiet", false) else 0.65)
				audio.play("foley.colaHit", {"k": 0.4 if e.get("quiet", false) else 0.8})
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
	if is_instance_valid(debug_flow): debug_flow.clear_preview()
	var error := router.switch_to(world_id)
	if not error.is_empty():
		ui.show_notice(error)
		return error
	var from_world := session.world_id
	rules_dlc_flow.cancel()
	if patrol() != null and from_world != world_id and school() != null:
		var pp: Array = player.capture_pose()["position"]
		var from_room: Variant = campus().room(from_world)
		patrol().set_context(_patrol_context(from_room, player.capture_pose()))
		patrol().left_scene(from_world, world_id)
	if from_world != world_id and campus() != null and (campus().is_stairwell(world_id) or campus().is_stairwell(from_world)) and not seamless:
		audio.play("foley.stairs")
	session.world_id = world_id
	if dread() != null and from_world != world_id:
		dread().set_context(_dread_context())
		dread().enter(world_id)
		_apply_dread_events()
	if atmos() != null and from_world != world_id:
		atmos().enter(world_id)
	if runscore() != null and from_world != world_id:
		runscore().enter_room(world_id)
		_runlog_room(world_id)
	_enter_cool = 0.0 if seamless else 0.9
	if seamless:
		player.place(pose)
	else:
		player.restore_pose(pose)
	maze_flow.changed_world()
	inception_flow.changed_world()
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


var _hands: HandsView


func _process(delta: float) -> void:
	if session != null and player != null and player.camera != null:
		if patrol()!=null and patrol().nav.maze!=null: patrol().nav.maze.warm_step()
		if _hands == null or not is_instance_valid(_hands):
			_hands = HandsView.new()
			_hands.name = "Hands"
			player.camera.add_child(_hands)
		var shown := not get_tree().paused and not story().dead and not driving() and not opening_busy()
		var inv := items()
		var torch_lit := inv != null and inv.torch_on and inv.has("torch")
		_hands.update(delta, torch_lit, inv != null and inv.brolly_up, phone_open() and not snake_open(), shown, player.moving, player.sprinting)
		var cw := _campus_world()
		if cw != null and cw.lighting != null and cw.lighting.cam_light != null:
			_hands.light(cw.lighting.cam_light.light_energy, cw.lighting.cam_light.light_color, torch_lit)
	var m := "menu"
	if session != null and not get_tree().paused and not opening_busy():
		m = "death" if story().dead else "play"
	playtest.frame(delta, m)


## F9 (debug build or --dev): the developer tools.
func _toggle_debug() -> void:
	if not DebugPanel.enabled():
		return
	if debug_panel == null:
		debug_panel = DebugPanel.new(audio._index)
		ui.get_node("Root").add_child(debug_panel)
		debug_panel.closed.connect(func() -> void:
			debug_flow.cancel()
			if session != null and player.enabled and not get_tree().paused and not ui.touch_enabled():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		debug_panel.action.connect(debug_flow.command)
		debug_panel.sound_play.connect(func(id: String) -> void: audio.audition(id))
		debug_panel.sound_stop.connect(audio.stop_audition)
		debug_panel.playtest_toggled.connect(func() -> void:
			if playtest.recording:
				playtest.stop()
			else:
				playtest.start(settings.values, get_viewport().get_visible_rect().size)
			debug_panel.set_playtest(playtest.recording, playtest.data.get("events", []).size(), not playtest.data.is_empty()))
		debug_panel.playtest_note.connect(func(t: String) -> void:
			debug_panel.say("已记入" if playtest.note(t, _playtest_state()) else "先开始记录，并写一句话")
			debug_panel.set_playtest(playtest.recording, playtest.data.get("events", []).size(), not playtest.data.is_empty()))
		debug_panel.clear_debug_records.connect(func() -> void: debug_panel.say("已清除 %d 条调试记录" % runs().remove_debug()))
		debug_panel.mark_untrusted.connect(func() -> void:
			if runscore() != null:
				debug_flow.dirty()
				debug_panel.say("本局已标为调试局：不计成就、真实评级与速通最佳")
			else:
				debug_panel.say("没有进行中的一局"))
	if debug_panel.visible:
		if debug_panel.collapsed:
			debug_panel.set_collapsed(false)
		else:
			debug_panel.dismiss()
			return
	else:
		debug_panel.show()
	if debug_panel.visible:
		debug_flow.dirty()
		player.clear_input()
		ui.clear_touch()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		debug_panel.set_playtest(playtest.recording, playtest.data.get("events", []).size(), not playtest.data.is_empty())
		debug_flow.refresh()


func _playtest_state() -> Dictionary:
	if session == null:
		return {}
	return {"day": school().day, "gameMinutes": school().tsec, "room": session.world_id, "san": school().san}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F2,KEY_F9]:
		_toggle_debug()
		get_viewport().set_input_as_handled()
		return
	if opening_busy():
		if _opening_cut != null and _opening_cut.on:
			return
		if event.is_action_pressed("pause"):
			ui._end_opening(true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			ui._next_opening()
			get_viewport().set_input_as_handled()
		return
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
	if is_instance_valid(debug_flow) and debug_flow.frozen: return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and snake_open():
		if key.keycode == KEY_ESCAPE:
			_stop_snake()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and phone_open():
		if key.keycode == KEY_ESCAPE:
			_close_phone()
		elif phone() != null and phone().page == "plane" and key.keycode in [KEY_SPACE, KEY_W]:
			_phone_flap()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_R and days() != null and session != null and not story().over():
		_lesson_press()
		get_viewport().set_input_as_handled()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_N and investigation() != null and player.enabled and not story().over():
		_show_notes("")
		get_viewport().set_input_as_handled()
		return
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
	_cancel_cinematics()
	if session != null:
		_unwire(session)
		session.stop()
	CampusData.clear_caches()
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
