class_name DebugPanel
extends PanelContainer
## The developer tools (debug-tab.js, sound-board.js, playtest.js; reference wd-fz.github.io@0bf508a).
## Not part of the player's game: it only opens in a debug build or when the game is started with
## `--dev`, with F9. Three pages: 声音试听 (public sounds only — the sound bank has none of the hidden
## ones), 试玩记录, 工具 (clear debug records; mark the run as not rated).

signal sound_play(id: String)
signal sound_stop
signal playtest_toggled
signal playtest_note(text: String)
signal clear_debug_records
signal mark_untrusted
signal closed

var _index: Dictionary = {}
var _cat: OptionButton
var _snd: OptionButton
var _info: Label
var _all: Button
var _state: Label
var _toggle: Button
var _note: LineEdit
var _msg: Label
var _cats: Array = []
var _ids: Array = []
var playing_all := false


static func enabled() -> bool:
	return OS.has_feature("debug") or OS.get_cmdline_user_args().has("--dev")


func _init(index: Dictionary = {}) -> void:
	_index = index
	name = "DebugPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.04, 0.06, 0.99)
	back.set_content_margin_all(12)
	back.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", back)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "开发工具（不属于玩家的游戏）"
	head.modulate = Color(1.0, 0.9, 0.55)
	box.add_child(head)
	# Sound audition.
	var n := Label.new()
	n.text = "声音试听：声音库 %d 个音效，播放时在配方范围里重新取值" % sfx().size()
	box.add_child(n)
	_cat = OptionButton.new()
	_cat.name = "SoundCat"
	var counts := {}
	for id: String in sfx():
		var c := String(sfx()[id]["cat"])
		counts[c] = int(counts.get(c, 0)) + 1
	_cats = counts.keys()
	_cats.sort()
	for c: String in _cats:
		_cat.add_item("%s（%d）" % [c, counts[c]])
	_cat.item_selected.connect(func(_i: int) -> void: _fill())
	var row := HBoxContainer.new()
	_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_cat)
	_all = Button.new()
	_all.name = "SoundAll"
	_all.text = "整类连放"
	_all.pressed.connect(_play_all)
	row.add_child(_all)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	_snd = OptionButton.new()
	_snd.name = "SoundId"
	_snd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snd.item_selected.connect(func(_i: int) -> void: _show_info())
	row2.add_child(_snd)
	var go := Button.new()
	go.name = "SoundGo"
	go.text = "试听"
	go.pressed.connect(func() -> void:
		if _snd.selected >= 0:
			sound_play.emit(String(_ids[_snd.selected])))
	row2.add_child(go)
	box.add_child(row2)
	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.65)
	box.add_child(_info)
	box.add_child(HSeparator.new())
	# Playtest log.
	_state = Label.new()
	_state.text = "试玩记录：未记录（只写本机，不发送网络请求，不保存身份）"
	box.add_child(_state)
	var prow := HBoxContainer.new()
	_toggle = Button.new()
	_toggle.name = "PlaytestToggle"
	_toggle.text = "开始记录"
	_toggle.pressed.connect(func() -> void: playtest_toggled.emit())
	prow.add_child(_toggle)
	_note = LineEdit.new()
	_note.name = "PlaytestNote"
	_note.placeholder_text = "观察者记录（一句话）"
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_note)
	var add := Button.new()
	add.text = "记入"
	add.pressed.connect(func() -> void:
		playtest_note.emit(_note.text)
		_note.text = "")
	prow.add_child(add)
	box.add_child(prow)
	box.add_child(HSeparator.new())
	var tools := HBoxContainer.new()
	var clear := Button.new()
	clear.name = "ClearDebug"
	clear.text = "清除调试记录"
	clear.pressed.connect(func() -> void: clear_debug_records.emit())
	tools.add_child(clear)
	var mark := Button.new()
	mark.name = "MarkUntrusted"
	mark.text = "把本局标为调试局（不计分）"
	mark.pressed.connect(func() -> void: mark_untrusted.emit())
	tools.add_child(mark)
	box.add_child(tools)
	_msg = Label.new()
	_msg.modulate = Color(0.85, 0.8, 0.55)
	box.add_child(_msg)
	var close := Button.new()
	close.name = "DebugClose"
	close.text = "关闭"
	close.pressed.connect(func() -> void:
		visible = false
		sound_stop.emit()
		closed.emit())
	box.add_child(close)
	add_child(box)
	_fill()


func sfx() -> Dictionary:
	return _index.get("sfx", {})


func ids_of(cat: String) -> Array:
	var out: Array = []
	for id: String in sfx():
		if String(sfx()[id]["cat"]) == cat:
			out.append(id)
	out.sort()
	return out


func _fill() -> void:
	_snd.clear()
	_ids = []
	if _cat.selected >= 0 and _cat.selected < _cats.size():
		_ids = ids_of(String(_cats[_cat.selected]))
	for id: String in _ids:
		_snd.add_item(id)
	_show_info()


func _show_info() -> void:
	if _snd.selected < 0 or _snd.selected >= _ids.size():
		_info.text = ""
		return
	var d: Dictionary = sfx()[_ids[_snd.selected]]
	_info.text = "%s · 约 %.1f 秒 · %d 个变体" % [_ids[_snd.selected], float(d["len"]), (d["files"] as Array).size()]


func _play_all() -> void:
	if playing_all:
		playing_all = false
		_all.text = "整类连放"
		sound_stop.emit()
		return
	playing_all = true
	_all.text = "停止"
	var t := 0.0
	for id: String in _ids:
		var sid := id
		get_tree().create_timer(t).timeout.connect(func() -> void:
			if playing_all:
				sound_play.emit(sid))
		t += float(sfx()[id]["len"]) + 0.6
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if playing_all:
			playing_all = false
			_all.text = "整类连放")


func set_playtest(on: bool, events: int, has_data: bool) -> void:
	_toggle.text = "停止记录" if on else ("重新开始记录" if has_data else "开始记录")
	_state.text = "试玩记录：记录中 · %d 条" % events if on else ("试玩记录：已停止，已写入 user://playtest.json" if has_data else "试玩记录：未记录（只写本机，不发送网络请求，不保存身份）")


func say(text: String) -> void:
	_msg.text = text
