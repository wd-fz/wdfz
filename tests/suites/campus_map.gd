extends "res://tests/support/test_suite.gd"

func test_original_draw() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/map-reference.json.gz")
	var source: Dictionary = JSON.parse_string(bytes.decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var data := CampusData.campus_map()
	for sample: Dictionary in source["samples"]:
		var sc := float(sample["extent"][0])/(float(data["bound"]["x1"])-float(data["bound"]["x0"]))
		var roads := MapView.road_rects(data,sc)
		check(not roads.is_empty(),"original campus roads are present")
		for i in roads.size():
			var expected: Array = sample["rects"][i]["rect"]
			check(roads[i].is_equal_approx(Rect2(expected[0],expected[1],expected[2],expected[3])),"road drawing follows original canvas rectangle %d" % i)
		var widths := {}
		for label: Dictionary in sample["labels"]:
			widths[label["text"]+":"+String(label["font"]).get_slice("px",0)] = label["width"]
		var measure := func(text: String,font_size: int) -> float: return widths.get(text+":"+str(font_size),0)
		var labels := MapView.plan_labels(data,sc,Vector2(sample["size"][0],sample["size"][1]),measure)
		check(labels.size()==sample["labels"].size(),"all building and gate labels are retained")
		for i in labels.size():
			var ref: Dictionary = sample["labels"][i]
			check(labels[i]["text"]==ref["text"] and (labels[i]["pos"] as Vector2).distance_to(Vector2(ref["x"],ref["y"]))<.0001,"original label placement, building avoidance and gate reservation: "+String(ref["text"]))

func test_layout() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	var old_size := root.size
	var old_scale := root.content_scale_size
	var options := [["campus","校园总图"],["teach1","教学楼一层　· 你在这里"],["exp5","实验楼五层　· 你在这里"]]
	var plan := CampusData.campus_map().duplicate()
	plan["me"] = Vector2(510,990)
	plan["ang"] = .6
	var room: Dictionary = CampusData.rules().room("teach1")
	var bits := PackedByteArray()
	bits.resize(int(room["cols"])*int(room["rows"]))
	bits.fill(1)
	for screen: Vector2i in [Vector2i(960,540),Vector2i(640,360),Vector2i(420,900),Vector2i(320,640)]:
		root.size = screen
		await _frames(3)
		for scale: int in [85,100,150]:
			ui.apply_text_scale(scale)
			var view := ui.open_map(options,"campus","走过 5 处室内","")
			view.show_plan(plan)
			await _frames(8)
			check(absf(view.get_global_rect().get_center().x-ui._map_scroll.get_global_rect().get_center().x)<8,"narrow campus canvas stays centred in its scrolling frame")
			check(root.get_visible_rect().encloses(ui.map_panel.get_global_rect()),"campus map fits %s / %d" % [screen,scale])
			ui.open_map(options,"teach1","教学楼一层　北 ↑　你在这一层　已看清 100%","空白处还没看到过。桌、柜、架等字表示看到过，不代表搜过。\n梯 楼梯　电 电梯　廊 连廊　出 出口　锁 门锁着　✓ 已解决　留 有东西没拿　× 钥匙不匹配")
			view.show_floor(room,bits,Callable(),Vector2(room["ox"]+48.8*room["tw"],room["oy"]+11.39*room["th"]),0,true)
			await _frames(8)
			check(root.get_visible_rect().encloses(ui.map_panel.get_global_rect()) and root.get_visible_rect().encloses(ui._map_close_button.get_global_rect()),"floor map, long legend and close fit %s / %d" % [screen,scale])
			if screen.x<screen.y:
				check(ui._map_scroll.scroll_horizontal>0 and 48.8*view.cell-ui._map_scroll.scroll_horizontal<ui._map_scroll.size.x,"opening the floor map centres the current player instead of unseen empty cells")
				check(view.size.x>ui._map_scroll.size.x and ui._map_scroll.get_h_scroll_bar().visible,"wide floor remains horizontally scrollable at readable cell sizes")
			await _tap(ui._map_close_button)
			check(not ui.map_panel.visible,"map close accepts a real screen touch")
	ui.open_map(options,"teach1","教学楼","")
	ui.map_view.show_floor(room,bits,Callable(),Vector2.ZERO,0,true)
	ui.set_mode("menu")
	await _frames(3)
	check(not ui.map_panel.visible,"returning to the menu cancels the open map and its deferred centring")
	ui.queue_free()
	await _frames(2)
	root.size = old_size
	root.content_scale_size = old_scale
