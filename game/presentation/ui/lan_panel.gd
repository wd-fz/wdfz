class_name LanPanel
extends Control
signal host_requested(name: String, nickname: String, port: int, resume: bool)
signal join_requested(address: String, nickname: String)
signal ready_requested(value: bool, talent: String)
signal start_requested
signal leave_requested
signal close_requested
signal discover_requested
signal pause_requested(value: bool)
signal reconnect_requested
signal remove_requested(id: String)
signal configure_requested(capacity: int, difficulty: String)
signal save_requested
signal ending_requested
signal give_requested(target: String, item: String)
signal debug_requested(action: String, fields: Dictionary)
var nickname: LineEdit
var address: LineEdit
var room_name: LineEdit
var port: SpinBox
var talent: OptionButton
var ready_button: CheckButton
var status: Label
var members: VBoxContainer
var discovered: VBoxContainer
var start_button: Button
var host_form: VBoxContainer
var lobby: VBoxContainer
var _panel: PanelContainer
var _scroll: TouchScroll
var _state: Dictionary = {}
var _local_id := ""
var _gifts: Array = []
var capacity: SpinBox
var difficulty: OptionButton
var transfer: OptionButton
var metrics: Label
var _addresses := ""
var _member_key := ""
var _member_labels: Dictionary = {}
var address_options: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.035, 0.045, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UISkin.panel(18))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var heading := Label.new()
	heading.text = "一起离开校园 · 局域网合作"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "2–4 人局域网合作 · 一人建房，其他人输入房主的局域网地址。"
	column.add_child(status)
	_scroll = TouchScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_scroll.add_child(content)
	host_form = VBoxContainer.new()
	host_form.add_theme_constant_override("separation", 10)
	content.add_child(host_form)
	var scope := Label.new()
	scope.text = "支持六条公开结局。隐藏路线、特殊空间、DLC、手机小游戏与相册暂仅支持单人。"
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(scope)
	nickname = _line(host_form, "你的称呼", "同学")
	room_name = _line(host_form, "房间名称", "好友的校园")
	var network := HBoxContainer.new()
	host_form.add_child(network)
	address = _line(network, "房主 IPv4:端口", "")
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = LanProtocol.PORT
	port.custom_minimum_size = Vector2(126, 44)
	network.add_child(port)
	capacity = SpinBox.new()
	capacity.min_value = 2
	capacity.max_value = 4
	capacity.value = 4
	capacity.prefix = "人数 "
	capacity.custom_minimum_size = Vector2(126, 44)
	difficulty = OptionButton.new()
	difficulty.add_item("普通")
	difficulty.add_item("困难")
	difficulty.custom_minimum_size.y = 44
	var rules := HBoxContainer.new()
	host_form.add_child(rules)
	rules.add_child(capacity)
	rules.add_child(difficulty)
	var commands := HBoxContainer.new()
	host_form.add_child(commands)
	_button(commands, "创建房间", func() -> void:
		host_requested.emit(room_name.text, nickname.text, int(port.value), false)
		configure_requested.emit(int(capacity.value), "hard" if difficulty.selected == 1 else "easy"))
	_button(commands, "恢复合作存档", func() -> void: host_requested.emit(room_name.text, nickname.text, int(port.value), true))
	_button(commands, "加入", func() -> void: join_requested.emit(address.text, nickname.text))
	var search := HBoxContainer.new()
	host_form.add_child(search)
	_button(search, "查找附近房间", func() -> void: discover_requested.emit())
	_button(search, "重连上次房间", func() -> void: reconnect_requested.emit())
	discovered = VBoxContainer.new()
	host_form.add_child(discovered)
	lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 10)
	content.add_child(lobby)
	members = VBoxContainer.new()
	lobby.add_child(members)
	address_options = OptionButton.new()
	address_options.custom_minimum_size.y = 44
	lobby.add_child(address_options)
	_button(lobby, "复制选中地址", func() -> void:
		if address_options.selected >= 0: DisplayServer.clipboard_set(address_options.get_item_text(address_options.selected)))
	transfer = OptionButton.new()
	transfer.custom_minimum_size.y = 44
	lobby.add_child(transfer)
	talent = OptionButton.new()
	talent.custom_minimum_size.y = 48
	_gifts.append("none")
	talent.add_item("不选天赋")
	for key: String in TalentModule.DEF:
		_gifts.append(key)
		talent.add_item(String(TalentModule.DEF[key]["n"]))
	lobby.add_child(talent)
	talent.item_selected.connect(func(_index: int) -> void:
		ready_button.set_pressed_no_signal(false)
		ready_requested.emit(false, String(_gifts[talent.selected])))
	ready_button = CheckButton.new()
	ready_button.text = "我已准备好"
	ready_button.custom_minimum_size.y = 48
	ready_button.toggled.connect(func(value: bool) -> void: ready_requested.emit(value, String(_gifts[talent.selected])))
	lobby.add_child(ready_button)
	start_button = _button(lobby, "开始合作", func() -> void: start_requested.emit())
	var pause_row := HBoxContainer.new()
	pause_row.name = "PauseRow"
	lobby.add_child(pause_row)
	_button(pause_row, "全队暂停（最长 120 秒）", func() -> void: pause_requested.emit(true))
	_button(pause_row, "恢复全队", func() -> void: pause_requested.emit(false))
	var actions := HBoxContainer.new()
	actions.name = "GameActions"
	lobby.add_child(actions)
	_button(actions, "发起共同逃离", func() -> void: ending_requested.emit())
	_button(actions, "保存合作进度（房主）", func() -> void: save_requested.emit())
	var debug_row := HBoxContainer.new()
	debug_row.name = "DebugRow"
	lobby.add_child(debug_row)
	_button(debug_row, "调试：恢复本人状态（标记整局）", func() -> void: debug_requested.emit("debug_recover", {}))
	metrics = Label.new()
	metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics.add_theme_font_size_override("font_size", 13)
	lobby.add_child(metrics)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_button(footer, "返回", func() -> void: close_requested.emit())
	_button(footer, "离开房间", func() -> void: leave_requested.emit())
	get_viewport().size_changed.connect(refit)
	visibility_changed.connect(refit)
	show_room({}, "", "")
	refit.call_deferred()


func _line(parent: Node, placeholder: String, value: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = value
	edit.max_length = 64
	edit.custom_minimum_size.y = 44
	parent.add_child(edit)
	return edit


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func show_room(state: Dictionary, local_id: String, addresses: String) -> void:
	_state = state
	_local_id = local_id
	if addresses != "": _addresses = addresses.split(" / ")[0]
	if not is_node_ready(): return
	host_form.visible = state.is_empty()
	lobby.visible = not state.is_empty()
	if addresses != "" and addresses != String(address_options.get_meta("list", "")):
		address_options.set_meta("list", addresses)
		address_options.clear()
		for address_value: String in addresses.split(" / "): address_options.add_item(address_value)
	if state.is_empty():
		_member_key = ""
		return
	var hosting: bool = state.get("host") == local_id
	var playing: bool = state.get("phase") in ["playing", "ended"]
	status.text = ("房主地址：" + addresses + "\n" if hosting else "已加入好友的校园\n") + ("联机中个人菜单不暂停世界。" if playing else "各自选择天赋并准备，房主即可开始。")
	var structural := [str(playing), local_id, String(state.get("host", ""))]
	for id: String in state["members"]: structural.append(id + String(state["members"][id]["state"]))
	var member_key := "|".join(PackedStringArray(structural))
	if _member_key != member_key:
		_member_key = member_key
		_member_labels.clear()
		for child in members.get_children():
			members.remove_child(child)
			child.queue_free()
		for id: String in state["members"]:
			var m: Dictionary = state["members"][id]
			var row := HBoxContainer.new()
			members.add_child(row)
			var label := Label.new()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(label)
			_member_labels[id] = label
			if playing and id != local_id and m["state"] == "alive":
				_button(row, "交付物品", func() -> void:
					if transfer.selected >= 0: give_requested.emit(id, String(transfer.get_item_metadata(transfer.selected))))
				if hosting: _button(row, "调试传送", func() -> void: debug_requested.emit("debug_teleport", {"to": id}))
			if hosting and id != local_id: _button(row, "移除", func() -> void: remove_requested.emit(id))
	for id: String in state["members"]:
		var m: Dictionary = state["members"][id]
		_member_labels[id].text = "%s%s · %s%s" % [m["name"], "（你）" if id == local_id else "", "已离队" if m["state"] == "departed" else ("死亡／观战" if m["state"] == "dead" else ("在线" if m["connected"] else "断线保留 %d 秒" % ceili(float(m["remaining"])))), " · 已准备" if m["ready"] and not playing else ""]
	if state["members"].has(local_id):
		ready_button.set_pressed_no_signal(state["members"][local_id]["ready"])
		var chosen := _gifts.find(state["members"][local_id]["talent"])
		if chosen >= 0: talent.select(chosen)
	ready_button.visible = state.get("phase") == "lobby"
	talent.visible = ready_button.visible
	start_button.visible = hosting and ready_button.visible
	lobby.get_node("PauseRow").visible = playing
	lobby.get_node("GameActions").visible = playing
	transfer.visible = playing
	lobby.get_node("DebugRow").visible = hosting and playing
	refit.call_deferred()


func inventory(entries: Array) -> void:
	var wanted := "|".join(PackedStringArray(entries.map(func(e: Dictionary) -> String: return String(e["id"]))))
	if wanted == String(transfer.get_meta("items", "")): return
	transfer.set_meta("items", wanted)
	transfer.clear()
	for entry: Dictionary in entries:
		transfer.add_item(String(entry.get("name", entry["id"])))
		transfer.set_item_metadata(transfer.item_count - 1, entry["id"])


func found(list: Array) -> void:
	for child in discovered.get_children():
		discovered.remove_child(child)
		child.queue_free()
	for entry: Dictionary in list:
		var target := "%s:%d" % [entry["ip"], int(entry["port"])]
		_button(discovered, "%s · %s · %d 人 · 协议 %d · %s" % [entry["name"], target, int(entry.get("count", 0)), LanProtocol.VERSION, {"lobby": "大厅", "loading": "加载中", "playing": "进行中", "ended": "已结束"}.get(entry.get("phase"), "未知")], func() -> void:
			address.text = target)
	refit.call_deferred()


func refit() -> void:
	if not is_node_ready(): return
	PanelLayout.fit(_panel, _scroll, 840.0, 400.0, float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0)
