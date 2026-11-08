class_name ResultsPanel
extends PanelContainer
## The result page, only after a clear (modules/run-record/results-ui.js): the grade picture on top, then
## the time and the score by category (open each for the lines), the survival story, the exploration and
## the achievements of this run. The clear record's detail and the CG archive reuse it (a different back
## button). The homeroom teacher's report card writes at most three lines from what really happened, in a
## calm voice; hidden content is never written (REPORT_SECRET, covered by a secrecy test).

signal footprint_pressed(id: String)
signal replay_pressed(id: String)
signal sound(band: String)
signal back_pressed

const REPORT_SECRET := ["满员", "可乐", "？？？", "先辈", "迷宫"]
const SURVIVAL_CATS := ["SAN", "应对 · 异象", "应对 · 选择", "校规与巡察", "保命与惊醒"]

var hero: GradeScreen
var line: Label
var body: VBoxContainer
var foot_button: Button
var replay_button: Button
var back_button: Button
var current: Dictionary = {}
var _scroll: ScrollContainer
var _feet: HFlowContainer


func _init() -> void:
	name = "ResultsPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.06, 0.05, 0.04, 0.99)
	back.set_content_margin_all(12)
	back.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	box.add_child(_scroll)
	hero = GradeScreen.new()
	hero.custom_minimum_size.x = 0
	hero.sound.connect(func(b: String) -> void: sound.emit(b))
	content.add_child(hero)
	line = Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(line)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	content.add_child(body)
	_feet = HFlowContainer.new()
	foot_button = Button.new()
	foot_button.name = "Footprint"
	foot_button.text = "足迹图"
	foot_button.pressed.connect(func() -> void: footprint_pressed.emit(String(current.get("id", ""))))
	_feet.add_child(foot_button)
	replay_button = Button.new()
	replay_button.name = "Replay"
	replay_button.text = "回放"
	replay_button.pressed.connect(func() -> void: replay_pressed.emit(String(current.get("id", ""))))
	_feet.add_child(replay_button)
	back_button = Button.new()
	back_button.name = "ResultsBack"
	back_button.text = "回到主菜单"
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	_feet.add_child(back_button)
	box.add_child(_feet)
	add_child(box)
	visibility_changed.connect(func() -> void:
		if not visible: hero.cancel()
		else: _fit.call_deferred())
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_inside_tree() or not visible: return
	var screen := get_viewport_rect().size
	custom_minimum_size.x = minf(720, screen.x - 24)
	_scroll.custom_minimum_size.y = minf(550, maxf(60, screen.y - _feet.get_combined_minimum_size().y - 56))
	reset_size()
	position = (screen - size) * .5


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(body):
		_scale_labels(body)
		_fit.call_deferred()


func _scale_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label and child.has_meta("base_font"):
			var font_size := roundi(float(child.get_meta("base_font")) * get_theme_default_font_size() / 16.0)
			if child.get_theme_font_size("font_size") != font_size: child.add_theme_font_size_override("font_size",font_size)
		_scale_labels(child)


static func fmt(sec: float) -> String:
	var s := maxi(0, roundi(sec))
	return "%02d:%02d" % [s / 60, s % 60]


static func talent_name(id: String) -> String:
	return String(TalentModule.DEF.get(id, {}).get("n", "")) if TalentModule.DEF.has(id) else ""


## The class teacher's remarks from the lines of the score (and the replay's events and clock), at most three.
static func report_card(m: Dictionary, replay: Dictionary = {}) -> Array:
	var items: Array = m.get("score", {}).get("items", [])
	var out: Array = []
	var events: Array = replay.get("events", [])
	var clock: Array = replay.get("clock", [])
	var at := func(t: float) -> String:
		var kk: Variant = null
		for c: Array in clock:
			if float(c[0]) <= t:
				kk = c
		return SchoolClock.fmt_clock(float(kk[2])) if kk != null else ""
	var find := func(re: String) -> Array:
		var rx := RegEx.create_from_string(re)
		return items.filter(func(it: Dictionary) -> bool:
			var secret := false
			for w: String in REPORT_SECRET:
				if String(it["text"]).contains(w):
					secret = true
			return rx.search(String(it["text"])) != null and not secret)
	var an: Array = find.call("^化解「")
	if not an.is_empty():
		var nm := String(an[0]["text"]).trim_prefix("化解「").trim_suffix("」")
		var t := ""
		for e: Array in events:
			if e[1] == "anomaly" and String(e[2]).contains(nm):
				t = String(at.call(float(e[0])))
				break
		out.append("该生%s在「%s」里没有回头。" % [(" " + t + " ") if t != "" else "", nm])
	var insp: Array = find.call("^学生会检查 · 在教室")
	if not insp.is_empty():
		out.append("该生 %d 次检查都在座位上。" % int(insp[0].get("n", 1)) if int(insp[0].get("n", 1)) > 1 else "该生检查的时候在座位上。")
	elif not (find.call("^学生会检查 · 缺席") as Array).is_empty():
		out.append("检查的时候，该生的座位是空的。")
	var hide: Array = find.call("躲在柜子里躲过")
	if not hide.is_empty():
		out.append("该生在柜子里待了很久，不止一次。" if int(hide[0].get("n", 1)) > 1 else "该生在柜子里待了很久。")
	if not (find.call("电梯门在它面前合上") as Array).is_empty():
		out.append("该生关电梯门的手很快。")
	if not (find.call("挡下一次$|^预知梦惊醒") as Array).is_empty():
		out.append("该生有一次差点没有回来。")
	if out.is_empty():
		out.append("该生第 %d 天离开了学校。没有人看见是怎么走的。" % int(m.get("day", 1)))
	return out.filter(func(t: String) -> bool:
		for w: String in REPORT_SECRET:
			if t.contains(w):
				return false
		return true).slice(0, 3)


func _label(text: String, color: Color = Color.WHITE, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = color
	l.set_meta("base_font",size)
	l.add_theme_font_size_override("font_size",roundi(size * get_theme_default_font_size() / 16.0))
	return l


func _section(title: String) -> void:
	body.add_child(_label(title, Color(1.0, 0.9, 0.55), 15))


## Open for a record (or a result). opts: replay (the replay pack, for the report card), back_label, silent, reduce.
func open(m: Dictionary, opts: Dictionary = {}) -> void:
	current = m
	var g := ScoreRules.by_letter(String(m["grade"]))
	hero.show_grade(String(m["grade"]), true, bool(opts.get("silent", false)), bool(opts.get("reduce", false)))
	var diff := "梦魇" if m["diff"] == "hard" else "预知梦"
	var tal := talent_name(String(m.get("talent", "none")))
	var t: String
	if m.get("mode") == "speedrun" and m["time"].get("rta") != null:
		t = "速通 %s · 有效游玩 %s" % [Speedrun.fmt(roundi(float(m["time"]["rta"]) * 1000.0)), fmt(float(m["time"]["active"]))]
	else:
		t = "用时 " + fmt(float(m["time"]["used"]))
	line.text = "%s「%s」\n评级分 %d　积分 %d + 时间分 %d\n%s · %s%s · 第 %d 天\n%s · 标准用时 %s" % [g["name"], g["memo"], int(m["gradeScore"]), int(m["score"]["total"]), int(m["timeScore"]),
		m["routeName"], diff, (" · " + tal) if tal != "" else "", int(m["day"]), t, fmt(float(m["time"]["par"]))]
	for c in body.get_children():
		c.queue_free()
	# Score by category, each opened to its lines.
	var cats := {}
	var survival := 0
	for it: Dictionary in m["score"]["items"]:
		if SURVIVAL_CATS.has(String(it["cat"])):
			survival += int(it["pts"]) * int(it.get("n", 1))
			continue
		var l: Array = cats.get(it["cat"], [])
		l.append(it)
		cats[it["cat"]] = l
	cats["生存经历"] = [{"text": "这一局的应对与经历", "pts": survival, "n": 1}]
	_section("积分 %d" % int(m["score"]["total"]))
	for cat: String in ScoreRules.CATS + ["生存经历"]:
		if not cats.has(cat):
			continue
		var sum := 0
		for it: Dictionary in cats[cat]:
			sum += int(it["pts"]) * int(it.get("n", 1))
		var toggle := Button.new()
		toggle.text = "%s　%s%d" % [cat, "+" if sum > 0 else "", sum]
		toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toggle.toggle_mode = true
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rows := VBoxContainer.new()
		rows.visible = false
		for it: Dictionary in cats[cat]:
			var n := int(it.get("n", 1))
			var p := int(it["pts"]) * n
			rows.add_child(_label("　%s%s　%s%d" % [it["text"], " ×%d" % n if n > 1 else "", "+" if p > 0 else "", p], Color(1, 1, 1, 0.85), 13))
		toggle.toggled.connect(func(on: bool) -> void: rows.visible = on)
		body.add_child(toggle)
		body.add_child(rows)
	if float(m["score"]["mult"]) > 1.0:
		body.add_child(_label("梦魇难度：合计 %d × %s = %d" % [int(m["score"]["sum"]), str(m["score"]["mult"]), int(m["score"]["total"])], Color(1, 1, 1, 0.65), 13))
	_section("成绩单")
	for r: String in report_card(m, opts.get("replay", {})):
		body.add_child(_label(r, Color(0.85, 0.9, 0.85)))
	body.add_child(_label("—— 班主任", Color(1, 1, 1, 0.55), 12))
	var ex: Dictionary = m["explore"]
	_section("探索度 %d%%" % int(ex["pct"]))
	body.add_child(_label("到过的地点 %d%% · 楼层草图 %d%% · 线索 %d%%" % [int(ex["place"]), int(ex["sketch"]), int(ex["clue"])], Color(1, 1, 1, 0.8), 13))
	_section("本局成就")
	var run_ach: Array = m.get("ach", {}).get("run", [])
	if run_ach.is_empty():
		body.add_child(_label("这一局没有达成成就。", Color(1, 1, 1, 0.7), 13))
	for id: Variant in run_ach:
		if AchievementsModule.LIST.has(id):
			var fresh := (m.get("ach", {}).get("newly", []) as Array).has(id)
			body.add_child(_label("%s · %s%s" % [AchievementsModule.TIERS[AchievementsModule.LIST[id][0]]["name"], AchievementsModule.LIST[id][1], " · 新" if fresh else ""], Color(0.65, 0.9, 0.7) if fresh else Color.WHITE, 13))
	var notes: Array = []
	if bool(m.get("capped", false)):
		notes.append("评级分够 SSS，但 SSS 需要梦魇难度、没被救过、没惊醒过，这一局给 SS。")
	if int(m.get("legacy", 0)) > 0:
		notes.append("这一局是从旧存档继续的：之前的部分没有记录，按 0 计。")
	if m.get("source") == "debug":
		notes.append("调试面板生成的示例记录，不是真实通关。")
	if m.get("source") == "archive":
		notes.append("直接解锁的示例画面：明细是示例数据。")
	if not notes.is_empty():
		_section("说明")
		for n: String in notes:
			body.add_child(_label(n, Color(1, 1, 1, 0.75), 13))
	var has := String(m.get("id", "")) != "" and int(m.get("replay", 0)) != 0
	foot_button.visible = has
	replay_button.visible = has
	back_button.text = String(opts.get("back_label", "回到主菜单"))
	_scroll.scroll_vertical = 0
	visible = true
	_fit.call_deferred()
