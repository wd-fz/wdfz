class_name LegacyState
extends RefCounted
## Translate saved data, never replay gameplay actions. The caller validates the complete
## candidate with every module before installing it. Unmapped source fields remain in an
## inert module payload so a later converter can recover them without running Web code.

var error := ""


func convert(plan: Dictionary, defaults: Dictionary, rooms: Dictionary, campus: Dictionary, maze_geometry: MazeGeometry) -> Dictionary:
	error = ""
	var s: Dictionary = plan["source"]
	_layout(plan, rooms, campus)
	var rt := _object(s.get("rt"), "rt")
	var mods := _object(s.get("mods"), "mods")
	if rt.get("rulesMode") != null:
		return {"error": "这份存档使用规则怪谈 DLC，当前尚不能恢复它的规则；本局没有被替换"}
	var result := defaults.duplicate(true)
	var world: String = plan["world"]
	result["world_id"] = world
	var data: Dictionary = result["modules"]
	var school := _module(data, "school.day")
	_copy(school, plan, {"day":"day", "tsec":"tsec", "san":"san", "viol":"viol", "stam":"stam", "tt":"tt"})
	_copy(school, s, {"tired":"tired", "ttTier":"tt_tier", "exam":"exam", "examCur":"exam_cur", "examSeat":"exam_seat", "examTot":"exam_tot"})
	_copy(school, rt, {"pressureClock":"pressure_clock", "pressureSeen":"pressure_seen", "violFull":"viol_full", "leaveUntil":"leave_until", "inspection":"inspection", "outing":"outing"})
	_inspection(school["inspection"])
	school["pressure_clock"] = maxf(float(school["pressure_clock"]), SchoolClock.continuous(int(plan["day"]), float(plan["tsec"])))
	var duties := _object(mods.get("attendanceDuty"), "attendanceDuty")
	_copy(school["duties"], duties, {"seq":"seq", "duties":"list", "processed":"processed"})
	var mechanics := _object(mods.get("mechanics"), "mechanics")
	var active: Variant = mechanics.get("activePlaySeconds", 0.0)
	if not SaveSchema.number_in(active, 0.0, SaveSchema.MAX_SECONDS):
		error = "旧存档的有效游玩时长无效"
		active = 0.0
	school["active_seconds"] = active
	result["clock"] = {"active_seconds":active, "calendar_seconds":active}
	_pose(result, plan, rooms, campus, school, mods, maze_geometry)
	var inv := _module(data, "items.bag")
	_copy(inv, plan, {"bag":"bag", "hot":"hot"})
	_copy(inv, s, {"pillT":"pill_t", "snackT":"snack_t"})
	_copy(inv, rt, {"deskUsed":"desk_used", "pendingLoot":"pending_loot", "keyMiss":"key_miss", "hwTaken":"hw_taken"})
	var use := _object(s.get("use"), "use")
	inv["torch"] = _flag(use.get("torch", false)) and plan["bag"].has("torch")
	inv["brolly"] = _flag(use.get("brollyShield", false)) and plan["bag"].has("brolly")
	var story := _module(data, "story.death")
	story["diff"] = plan["diff"]
	_copy(story, rt, {"wakes":"wakes"})
	var talent := _module(data, "story.talent")
	talent["id"] = plan["talent"]
	var ts := _object(s.get("talentState"), "talentState")
	_copy(talent, ts, {"consumed":"consumed", "notified":"notified"})
	if ts.is_empty() and _flag(s.get("immuneUsed", false)):
		talent["consumed"]["fatalProtection"] = true
	var doors := _object(s.get("openDoors"), "openDoors")
	_module(data, "campus.world")["open_doors"] = doors.keys().filter(func(k: String) -> bool: return _flag(doors[k]))
	var lift := _module(data, "campus.elevator")
	_copy(lift, rt, {"elevators":"lifts", "elevatorRide":"ride"})
	var crowd := _module(data, "campus.lift_crowd")
	crowd["run"] = _object(mods.get("lift-crowd"), "lift-crowd").get("run",60.0)
	crowd["state"] = _object(rt.get("liftCrowd"), "liftCrowd").duplicate(true)
	if not crowd["state"].is_empty():
		crowd["state"]["said"] = _flag(crowd["state"].get("said",false))
	var fac := _module(data, "campus.facilities")
	_copy(fac, s, {"actCool":"act_cool", "spots":"spots"})
	for pair: Array in [["vialTaken","vial"],["lensTaken","lens"],["coilTaken","coil"],["geoCompass","compass"],["adminDesk","admin_desk"],["labReagent","goggles"],["geoMaps","geo_maps"],["altarCoin","altar_coin"],["guardKeysTold","guard_told"]]:
		if rt.has(pair[0]):
			fac["flags"][pair[1]] = rt[pair[0]]
	_copy(fac["portal"], rt, {"portalDiary":"diary", "portalBlueprints":"blueprints", "portalWork":"work", "portalSketch":"sketch", "portalOpen":"open", "portalReturn":"ret"})
	var route := _module(data, "story.routes")
	_copy(route, rt, {"hacked":"hacked", "beastDrop":"beast_drop", "data":"data", "dataSource":"data_source", "faceQuiz":"face_quiz"})
	_copy(route, s, {"clues":"clues"})
	var garage := _module(data, "garage.world")
	_copy(garage, s, {"roam":"roam"})
	_copy(garage, rt, {"lure":"lure", "carRight":"car_right", "carTried":"car_tried", "carUsed":"car_used", "carChase":"chase"})
	var net := _module(data, "phone.network")
	_copy(net, mechanics, {"runSeed":"run_seed", "attemptId":"attempt_id"})
	_copy(net, mods, {"phoneDevice":"device", "terminalPuzzle":"puzzle", "termination":"termination"})
	if not mods.has("terminalPuzzle"):
		net["puzzle"] = CampusTerminal.fresh(net["run_seed"], int(net["attempt_id"]))
	var patrol := _module(data, "patrol.world")
	_copy(patrol, mods, {"patrolWorld":"pat"})
	var hiding := _object(s.get("hiding"), "hiding")
	if not hiding.is_empty():
		_copy(patrol["hide"], hiding, {"c":"c", "r":"r", "seen":"seen", "t":"t"})
		var row := int(patrol["hide"]["r"])
		var col := int(patrol["hide"]["c"])
		var grid: Array = rooms.get(world, {}).get("grid", [])
		patrol["hide"]["on"] = row >= 0 and row < grid.size() and col >= 0 and col < String(grid[row]).length() and String(grid[row]).substr(col,1) == "H"
	_anomaly(_module(data, "anomaly.world"), s, rt)
	_copy(_module(data, "story.fake_normal"), _object(s.get("fn"), "fn"), {})
	_copy(_module(data, "story.broadcast"), _object(mods.get("broadcast"), "broadcast"), {})
	_copy(_module(data, "school.days"), rt, {"runSeed":"seed", "dayEvents":"day_events", "daySaid":"said", "lessons":"lessons"})
	if not rt.has("dayEvents"):
		_module(data, "school.days")["day_events"][str(plan["day"])] = "none"
	_module(data, "school.classmates")["seed"] = net["run_seed"]
	_copy(_module(data, "body.injury"), _object(rt.get("body"), "body"), {"injury":"injury", "restT":"rest_t", "medDay":"med_day"})
	_copy(_module(data, "story.investigation"), _object(rt.get("investigation"), "investigation"), {})
	_copy(_module(data, "story.atmos"), _object(rt.get("atmos"), "atmos"), {"stares":"stares", "shift":"shift", "shiftPose":"shift_pose", "seats":"seats", "said":"said", "left":"left"})
	_copy(_module(data, "story.dread"), rt, {"visits":"visits"})
	_copy(_module(data, "campus.tales"), rt, {"midnightMeal":"meal", "checkup":"checkup", "patrolNotes":"notes"})
	_copy(_module(data, "phone.camera"), rt, {"photos":"photos", "cameraFlash":"flash"})
	for photo: Variant in _module(data, "phone.camera")["photos"]:
		if photo is Dictionary and photo.get("img") is String:
			photo["img"] = String(photo["img"]).trim_prefix("data:image/jpeg;base64,")
	var marks := _object(mods.get("chalk-marks"), "chalk-marks")
	_copy(_module(data, "campus.marks"), marks, {"serial":"serial", "marks":"marks"})
	_copy(_module(data, "campus.marks"), rt, {"lastLife":"last_life"})
	for mark: Variant in _module(data, "campus.marks")["marks"]:
		if mark is Dictionary:
			mark["room"] = "out" if mark.get("room") == null else mark["room"]
	_copy(_module(data, "story.paper_plane"), _object(rt.get("paper"), "paper"), {"roll":"roll", "used":"used", "calmUntil":"calm_until"})
	_copy(_module(data, "story.window_gaze"), _object(rt.get("windowGaze"), "windowGaze"), {"next":"next", "n":"n", "escaped":"escaped"})
	_copy(_module(data, "story.exchange"), _object(rt.get("exchange"), "exchange"), {})
	_module(data, "story.exchange")["multi"] = _flag(_object(rt.get("multilingual"), "multilingual").get("active", false))
	_exploration(_module(data, "campus.exploration"), _object(rt.get("exploration"), "exploration"), rooms)
	var score := _module(data, "progress.score")
	_copy(score, _object(mods.get("runScore"), "runScore"), {"run":"run", "ledger":"ledger", "minSan":"min_san", "saved":"saved", "wakes":"wakes", "locked":"locked", "rooms":"rooms", "zones":"zones"})
	score["legacy"] = 1
	if score["run"] == "":
		score["run"] = "legacy:" + String(net["run_seed"])
	var achievement := _object(mods.get("achievements"), "achievements")
	var ach := _module(data, "profile.achievements")
	_copy(ach, achievement, {"insp":"insp", "faceWrong":"face_wrong", "saved":"saved", "exams":"exams", "fresh":"run_new"})
	ach["rooms"] = _object(achievement.get("rooms"), "achievements.rooms").keys()
	if _flag(achievement.get("debug", false)) or _flag(achievement.get("mod", false)):
		score["trusted"] = false
	_copy(_module(data, "story.fake_normal"), achievement, {"laughs":"laughs"})
	var maze := _module(data, "campus.maze")
	var old_maze := _object(mods.get("void-maze"), "void-maze")
	_copy(maze, old_maze, {"t":"elapsed", "falls":"falls"})
	maze["told_long"] = _flag(_object(old_maze.get("told"), "void-maze.told").get("long", false))
	maze["active"] = world == "lift_dream"
	# Keep compatibility metadata inert; ModuleHost preserves unknown payloads without executing them.
	data["legacy.web"] = {"version":1, "data":{"source":plan["original"].duplicate(true)}}
	return {"error":error, "snapshot":result}


func _module(data: Dictionary, id: String) -> Dictionary:
	return data[id]["data"]


func _object(value: Variant, path: String) -> Dictionary:
	if value == null:
		return {}
	if value is Dictionary:
		return value
	error = "旧存档字段 %s 应为对象" % path
	return {}


func _flag(value: Variant) -> bool:
	if value is bool:
		return value
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and value != 0


func _layout(plan: Dictionary, rooms: Dictionary, campus: Dictionary) -> void:
	var s: Dictionary = plan["source"]
	if not SaveSchema.is_integer(s.get("layoutVersion", 0), 0, 4):
		error = "不支持的教室布局版本"
		return
	if int(s.get("layoutVersion", 0)) >= 4:
		return
	var own: Dictionary = campus["own_seat"]
	var seat := _object(s.get("seat"), "seat")
	if _flag(s.get("seated", false)) and seat.get("seatId") == "teach1:48:6" and plan["world"] == own["room"] and s.get("hiding") == null:
		for anchor: Dictionary in rooms[own["room"]]["seats"]:
			if anchor["seat_id"] == own["seatId"]:
				plan["x"] = anchor["seated"]["x"]
				plan["y"] = anchor["seated"]["y"]
	var doors := _object(s.get("openDoors"), "openDoors")
	var wall_row := int(campus["classroom_rows"][1]) + 1
	for key: String in doors.keys():
		var parts := key.split(":")
		if parts.size()!=3 or not rooms.has(parts[0]) or not parts[0].begins_with("teach") or not parts[1].is_valid_int() or int(parts[2]) != wall_row:
			continue
		var row: String = rooms[parts[0]]["grid"][wall_row]
		var col := int(parts[1])
		if col>=0 and col<row.length() and row[col]=="=":
			continue
		doors.erase(key)
		var best := -1
		for c in row.length():
			if row[c]=="=" and (best<0 or absi(c-col)<absi(best-col)):
				best=c
		if best>=0 and absi(best-col)<=6:
			doors["%s:%d:%d" % [parts[0],best,wall_row]]=true


func _inspection(st: Dictionary) -> void:
	_copy(st, st.duplicate(true), {"calmRoom":"calm_room"})
	var current := _object(st.get("current"), "inspection.current")
	if current.is_empty():
		return
	var points: Array = []
	if not current.get("points", []) is Array:
		error = "检查人影的位置无效"
		return
	for p: Variant in current.get("points", []):
		if p is Dictionary and LegacySave._num(p.get("x")) and LegacySave._num(p.get("y")):
			points.append([p["x"],p["y"]])
		else:
			error = "检查人影的位置无效"
	current["points"] = points
	for key: String in ["compliant", "excused"]:
		if current.has(key):
			current[key] = _flag(current[key])


func _copy(target: Dictionary, source: Dictionary, names: Dictionary) -> void:
	var fields := names
	if fields.is_empty():
		fields = {}
		for key: String in target:
			fields[key] = key
	for key: String in fields:
		if source.has(key) and source[key] != null:
			var to: String = fields[key]
			target[to] = _merge(source[key], target.get(to), key)


func _merge(value: Variant, base: Variant, path: String) -> Variant:
	if value == null:
		return base.duplicate(true) if base is Dictionary or base is Array else base
	if base == null:
		return value.duplicate(true) if value is Dictionary or value is Array else value
	if base is bool:
		if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
			return _flag(value)
	elif typeof(base) in [TYPE_INT, TYPE_FLOAT]:
		if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			return value
	elif base is Dictionary and value is Dictionary:
		var out: Dictionary = base.duplicate(true)
		for key: String in value:
			out[key] = _merge(value[key], base.get(key), path+"."+key)
		return out
	elif typeof(base) == typeof(value):
		return value.duplicate(true) if value is Array else value
	error = "旧存档字段 %s 类型无效" % path
	return base


func _pose(result: Dictionary, plan: Dictionary, rooms: Dictionary, campus: Dictionary, school: Dictionary, mods: Dictionary, geometry: MazeGeometry) -> void:
	var s: Dictionary = plan["source"]
	var world: String = plan["world"]
	var room: Variant = rooms.get(world)
	var at := Vector2(plan["x"], plan["y"])
	var point := CampusGeometry.to_scene(room, at)
	var height := 0.0
	var stair := _object(s.get("stairwell"), "stairwell")
	if stair.get("id") == world and SaveSchema.number_in(stair.get("height"), 0, 30):
		height = float(stair["height"])
	var stair_cfg := CampusPortals.stair_config(campus["stair_layout"], world)
	if not stair_cfg.is_empty():
		var surfaces := CampusPortals.stair_surfaces(stair_cfg["rooms"].size(), float(stair_cfg["rise"]))
		var surface := CampusPortals.surface_at(surfaces, point.x, point.y, height, .4)
		if surface.is_empty():
			point = Vector2(0,-1.8)
			height = 0.0
		else:
			height = float(surface["h"])
	var spiral := _object(s.get("spiral"), "spiral")
	if world == "bell1" and not spiral.is_empty():
		var cfg: Dictionary = campus["spiral"]
		if spiral.get("state") == "top":
			height = float(cfg["topH"])
		elif spiral.get("state") == "stair" and SaveSchema.number_in(spiral.get("a"), float(cfg["enter"][0]), float(cfg["amax"])):
			height = maxf(0.0,float(spiral["a"]))/TAU*float(cfg["turnH"])
	var maze := _object(mods.get("void-maze"), "void-maze")
	if world == "lift_dream" and SaveSchema.number_in(maze.get("fy", 0), -32, 40):
		height = float(maze.get("fy", 0))
		var ground := geometry.ground_at(point.x, point.y, height + float(geometry.cfg["step"]))
		if is_finite(ground) and absf(ground-height) <= float(geometry.cfg["snap"]) and geometry.depth_at(point.x,point.y,float(campus["PRAD"])*CampusGeometry.U2M,ground) == 0.0:
			height = ground
		else:
			var spawn: Dictionary = geometry.cfg["spawn"]
			point = Vector2((float(spawn["x0"])+float(spawn["x1"]))/2,(float(spawn["z0"])+float(spawn["z1"]))/2)
			height = float(spawn["h"])
	result["player"] = {"position":[point.x,height+.01,point.y], "yaw":CampusGeometry.yaw_from_ang(float(plan["ang"])), "pitch":plan["pitch"]}
	if _flag(s.get("seated", false)) and room != null:
		for seat: Dictionary in room.get("seats", []):
			if at.distance_to(Vector2(seat["seated"]["x"],seat["seated"]["y"])) <= 1.5:
				school["seated"] = true
				school["seat_id"] = seat["seat_id"]
				break


func _anomaly(target: Dictionary, s: Dictionary, rt: Dictionary) -> void:
	_copy(target["an"], s, {"anId":"id", "anT":"t", "anAcc":"acc", "anNext":"next", "anData":"data", "anRained":"rained", "anCool":"cool", "anLastBig":"lastBig", "anPre":"pre", "anPreNext":"preNext", "anLocked":"locked", "anLockWait":"lockWait"})
	var an: Dictionary = target["an"]
	an["active"] = an["id"] != ""
	var d: Dictionary = an["data"]
	if an["active"] and _flag(d.get("asked", false)) and d.get("chosen") == null and an["id"] in ["turn", "hand", "repeat", "cold"]:
		d["asked"] = false
		if SaveSchema.number_in(s.get("anChoiceMs"), 0, 1000000):
			d["choiceRemaining"] = s["anChoiceMs"]
	if an["id"] == "roster" and SaveSchema.number_in(s.get("anChoiceMs"), 0, 1000000):
		d["choiceRemaining"] = s["anChoiceMs"]
	_copy(target, rt, {"anHist":"hist", "anSeen":"seen", "preTold":"pre_told", "colaPending":"cola_pending", "colaSeq":"cola_seq", "colaDone":"cola_done", "colaWait":"cola_wait", "traces":"traces"})
	_copy(target, s, {"clues":"clues"})


func _exploration(target: Dictionary, source: Dictionary, rooms: Dictionary) -> void:
	var seen := {}
	for id: String in source:
		if not rooms.has(id):
			continue
		if source[id] is String:
			seen[id] = source[id]
		elif source[id] is Dictionary:
			var room: Dictionary = rooms[id]
			var bits := PackedByteArray()
			bits.resize(int(room["cols"])*int(room["rows"]))
			for key: String in source[id]:
				var xy := key.split(":")
				if xy.size() == 2 and xy[0].is_valid_int() and xy[1].is_valid_int():
					var x := int(xy[0])
					var y := int(xy[1])
					if x >= 0 and x < int(room["cols"]) and y >= 0 and y < int(room["rows"]):
						bits[y*int(room["cols"])+x] = 1
			seen[id] = ExplorationModule.pack(bits)
		else:
			error = "旧存档楼层草图格式无效"
	target["seen"] = seen
