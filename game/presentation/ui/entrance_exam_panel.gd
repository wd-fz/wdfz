class_name EntranceExamPanel
extends ColorRect
## The classroom remains visible behind the paper. Navigation never commits an answer.
signal action(operation: String, index: int, option: int)
signal expired

var index := 0
var _exam: EntranceExam
var _sheet := PanelContainer.new()
var _title := Label.new()
var _clock := Label.new()
var _pages := OptionButton.new()
var _prompt := Label.new()
var _options: Array[Button] = []
var _prev := Button.new()
var _next := Button.new()
var _submit := Button.new()
var _scroll := TouchScroll.new()
var _phase := ""
var _confirming := false
var _submitted := false
var _expired := false
var _until_ms := 0
var _last_second := -1


func _ready() -> void:
	name = "EntranceExam"
	process_mode = Node.PROCESS_MODE_ALWAYS
	color = Color(0.035, 0.055, 0.075, 0.38)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _sheet
	panel.add_theme_stylebox_override("panel", UISkin.panel(12))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_fit)
	_fit()
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", UISkin.ACCENT)
	header.add_child(_title)
	header.add_child(_clock)
	_pages.custom_minimum_size.y = 40
	_pages.fit_to_longest_item = false
	layout.add_child(_pages)
	_pages.item_selected.connect(_go)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(body)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_font_size_override("font_size", 20)
	body.add_child(_prompt)
	for i in 4:
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 44
		body.add_child(b)
		_options.append(b)
		b.pressed.connect(_pick.bind(i))
	var nav := HBoxContainer.new()
	layout.add_child(nav)
	for b: Button in [_prev, _next, _submit]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 44
		nav.add_child(b)
	_prev.text = "上一题"
	_prev.pressed.connect(func() -> void:
		if _confirming:
			_confirming = false
			_paint()
		else: _go(index - 1))
	_next.text = "下一题"
	_next.pressed.connect(func() -> void: _go(index + 1))
	_submit.pressed.connect(_commit)


func _fit() -> void:
	var margin := maxf(10, (size.x - 730) * 0.5)
	_sheet.offset_left = margin
	_sheet.offset_right = -margin
	_sheet.offset_top = maxf(6, (size.y - 490) * 0.5) if _phase == "writing" else maxf(6, size.y - 190)
	_sheet.offset_bottom = -_sheet.offset_top if _phase == "writing" else -6


func present(exam: EntranceExam, student: String, seconds_left: float) -> void:
	_exam = exam
	_title.text = "武大附中　·　高二综合测验　　　姓名　" + student
	_until_ms = Time.get_ticks_msec() + roundi(seconds_left * 1000)
	if _phase != exam.phase:
		_confirming = false
		_submitted = false
		_expired = false
		if _phase.is_empty(): index = 0
	_phase = exam.phase
	_fit()
	_paint()
	_process(0.0)


func _go(target: int) -> void:
	index = clampi(target, 0, EntranceExam.COUNT - 1)
	_scroll.scroll_vertical = 0
	_paint()


func _pick(option: int) -> void:
	if _submitted or _expired: return
	action.emit("exam_answer", index, option)
	_paint()


func _commit() -> void:
	if _submitted: return
	if _phase == "waiting":
		_submitted = true
		action.emit("exam_start", -1, -1)
	elif _phase == "graded":
		_submitted = true
		action.emit("exam_wake", -1, -1)
	elif _phase == "writing":
		if not _confirming:
			_confirming = true
			_paint()
			_prev.grab_focus()
		else:
			_submitted = true
			_paint()
			action.emit("exam_submit", -1, -1)


func _paint() -> void:
	var writing := _phase == "writing"
	var reading := writing and not _confirming
	_clock.visible = writing
	_pages.visible = reading
	_prev.visible = writing
	_prev.disabled = _submitted or (not _confirming and index == 0)
	_prev.text = "返回答题" if _confirming else "上一题"
	_next.visible = reading
	_next.disabled = index == EntranceExam.COUNT - 1
	_submit.visible = _phase in ["waiting", "writing", "graded"]
	_submit.disabled = _submitted or (writing and _expired)
	match _phase:
		"waiting": _submit.text = "写下姓名，开始答题"
		"graded": _submit.text = "收起试卷"
		_: _submit.text = "确认交卷" if _confirming else "提前交卷"
	for b: Button in _options: b.visible = reading
	if reading:
		var q := _exam.question(index)
		var selected := int(_exam.answers[index])
		_prompt.text = q.text
		if _pages.item_count != EntranceExam.COUNT:
			_pages.clear()
			for n in EntranceExam.COUNT: _pages.add_item("")
		for n in EntranceExam.COUNT:
			var subject: String = EntranceExamBank.SUBJECTS[floori(float(n) / EntranceExam.PER_SUBJECT)]
			var label := "%s　%02d / 30　·　%s" % [subject, n + 1, "已答" if int(_exam.answers[n]) >= 0 else "待答"]
			if _pages.get_item_text(n) != label: _pages.set_item_text(n, label)
		_pages.select(index)
		for i in 4:
			_options[i].text = "%s　%s" % [char(65 + i), q.choices[i]]
			_options[i].set_pressed_no_signal(i == selected)
	elif _confirming:
		_prompt.text = "还有 %d 道题未答。交卷后只公布总分，无法再改答案。" % _exam.answers.count(-1)
	elif _phase == "waiting":
		_prompt.text = "监考老师把试卷放上课桌。「先写姓名。六科各五题，十分钟。交卷前可以改答案。」窗外传来操场上的哨声。"
	elif _phase == "graded":
		_prompt.text = "得分　%d / %d" % [_exam.score, EntranceExam.COUNT]
	else:
		_prompt.text = "我的试卷已经交了。等待队友收卷并醒来……"


func _process(_dt: float) -> void:
	if not visible or _phase != "writing": return
	var left := maxi(0, ceili((_until_ms - Time.get_ticks_msec()) / 1000.0))
	if left != _last_second:
		_clock.text = "%02d:%02d" % [floori(left / 60.0), left % 60]
		_last_second = left
	if left == 0 and not _expired:
		_expired = true
		expired.emit()
