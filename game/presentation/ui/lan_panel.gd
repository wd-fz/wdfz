class_name LanPanel
extends Control
## One task per page; connection details and host tools are opt-in.
signal host_requested(name: String, nickname: String, port: int, resume: bool)
signal join_requested(address: String, nickname: String)
signal ready_requested(value: bool, talent: String)
signal start_requested
signal leave_requested
signal close_requested
signal discover_requested
signal cancel_requested
signal mode_requested(remote: bool)
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
var capacity: OptionButton
var difficulty: OptionButton
var transfer: OptionButton
var metrics: Label
var connection_info: Label
var address_options: OptionButton
var remote_mode := false
var page := "home"
var busy := false
var _panel: PanelContainer
var _scroll: TouchScroll
var _state: Dictionary = {}
var _local_id := ""
var _gifts: Array = ["none"]
var _pages: Dictionary = {}
var _heading: Label
var _search: Button
var search_note: Label
var _scanned := false
var _copy_address: Button
var _remote_info: VBoxContainer
var _invitation: LineEdit
var _copy_code: Button
var _remote_status := ""
var _remote_connected := false
var _member_key := ""
var _member_labels: Dictionary = {}
var _modes: HBoxContainer
var _direct: VBoxContainer
var _direct_button: Button
var _settings: VBoxContainer
var _settings_button: Button
var _host_settings: VBoxContainer
var _port_row: HBoxContainer
var _progress: VBoxContainer
var _back: Button
var _leave: Button
var _reconnect: Button
var _restore: Button
var _actions: HBoxContainer
var _team_actions: VBoxContainer
var _management: VBoxContainer
var _details: VBoxContainer
var _network_details: VBoxContainer
var _local_content := ""
var _debug_target: OptionButton
var _room_buttons: Dictionary = {}
var _keyboard_height := 0
var _keyboard_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.035, 0.045, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UISkin.panel(14))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_heading = _label(column, "与好友联机", 26)
	_modes = HBoxContainer.new()
	column.add_child(_modes)
	_button(_modes, "同一 Wi-Fi / 热点", func() -> void: mode_requested.emit(false), "LanMode")
	_button(_modes, "远程联机", func() -> void: mode_requested.emit(true), "RemoteMode")
	status = _label(column, "2–4 人合作 · 一人建房，好友加入")
	status.add_theme_color_override("font_color", UISkin.MUTED)
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
	for key: String in ["home", "create", "join"]:
		var body := VBoxContainer.new()
		body.name = key.capitalize() + "Page"
		body.add_theme_constant_override("separation", 10)
		host_form.add_child(body)
		_pages[key] = body
	var home: VBoxContainer = _pages.home
	_button(home, "创建房间\n邀请好友一起探索", func() -> void: select_page("create"), "CreatePage").custom_minimum_size.y = 76
	_button(home, "加入房间\n找到好友的校园", func() -> void: select_page("join"), "JoinPage").custom_minimum_size.y = 76
	_reconnect = _button(home, "重连上次房间", func() -> void: reconnect_requested.emit(), "Reconnect")
	_reconnect.visible = false
	var create: VBoxContainer = _pages.create
	_label(create, "选择难度，创建后等待好友加入。")
	var rules := HBoxContainer.new()
	create.add_child(rules)
	capacity = OptionButton.new()
	for n in [2, 3, 4]: capacity.add_item("最多 %d 人" % n, n)
	capacity.select(2)
	capacity.custom_minimum_size.y = 48
	capacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.add_child(capacity)
	difficulty = OptionButton.new()
	difficulty.add_item("普通难度")
	difficulty.add_item("困难难度")
	difficulty.custom_minimum_size.y = 48
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.add_child(difficulty)
	_button(create, "创建并等待好友", func() -> void: _create(false), "CreateRoom")
	_restore = _button(create, "继续上次合作", func() -> void: _create(true), "RestoreRoom")
	_restore.visible = false
	var join: VBoxContainer = _pages.join
	_search = _button(join, "刷新附近房间", func() -> void: discover_requested.emit(), "FindRooms")
	search_note = _label(join, "正在寻找房间……")
	search_note.name = "SearchNote"
	discovered = VBoxContainer.new()
	discovered.add_theme_constant_override("separation", 8)
	join.add_child(discovered)
	_direct_button = _button(join, "找不到房间？直接连接", func() -> void:
		_direct.visible = not _direct.visible
		refit.call_deferred(), "DirectJoin")
	_direct = VBoxContainer.new()
	join.add_child(_direct)
	address = _line(_direct, "房主地址", "")
	address.name = "JoinAddress"
	address.text_submitted.connect(func(_text: String) -> void: request_join(address.text))
	var join_actions := HBoxContainer.new()
	_direct.add_child(join_actions)
	_button(join_actions, "粘贴", func() -> void: address.text = DisplayServer.clipboard_get().strip_edges(), "PasteAddress")
	_button(join_actions, "加入房间", func() -> void: request_join(address.text), "JoinRoom")
	_settings_button = _button(host_form, "更多设置", func() -> void:
		_settings.visible = not _settings.visible
		_update_layout(), "MoreSettings")
	_settings = VBoxContainer.new()
	host_form.add_child(_settings)
	nickname = _line(_settings, "你的称呼", "同学")
	_host_settings = VBoxContainer.new()
	_settings.add_child(_host_settings)
	room_name = _line(_host_settings, "房间名称（可不填）", "")
	_port_row = HBoxContainer.new()
	_host_settings.add_child(_port_row)
	_label(_port_row, "游戏端口")
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = LanProtocol.PORT
	port.custom_minimum_size = Vector2(150, 48)
	_port_row.add_child(port)
	_progress = VBoxContainer.new()
	content.add_child(_progress)
	var progress := ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	_progress.add_child(progress)
	_label(_progress, "正在连接，请稍候。可以随时取消。")
	lobby = VBoxContainer.new()
	lobby.add_theme_constant_override("separation", 10)
	content.add_child(lobby)
	_remote_info = VBoxContainer.new()
	lobby.add_child(_remote_info)
	_label(_remote_info, "把邀请码发给好友")
	var invitation_row := HBoxContainer.new()
	_remote_info.add_child(invitation_row)
	_invitation = _line(invitation_row, "正在准备邀请码……", "")
	_invitation.editable = false
	_copy_code = _button(invitation_row, "复制", func() -> void:
		DisplayServer.clipboard_set(_invitation.text)
		status.text = "邀请码已复制，发给好友即可加入。", "CopyInvitation")
	members = VBoxContainer.new()
	lobby.add_child(members)
	talent = OptionButton.new()
	talent.custom_minimum_size.y = 48
	talent.add_item("天赋 · 不选择")
	for key: String in TalentModule.DEF:
		_gifts.append(key)
		talent.add_item("天赋 · " + String(TalentModule.DEF[key]["n"]))
	lobby.add_child(talent)
	talent.item_selected.connect(func(_index: int) -> void:
		ready_button.set_pressed_no_signal(false)
		ready_requested.emit(false, String(_gifts[talent.selected])))
	_team_actions = _fold(lobby, "队伍操作", "TeamActions")
	var pause_row := HBoxContainer.new()
	pause_row.name = "PauseRow"
	_team_actions.add_child(pause_row)
	_button(pause_row, "全队暂停", func() -> void: pause_requested.emit(true)).name = "PauseTeam"
	_button(pause_row, "继续游戏", func() -> void: pause_requested.emit(false))
	_button(_team_actions, "共同逃离", func() -> void: ending_requested.emit(), "EscapeTeam")
	_button(_team_actions, "保存进度", func() -> void: save_requested.emit()).name = "SaveTeam"
	transfer = OptionButton.new()
	transfer.custom_minimum_size.y = 48
	_team_actions.add_child(transfer)
	_management = VBoxContainer.new()
	_team_actions.add_child(_management)
	_details = _fold(content, "连接帮助与诊断", "ConnectionDetails")
	_network_details = VBoxContainer.new()
	_details.add_child(_network_details)
	address_options = OptionButton.new()
	address_options.custom_minimum_size.y = 48
	_network_details.add_child(address_options)
	_copy_address = _button(_network_details, "复制连接地址", func() -> void:
		if address_options.selected >= 0:
			DisplayServer.clipboard_set(address_options.get_item_text(address_options.selected))
			status.text = "地址已复制，让好友在“直接连接”中粘贴。")
	_label(_details, "同一 Wi-Fi 或连接房主的热点；房主保持游戏前台。\n看得到房间却进不去时，检查双方版本是否一致，以及路由器的设备隔离设置。")
	connection_info = _label(_details, "")
	connection_info.add_theme_font_size_override("font_size", 14)
	metrics = _label(_details, "")
	metrics.add_theme_font_size_override("font_size", 14)
	_button(_details, "复制诊断信息", func() -> void:
		DisplayServer.clipboard_set(connection_info.text + "\n" + metrics.text)
		status.text = "诊断信息已复制。")
	var debug := _fold(_details, "房主调试工具", "HostDebug")
	_button(debug, "恢复本人状态（标记整局）", func() -> void: debug_requested.emit("debug_recover", {}))
	_debug_target = OptionButton.new()
	_debug_target.custom_minimum_size.y = 48
	debug.add_child(_debug_target)
	_button(debug, "传送到队友（标记整局）", func() -> void:
		if _debug_target.selected >= 0: debug_requested.emit("debug_teleport", {"to": _debug_target.get_item_metadata(_debug_target.selected)}))
	_button(_details, "Terracotta · 开源许可", func() -> void: OS.shell_open("https://github.com/burningtnt/Terracotta/tree/v0.4.2"))
	_label(_details, "支持六条公开结局。隐藏路线、特殊空间、DLC、手机小游戏与相册暂仅支持单人。")
	_actions = HBoxContainer.new()
	column.add_child(_actions)
	ready_button = CheckButton.new()
	ready_button.text = "准备好了"
	ready_button.custom_minimum_size.y = 50
	ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready_button.toggled.connect(func(value: bool) -> void: ready_requested.emit(value, String(_gifts[talent.selected])))
	_actions.add_child(ready_button)
	start_button = _button(_actions, "开始合作", func() -> void: start_requested.emit(), "StartCoop")
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_back = _button(footer, "返回", _go_back, "Back")
	_leave = _button(footer, "离开房间", func() -> void: leave_requested.emit(), "LeaveRoom")
	_settings_button.reparent(footer)
	var help_button: Button = _details.get_parent().get_child(0)
	help_button.text = "连接帮助"
	help_button.reparent(footer)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/lan_manifest.json"))
	if manifest is Dictionary: _local_content = String(manifest.get("digest", ""))
	get_viewport().size_changed.connect(refit)
	visibility_changed.connect(refit)
	_panel.minimum_size_changed.connect(refit, CONNECT_DEFERRED)
	set_remote(false)
	show_room({}, "", "")


func select_page(value: String) -> void:
	if busy or not _state.is_empty() or not _pages.has(value): return
	page = value
	_settings.hide()
	_direct.visible = remote_mode
	_scroll.scroll_vertical = 0
	_update_layout()
	if page == "join" and not remote_mode: discover_requested.emit()


func _go_back() -> void:
	if busy:
		cancel_requested.emit()
	elif _state.is_empty() and page != "home": select_page("home")
	else: close_requested.emit()


func _create(restore: bool) -> void:
	if busy or not _state.is_empty(): return
	var nick := nickname.text.strip_edges()
	if nick == "": nick = "同学"
	var title := room_name.text.strip_edges()
	if title == "": title = nick + "的校园"
	set_busy(true)
	host_requested.emit(title, nick, int(port.value), restore)
	if not restore: configure_requested.emit(capacity.get_selected_id(), "hard" if difficulty.selected == 1 else "easy")


func request_join(target: String) -> void:
	if busy or not _state.is_empty(): return
	address.text = target.strip_edges()
	var nick := nickname.text.strip_edges()
	if nick == "": nick = "同学"
	set_busy(true)
	join_requested.emit(address.text, nick)


func set_history(reconnect: bool, restore: bool) -> void:
	_reconnect.visible = reconnect
	_restore.visible = restore


func set_remote(value: bool) -> void:
	remote_mode = value
	_remote_status = ""
	_remote_connected = false
	_scanned = false
	address.text = ""
	address.placeholder_text = "粘贴好友的邀请码 U/…" if value else "粘贴房主地址，例如 192.168.1.2"
	_invitation.text = ""
	_copy_code.disabled = true
	page = "home"
	_settings.hide()
	_direct.visible = value
	status.text = "好友不在身边？创建房间后分享邀请码。" if value else "2–4 人合作 · 一人建房，好友加入"
	_update_layout()


func remote_status(text: String, invitation: String = "", connected: bool = false) -> void:
	_remote_status = text
	_remote_connected = connected
	status.text = text
	_invitation.text = invitation
	_copy_code.disabled = invitation == ""
	_update_layout()


func set_busy(value: bool) -> void:
	busy = value
	_update_layout()


func _update_layout() -> void:
	var in_room := not _state.is_empty()
	var hosting: bool = in_room and _state.get("host") == _local_id
	var playing: bool = in_room and _state.get("phase") in ["playing", "ended"]
	var waiting: bool = in_room and _state.get("phase") == "lobby"
	_heading.text = ("远程联机" if remote_mode else "附近联机") + (" · 队伍" if playing else " · 房间" if in_room else "")
	_modes.visible = not in_room and not busy
	for button: Button in _modes.get_children():
		button.toggle_mode = true
		button.set_pressed_no_signal((button.name == "RemoteMode") == remote_mode)
	host_form.visible = not in_room and not busy
	for key: String in _pages: _pages[key].visible = page == key
	_settings_button.visible = not in_room and not busy
	_settings_button.text = "收起设置" if _settings.visible else "设置"
	_host_settings.visible = page == "create"
	_port_row.visible = not remote_mode
	port.visible = not remote_mode
	_search.visible = not remote_mode
	_direct_button.visible = not remote_mode
	discovered.visible = not remote_mode
	search_note.visible = not remote_mode
	_progress.visible = busy and not in_room
	lobby.visible = in_room
	_remote_info.visible = remote_mode and hosting
	_network_details.visible = not remote_mode and in_room
	_team_actions.get_parent().visible = in_room and (hosting or playing)
	_team_actions.get_node("PauseRow").visible = playing
	_team_actions.find_child("PauseTeam", true, false).visible = hosting
	_team_actions.get_node("SaveTeam").visible = hosting and playing
	_team_actions.get_node("EscapeTeam").visible = playing
	transfer.visible = playing
	_details.get_node("HostDebug").visible = hosting and playing
	talent.visible = waiting
	_actions.visible = waiting
	ready_button.visible = waiting
	start_button.visible = waiting and hosting
	start_button.disabled = remote_mode and not _remote_connected
	ready_button.disabled = remote_mode and not _remote_connected
	_back.text = "取消连接" if busy else "返回游戏" if playing else "关闭房间" if hosting else "离开房间" if in_room else "返回"
	_leave.visible = playing
	refit.call_deferred()


func show_room(state: Dictionary, local_id: String, addresses: String) -> void:
	_state = state
	_local_id = local_id
	if not is_node_ready(): return
	if not state.is_empty(): busy = false
	if addresses != "" and addresses != String(address_options.get_meta("list", "")):
		address_options.set_meta("list", addresses)
		address_options.clear()
		for value: String in addresses.split(" / "): address_options.add_item(value)
	if state.is_empty():
		_member_key = ""
		_update_layout()
		return
	var hosting: bool = state.get("host") == local_id
	var playing: bool = state.get("phase") in ["playing", "ended"]
	status.text = "个人菜单不会暂停队友。" if playing else "选择天赋并准备，房主开始游戏。"
	if remote_mode and not _remote_connected: status.text = _remote_status
	var structural := [str(playing), local_id, String(state.get("host", ""))]
	for id: String in state["members"]: structural.append(id + String(state["members"][id]["state"]))
	var member_key := "|".join(PackedStringArray(structural))
	if _member_key != member_key:
		_member_key = member_key
		_member_labels.clear()
		_clear(members)
		_clear(_management)
		_debug_target.clear()
		for id: String in state["members"]:
			_member_labels[id] = _label(UISkin.card(members), "")
			var m: Dictionary = state["members"][id]
			if id == local_id: continue
			_debug_target.add_item(String(m["name"]))
			_debug_target.set_item_metadata(_debug_target.item_count - 1, id)
			var row := HBoxContainer.new()
			_management.add_child(row)
			_label(row, String(m["name"]))
			if playing and m["state"] == "alive":
				_button(row, "交付物品", func() -> void:
					if transfer.selected >= 0: give_requested.emit(id, String(transfer.get_item_metadata(transfer.selected))))
			if hosting: _button(row, "移除", func() -> void: remove_requested.emit(id))
	for id: String in state["members"]:
		var m: Dictionary = state["members"][id]
		var role := " · 房主" if id == state.get("host") else ""
		var detail := "已离队" if m["state"] == "departed" else "观战中" if m["state"] == "dead" else "暂时断线" if not m["connected"] else "已准备" if m["ready"] and not playing else "探索中" if playing else "未准备"
		_member_labels[id].text = "%s%s%s    %s" % [m["name"], "（你）" if id == local_id else "", role, detail]
	if state["members"].has(local_id):
		ready_button.set_pressed_no_signal(state["members"][local_id]["ready"])
		var chosen := _gifts.find(state["members"][local_id]["talent"])
		if chosen >= 0: talent.select(chosen)
	_update_layout()


func inventory(entries: Array) -> void:
	var wanted := "|".join(PackedStringArray(entries.map(func(e: Dictionary) -> String: return String(e["id"]))))
	if wanted == String(transfer.get_meta("items", "")): return
	transfer.set_meta("items", wanted)
	transfer.clear()
	for entry: Dictionary in entries:
		transfer.add_item(String(entry.get("name", entry["id"])))
		transfer.set_item_metadata(transfer.item_count - 1, entry["id"])


func scanning(active: bool) -> void:
	_scanned = true
	_search.disabled = active
	_search.text = "正在查找……" if active else "刷新附近房间"
	_note_scan(active)


func _note_scan(active: bool) -> void:
	search_note.text = "点击房间即可加入" if not _room_buttons.is_empty() else "正在寻找好友的房间……" if active else "没有找到房间。请先让好友创建房间。"


func found(list: Array) -> void:
	var wanted := {}
	for entry: Dictionary in list:
		var target := "%s:%d" % [entry["ip"], int(entry["port"])]
		var key := String(entry.get("room", target))
		wanted[key] = true
		var incompatible: bool = entry.has("content") and entry["content"] != _local_content
		var full := int(entry.get("count", 0)) >= int(entry.get("capacity", 4))
		var phase := String(entry.get("phase", "lobby"))
		var note := "版本不同，请双方更新" if incompatible else "房间已满" if full else "游戏进行中" if phase != "lobby" else "点击加入"
		# Discovery replies arrive several times per second. Replacing a button
		# under a pressed finger loses the release and silently drops the join.
		if not _room_buttons.has(key):
			_room_buttons[key] = _button(discovered, "", func() -> void:
				if _room_buttons.has(key): request_join(String(_room_buttons[key].get_meta("address"))))
		var button: Button = _room_buttons[key]
		button.text = "%s    %d/%d 人\n%s" % [entry["name"], int(entry.get("count", 0)), int(entry.get("capacity", 4)), note]
		button.set_meta("address", target)
		button.disabled = incompatible or full or phase != "lobby"
		button.custom_minimum_size.y = 68
	for key: String in _room_buttons.keys():
		if wanted.has(key): continue
		var button: Button = _room_buttons[key]
		discovered.remove_child(button)
		button.queue_free()
		_room_buttons.erase(key)
	if _scanned: _note_scan(_search.disabled)
	refit.call_deferred()


func _label(parent: Node, text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _line(parent: Node, placeholder: String, value: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = value
	edit.max_length = 64
	edit.custom_minimum_size.y = 48
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


func _button(parent: Node, text: String, action: Callable, node_name: String = "") -> Button:
	var button := Button.new()
	if node_name != "": button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _fold(parent: Node, title: String, node_name: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = node_name
	parent.add_child(group)
	var body := VBoxContainer.new()
	_button(group, title, func() -> void:
		body.visible = not body.visible
		refit.call_deferred())
	group.add_child(body)
	body.hide()
	return body


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func refit() -> void:
	if not is_node_ready(): return
	var keyboard := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	# Keyboard height is in window pixels; layout uses stretched canvas units.
	keyboard /= maxf(0.01, get_viewport().get_screen_transform().get_scale().y)
	PanelLayout.fit(_panel, _scroll, 760.0, 280.0 if page == "home" and _state.is_empty() else 380.0, keyboard if keyboard > 0 else -1.0)
	for option: OptionButton in [talent, capacity, difficulty, address_options, transfer]:
		option.get_popup().max_size.y = maxi(120, mini(360, int(get_viewport_rect().size.y) - 100))


func _process(dt: float) -> void:
	if not is_visible_in_tree() or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return
	_keyboard_timer += dt
	if _keyboard_timer < 0.15: return
	_keyboard_timer = 0.0
	var height := DisplayServer.virtual_keyboard_get_height()
	if height != _keyboard_height:
		_keyboard_height = height
		refit()
