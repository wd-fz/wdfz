class_name CooperativeValidation
extends RefCounted
## Validate a complete candidate before changing any active cooperative session.


static func validate(data: Dictionary) -> String:
	if not LanProtocol.safe(data) or data.get("format") != "wdfz-godot-coop" or data.get("version") != 1: return "合作存档格式不兼容。"
	for key: String in ["room", "calendar", "actors", "items", "patrol", "gameplay", "leases"]:
		if not data.get(key) is Dictionary: return "合作存档缺少 " + key
	var room: Dictionary = data["room"]
	var actors: Dictionary = data["actors"]
	if not room.get("members") is Dictionary or actors.size() < 2 or actors.size() > 4 or actors.size() != room["members"].size() or not actors.has(room.get("host")): return "合作成员表无效。"
	if room.get("difficulty") not in StoryModule.DIFFICULTIES or not room.get("epoch") is String: return "合作规则无效。"
	if room.get("phase") not in ["loading", "playing", "ended"] or not SaveSchema.is_integer(room.get("capacity"), 2, 4): return "合作房间阶段无效。"
	var calendar: Dictionary = data["calendar"]
	if not SaveSchema.number_in(calendar.get("tsec"), 0, 1500) or not SaveSchema.is_integer(calendar.get("day"), 1, 100000) or not SaveSchema.number_in(calendar.get("seconds"), 0, SaveSchema.MAX_SECONDS): return "合作日历无效。"
	var seats := {}
	var candidate := SessionFactory.create()
	var known := PackedStringArray(CampusData.rooms().keys())
	known.append("out")
	var common := {}
	for id: String in actors:
		var actor_data: Variant = actors[id]
		var member: Variant = room["members"].get(id)
		if not actor_data is Dictionary or not member is Dictionary or not member.get("name") is String or not member.get("connected") is bool or (member.get("talent") != "none" and not TalentModule.DEF.has(member.get("talent"))): return "合作成员资料无效。"
		if not actor_data.get("session") is Dictionary or not actor_data.get("life") is Dictionary or not actor_data.get("seat") is String: return "合作角色状态无效。"
		if member.get("state") not in ["loading", "alive", "dead", "departed"] or not SaveSchema.number_in(member.get("remaining"), 0, CooperativeRoom.RESERVATION_SECONDS): return "合作成员阶段无效。"
		for key: String in ["choice", "search", "runtime"]:
			if not actor_data.get(key) is Dictionary: return "合作角色缺少 " + key
		if not actor_data.get("events") is Array or actor_data["events"].size() > 64 or not actor_data.get("pending") is Array or actor_data["pending"].size() > 32 or not actor_data.get("terminal") is bool or not actor_data.get("vehicle") is bool: return "合作操作状态无效。"
		for key: String in ["ended", "fx", "msg", "source"]:
			if not actor_data["life"].get(key) is String: return "合作生死资料无效。"
		var seat := String(actor_data["seat"])
		if seats.has(seat) or not (candidate.modules.get_module(&"school.day") as SchoolModule).assign_own_seat(seat): return "合作座位重复或无效。"
		seats[seat] = true
		var error := candidate.validate(actor_data["session"], known)
		if not error.is_empty(): return "合作角色校验失败：" + error
		if not SaveSchema.is_integer(actor_data.get("scene"), 1, 2147483646) or not actor_data["life"].get("dead") is bool or not actor_data["life"].get("wake") is bool or not SaveSchema.number_in(actor_data["life"].get("elapsed"), 0, SaveSchema.MAX_SECONDS): return "合作生死状态无效。"
		var extra_error := _runtime(actor_data)
		if extra_error != "": return extra_error
		for key: StringName in CooperativeFactory.SHARED:
			var value: Variant = actor_data["session"]["modules"].get(String(key))
			var normalized := JSON.stringify(value)
			if common.has(key) and common[key] != normalized: return "共享世界在不同成员中不一致。"
			common[key] = normalized
	var inventory: Dictionary = data["items"]
	if not inventory.get("stash") is Array or inventory["stash"].size() > 32 or not inventory.get("ground") is Array or not inventory.get("owners") is Dictionary or not inventory.get("containers") is Dictionary or not inventory.get("searches") is Dictionary: return "合作物品表无效。"
	var item_ids := {}
	if not SaveSchema.is_integer(inventory.get("serial"), 0, 2147483647) or not SaveSchema.is_integer(inventory.get("revision"), 0, 2147483647): return "合作物品版本无效。"
	var item_types: Dictionary = CampusData.campus()["items"]
	if not InventoryModule._validate_ground(inventory["ground"], item_types).is_empty(): return "合作地面物品无效。"
	if not InventoryModule._validate_ground(inventory["stash"], item_types).is_empty(): return "合作保管物品无效。"
	for entry: Dictionary in inventory["ground"] + inventory["stash"]:
		if not entry.get("uid") is String or item_ids.has(entry["uid"]): return "合作物品编号重复。"
		item_ids[entry["uid"]] = true
	for id: String in actors:
		var ownership: Variant = inventory["owners"].get(id)
		if not ownership is Dictionary: return "缺少个人物品归属。"
		var bag: Array = actors[id]["session"]["modules"]["items.bag"]["data"]["bag"]
		if ownership.size() != bag.size(): return "背包与物品归属不一致。"
		for item: String in bag:
			var uid: Variant = ownership.get(item)
			if not uid is String or item_ids.has(uid): return "同一物品存在多个所有者。"
			item_ids[uid] = true
	for uid: String in item_ids:
		if not uid.begins_with("item-") or not uid.trim_prefix("item-").is_valid_int() or int(uid.trim_prefix("item-")) < 1 or int(uid.trim_prefix("item-")) > int(inventory["serial"]): return "合作物品序列无效。"
	for key: String in ["desk_used", "pending_loot"]:
		if not inventory["containers"].get(key) is Dictionary: return "合作容器无效。"
	if not SaveSchema.is_integer(inventory["containers"].get("key_miss"), 0, 1000000) or not inventory["containers"].get("hw_taken") is bool: return "合作容器抽取无效。"
	for key: String in ["rng_seed", "rng_state"]:
		if not inventory["containers"].get(key) is String or not String(inventory["containers"][key]).is_valid_int(): return "合作随机序列无效。"
	var watcher := CampusData.make_patrol()
	if not data["patrol"].get("patrol") is Dictionary or not watcher.validate(data["patrol"]["patrol"]).is_empty(): return "合作巡察状态无效。"
	if not data["patrol"].get("target") is String or (data["patrol"]["target"] != "" and not actors.has(data["patrol"]["target"])): return "合作巡察目标无效。"
	if not data["patrol"].get("reports") is Array or data["patrol"]["reports"].size() > 16 or not data["patrol"].get("permanent") is Dictionary: return "合作目击证据无效。"
	for key: String in ["regions", "lockers"]:
		if not data["patrol"].get(key) is Dictionary: return "合作巡察个人状态无效。"
	for report: Variant in data["patrol"]["reports"]:
		if not report is Dictionary or not actors.has(report.get("member")) or not report.get("signal") is Dictionary or not report["signal"].get("point") is Dictionary: return "合作报点目标无效。"
		if not SaveSchema.number_in(report["signal"].get("remaining"), 0, 30): return "合作报点时限无效。"
		var point: Dictionary = report["signal"]["point"]
		if not point.get("scene") in known or not SaveSchema.number_in(point.get("x"), -100000, 100000) or not SaveSchema.number_in(point.get("y"), -100000, 100000): return "合作报点位置无效。"
	for key: String in inventory["searches"]:
		if not actors.has(inventory["searches"][key]): return "合作容器操作者不存在。"
	for key: String in data["leases"]:
		if not actors.has(data["leases"][key]): return "合作占用者不存在。"
	if not SaveSchema.number_in(room.get("paused"), 0, CooperativeRoom.PAUSE_SECONDS) or not room.get("debug") is bool or not room.get("offer") is Dictionary: return "合作暂停或结算状态无效。"
	if not room["offer"].is_empty():
		if room["offer"].get("route") not in CooperativeRoom.ENDINGS or not _people(room["offer"].get("members"), actors) or not _people(room["offer"].get("confirmed"), actors): return "合作结算确认无效。"
	return _gameplay(data["gameplay"], actors)


static func _runtime(a: Dictionary) -> String:
	for key: String in a["runtime"]:
		if not CooperativeActor.RUNTIME_FIELDS.has(key) or not a["runtime"][key] is Dictionary: return "合作附加状态模块无效。"
		for property: String in a["runtime"][key]:
			if property not in CooperativeActor.RUNTIME_FIELDS[key]: return "合作附加状态字段无效。"
			var value: Variant = a["runtime"][key][property]
			if property == "lesson_key":
				if not value is String: return "课堂任务编号无效。"
			elif value != null and not value is Dictionary: return "合作进行中的操作无效。"
	var phone: Variant = a["runtime"].get("phone.network", {}).get("connection")
	if phone != null and (not phone is Dictionary or not SaveSchema.number_in(phone.get("x"), -100000, 100000) or not SaveSchema.number_in(phone.get("y"), -100000, 100000)): return "手机连接位置无效。"
	var body: Dictionary = a["runtime"].get("body.injury", {})
	if body.get("treat") != null and (not body["treat"] is Dictionary or not SaveSchema.number_in(body["treat"].get("t"), 0, 60)): return "治疗进度无效。"
	if body.get("fall") != null:
		var fall: Dictionary = body["fall"]
		if not fall.get("kind") is String or not CampusData.rooms().has(fall.get("room")) or not SaveSchema.is_integer(fall.get("side"), -1, 1) or not SaveSchema.number_in(fall.get("t"), 0, 60) or not fall.get("from") is Dictionary: return "翻越状态无效。"
		for key: String in ["x", "y", "ang"]:
			if not SaveSchema.number_in(fall["from"].get(key), -100000, 100000): return "翻越起点无效。"
	var lesson := String(a["runtime"].get("school.days", {}).get("lesson_key", ""))
	if not lesson.is_empty() and not a["session"]["modules"]["school.days"]["data"]["lessons"].has(lesson): return "课堂任务不存在。"
	var job: Dictionary = a["search"]
	if not job.is_empty():
		if not CampusData.rooms().has(job.get("room")) or not SaveSchema.is_integer(job.get("c"), 0, 1000) or not SaveSchema.is_integer(job.get("r"), 0, 1000) or not SaveSchema.number_in(job.get("t"), 0, InventoryModule.SEARCH_SECONDS) or not SaveSchema.number_in(job.get("x"), -100000, 100000) or not SaveSchema.number_in(job.get("y"), -100000, 100000): return "搜索进度无效。"
	var choice: Dictionary = a["choice"]
	if not choice.is_empty():
		if choice.get("source") != "lift" and not CooperativeGameplay.SOURCES.has(choice.get("source")): return "选择来源无效。"
		if not choice.get("text") is String or not choice.get("labels") is Array or choice["labels"].size() > 40 or not SaveSchema.is_integer(choice.get("id"), 0, 2147483647): return "选择内容无效。"
		for label: Variant in choice["labels"]:
			if not label is String: return "选择文本无效。"
	if choice.has("remaining") and not SaveSchema.number_in(choice["remaining"], 0, 120): return "选择倒计时无效。"
	for event: Variant in a["events"]:
		if not event is Dictionary or not event.get("kind") is String or not SaveSchema.is_integer(event.get("seq"), 1, 2147483647): return "合作事件无效。"
	for pending: Variant in a["pending"]:
		if not pending is Dictionary or pending.get("kind") != "portal_ask" or not CampusData.rooms().has(pending.get("world")) or not SaveSchema.number_in(pending.get("left"), 0, 60): return "合作延时操作无效。"
	return ""


static func _gameplay(g: Dictionary, actors: Dictionary) -> String:
	for key: String in ["lifts", "lift_engines", "lift_owners", "lift_riders", "radio_job", "pending", "time_offer", "extra"]:
		if not g.get(key) is Dictionary: return "合作玩法状态缺少 " + key
	for key: String in ["driver", "termination_owner", "anomaly_owner"]:
		if not g.get(key) is String or (g[key] != "" and not actors.has(g[key])): return "合作任务负责人无效。"
	for key: String in ["passengers", "anomaly_participants"]:
		if not g.get(key) is Array or g[key].size() > 4: return "合作参与名单无效。"
		for id: Variant in g[key]:
			if not actors.has(id): return "合作参与者不存在。"
	if not SaveSchema.is_integer(g.get("anomaly_round"), 0, 2147483647): return "合作异象序列无效。"
	var lift := ElevatorModule.new(CampusData.rooms())
	for host: String in ElevatorModule.HOSTS:
		if not g["lift_engines"].get(host) is Dictionary or not lift.validate(g["lift_engines"][host]).is_empty(): return "合作电梯无效。"
	var extra: Dictionary = g["extra"]
	for key: String in ["radio", "qualified", "boarding", "escort_lag", "escort_lost"]:
		if not extra.get(key) is Dictionary: return "合作路线状态缺少 " + key
	if not extra["radio"].get("held") is bool or not SaveSchema.number_in(extra["radio"].get("progress"), 0, 60): return "广播进度无效。"
	if extra["radio"].get("origin") != null:
		var origin: Variant = extra["radio"]["origin"]
		if not origin is Dictionary or not SaveSchema.number_in(origin.get("x"), -100000, 100000) or not SaveSchema.number_in(origin.get("y"), -100000, 100000) or not SaveSchema.is_integer(origin.get("day"), 1, 100000): return "广播起点无效。"
	var job: Variant = extra.get("garage_job")
	if job != null:
		if not job is Dictionary or not job.get("cell") is String or not job.get("wire") is bool: return "车辆操作无效。"
		for key: String in ["x", "y", "t", "dur"]:
			if not SaveSchema.number_in(job.get(key), 0, 100000): return "车辆操作进度无效。"
	var board: Dictionary = extra["boarding"]
	if not board.is_empty():
		if not actors.has(board.get("driver")) or not _people(board.get("members"), actors) or not _people(board.get("confirmed"), actors) or not SaveSchema.number_in(board.get("expires"), 0, SaveSchema.MAX_SECONDS): return "上车确认无效。"
	var qualified: Dictionary = extra["qualified"]
	if not qualified.is_empty():
		if not actors.has(qualified.get("owner")) or qualified.get("route") not in CooperativeRoom.ENDINGS or not _world(qualified.get("world")) or not SaveSchema.number_in(qualified.get("x"), -100000, 100000) or not SaveSchema.number_in(qualified.get("y"), -100000, 100000): return "共同结局条件无效。"
	for id: Variant in extra["escort_lag"]:
		if not actors.has(id) or not SaveSchema.number_in(extra["escort_lag"][id], 0, SaveSchema.MAX_SECONDS): return "队伍跟随时间无效。"
	for id: Variant in extra["escort_lost"]:
		if not actors.has(id) or not extra["escort_lost"][id] is bool: return "队伍跟随状态无效。"
	for host: String in g["lift_owners"]:
		if host not in ElevatorModule.HOSTS or not actors.has(g["lift_owners"][host]): return "电梯操作者无效。"
	for host: String in g["lift_riders"]:
		if host not in ElevatorModule.HOSTS or not _people(g["lift_riders"][host], actors): return "电梯乘客无效。"
	var radio_job: Dictionary = g["radio_job"]
	if not radio_job.is_empty():
		if not actors.has(radio_job.get("owner")) or not SaveSchema.is_integer(radio_job.get("index"), 0, 20) or not SaveSchema.number_in(radio_job.get("left"), 0, 120) or not _world(radio_job.get("world")) or not _pose(radio_job.get("pose")): return "广播工作进度无效。"
	for key: String in g["pending"]:
		if StringName(key) not in CooperativeFactory.SHARED or not g["pending"][key] is Dictionary: return "共享操作来源无效。"
	var offer: Dictionary = g["time_offer"]
	if offer.is_empty(): return ""
	if not actors.has(offer.get("owner")) or not SaveSchema.is_integer(offer.get("scene"), 1, 2147483647) or not _vector(offer.get("position")) or not SaveSchema.number_in(offer.get("minutes"), 0, 180) or not SaveSchema.number_in(offer.get("expires"), 0, SaveSchema.MAX_SECONDS) or not _people(offer.get("confirmed"), actors) or not offer.get("operation") is Dictionary or not offer.get("id") is String: return "全队等待确认无效。"
	var operation: Dictionary = offer["operation"]
	if operation.is_empty(): return ""
	match String(operation.get("kind", "")):
		"rest":
			if not FacilitiesModule.SAN_ACTS.has(operation.get("key")): return "等待活动无效。"
		"facility":
			var value: Variant = operation.get("value")
			if not value is Array or value.size() != 3 or value[0] not in ["Z", "C"] or not SaveSchema.is_integer(value[1], 0, 1000) or not SaveSchema.is_integer(value[2], 0, 1000): return "等待设施无效。"
		"lesson":
			if not operation.get("key") is String: return "等待课堂无效。"
		"meal", "supply": pass
		_: return "等待操作无效。"
	return ""


static func _people(value: Variant, actors: Dictionary) -> bool:
	if not value is Array or value.size() > 4: return false
	var seen := {}
	for id: Variant in value:
		if not id is String or not actors.has(id) or seen.has(id): return false
		seen[id] = true
	return true


static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for number: Variant in value:
		if not SaveSchema.number_in(number, -100000, 100000): return false
	return true


static func _pose(value: Variant) -> bool:
	return value is Dictionary and _vector(value.get("position")) and SaveSchema.number_in(value.get("yaw"), -TAU, TAU) and SaveSchema.number_in(value.get("pitch"), -PI, PI)


static func _world(value: Variant) -> bool:
	return value is String and (value == "out" or CampusData.rooms().has(value))
