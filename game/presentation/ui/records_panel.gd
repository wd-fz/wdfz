class_name RecordsPanel
extends PanelContainer
## The clear records screen (modules/run-record/records-ui.js, reference wd-fz.github.io@0bf508a): the list
## with filters and a sort, the speedrun ranking, and the replay / footprint viewer of one record.
## The list's rows open the result page (ResultsPanel, signalled out); the viewer is here.

signal detail_requested(id: String)
signal closed
signal sample_requested(grade: String)

const KIND_COL := {"anomaly": Color("#e0675c"), "patrol": Color("#d9473e"), "inspect": Color("#e2bd6a"), "choice": Color("#8fa28a"), "achieve": Color("#79c8a4"),
	"ending": Color("#e6dcc4"), "death": Color("#e0675c"), "room": Color("#9c9384")}
const SORTS := {"time": "时间", "grade": "评级", "score": "积分", "used": "用时"}

var records: RunRecords
var _rooms: Dictionary = {}
var _mode := "list"            # list | rank | view
var _diff := ""
var _route := ""
var _sort := "time"
var _body: VBoxContainer
var _head: Label
var _tabs: HFlowContainer
var _scroll: ScrollContainer
var _close_button: Button

# The viewer.
var _rec: Dictionary = {}
var _pack: Dictionary = {}
var _foot := false
var _scene := ""
var _t := 0.0
var _t_max := 0.0
var _playing := false
var _speed := 4.0
var _map: MapView
var _slider: HSlider
var _time_label: Label
var _play: Button
var _scene_tabs: HFlowContainer
var _event_box: VBoxContainer
var _view: VBoxContainer


func _init(store: RunRecords = null, rooms: Dictionary = {}) -> void:
	records = store
	_rooms = rooms
	name = "RecordsPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := UISkin.panel(12)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_head = Label.new()
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_head.add_theme_color_override("font_color",UISkin.ACCENT)
	box.add_child(_head)
	_tabs = HFlowContainer.new()
	box.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	box.add_child(_scroll)
	_close_button = Button.new()
	_close_button.name = "RecordsClose"
	_close_button.text = "关闭"
	_close_button.pressed.connect(_close)
	box.add_child(_close_button)
	add_child(box)
	UIArt.decorate(self)
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	visibility_changed.connect(func() -> void: _fit.call_deferred())


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if not is_inside_tree() or not visible: return
	var screen := get_viewport_rect().size
	custom_minimum_size.x = minf(720, screen.x - 24)
	var fixed := _head.get_combined_minimum_size().y + _tabs.get_combined_minimum_size().y + _close_button.get_combined_minimum_size().y + 66
	_scroll.custom_minimum_size.y = minf(480, maxf(60, screen.y - fixed))
	reset_size()
	position = (screen - size) * .5
	if _mode == "view": _redraw()


func _close() -> void:
	if _mode == "view":
		_playing = false
		_mode = "list"
		_refresh()
		return
	visible = false
	closed.emit()


func open() -> void:
	_mode = "list"
	_playing = false
	visible = true
	_refresh()


## Back to the list after the result page (keeps the filters).
func reopen() -> void:
	visible = true
	_mode = "list"
	_refresh()


func _btn(text: String, on: bool, call: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size.y = 44
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.pressed.connect(call)
	return b


func _fmt_date(ms: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


func _routes_of(list: Array) -> Array:
	var seen := {}
	for x: Dictionary in list:
		seen[String(x["route"])] = String(x["routeName"])
	return seen.keys()


func filtered() -> Array:
	var out: Array = []
	for x: Dictionary in records.list():
		if _diff != "" and x["diff"] != _diff:
			continue
		if _route != "" and x["route"] != _route:
			continue
		out.append(x)
	match _sort:
		"grade":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gradeScore"]) > float(b["gradeScore"]))
		"score":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]["total"]) > float(b["score"]["total"]))
		"used":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]["used"]) < float(b["time"]["used"]))
		_:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) > float(b["at"]))
	return out


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	for c in _tabs.get_children():
		c.queue_free()
	_scroll.scroll_vertical = 0
	_fit.call_deferred()
	if _mode == "view":
		_build_view()
		return
	_head.text = "通关记录 · 本机 %d 条" % records.list().size()
	_tabs.add_child(_btn("记录", _mode == "list", func() -> void:
		_mode = "list"
		_refresh()))
	_tabs.add_child(_btn("速通排行", _mode == "rank", func() -> void:
		_mode = "rank"
		_refresh()))
	_tabs.add_child(_btn("结算画面", _mode == "grades", func() -> void:
		_mode = "grades"
		_refresh()))
	if _mode == "rank":
		_build_rank()
	elif _mode == "grades":
		_build_grades()
	else:
		_build_list()


func _build_list() -> void:
	var filt := HFlowContainer.new()
	for pair: Array in [["", "全部难度"], ["easy", "预知梦"], ["hard", "梦魇"]]:
		filt.add_child(_btn(String(pair[1]), _diff == pair[0], func() -> void:
			_diff = String(pair[0])
			_refresh()))
	_body.add_child(filt)
	var rt := HFlowContainer.new()
	rt.add_child(_btn("全部路线", _route == "", func() -> void:
		_route = ""
		_refresh()))
	var names := {}
	for x: Dictionary in records.list():
		names[String(x["route"])] = String(x["routeName"])
	for k: String in names:
		rt.add_child(_btn(String(names[k]), _route == k, func() -> void:
			_route = k
			_refresh()))
	_body.add_child(rt)
	var srt := HFlowContainer.new()
	srt.add_child(Label.new())
	(srt.get_child(0) as Label).text = "排序："
	for k: String in SORTS:
		srt.add_child(_btn(String(SORTS[k]), _sort == k, func() -> void:
			_sort = k
			_refresh()))
	_body.add_child(srt)
	var rows := filtered()
	if rows.is_empty():
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "还没有记录。通关一次（有评级的局）才会留下。"
		l.modulate = Color(1, 1, 1, 0.6)
		_body.add_child(UIArt.view(UIArt.surface("empty_records"), Vector2(0, 120)))
		_body.add_child(l)
	for x: Dictionary in rows:
		var b := Button.new()
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tag := "（调试）" if not RunRecords.is_real(x) else ""
		b.custom_minimum_size.y = 88
		UIArt.button(b, UIArt.grade(String(x["grade"])), 64)
		b.text = "%s　%s · %s%s\n积分 %d　用时 %s\n%s%s" % [x["grade"], x["routeName"], "梦魇" if x["diff"] == "hard" else "预知梦", tag, int(x["score"]["total"]),
			ResultsPanel.fmt(float(x["time"]["used"])), _fmt_date(float(x["at"])), "　▶" if int(x.get("replay", 0)) != 0 else ""]
		b.pressed.connect(func() -> void: detail_requested.emit(String(x["id"])))
		_body.add_child(b)


## The CG archive's result screens: a grade shows once a real run has earned it; the sample page (source
## "archive") is a made-up detail, only the picture is the real thing.
func _build_grades() -> void:
	var got: Dictionary = records.grades()
	var n := 0
	for g: Dictionary in ScoreRules.GRADES:
		if got.has(g["g"]):
			n += 1
	var h := Label.new()
	h.text = "已得到 %d / %d 档" % [n, ScoreRules.GRADES.size()]
	h.modulate = Color(1.0, 0.9, 0.55)
	_body.add_child(h)
	for g: Dictionary in ScoreRules.GRADES:
		var b := Button.new()
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UIArt.button(b, UIArt.grade(String(g["g"])) if got.has(g["g"]) else UIArt.surface("locked"), 56)
		b.custom_minimum_size.y = 72
		if got.has(g["g"]):
			var v: Dictionary = got[g["g"]]
			b.text = "%s　%s　×%d　首次 %s" % [g["g"], g["name"], int(v["count"]), _fmt_date(float(v["first"]))]
			var best: Variant = v.get("best")
			b.pressed.connect(func() -> void:
				if best is String and not records.get_record(String(best)).is_empty():
					detail_requested.emit(String(best))
				else:
					sample_requested.emit(String(g["g"])))
		else:
			b.text = "%s　？？？" % g["g"]
			b.disabled = true
		_body.add_child(b)


func _build_rank() -> void:
	var any := false
	for diff: String in ["easy", "hard"]:
		var routes: Dictionary = {}
		for x: Dictionary in records.list():
			if RunRecords.is_base(x) and x.get("mode") == "speedrun":
				routes[String(x["route"])] = String(x["routeName"])
		for rk: String in routes:
			var rows := records.ranking(diff, rk, "time")
			if rows.is_empty():
				continue
			any = true
			var h := Label.new()
			h.text = "%s · %s（按用时）" % ["梦魇" if diff == "hard" else "预知梦", routes[rk]]
			h.modulate = Color(1.0, 0.9, 0.55)
			_body.add_child(h)
			var n := 0
			for x: Dictionary in rows:
				n += 1
				var b := Button.new()
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.text = "%d　%s　%s　%s" % [n, Speedrun.fmt(roundi(float(x["time"]["rta"]) * 1000.0)), x["grade"], _fmt_date(float(x["at"]))]
				b.pressed.connect(func() -> void: detail_requested.emit(String(x["id"])))
				_body.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "还没有速通记录。"
		l.modulate = Color(1, 1, 1, 0.6)
		_body.add_child(l)


# ---- the viewer ----

## Open the replay (foot = false) or the footprint map (foot = true) of a record.
func open_view(id: String, foot: bool) -> bool:
	var rec := records.get_record(id)
	var pack := records.replay(id)
	if rec.is_empty() or pack.is_empty():
		return false
	_rec = rec
	_pack = pack
	_foot = foot
	_playing = false
	_time_label = null
	_slider = null
	_t = 0.0
	var samples: Array = RunTrack.decode(String(pack.get("track", "")))
	_pack["samples"] = samples
	_t_max = float(samples[samples.size() - 1][0]) if not samples.is_empty() else 0.0
	_scene = ""
	for s: Variant in pack.get("scenes", []):
		if _drawable(String(s)):
			_scene = String(s)
			break
	_mode = "view"
	visible = true
	_refresh()
	return true


func _drawable(id: String) -> bool:
	var r: Dictionary = _rooms.get(id, {})
	return not r.is_empty() and not bool(r.get("flags", {}).get("noMap", false))


func _scene_index(id: String) -> int:
	return (_pack.get("scenes", []) as Array).find(id)


func _build_view() -> void:
	_head.text = "%s · %s %s" % ["足迹图" if _foot else "回放", _rec["routeName"], _fmt_date(float(_rec["at"]))]
	if int(_pack.get("partial", 0)) != 0:
		_head.text += "（只记录了读档之后的部分）"
	_view = _body
	_scene_tabs = HFlowContainer.new()
	for s: Variant in _pack.get("scenes", []):
		var id := String(s)
		if not _drawable(id):
			continue
		var nm := String(_rooms[id].get("name", id))
		_scene_tabs.add_child(_btn(nm, id == _scene, func() -> void:
			_scene = id
			_redraw()
			for c in _scene_tabs.get_children():
				(c as Button).button_pressed = (c as Button).text == nm))
	_body.add_child(_scene_tabs)
	var scroll := ScrollContainer.new()
	_map = MapView.new()
	_map.scroll_min_width = 0
	_map.scroll_max_height = 230
	scroll.add_child(_map)
	_body.add_child(scroll)
	if not _foot:
		var ctl := HFlowContainer.new()
		_play = Button.new()
		_play.text = "播放"
		_play.pressed.connect(func() -> void:
			_playing = not _playing
			_play.text = "暂停" if _playing else "播放")
		ctl.add_child(_play)
		var sp := Button.new()
		sp.text = "×4"
		sp.pressed.connect(func() -> void:
			_speed = {1.0: 4.0, 4.0: 16.0, 16.0: 1.0}.get(_speed, 4.0)
			sp.text = "×%d" % int(_speed))
		ctl.add_child(sp)
		_slider = HSlider.new()
		_slider.min_value = 0.0
		_slider.max_value = maxf(_t_max, 1.0)
		_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider.value_changed.connect(func(v: float) -> void:
			_t = v
			_redraw())
		_time_label = Label.new()
		ctl.add_child(_time_label)
		_body.add_child(ctl)
		_body.add_child(_slider)
		_event_box = VBoxContainer.new()
		for e: Array in _pack.get("events", []):
			var b := Button.new()
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "%s　%s" % [ResultsPanel.fmt(float(e[0]) / 10.0), e[2]]
			b.modulate = KIND_COL.get(String(e[1]), Color.WHITE)
			b.pressed.connect(func() -> void:
				_t = float(e[0])
				_slider.value = _t)
			_event_box.add_child(b)
		_body.add_child(_event_box)
	_redraw()


## The sample index list of the shown scene; dwell circles where the player stood still for long.
func _redraw() -> void:
	if _map == null or not is_instance_valid(_map):
		return
	var room: Dictionary = _rooms.get(_scene, {})
	if room.is_empty():
		return
	var cols := int(room["cols"])
	var rows := int(room["rows"])
	var bits := PackedByteArray()
	bits.resize(cols * rows)
	var sketch: Dictionary = _pack.get("sketch", {})
	if sketch.has(_scene):
		bits = ExplorationModule.unpack(String(sketch[_scene]), room)
	else:
		bits.fill(1)
	var si := _scene_index(_scene)
	var samples: Array = _pack["samples"]
	var pts := PackedVector2Array()
	var dwell: Dictionary = {}
	for s: Array in samples:
		if int(s[1]) != si or (not _foot and float(s[0]) > _t):
			continue
		pts.append(Vector2(float(s[2]), float(s[3])) * 2.0)
		var key := Vector2i(roundi(float(s[2]) / 2.0), roundi(float(s[3]) / 2.0))
		dwell[key] = int(dwell.get(key, 0)) + 1
	var trails: Array = [{"pts": pts, "col": Color(0.9, 0.86, 0.77, 0.55)}]
	var pat := PackedVector2Array()
	for p: Array in _pack.get("pat", []):
		if int(p[1]) == si and (_foot or float(p[0]) <= _t):
			pat.append(Vector2(float(p[2]), float(p[3])) * 2.0)
	trails.append({"pts": pat, "col": Color(0.85, 0.28, 0.24, 0.5)})
	var cur: Array = RunTrack.at(samples, _t)
	var here := not _foot and not cur.is_empty() and int(cur[1]) == si
	_map.show_floor(room, bits, Callable(), Vector2(float(cur[2]), float(cur[3])) * 2.0 if here else Vector2.ZERO, float(cur[4]) / 64.0 * TAU if here else 0.0, here, minf(440, get_viewport_rect().size.x - 76))
	_map.trails = trails
	var dws: Array = []
	if _foot:
		for k: Vector2i in dwell:
			if int(dwell[k]) >= 6:
				dws.append({"p": Vector2(k) * 2.0 * 2.0, "r": float(dwell[k]) / 10.0})
	_map.dwells = dws
	_map.queue_redraw()
	if _time_label != null:
		_time_label.text = "%s / %s" % [ResultsPanel.fmt(_t / 10.0), ResultsPanel.fmt(_t_max / 10.0)]


func _process(delta: float) -> void:
	if not visible or not _playing or _mode != "view" or _foot:
		return
	_t = minf(_t + delta * 10.0 * _speed, _t_max)
	if _slider != null:
		_slider.set_value_no_signal(_t)
	_redraw()
	if _t >= _t_max:
		_playing = false
		_play.text = "播放"
