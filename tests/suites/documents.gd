extends "res://tests/support/test_suite.gd"

func notes() -> Dictionary:
	var rows := []
	for i in 32: rows.append({"kind":"事实","text":"楼梯口的灯闪了两次。我记下了这一层的声音和门牌，准备回去核对通知稿与图纸。","day":i/8+1,"source":"教学楼与实验楼"})
	return {"goal":"寻找离开学校的方法，核对每一页记录与刚才看见的东西。","focus":"car","routes":[["car","车辆"],["face","白名单"],["portal","造门"],["cyber","网安仙人"],["dismissal","放学"],["international","国际部"]],"recent":rows.slice(0,3),"groups":{"事实":rows},"progress":[["造门","还没有找到门框图纸与电源模块，需要返回实验楼继续调查。",false]],"found":32,"query":""}

func type_text(text: String) -> void:
	for c: String in text:
		for pressed: bool in [true,false]:
			var event := InputEventKey.new()
			event.pressed = pressed
			event.keycode = c.to_upper().unicode_at(0)
			event.physical_keycode = event.keycode
			event.unicode = c.unicode_at(0)
			Input.parse_input_event(event)
		await _frames(1)

func touch(control: Control, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = root.get_final_transform()*control.get_global_rect().get_center()
	Input.parse_input_event(event)
	await _frames(2)

func test_layout_and_input() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	var old_size := root.size
	var old_scale := root.content_scale_size
	var commands: Array[String] = []
	ui.terminal_command.connect(func(command: String) -> void: commands.append(command))
	var returns := [0]
	ui.death_menu_requested.connect(func() -> void: returns[0]+=1)
	var mic := MicPanel.new()
	ui.get_node("Root").add_child(mic)
	var held := [false]
	mic.hold_changed.connect(func(on: bool) -> void: held[0]=on)
	mic.closed.connect(mic.hide)
	for screen: Vector2i in [Vector2i(960,540),Vector2i(640,360),Vector2i(420,900),Vector2i(320,640)]:
		root.size = screen
		await _frames(3)
		for scale: int in [85,100,150]:
			ui.apply_text_scale(scale)
			var bounds := root.get_visible_rect()
			ui.show_notes(notes())
			await _frames(8)
			var close: Button = ui.notes_panel.find_child("NotesClose",true,false)
			check(bounds.encloses(ui.notes_panel.get_global_rect()) and bounds.encloses(close.get_global_rect()),"notes and sticky close fit %s / %d" % [screen,scale])
			check(ui._notes_box.size.x<=ui._notes_scroll.size.x and ui._notes_scroll.get_v_scroll_bar().visible,"long records and route filters wrap inside a scrollable body")
			await _tap(close)
			check(not ui.notes_panel.visible,"notes close accepts screen touch")
			ui.show_import()
			ui._import_text.text = "{\"version\":\"not-a-save\"}"
			ui.show_import_result("存档中的扩展版本不兼容，原进度仍然保留。".repeat(6))
			await _frames(8)
			close = ui._import_panel.find_child("ImportClose",true,false)
			check(bounds.encloses(ui._import_panel.get_global_rect()) and bounds.encloses(close.get_global_rect()),"import help, editor and error stay inside %s / %d" % [screen,scale])
			check(ui._import_text.text.contains("not-a-save"),"resizing import preserves the pasted source")
			await _tap(close)
			check(not ui._import_panel.visible,"import closes by screen touch even with a long error")
			ui.show_terminal("校园维护终端\n".repeat(50),"连接正常 · 巡察者正在室外调查，留意脚步和灯光。")
			await _frames(8)
			close = ui.terminal_panel.find_child("TerminalExit",true,false)
			check(ui._term_line.has_focus(),"terminal takes input focus including its very first opening")
			check(bounds.encloses(ui.terminal_panel.get_global_rect()) and bounds.encloses(close.get_global_rect()),"terminal output, command and all buttons fit %s / %d" % [screen,scale])
			await type_text("help")
			var enter := InputEventKey.new()
			enter.pressed = true
			enter.keycode = KEY_ENTER
			Input.parse_input_event(enter)
			enter = enter.duplicate()
			enter.pressed = false
			Input.parse_input_event(enter)
			await _frames(2)
			check(commands.size()==1 and commands[0]=="help" and ui._term_line.text.is_empty(),"physical typing and Enter dispatch exactly one intact command")
			commands.clear()
			await _tap(close)
			check(not ui.terminal_open() and not ui._term_line.has_focus(),"touch exit releases terminal focus")
			ui.show_death_card("那扇门在身后关上了。","你听见自己的名字。","巡察者抓住了你。",PackedStringArray(["注意灯光和脚步。".repeat(20)]),PackedStringArray(["本局见到的新事件。".repeat(10)]),"本局积分：120")
			await _frames(8)
			close = ui.death_panel.find_child("DeathMenu",true,false)
			check(bounds.encloses(ui.death_panel.get_global_rect()) and bounds.encloses(close.get_global_rect()),"long death clues scroll without hiding the menu button")
			await _tap(close)
			check(returns[0]==1,"death return accepts screen touch")
			returns[0] = 0
			ui.hide_death()
			mic.show()
			mic.paint([["notice1","第一段通知稿：行政楼广播站的补充通知与朗读说明"]],"notice1","这是一份很长的通知。请按原来的顺序阅读，不要跳过重复的句子。\n".repeat(14),"广播已接通。完成这段后切换下一张通知稿。",2,14,false,true)
			await _frames(8)
			check(bounds.encloses(mic.get_global_rect()) and bounds.encloses(mic.hold_button.get_global_rect()) and bounds.encloses(mic.leave_button.get_global_rect()),"microphone keeps read and leave controls visible %s / %d" % [screen,scale])
			await touch(mic.hold_button,true)
			check(held[0],"real touch begins reading")
			await touch(mic.hold_button,false)
			check(not held[0],"real touch release stops reading")
			await touch(mic.hold_button,true)
			mic.hide()
			check(not held[0],"hiding a held microphone cancels its pointer state")
			await touch(mic.hold_button,false)
	mic.show()
	await _frames(4)
	await touch(mic.hold_button,true)
	root.size = Vector2i(960,540)
	await _frames(5)
	check(not held[0],"orientation changes cancel an active microphone touch")
	await touch(mic.hold_button,false)
	await _tap(mic.leave_button)
	check(not mic.visible,"microphone leave works after rotating while held")
	ui.queue_free()
	await _frames(2)
	root.size = old_size
	root.content_scale_size = old_scale

func test_microphone_boundaries() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/mic/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.items().add("notice1")
	app.save_game()
	for boundary: String in ["load","new","menu"]:
		for id: String in ["notice1","notice2","notice3","notice4"]: app.items().add(id)
		app.school().day = 2
		app.school().tsec = 1100
		app.broadcast().b["book"] = true
		app.broadcast().b["fuse"] = true
		var room: Dictionary = CampusData.layout("admin2")
		app.travel("admin2",_campus_pose(room,CampusGeometry.tile_center(room,5,3)+Vector2(0,9),-PI*.5),false)
		app.broadcast().set_context(app._broadcast_context())
		app._open_mic()
		var previous := app.broadcast()
		app._mic_hold_button = true
		check(previous.hold(true),"reading really starts before "+boundary)
		check(app._mic_panel.visible and app._mic_open,"microphone opens before "+boundary)
		match boundary:
			"load": app.load_game()
			"new": app.start_new_game("hard","none")
			"menu": app.return_to_menu()
		check(not app._mic_panel.visible and not app._mic_open and not app._mic_hold_button and not previous.held,"session boundary releases the previous microphone, panel and reading: "+boundary)
	app.queue_free()
	await _frames(2)


func test_outing_notes() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir()+"/outing-notes/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard","none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	var day := app.school()
	var text := func() -> String:
		var parts := PackedStringArray()
		for child in app.ui._notes_box.get_children():
			if child is Label: parts.append(child.text)
		return "\n".join(parts)
	app._show_notes()
	check(not text.call().contains("外出记录"),"notes omit an outing card when no duty or permanent pursuit exists")
	day.day = 2
	day.tsec = 700
	check(day.grant_outing(true),"real outing registration creates the pending attendance duty")
	var before := day.capture().duplicate(true)
	app._show_notes("没有匹配的记录")
	check(text.call().contains("仍须到教室参加：第 2 天 12:50。许可到期不免除责任；系统取消的检查会顺延。"),"original outing summary remains visible during note search")
	check(same_json(before,day.capture()),"reading the card cannot renew a permit or change a duty")
	day._duty_cancel({"day":2,"slot":0})
	app._show_notes()
	check(text.call().contains("第 2 天 17:50") and not text.call().contains("第 2 天 12:50"),"a system-cancelled inspection shows the rolled-forward obligation")
	day._duty_settle({"day":2,"slot":1},false,false)
	app.patrol().registered_absence("2:1")
	app._show_notes()
	check(text.call().contains("登记后缺席：持续追踪仍生效。假条、重新登记和符纸不能解除。") and not text.call().contains("仍须到教室参加"),"a settled absence shows the original permanent pursuit warning")
	day.tsec = 1100
	day.grant_outing(true)
	app._show_notes()
	check(text.call().contains("第 3 天 12:50") and text.call().contains("持续追踪仍生效"),"new registration retains permanent pursuit and shows tomorrow's attendance")
	app.save_game()
	app.load_game()
	app._show_notes()
	check(text.call().contains("第 3 天 12:50") and text.call().contains("持续追踪仍生效"),"reloading preserves both pieces of live outing information")
	app.return_to_menu()
	app.queue_free()
	await _frames(2)
