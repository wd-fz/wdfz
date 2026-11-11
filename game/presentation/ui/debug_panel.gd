class_name DebugPanel
extends FloatingPanel
## The developer tools (debug-tab.js, sound-board.js, playtest.js; reference wd-fz.github.io@0bf508a).
## Not part of the player's game: it only opens in a debug build or when the game is started with
## `--dev`, with F9 or the menu button. Audition, playtest notes and developer actions remain
## usable in a bounded movable window, or a small floating dot.

signal sound_play(id: String)
signal sound_stop
signal playtest_toggled
signal playtest_note(text: String)
signal clear_debug_records
signal mark_untrusted
signal closed
signal action(id: String, args: Dictionary)

var _index: Dictionary = {}
var _cat: OptionButton
var _snd: OptionButton
var _info: Label
var _all: Button
var _state: Label
var _toggle: Button
var _note: LineEdit
var _msg: Label
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _selectors: Dictionary = {}
var _live: Label
var _bag_info: Label
var _diagnostics: Label
var _switches: Dictionary = {}
var _active_page := "状态"
var _cats: Array = []
var _ids: Array = []
var playing_all := false
var _audition_generation := 0
var _perf: Label
var _inspect: Label
var _preview_status: Label
var _preview_slider: HSlider
var _preview_pause: Button
var _preview_rate: OptionButton
var _bookmark_list: OptionButton
var _bookmark_ids: Array[String] = ["<initial>"]
var _trace_view: RichTextLabel
var _trace_search: LineEdit
var _trace_kind: OptionButton
var _trace_toggle: Button
var _trace_info: Label
var _trace_data: Dictionary = {}
var _trace_signature := ""


static func enabled() -> bool:
	return OS.has_feature("debug") or OS.get_cmdline_user_args().has("--dev")


func _init(index: Dictionary = {}) -> void:
	super()
	_index = index
	name = "DebugPanel"
	visible = false
	var root_box := VBoxContainer.new()
	var box := _make_pages(root_box)
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "开发工具（不属于玩家的游戏）"
	head.add_theme_color_override("font_color",UISkin.ACCENT)
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
	_snd.fit_to_longest_item = false
	_snd.clip_text = true
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
	var tools := HFlowContainer.new()
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
	_msg.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_msg.max_lines_visible=2
	_msg.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_frame.add_child(_msg)
	var close := Button.new()
	close.name = "DebugClose"
	close.text = "关闭"
	close.pressed.connect(dismiss)
	root_box.add_child(close)
	set_body(root_box)
	for label: Node in root_box.find_children("*", "Label", true, false):
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(label as Label).custom_minimum_size.x = 0
	dismissed.connect(func() -> void:
		stop_audition()
		closed.emit())
	visibility_changed.connect(func() -> void:
		if not visible:
			stop_audition())
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
	stop_audition()
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


func stop_audition() -> void:
	_audition_generation += 1
	playing_all = false
	if is_instance_valid(_all):
		_all.text = "整类连放"
	sound_stop.emit()


func _play_all() -> void:
	if playing_all:
		stop_audition()
		return
	_audition_generation += 1
	var generation := _audition_generation
	playing_all = true
	_all.text = "停止"
	var t := 0.0
	for id: String in _ids.duplicate():
		var sid := id
		get_tree().create_timer(t).timeout.connect(func() -> void:
			if playing_all and generation == _audition_generation and visible:
				sound_play.emit(sid))
		t += float(sfx()[id]["len"]) + 0.6
	get_tree().create_timer(t).timeout.connect(func() -> void:
		if playing_all and generation == _audition_generation:
			playing_all = false
			_all.text = "整类连放")


func set_playtest(on: bool, events: int, has_data: bool) -> void:
	_toggle.text = "停止记录" if on else ("重新开始记录" if has_data else "开始记录")
	_state.text = "试玩记录：记录中 · %d 条" % events if on else ("试玩记录：已停止，已写入 user://playtest.json" if has_data else "试玩记录：未记录（只写本机，不发送网络请求，不保存身份）")


func say(text: String) -> void:
	_msg.text = text
	_msg.tooltip_text = text


func _label(parent: Node, text: String) -> Label:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, key: String, fn: Callable) -> Button:
	var b:=Button.new()
	b.name=key
	b.text=title
	b.custom_minimum_size.y=40
	b.pressed.connect(fn)
	parent.add_child(b)
	return b

func _row(parent: Node) -> HFlowContainer:
	var row:=HFlowContainer.new()
	parent.add_child(row)
	return row

func _send(id: String, args: Dictionary = {}) -> void:
	action.emit(id,args)

func _select(parent: Node, key: String, choices: Array) -> void:
	var search:=LineEdit.new()
	search.name=key+"Search"
	search.placeholder_text="搜索名称或 ID"
	parent.add_child(search)
	var option:=OptionButton.new()
	option.name=key+"Select"
	option.fit_to_longest_item=false
	option.clip_text=true
	option.custom_minimum_size.y=40
	parent.add_child(option)
	_selectors[key]={"option":option,"search":search,"choices":choices}
	search.text_changed.connect(func(_text: String) -> void: _filter(key))
	_filter(key)

func _filter(key: String) -> void:
	var entry: Dictionary=_selectors[key]
	var option: OptionButton=entry.option
	var old:=selected(key)
	option.clear()
	var query:=String(entry.search.text).strip_edges().to_lower()
	for pair: Array in entry.choices:
		if query!="" and not (String(pair[0])+" "+String(pair[1])).to_lower().contains(query): continue
		var art: Texture2D
		if key == "DevItem": art = UIArt.item(String(pair[0]))
		elif key == "DevRoom": art = UIArt.landmark(String(pair[0]))
		elif key == "DevAnomaly": art = UIArt.memory("an:" + String(pair[0]))
		option.add_icon_item(art, String(pair[1])+" · "+String(pair[0]))
		option.get_popup().set_item_icon_max_width(option.item_count - 1, 28)
		option.set_item_metadata(option.item_count-1,String(pair[0]))
		if String(pair[0])==old: option.select(option.item_count-1)
	UIArt.button(option, option.icon, 24)
	option.disabled=option.item_count==0
	if option.item_count==0: option.text="没有匹配项"

func selected(key: String) -> String:
	var option: OptionButton=_selectors[key].option
	return String(option.get_item_metadata(option.selected)) if option.selected>=0 and option.item_count>0 else ""

func select_page(title: String) -> void:
	_scroll.stop_motion()
	_active_page=title
	for key: String in _pages:
		_pages[key].visible=key==title
		(_tabs[key] as Button).set_pressed_no_signal(key==title)
	_scroll.scroll_vertical=0

func _make_pages(parent: VBoxContainer) -> VBoxContainer:
	var tabs:=_row(parent)
	tabs.reparent(_frame,false)
	_frame.move_child(tabs,1)
	for title: String in ["状态","场景","物品","事件","诊断","日志","工具"]:
		var page:=VBoxContainer.new()
		page.name="DevPage"+title
		parent.add_child(page)
		_pages[title]=page
		var tab:=_button(tabs,title,"DevTab"+title,select_page.bind(title))
		UIArt.button(tab, UIArt.nav(String({"状态":"inspect", "场景":"map", "物品":"archive", "事件":"warning", "诊断":"inspect", "日志":"archive", "工具":"debug"}[title])), 18)
		tab.toggle_mode=true
		_tabs[title]=tab
	var status: VBoxContainer=_pages["状态"]
	_live=_label(status,"没有进行中的一局")
	var switches:=_row(status)
	for pair: Array in [["freeze","冻结模拟"],["fast","快跑 ×2.6"],["god","无敌"],["search","立即翻找"]]:
		var key:=String(pair[0])
		var b:=_button(switches,pair[1],"Dev"+key,_send.bind(key,{}))
		b.toggle_mode=true
		_switches[key]=b
	var steps:=_row(status)
	for pair: Array in [["单帧逻辑",1.0/60.0],["步进 0.1 秒",.1],["步进 1 秒",1.0]]:
		_button(steps,pair[0],"DevStep"+str(pair[1]),_send.bind("step",{"seconds":pair[1]}))
	_label(status,"冻结后可逐步推进游戏逻辑／AI；角色物理移动仍保持冻结。")
	var stats:=OptionButton.new()
	stats.name="DevStat"
	for key: String in ["san","stam","viol","tt"]: stats.add_item(key)
	status.add_child(stats)
	var value:=LineEdit.new()
	value.name="DevStatValue"
	value.placeholder_text="0–100（SAN／体力／违规／同化）"
	status.add_child(value)
	var sr:=_row(status)
	_button(sr,"应用数值","DevSetStat",func() -> void: _send("stat",{"key":stats.get_item_text(stats.selected),"value":value.text}))
	_button(sr,"恢复 SAN / 体力","DevHeal",_send.bind("heal",{}))
	var time:=LineEdit.new()
	time.name="DevClock"
	time.placeholder_text="HH:MM · 07:20–次日 00:59"
	status.add_child(time)
	var tr:=_row(status)
	_button(tr,"设置时间","DevSetClock",func() -> void: _send("clock",{"value":time.text}))
	for minutes: int in [-60,-10,10,60]:
		_button(tr,"%+d 分钟" % minutes,"DevTime%d" % minutes,_send.bind("time",{"minutes":minutes}))
	var scene: VBoxContainer=_pages["场景"]
	_label(scene,"传送会结束异象、检查、驾驶与电梯，关闭互动和预览。")
	var rooms: Array=[]
	for id: String in CampusData.rooms(): rooms.append([id,CampusData.rooms()[id]["name"]])
	_select(scene,"DevRoom",rooms)
	_button(scene,"传送到室内","DevTeleport",func() -> void: _send("teleport",{"id":selected("DevRoom")}))
	var outside: Array=[]
	for i in DebugFlow.POI.size(): outside.append([str(i),DebugFlow.POI[i][0]])
	_select(scene,"DevOutdoor",outside)
	_button(scene,"传送到室外","DevTeleportOut",func() -> void: _send("outdoor",{"id":selected("DevOutdoor")}))
	scene.add_child(HSeparator.new())
	_label(scene,"临时位置书签 · 本局最多 8 个；只恢复位置和朝向，不回滚道具、门或剧情。")
	var bookmark_name:=LineEdit.new()
	bookmark_name.name="DevBookmarkName"
	bookmark_name.placeholder_text="书签名称（可留空）"
	bookmark_name.max_length=32
	scene.add_child(bookmark_name)
	_button(scene,"记录当前位置","DevBookmarkAdd",func() -> void: _send("bookmark_add",{"name":bookmark_name.text}))
	_bookmark_list=OptionButton.new()
	_bookmark_list.name="DevBookmarks"
	_bookmark_list.fit_to_longest_item=false
	_bookmark_list.clip_text=true
	scene.add_child(_bookmark_list)
	var bookmarks:=_row(scene)
	_button(bookmarks,"返回书签","DevBookmarkGo",func() -> void:
		if _bookmark_list.selected>=0: _send("bookmark_go",{"id":_bookmark_list.get_item_metadata(_bookmark_list.selected)}))
	_button(bookmarks,"复制位置","DevCopyPosition",_send.bind("copy_position",{}))
	_button(bookmarks,"清空书签","DevBookmarkClear",_send.bind("bookmark_clear",{}))
	var items: VBoxContainer=_pages["物品"]
	_bag_info=_label(items,"")
	var catalog: Array=[]
	for id: String in CampusData.campus()["items"]: catalog.append([id,CampusData.campus()["items"][id]["n"]])
	_select(items,"DevItem",catalog)
	var ir:=_row(items)
	for pair: Array in [["item_add","给予"],["item_remove","移除"],["hot1","设为快捷 1"],["hot2","设为快捷 2"]]:
		var key:=String(pair[0])
		_button(ir,pair[1],"Dev"+key,func() -> void: _send(key,{"id":selected("DevItem")}))
	var events: VBoxContainer=_pages["事件"]
	var anomalies: Array=[]
	for id: String in AnomalyModule.DEFS: anomalies.append([id,AnomalyModule.DEFS[id].get("cn",id)])
	_select(events,"DevAnomaly",anomalies)
	var ar:=_row(events)
	_button(ar,"触发异象","DevAnomalyStart",func() -> void: _send("anomaly",{"id":selected("DevAnomaly")}))
	_button(ar,"结束异象","DevAnomalyEnd",_send.bind("anomaly_end",{}))
	var er:=_row(events)
	for pair: Array in [["fake_normal","切换假正常"],["patrol_start","重置巡察"],["patrol_end","解除追逐"],["inspection","开始检查"],["inspection_end","取消检查"]]:
		_button(er,pair[1],"Dev"+pair[0],_send.bind(pair[0],{}))
	var causes: Array=[]
	for id: String in DeathCG.CAUSES: causes.append([id,DeathCG.title(id)])
	_select(events,"DevDeath",causes)
	var dr:=_row(events)
	_button(dr,"预览演出","DevPreview",func() -> void: _send("preview",{"id":selected("DevDeath")}))
	_button(dr,"停止预览","DevStopPreview",_send.bind("clear_preview",{}))
	_preview_status=_label(events,"未开始演出预览。")
	_preview_slider=HSlider.new()
	_preview_slider.name="DevPreviewTimeline"
	_preview_slider.min_value=0
	_preview_slider.max_value=100
	_preview_slider.step=.1
	_preview_slider.editable=false
	_preview_slider.value_changed.connect(func(value: float) -> void: _send("preview_seek",{"fraction":value/100}))
	events.add_child(_preview_slider)
	var playback:=_row(events)
	_preview_pause=_button(playback,"暂停","DevPreviewPause",_send.bind("preview_pause",{}))
	_button(playback,"从头重播","DevPreviewRestart",_send.bind("preview_restart",{}))
	_preview_rate=OptionButton.new()
	_preview_rate.name="DevPreviewRate"
	for rate: float in [.25,.5,1.0,2.0]:
		_preview_rate.add_item("×%.2f" % rate)
		_preview_rate.set_item_metadata(_preview_rate.item_count-1,rate)
	_preview_rate.select(2)
	_preview_rate.item_selected.connect(func(index: int) -> void: _send("preview_rate",{"rate":_preview_rate.get_item_metadata(index)}))
	playback.add_child(_preview_rate)
	_button(dr,"实际死亡…","DevDeath",_confirm_death)
	_button(dr,"复活","DevRevive",_send.bind("revive",{}))
	var diagnostics: VBoxContainer=_pages["诊断"]
	_perf=_label(diagnostics,"性能采样等待中。")
	_button(diagnostics,"重置帧时间采样","DevMetricsReset",_send.bind("metrics_reset",{}))
	var collision:=_button(diagnostics,"碰撞透视线框","DevCollisions",_send.bind("collisions",{}))
	collision.toggle_mode=true
	_switches["collision_view"]=collision
	_label(diagnostics,"青色为实际碰撞体，橙色为门；最多显示附近 12 米内的 96 个形状。不会修改碰撞。")
	_inspect=_label(diagnostics,"进入游戏后可检查视线命中。")
	_button(diagnostics,"复制位置与朝向","DevInspectCopyPosition",_send.bind("copy_position",{}))
	var logs: VBoxContainer=_pages["日志"]
	_trace_info=_label(logs,"只记录本机内存中的最近 %d 条事件。" % DebugTrace.LIMIT)
	_trace_search=LineEdit.new()
	_trace_search.name="DevTraceSearch"
	_trace_search.placeholder_text="筛选事件、房间或内容"
	_trace_search.max_length=100
	_trace_search.text_changed.connect(func(_value: String) -> void: _show_trace())
	logs.add_child(_trace_search)
	_trace_kind=OptionButton.new()
	_trace_kind.name="DevTraceKind"
	for title: String in ["全部","游戏事实","调试操作"]: _trace_kind.add_item(title)
	_trace_kind.item_selected.connect(func(_index: int) -> void: _show_trace())
	logs.add_child(_trace_kind)
	_trace_view=RichTextLabel.new()
	_trace_view.name="DevTraceEntries"
	_trace_view.custom_minimum_size=Vector2(0,170)
	_trace_view.selection_enabled=true
	_trace_view.bbcode_enabled=false
	logs.add_child(_trace_view)
	var log_buttons:=_row(logs)
	_trace_toggle=_button(log_buttons,"暂停记录","DevTraceToggle",_send.bind("trace_toggle",{}))
	_button(log_buttons,"清空列表","DevTraceClear",_send.bind("trace_clear",{}))
	_button(log_buttons,"复制事件 JSON","DevTraceCopy",_send.bind("trace_copy",{}))
	var tools: VBoxContainer=_pages["工具"]
	_diagnostics=_label(tools,"")
	_button(tools,"复制诊断信息","DevCopy",_send.bind("copy",{}))
	_button(tools,"导出本机诊断报告","DevExportReport",_send.bind("export_report",{}))
	select_page("状态")
	return tools

func _confirm_death() -> void:
	var id:=selected("DevDeath")
	if id=="": return
	var dialog:=ConfirmationDialog.new()
	dialog.title="实际死亡"
	dialog.dialog_text="会触发救命道具，并可能删除本局存档。继续？"
	dialog.confirmed.connect(func() -> void: _send("death",{"id":id}); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(300,140))

func set_runtime(state: Dictionary) -> void:
	for key: String in _switches: (_switches[key] as Button).set_pressed_no_signal(bool(state.get(key,false)))
	if state.has("room"):
		_live.text="第 %d 天 %s · %s\nSAN %.1f · 违规 %.1f · 同化 %.1f · 体力 %.1f / %.1f\n异象 %s · 检查 %s / 排队 %d · 巡察 %s\n%s" % [state.day,state.time,state.room,state.san,state.viol,state.tt,state.stam,state.cap,state.anomaly,"进行中" if state.inspection else "无",state.queued,state.patrol,"真实局" if state.trusted else "调试局（不计真实成绩）"]
		_live.text+="\n位置 %.2f, %.2f, %.2f m" % state.pose.position
		var names: Array=[]
		for id: String in state.bag: names.append(CampusData.campus()["items"].get(id,{}).get("n",id))
		_bag_info.text="背包 %d / 8：%s\n快捷栏：%s" % [names.size(),"、".join(names),str(state.hot)]
	else:
		_live.text="没有进行中的一局。"
		_bag_info.text="背包未载入。"
	_diagnostics.text="%s / %s · %s · FPS %d\n%s" % [state.rendering_driver,state.renderer,state.get("quality_label",str(state.quality)),state.fps,"\n".join(state.history)]

	_show_diagnostics(state)
	_show_preview(state.get("preview",{}))
	_show_bookmarks(state.get("bookmarks",[]))
	_trace_data=state.get("trace",{})
	_show_trace()

func _show_diagnostics(state: Dictionary) -> void:
	var metrics: Dictionary=state.get("metrics",{})
	if metrics.is_empty(): return
	var render:="Draw Calls %d · 图元 %d · 可见对象 %d" % [metrics.draw_calls,metrics.primitives,metrics.render_objects] if metrics.rendered else "无窗口模式：没有真实 GPU 渲染数据"
	_perf.text="%s / %s · %s
FPS %d · 最近 %d 帧 · 均值 %.2f ms · P95 %.2f ms
%s
节点 %d · 资源 %d · 引擎静态内存 %.1f MiB
线框 %d / 附近 %d 个" % [state.rendering_driver,state.renderer,state.get("quality_label",str(state.quality)),metrics.fps,metrics.samples,metrics.average_ms,metrics.p95_ms,render,metrics.nodes,metrics.resources,metrics.static_mib,state.get("collision_count",0),state.get("collision_nearby",0)]
	_perf.text+="\n模型 %d · 光照 %d · 帧率上限 %s · 垂直同步 %s" % [state.get("model_detail",state.quality),state.get("lighting_detail",state.quality),"不限" if int(state.get("fps_limit",0))==0 else str(state.fps_limit),"开" if state.get("vsync",1)==1 else "关"]
	var hit: Dictionary=state.get("inspect",{})
	if hit.is_empty():
		_inspect.text="进入游戏并选择此页后检查视线；过场期间停用。"
		return
	_inspect.text="姿态：%s · 原地图坐标：%s
格子：%s · 类型：%s
当前交互提示：%s" % [hit.get("posture",""),str(hit.get("world_units",[])),str(hit.get("tile",[])),hit.get("cell","室外"),hit.get("interaction","")]
	_inspect.text+="\n物理交互提示："+String(hit.get("physical_interaction",""))
	if hit.get("hit",false):
		_inspect.text+="
视线命中 %.2f m · %s
碰撞节点：%s
形状：%s · 层 %d
命中点 %s · 法线 %s" % [hit.distance,hit["class"],hit.collider,String(hit.shape)+" / "+String(hit.get("kind","")),hit.layer,str(hit.point),str(hit.normal)]
	else: _inspect.text+="
视线前方 30 米内无物理命中。"

func _show_preview(state: Dictionary) -> void:
	var active:=bool(state.get("active",false))
	_preview_slider.editable=active
	_preview_pause.disabled=not active
	_preview_rate.disabled=not active
	_preview_pause.text="继续" if state.get("paused",false) else "暂停"
	_preview_status.text="%s · %.2f / %.2f 秒 · %s" % [state.get("title",""),state.get("time",0),state.get("duration",0),"暂停" if state.get("paused",false) else "播放中"] if active else "未开始演出预览。"
	_preview_slider.set_value_no_signal(100*float(state.get("time",0))/maxf(.1,float(state.get("duration",0))))
	for i in _preview_rate.item_count:
		if is_equal_approx(float(_preview_rate.get_item_metadata(i)),float(state.get("rate",1))): _preview_rate.select(i)

func _show_bookmarks(bookmarks: Array) -> void:
	var ids: Array[String]=[]
	for bookmark: Dictionary in bookmarks: ids.append("%s/%s/%s" % [bookmark.id,bookmark.name,bookmark.room])
	if ids==_bookmark_ids: return
	_bookmark_ids=ids
	_bookmark_list.clear()
	for bookmark: Dictionary in bookmarks:
		_bookmark_list.add_item(String(bookmark.name)+" · "+String(bookmark.room))
		_bookmark_list.set_item_metadata(_bookmark_list.item_count-1,String(bookmark.id))
	_bookmark_list.disabled=bookmarks.is_empty()
	if bookmarks.is_empty(): _bookmark_list.text="还没有位置书签"

func _show_trace() -> void:
	if not is_instance_valid(_trace_view): return
	var query:=_trace_search.text.strip_edges().to_lower()
	var kind: String=["","fact","command"][_trace_kind.selected]
	var signature:="%s/%s/%s/%s" % [_trace_data.get("revision",0),_trace_data.get("recording",true),query,kind]
	if signature==_trace_signature: return
	_trace_signature=signature
	var lines:=PackedStringArray()
	for entry: Dictionary in _trace_data.get("entries",[]):
		if kind!="" and entry.kind!=kind: continue
		var context: Dictionary=entry.context
		var line:="[%d] #%d %s %s · %s · %s\n%s" % [entry.seq,context.get("session",0),context.get("time",""),context.get("room","菜单"),"事实" if entry.kind=="fact" else "操作",entry.title,JSON.stringify(entry.detail)]
		if query!="" and not line.to_lower().contains(query): continue
		lines.append(line)
	_trace_view.text="\n\n".join(lines) if not lines.is_empty() else "没有匹配的事件。"
	_trace_toggle.text="暂停记录" if _trace_data.get("recording",true) else "继续记录"
	_trace_info.text="%s · 显示 %d / %d 条 · 已淘汰 %d 条" % ["记录中" if _trace_data.get("recording",true) else "已暂停",lines.size(),_trace_data.get("entries",[]).size(),_trace_data.get("discarded",0)]

func refit() -> void:
	super.refit()
	if not is_inside_tree(): return
	# Keep touch hit targets at least 44 viewport pixels after compact scaling.
	var pixel_scale:=absf(get_viewport().get_final_transform().get_scale().y)*scale.y
	var height:=ceilf(44/maxf(.1,pixel_scale))
	for node: Node in find_children("*","Control",true,false):
		if node is BaseButton or node is LineEdit or node is HSlider:
			if not is_equal_approx(node.custom_minimum_size.y,height): node.custom_minimum_size.y=height
			if node is Button and node.name in ["Collapse","CloseWindow"]: node.custom_minimum_size.x=height
