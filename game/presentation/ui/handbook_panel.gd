class_name HandbookPanel
extends PanelContainer
## Each page has one purpose. Investigation data stays in the rule module.
signal query_changed(text: String)
signal focus_requested(route: String)
signal locate_requested(route: String)
signal action_requested(action: String)
signal dismissed

const TABS := {"tasks": "任务", "clues": "线索", "rules": "校规"}
var search: LineEdit
var entries: VBoxContainer
var _body: TouchScroll
var _tabs: Dictionary = {}
var _data: Dictionary = {}
var _page := "tasks"


func _ready() -> void:
	name = "NotesPanel"
	add_theme_stylebox_override("panel", UISkin.panel(14))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 7)
	add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "手册"
	title.theme_type_variation = "HeadingLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "NotesClose"
	close.text = "关闭"
	close.theme_type_variation = "QuietButton"
	close.custom_minimum_size = Vector2(68, 44)
	close.pressed.connect(dismiss)
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	layout.add_child(tabs)
	var group := ButtonGroup.new()
	for id: String in TABS:
		var tab := Button.new()
		tab.name = "Handbook_" + id
		tab.text = TABS[id]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 44
		tab.pressed.connect(set_page.bind(id))
		_tabs[id] = tab
		tabs.add_child(tab)
	search = LineEdit.new()
	search.name = "NotesSearch"
	search.custom_minimum_size.y = 44
	search.placeholder_text = "搜索已发现的线索"
	search.text_changed.connect(query_changed.emit)
	layout.add_child(search)
	_body = TouchScroll.new()
	_body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	entries = VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 7)
	_body.add_child(entries)
	layout.add_child(_body)
	get_viewport().size_changed.connect(_fit)
	minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	UIArt.decorate(self)
	hide()


func open(data: Dictionary) -> void:
	if not visible: _page = "tasks"
	_data = data
	var query := String(data.get("query", ""))
	if not query.is_empty() and (not visible or query != search.text): _page = "clues"
	search.text = query
	show()
	move_to_front()
	_render()


func dismiss() -> void:
	hide()
	search.release_focus()
	dismissed.emit()


func set_page(id: String) -> void:
	if not TABS.has(id): return
	_page = id
	search.release_focus()
	_body.stop_motion()
	_body.scroll_vertical = 0
	_render()


func _fit() -> void:
	PanelLayout.fit(self, _body, 650.0, 400.0)


func _render() -> void:
	for child in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	for tab: String in _tabs: _tabs[tab].set_pressed_no_signal(tab == _page)
	search.visible = _page == "clues"
	match _page:
		"tasks": _tasks()
		"clues": _clues()
		"rules": _rules()
	_fit.call_deferred()


func _tasks() -> void:
	var route := String(_data.get("focus", ""))
	var routes: Array = _data.get("routes", [])
	var goal := UISkin.card(entries)
	UIArt.heading(goal, "当前目标", UIArt.route_hint(route), UISkin.ACCENT)
	_line(goal, String(_data.get("goal", "")), UISkin.INK, 18)
	if not String(_data.get("landmark", "")).is_empty():
		var pin := Button.new()
		pin.text = "地图定位 · " + String(_data["landmark"])
		pin.custom_minimum_size.y = 44
		pin.pressed.connect(locate_requested.emit.bind(route))
		goal.add_child(pin)
	if routes.size() > 1:
		var chooser := OptionButton.new()
		chooser.fit_to_longest_item = false
		chooser.clip_text = true
		chooser.custom_minimum_size.y = 44
		chooser.add_item("切换调查方向")
		chooser.set_item_disabled(0, true)
		for lead: Array in routes:
			chooser.add_item(lead[1])
			chooser.set_item_metadata(chooser.item_count - 1, lead[0])
			if lead[0] == route: chooser.select(chooser.item_count - 1)
		chooser.item_selected.connect(func(i: int) -> void: focus_requested.emit(String(chooser.get_item_metadata(i))))
		entries.add_child(chooser)
	var actions: Array = _data.get("actions", [])
	if not actions.is_empty():
		var bar := HFlowContainer.new()
		for action: Array in actions:
			var button := Button.new()
			button.text = action[1]
			button.custom_minimum_size.y = 44
			button.pressed.connect(action_requested.emit.bind(String(action[0])))
			bar.add_child(button)
		entries.add_child(bar)
	for progress: Array in _data.get("progress", []):
		var card := UISkin.card(entries)
		_line(card, ("✓  " if progress[2] else "") + String(progress[0]), UISkin.ACCENT)
		_line(card, String(progress[1]), UISkin.INK)


func _clues() -> void:
	var groups: Dictionary = _data.get("groups", {})
	var latest: Array = _data.get("recent", [])
	var shown := {}
	for row: Dictionary in latest:
		_clue_card(row)
		shown[row.get("id", row["text"])] = true
	for kind: String in InvestigationModule.KINDS:
		for row: Dictionary in groups.get(kind, []):
			if not shown.has(row.get("id", row["text"])): _clue_card(row)
	if int(_data.get("found", 0)) == 0:
		var text := "探索校园时，亲手查到的线索会留在这里。" if search.text.strip_edges().is_empty() else "没有匹配的线索。"
		_line(entries, text, UISkin.MUTED)


func _clue_card(row: Dictionary) -> void:
	var card := UISkin.card(entries)
	_line(card, "%s   ·   第 %d 天   ·   %s" % [row["kind"], int(row.get("day", 1)), row["source"]], UISkin.ACCENT)
	_line(card, String(row["text"]), UISkin.INK)


func _rules() -> void:
	var basics := UISkin.card(entries)
	_line(basics, "学生会检查", UISkin.ACCENT)
	_line(basics, "回教室，停下脚步，移开看向黑影的视线。", UISkin.INK)
	_line(basics, "巡察者", UISkin.ACCENT)
	_line(basics, "走路安静，奔跑会暴露脚步。被盯上时，绕过拐角后再找掩护。", UISkin.INK)
	_line(basics, "精神受到冲击时，巡察者会得知事发区域。", UISkin.INK)
	var seat := String(_data.get("seat_record", ""))
	if not seat.is_empty():
		_line(entries, "座位记录", UISkin.ACCENT)
		_line(entries, seat, UISkin.INK)
	var duty := String(_data.get("duty", ""))
	var permanent := bool(_data.get("permanent", false))
	if permanent or not duty.is_empty():
		_line(entries, "外出记录", UISkin.WARM)
		if permanent: _line(entries, "登记后缺席：持续追踪仍生效。假条、重新登记和符纸不能解除。", UISkin.WARM)
		if not duty.is_empty(): _line(entries, "仍须到教室参加：" + duty + "。许可到期不免除责任；系统取消的检查会顺延。", UISkin.INK)
	var background := String(_data.get("background", ""))
	if not background.is_empty():
		_line(entries, "我的资料", UISkin.ACCENT)
		_line(entries, background, UISkin.INK)


func _line(parent: Control, words: String, tint: Color, size: int = 0) -> void:
	var label := Label.new()
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", tint)
	if size > 0: label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
