extends "res://tests/support/test_suite.gd"

func test_original_draw() -> void:
	check(MapView.landmark_note("保安岗", Vector2(0, -250), true).contains("北侧"), "north on the campus plan is smaller Y")
	check(MapView.landmark_note("西小门", Vector2.ZERO, false, "向校外跨过白线").contains("就在附近。向校外跨过白线"), "at the marked exit the map names the remaining physical action")
	check(MapView.landmark_note("保安岗", Vector2.INF, true, "找柜台上的底联") == "保安岗 · 找柜台上的底联", "an unmapped room still names the destination without inventing a bearing")
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/map-reference.json.gz")
	var source: Dictionary = JSON.parse_string(bytes.decompress_dynamic(4*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	var data: Dictionary = source["content"]
	# The legacy canvas only labels buildings. The current plan also names plazas, gardens and bridges.
	for object: Dictionary in data.objects:
		if object.k != "roof": object.k = "open"
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

func test_campus_placement() -> void:
	var plan := CampusData.campus_map()
	var bounds := MapView.aerial_bounds(plan)
	var pixels := MapView.AERIAL.get_size()
	check(absf(pixels.x / pixels.y - bounds.size.x / bounds.size.y) < .002, "the north-up photo fills the exact campus coordinate bounds")
	var objects := {}
	var buildings: Array[Rect2] = []
	for object: Dictionary in plan.objects:
		var plot := Rect2(object.x, object.y, object.w, object.h)
		objects[object.id] = plot
		if object.k == "roof":
			check(not buildings.any(func(other: Rect2) -> bool: return plot.intersects(other)), String(object.id) + " does not overlap another building")
			buildings.append(plot)
	var admin: Rect2 = objects.admin
	var lab: Rect2 = objects.lab
	var teach: Rect2 = objects.teach
	var plaza: Rect2 = objects.plaza
	var garden: Rect2 = objects.garden
	check(admin.end.y < lab.position.y and lab.position.x > admin.position.x, "the lab is southeast of the administration building")
	check(is_equal_approx(lab.end.x, teach.end.x) and teach.position.x < lab.position.x, "the wider teaching building extends west of the lab")
	check(plaza.position.y > lab.end.y and plaza.end.y < teach.position.y and plaza.end.x < (objects.c2 as Rect2).position.x, "the green plaza opens between the teaching wings west of the Orange Walk")
	check(garden.position.y > admin.end.y and garden.end.y < lab.position.y, "the geography garden is between the lab and administration building")
	var dining: Rect2 = objects.canteen
	var north: Rect2 = objects.dormN
	var south: Rect2 = objects.dormS
	check(dining.position.x > north.end.x and dining.position.x > south.end.x
		and dining.get_center().y > north.end.y and dining.get_center().y < south.position.y, "the dining hall closes the east side of the dorm courtyard and opens between the wings")
	var labels := MapView.plan_labels(plan, .52, Vector2(327.6, 676.52), func(label: String, size: int) -> float: return label.length() * size)
	for title: String in ["空中连廊", "橙色之路", "绿色广场", "地理园"]:
		check(labels.any(func(label: Dictionary) -> bool: return label.text == title), "the current map labels " + title)

func test_layout() -> void:
	var ui: GameUI = preload("res://game/presentation/ui/game_ui.tscn").instantiate()
	root.add_child(ui)
	await _frames(3)
	ui.set_mode("play")
	var old_size := root.size
	var old_scale := root.content_scale_size
	var options := [["campus","校园总图"],["teach1","教学楼一层　· 你在这里"],["exp5","实验楼五层　· 你在这里"]]
	var routes := [["identity", "离校回执"], ["car", "车辆"], ["dismissal", "放学广播"]]
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
			var view := ui.open_map(options,"campus","你在保安岗　北 ↑","可跟进离校回执、车辆、放学广播。",routes)
			view.show_plan(plan)
			await _frames(8)
			check(absf(view.get_global_rect().get_center().x-ui._map_scroll.get_global_rect().get_center().x)<8,"narrow campus canvas stays centred in its scrolling frame")
			check(root.get_visible_rect().encloses(ui.map_panel.get_global_rect()),"campus map fits %s / %d" % [screen,scale])
			check(ui._map_route_select.visible and ui._map_route_select.item_count == 4 and ui._map_route_select.selected == 0, "the campus plan offers all known leads without choosing an exit")
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
