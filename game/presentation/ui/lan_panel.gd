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
signal rules_requested(enabled: bool)
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
var rules_dlc: CheckButton
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
var _feedback_until := 0
var _default_status := ""
var _team: Dictionary = {}
var _gift_buttons: Dictionary = {}
var _talent_info: HBoxContainer
var _talent_image: TextureRect
var _talent_text: Label
var _retry: Button
var _can_reconnect := false
var _reconnect_address := ""
var _connection_failed := false
var _confirmation: Dictionary = {}
var _confirm_box: VBoxContainer
var _confirm_text: Label
var _confirm_button: Button
var _help_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UISkin.shade(self, 0.76)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UISkin.cinematic_panel(16))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_heading = _label(column, "与好友联机", 26)
	_heading.theme_type_variation = "HeadingLabel"
	_modes = HBoxContainer.new()
	column.add_child(_modes)
	_button(_modes, "同一 Wi-Fi / 热点", func() -> void: mode_requested.emit(false), "LanMode").theme_type_variation = "RailButton"
	_button(_modes, "远程联机", func() -> void: mode_requested.emit(true), "RemoteMode").theme_type_variation = "RailButton"
	column.add_child(HSeparator.new())
	_scroll = TouchScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_scroll.add_child(content)
	# Long failure reports belong to the scrollable body; they must not squeeze
	# its viewport into the fixed tabs/footer on a short landscape screen.
	status = _label(content, "2–4 人合作 · 一人建房，好友加入")
	status.add_theme_color_override("font_color", UISkin.MUTED)
	_retry = _button(content, "重连原角色", func() -> void: reconnect_requested.emit(), "RetryConnection")
	_retry.hide()
	_confirm_box = VBoxContainer.new()
	content.add_child(_confirm_box)
	_confirm_text = _label(_confirm_box, "")
	_confirm_box.hide()
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
	var home_actions := HBoxContainer.new()
	home_actions.add_theme_constant_override("separation", 12)
	home.add_child(home_actions)
	var create_page := _button(home_actions, "创建房间", func() -> void: select_page("create"), "CreatePage")
	var join_page := _button(home_actions, "加入房间", func() -> void: select_page("join"), "JoinPage")
	for action: Button in [create_page, join_page]:
		action.custom_minimum_size.y = 118
		action.theme_type_variation = "CommandButton"
		action.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		action.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	UIArt.button(create_page, UIArt.nav("new_game"), 62)
	UIArt.button(join_page, UIArt.nav("continue"), 62)
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
	rules_dlc = CheckButton.new()
	rules_dlc.text = "规则怪谈 DLC（全队统一）"
	rules_dlc.custom_minimum_size.y = 48
	create.add_child(rules_dlc)
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
		feedback("邀请码已复制，发给好友即可加入。"), "CopyInvitation")
	members = VBoxContainer.new()
	lobby.add_child(members)
	talent = OptionButton.new()
	talent.custom_minimum_size.y = 48
	talent.add_item("天赋 · 不选择")
	for key: String in TalentModule.DEF:
		_gifts.append(key)
		talent.add_item("天赋 · " + String(TalentModule.DEF[key]["n"]))
	lobby.add_child(talent)
	_talent_info = HBoxContainer.new()
	lobby.add_child(_talent_info)
	_talent_image = TextureRect.new()
	_talent_image.custom_minimum_size = Vector2(72, 72)
	_talent_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_talent_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_talent_info.add_child(_talent_image)
	_talent_text = _label(_talent_info, "", 16)
	talent.item_selected.connect(func(_index: int) -> void:
		ready_button.set_pressed_no_signal(false)
		_update_talent()
		ready_requested.emit(false, String(_gifts[talent.selected])))
	_team_actions = _fold(lobby, "队伍操作", "TeamActions")
	var pause_row := HBoxContainer.new()
	pause_row.name = "PauseRow"
	_team_actions.add_child(pause_row)
	_button(pause_row, "全队暂停", func() -> void: pause_requested.emit(true)).name = "PauseTeam"
	_button(pause_row, "恢复全队", func() -> void: pause_requested.emit(false), "ResumeTeam")
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
			feedback("地址已复制，让好友在“直接连接”中粘贴。"))
	_label(_details, "双方使用同一版本，连接同一 Wi-Fi 或房主热点，并保持游戏前台。\n能发现房间但加入失败时，请复制房主与客户端两端的诊断；发现房间与游戏连接使用不同端口。")
	connection_info = _label(_details, "")
	connection_info.add_theme_font_size_override("font_size", 14)
	metrics = _label(_details, "")
	metrics.add_theme_font_size_override("font_size", 14)
	_button(_details, "复制诊断信息", func() -> void:
		DisplayServer.clipboard_set(connection_info.text + "\n" + metrics.text)
		feedback("诊断信息已复制。"), "CopyDiagnostics")
	var debug := _fold(_details, "房主调试工具", "HostDebug")
	_button(debug, "恢复本人状态（标记整局）", func() -> void: debug_requested.emit("debug_recover", {}))
	_debug_target = OptionButton.new()
	_debug_target.custom_minimum_size.y = 48
	debug.add_child(_debug_target)
	_button(debug, "传送到队友（标记整局）", func() -> void:
		if _debug_target.selected >= 0: debug_requested.emit("debug_teleport", {"to": _debug_target.get_item_metadata(_debug_target.selected)}))
	_button(_details, "Terracotta · 开源许可", func() -> void: OS.shell_open("https://github.com/burningtnt/Terracotta/tree/v0.4.2"))
	_label(_details, "公开路线与隐藏逃离均需全队确认。梦境和特殊电梯只影响进入者；小游戏独立进行，照片只留本机。规则怪谈由房主建房时选择。")
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
	_confirm_button = _button(footer, "确认", _confirm_action, "ConfirmRoomAction")
	_leave = _button(footer, "离开房间", _ask_leave, "LeaveRoom")
	_settings_button.reparent(footer)
	_help_button = _details.get_parent().get_child(0)
	_help_button.text = "连接帮助"
	_help_button.reparent(footer)
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


func show_connection_error(reason: String) -> void:
	_connection_failed = true
	feedback(reason, 0)
	_details.show()
	_update_layout()
	_scroll.stop_motion()
	_scroll.scroll_vertical = 0
	refit.call_deferred()


func _go_back() -> void:
	if not _confirmation.is_empty(): _cancel_confirmation()
	elif busy:
		cancel_requested.emit()
	elif _state.is_empty() and page != "home": select_page("home")
	elif not _state.is_empty() and _state.get("phase") not in ["playing", "ended"]: _ask_leave()
	else: close_requested.emit()


func _create(restore: bool) -> void:
	if busy or not _state.is_empty(): return
	_connection_failed = false
	_feedback_until = 0
	var nick := nickname.text.strip_edges()
	if nick == "": nick = "同学"
	var title := room_name.text.strip_edges()
	if title == "": title = nick + "的校园"
	set_busy(true)
	host_requested.emit(title, nick, int(port.value), restore)
	if not restore:
		configure_requested.emit(capacity.get_selected_id(), "hard" if difficulty.selected == 1 else "easy")
		rules_requested.emit(rules_dlc.button_pressed)


func request_join(target: String) -> void:
	if busy or not _state.is_empty(): return
	_connection_failed = false
	_feedback_until = 0
	address.text = target.strip_edges()
	var nick := nickname.text.strip_edges()
	if nick == "": nick = "同学"
	set_busy(true)
	join_requested.emit(address.text, nick)


func set_history(reconnect: bool, restore: bool, endpoint: String = "") -> void:
	_can_reconnect = reconnect
	_reconnect_address = endpoint
	_reconnect.visible = reconnect
	_restore.visible = restore
	_retry.visible = reconnect and _connection_failed and not busy


func set_remote(value: bool) -> void:
	remote_mode = value
	_remote_status = ""
	_remote_connected = false
	_scanned = false
	_connection_failed = false
	_feedback_until = 0
	_confirmation.clear()
	_team.clear()
	address.text = ""
	address.placeholder_text = "粘贴好友的邀请码 U/…" if value else "粘贴房主地址，例如 192.168.1.2"
	_invitation.text = ""
	_copy_code.disabled = true
	page = "home"
	_settings.hide()
	_details.hide()
	_direct.visible = value
	_default_status = "好友不在身边？创建房间后分享邀请码。" if value else "2–4 人合作 · 一人建房，好友加入"
	status.text = _default_status
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
	if value:
		_connection_failed = false
		_feedback_until = 0
	_update_layout()


func _update_layout() -> void:
	var in_room := not _state.is_empty()
	var hosting: bool = in_room and _state.get("host") == _local_id
	var playing: bool = in_room and _state.get("phase") in ["playing", "ended"]
	var running: bool = in_room and _state.get("phase") == "playing"
	var waiting: bool = in_room and _state.get("phase") == "lobby"
	var confirming := not _confirmation.is_empty()
	_heading.text = ("远程联机" if remote_mode else "附近联机") + (" · 队伍" if playing else " · 房间" if in_room else "")
	if in_room: _heading.text = String(_state.get("title", _heading.text)) + (" · 困难" if _state.get("difficulty") == "hard" else " · 普通") + (" · 规则怪谈" if _state.get("rules_dlc", false) else "")
	_confirm_box.visible = confirming
	_confirm_button.visible = confirming
	_help_button.visible = not confirming
	_retry.visible = _connection_failed and _can_reconnect and not busy
	_modes.visible = not in_room and not busy and not confirming
	for button: Button in _modes.get_children():
		button.toggle_mode = true
		button.set_pressed_no_signal((button.name == "RemoteMode") == remote_mode)
	host_form.visible = not in_room and not busy and not confirming
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
	lobby.visible = in_room and not confirming
	_remote_info.visible = remote_mode and hosting
	_network_details.visible = not remote_mode and in_room
	_team_actions.get_parent().visible = in_room and (hosting or playing)
	_team_actions.get_node("PauseRow").visible = running
	_team_actions.find_child("PauseTeam", true, false).visible = hosting
	_team_actions.get_node("SaveTeam").visible = hosting and running
	_team_actions.get_node("EscapeTeam").visible = running
	transfer.visible = running
	_details.get_node("HostDebug").visible = hosting and running
	talent.visible = waiting
	_talent_info.visible = waiting
	_actions.visible = waiting and not confirming
	ready_button.visible = waiting
	start_button.visible = waiting and hosting
	_update_readiness()
	ready_button.disabled = remote_mode and not _remote_connected
	_back.text = "取消" if confirming else "取消连接" if busy else "返回游戏" if playing else "关闭房间" if hosting else "离开房间" if in_room else "返回"
	_leave.visible = playing and not confirming
	_details.get_parent().visible = not confirming
	_update_talent()
	refit.call_deferred()


func show_room(state: Dictionary, local_id: String, addresses: String) -> void:
	var old_phase := String(_state.get("phase", ""))
	_state = state
	_local_id = local_id
	if not is_node_ready(): return
	if not state.is_empty():
		busy = false
		_connection_failed = false
		if old_phase.is_empty(): _details.hide()
	if addresses != "" and addresses != String(address_options.get_meta("list", "")):
		address_options.set_meta("list", addresses)
		address_options.clear()
		for value: String in addresses.split(" / "): address_options.add_item(value)
	if state.is_empty():
		_member_key = ""
		_team.clear()
		_confirmation.clear()
		_default_status = "好友不在身边？创建房间后分享邀请码。" if remote_mode else "2–4 人合作 · 一人建房，好友加入"
		if _feedback_until == 0: status.text = _default_status
		_update_layout()
		return
	if _confirmation.get("kind") == "remove" and state.get("members", {}).get(_confirmation.get("id"), {}).get("state", "departed") == "departed":
		_cancel_confirmation()
	var hosting: bool = state.get("host") == local_id
	_default_status = LanRoomView.summary(state)
	if remote_mode and not _remote_connected: _default_status = _remote_status
	if old_phase != String(state.get("phase", "")): _feedback_until = 0
	if _feedback_until == 0: status.text = _default_status
	var structural := [String(state.get("phase", "")), local_id, String(state.get("host", ""))]
	var ids := LanRoomView.ordered_ids(state, local_id)
	for id: String in ids: structural.append(id + String(state["members"][id]["state"]))
	var member_key := "|".join(PackedStringArray(structural))
	var changed := _member_key != member_key
	if _member_key != member_key:
		_member_key = member_key
		_member_labels.clear()
		_gift_buttons.clear()
		_clear(members)
		_clear(_management)
		_debug_target.clear()
		for id: String in ids:
			_member_labels[id] = _label(UISkin.card(members), "")
			_member_labels[id].add_theme_color_override("font_color", LanRoomView.color(id))
			var m: Dictionary = state["members"][id]
			if id == local_id or m["state"] == "departed": continue
			_debug_target.add_item(String(m["name"]))
			_debug_target.set_item_metadata(_debug_target.item_count - 1, id)
			var row := HBoxContainer.new()
			_management.add_child(row)
			_label(row, String(m["name"]))
			if state.get("phase") == "playing" and m["state"] == "alive":
				_gift_buttons[id] = _button(row, "交付物品", func() -> void:
					if transfer.selected >= 0 and transfer.get_item_metadata(transfer.selected) != null: give_requested.emit(id, String(transfer.get_item_metadata(transfer.selected))))
			if hosting: _button(row, "移除", func() -> void: _ask_remove(id))
	_update_members()
	if state["members"].has(local_id):
		ready_button.set_pressed_no_signal(state["members"][local_id]["ready"])
		var chosen := _gifts.find(state["members"][local_id]["talent"])
		if chosen >= 0: talent.select(chosen)
	if changed or old_phase != String(state.get("phase", "")): _update_layout()
	else:
		_update_readiness()
		_update_talent()


func inventory(entries: Array) -> void:
	var wanted := JSON.stringify(entries.map(func(e: Dictionary) -> Array: return [e["id"], e.get("name", e["id"])]))
	if wanted == String(transfer.get_meta("items", "")): return
	var selected: Variant = transfer.get_item_metadata(transfer.selected) if transfer.selected >= 0 else null
	transfer.set_meta("items", wanted)
	transfer.clear()
	for entry: Dictionary in entries:
		transfer.add_item(String(entry.get("name", entry["id"])))
		transfer.set_item_metadata(transfer.item_count - 1, entry["id"])
		if selected == entry["id"]: transfer.select(transfer.item_count - 1)
	if entries.is_empty(): transfer.add_item("背包里暂无可交付物品")
	transfer.disabled = entries.is_empty()
	_update_members()


func feedback(text: String, seconds: float = 5.0) -> void:
	status.text = text
	_feedback_until = Time.get_ticks_msec() + int(seconds * 1000) if seconds > 0 else -1


func show_team(details: Dictionary) -> void:
	_team = details
	_update_members()


func _update_members() -> void:
	for id: String in _member_labels:
		var member: Dictionary = _state.get("members", {}).get(id, {})
		_member_labels[id].text = LanRoomView.member_text(id, member, _state, _local_id, _team.get(id, {}))
	for id: String in _gift_buttons:
		var near: bool = _team.get(id, {}).get("can_give", false)
		var online: bool = _state.get("members", {}).get(id, {}).get("connected", false)
		var button: Button = _gift_buttons[id]
		button.disabled = transfer.disabled or not online or not near or _state.get("phase") != "playing"
		button.text = "等待重连" if not online else "靠近并开门" if not near else "交付物品"


func _update_readiness() -> void:
	var hint := LanRoomView.start_hint(_state)
	start_button.disabled = _state.get("phase") != "lobby" or not hint.is_empty() or (remote_mode and not _remote_connected)
	start_button.text = "等待远程连接" if remote_mode and not _remote_connected else hint if not hint.is_empty() else "开始合作"
	var paused: bool = float(_state.get("paused", 0)) > 0
	(_team_actions.get_node("PauseRow/PauseTeam") as Button).disabled = paused
	(_team_actions.get_node("PauseRow/ResumeTeam") as Button).disabled = not paused


func _update_talent() -> void:
	var id := String(_gifts[talent.selected]) if talent.selected >= 0 else "none"
	if _talent_info.get_meta("gift", "") == id: return
	_talent_info.set_meta("gift", id)
	var data: Dictionary = TalentModule.DEF.get(id, {})
	_talent_image.texture = UIArt.talent(id) if not data.is_empty() else null
	_talent_image.visible = _talent_image.texture != null
	_talent_text.text = String(data.get("does", "不选择天赋也可以开始。每位队员独立选择。"))
	if not data.is_empty(): _talent_text.text += "\n" + String(data["limit"])


func _ask_leave() -> void:
	if _state.is_empty(): close_requested.emit(); return
	var hosting: bool = _state.get("host") == _local_id
	_confirmation = {"kind": "leave"}
	_confirm_text.text = "关闭房间会断开所有队友。合作进度由房主保管，可先保存。" if hosting else "离开后将断开连接。角色暂时保留，可使用本机重连记录回来。"
	_confirm_button.text = "确认关闭房间" if hosting else "确认离开"
	_scroll.scroll_vertical = 0
	_update_layout()


func _ask_remove(id: String) -> void:
	if not _state.get("members", {}).has(id): return
	_confirmation = {"kind": "remove", "id": id}
	_confirm_text.text = "将 %s 移出本局？该角色无法再重连，携带物品会留在校园。" % _state["members"][id]["name"]
	_confirm_button.text = "确认移除"
	_scroll.scroll_vertical = 0
	_update_layout()


func _cancel_confirmation() -> void:
	_confirmation.clear()
	_update_layout()


func _confirm_action() -> void:
	var action := _confirmation.duplicate()
	_cancel_confirmation()
	if action.get("kind") == "leave": leave_requested.emit()
	elif action.get("kind") == "remove": remove_requested.emit(String(action["id"]))


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
		var remembered := LanProtocol.address(_reconnect_address)
		var rejoin := _can_reconnect and not remembered.is_empty() and remembered == LanProtocol.address(target) and phase != "ended"
		var note := "版本不同，请双方更新" if incompatible else "恢复原角色" if rejoin else "房间已满" if full else "游戏进行中" if phase != "lobby" else "点击加入"
		# Discovery replies arrive several times per second. Replacing a button
		# under a pressed finger loses the release and silently drops the join.
		if not _room_buttons.has(key):
			_room_buttons[key] = _button(discovered, "", func() -> void:
				if not _room_buttons.has(key) or busy: return
				if _room_buttons[key].get_meta("rejoin", false): reconnect_requested.emit()
				else: request_join(String(_room_buttons[key].get_meta("address"))))
		var button: Button = _room_buttons[key]
		button.text = "%s    %d/%d 人\n%s" % [entry["name"], int(entry.get("count", 0)), int(entry.get("capacity", 4)), note]
		button.set_meta("address", target)
		button.set_meta("rejoin", rejoin)
		button.disabled = incompatible or (not rejoin and (full or phase != "lobby"))
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
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if node_name in ["CreateRoom", "JoinRoom", "StartRoom", "ConfirmRoomAction"]:
		button.theme_type_variation = "PrimaryButton"
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
	if not is_node_ready() or not is_inside_tree(): return
	var keyboard := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	# Keyboard height is in window pixels; layout uses stretched canvas units.
	keyboard /= maxf(0.01, get_viewport().get_screen_transform().get_scale().y)
	var home := page == "home" and _state.is_empty() and not busy and not _connection_failed
	var height := 380.0
	if home:
		height = minf(280.0, (_scroll.get_child(0) as Control).get_combined_minimum_size().y)
	PanelLayout.fit(_panel, _scroll, 760.0, height, keyboard if keyboard > 0 else -1.0)
	for option: OptionButton in [talent, capacity, difficulty, address_options, transfer]:
		option.get_popup().max_size.y = maxi(120, mini(360, int(get_viewport_rect().size.y) - 100))


func _process(dt: float) -> void:
	if _feedback_until > 0 and Time.get_ticks_msec() >= _feedback_until:
		_feedback_until = 0
		status.text = _default_status
	if not is_visible_in_tree() or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): return
	_keyboard_timer += dt
	if _keyboard_timer < 0.15: return
	_keyboard_timer = 0.0
	var height := DisplayServer.virtual_keyboard_get_height()
	if height != _keyboard_height:
		_keyboard_height = height
		refit()
