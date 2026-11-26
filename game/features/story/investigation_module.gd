class_name InvestigationModule
extends FeatureModule
## The investigation notebook, ported from the Web version (reference wd-fz.github.io@0bf508a,
## investigation.js): what the player found out, written only by real interactions, reread from the
## handbook's notes page. Records have a kind (事实 / 推测 / 验证 / 线索), the place and the day they
## were found; the most recent eight are remembered; the "current investigation" card names the goal of
## the route that reader follows. Published notices, items and interactions reveal routes. The module
## also owns the three flows that start the first route: the parking ticket in the own desk (R),
## the handover note on the own classroom's podium and the temporary supply box.
## Events out: say {text}, choice {text, labels}, save, outing, chalk, spots {names}, supply {pay},
## continue (the supply choice was declined: go on with the facility), record is silent.

const DESK_RECORDS := {
	"desk": "名牌底下压着点名联。我认出了姓名栏里蹭花的墨点——刚才那张试卷上，我就在这里停过笔。纸背写着，底联在北门旁的保安岗，讲台上还有钥匙移交单。",
	"landing:knock": "喇叭里响了三下球鞋声，接着是开门声。隔了四秒，又是同样的三下，连鞋底打滑的位置都相同。",
	"landing:star": "标签背面写着「西梯二楼，实地采录」。录音的日期比今天早了好几年。我取下耳朵旁边的听筒，楼下静悄悄的。",
}
const STATE_VERSION := 1
const KINDS := ["事实", "推测", "验证", "线索", "规则"]
const RECENT_MAX := 8
const PAPER_TRIAL_SOURCE := "保安岗 · 17 号工单观察联"
const PAPER_TRIAL_NOTE := "安抄派智能，17 号工单。纸袋里装着半圆形纸屑，旁边订着值班员的手记。\n「试员在模型里给甲纸打孔。我在现实的岗亭看着玻璃盒，甲纸右边掉了一小片，乙纸四边还齐。封条是我亲手拆的。现把纸屑附上。」"
const BROADCAST_NOTE := "行政楼二楼广播站。放学通知被撕成四页，蓝黑墨水、日期「第二天」。第二天起，第八节下课后至熄灯前播出。教导处文件柜、琴凳、保安岗登记簿、天台喇叭箱各有一页。\n「全体」底下有人划了一道线，旁边写着「终止当前的点名循环」。背页是一次试播的记录：「听到长铃后，主时钟与广播同时停止，出口指示灯亮起。」"

var entries: Dictionary = {}   # id → {text, kind, source, day}
var recent: Array = []
var focus := ""
var pins: Dictionary = {}
var supply: Dictionary = {}    # {site: "guard1" | "canteen1", taken: bool}
var events: Array = []

var _c: Dictionary = {}
var _pending: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func module_id() -> StringName:
	return &"story.investigation"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	entries = {}
	recent = []
	focus = ""
	pins = {}
	supply = {}
	events = []
	_pending = {}


func capture() -> Dictionary:
	return {"random": RandomState.capture(_rng), "entries": entries.duplicate(true), "recent": recent.duplicate(), "focus": focus, "pins": pins.duplicate(), "supply": supply.duplicate()}


func validate(data: Dictionary) -> String:
	if not (data.get("entries", {}) is Dictionary) or not (data.get("recent", []) is Array) or not (data.get("supply", {}) is Dictionary):
		return "调查笔记无效"
	var notes: Dictionary = data.get("entries", {})
	if notes.has("paper:lesson:A") and notes.has("paper:lesson:B"): return "同一根打孔杆有两次落锁记录"
	if not data.get("pins", {}) is Dictionary: return "调查路线无效"
	for reader: Variant in data.get("pins", {}):
		if not reader is String or data["pins"][reader] not in ["identity", "car", "face", "portal", "cyber", "dismissal", "international"]: return "调查路线无效"
	for v: Variant in (data.get("entries", {}) as Dictionary).values():
		if not (v is Dictionary) or not (v.get("text") is String) or not KINDS.has(String(v.get("kind", ""))):
			return "调查笔记无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	RandomState.restore(_rng, data)
	entries = (data.get("entries", {}) as Dictionary).duplicate(true)
	# Preserve discovery, day and reading order for the guard and radio exhibits in older notebooks.
	if entries.has("dutyBook1987"):
		entries["dutyBook1987"]["text"] = PAPER_TRIAL_NOTE
		entries["dutyBook1987"]["source"] = PAPER_TRIAL_SOURCE
	for key: String in DESK_RECORDS:
		if entries.has(key): entries[key]["text"] = DESK_RECORDS[key]
	if entries.has("campus:stair_teach_w"):
		entries["campus:stair_teach_w"]["text"] = CampusObservations.LANDINGS["stair_teach_w"][2]
	if entries.has("broadcastBook"): entries["broadcastBook"]["text"] = BROADCAST_NOTE
	recent = (data.get("recent", []) as Array).filter(func(id: Variant) -> bool: return id is String and entries.has(id)).slice(-RECENT_MAX)
	focus = String(data.get("focus", ""))
	pins = data.get("pins", {}).duplicate()
	supply = (data.get("supply", {}) as Dictionary).duplicate()


## ctx: day, place, has_key, has_phone, has_coin, has_pill, bag_full, car {ok, via}, car_tried, car_used,
## hacked, data, face_done (or -1), spot_comp, spot_data, portal {diary, sketch, open, count, floors_left, need},
## cyber {initialized, network, download, term}, desk_ok (idle, in teach1, near the own seat).
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


## Written only by an actual interaction. A repeat refreshes the text, the place and the day.
func record(id: String, text: String, kind: String = "事实", source: String = "") -> void:
	entries[id] = {"text": text, "kind": kind if KINDS.has(kind) else "事实", "source": source if not source.is_empty() else String(_c.get("place", "")), "day": int(_c.get("day", 1))}
	if id == "portalDiary" or id.begins_with("blueprint:"):
		focus = "portal"
	elif id == "whitelistWritten" or id == "whitelistSynced":
		focus = "face"
	elif id == "notice" or id == "parking" or id == "carKey":
		focus = "car"
	elif id in ["broadcastBook", "broadcastTeacher", "notice1", "notice2", "notice3", "notice4"]:
		focus = "dismissal"
	recent = recent.filter(func(k: String) -> bool: return k != id)
	recent.append(id)
	recent = recent.slice(-RECENT_MAX)


func visible(id: String) -> bool:
	return entries.has(id)


func paper_sample() -> String:
	if entries.has("paper:lesson:A"): return "甲"
	if entries.has("paper:lesson:B"): return "乙"
	return ""


func observe(site: Dictionary) -> void:
	var source := String(_c.get("place", "")) + " · " + String(site.title)
	var id := "campus:" + String(site.id)
	if not entries.has(id):
		record(id, site.text, "事实", source)
		_emit("save")
	if site.id == "stair_teach_w":
		_pending = {"kind": "stair_voice"}
		_emit("choice", {"text": "扶手旁有两道粉笔杠。铁盖下藏着个小扬声器，标签上写着「楼梯间采样」。", "labels": ["听完这段录音", "翻看标签背面", "轻轻走开"]})
		return
	if site.id != "lab1":
		_emit("say", {"text": site.text})
		return
	var selected := paper_sample()
	if not selected.is_empty():
		_emit("say", {"text": "夹里的%s纸上边缺了一小块。打孔杆锁住了。底板刻着这一组的编号「四·二」。" % selected})
		return
	_pending = {"kind": "paper_sample"}
	_emit("choice", {"text": "夹里有两张完整的纸，编号「四·二」。杆子只能按一次。封套写着「配对表由北门值班员保管」。", "labels": ["在甲纸上打孔", "在乙纸上打孔", "放下打孔杆"]})


# ---- the parking ticket, the handover note, the supply box ----

## R at the own seat in teach1: the parking ticket. False when it is not available (the lesson opens instead).
func open_desk() -> bool:
	if not bool(_c.get("desk_ok", false)) or visible("desk"):
		return false
	record("desk", DESK_RECORDS.desk, "事实", "自己的课桌")
	_emit("spots", {"names": ["guard"]})
	_emit("say", {"text": "点名联上的名字来自我的试卷。去保安岗查底联，或者先看看讲台上的钥匙移交单。", "keep": true})
	_emit("save")
	return true


## The own classroom's podium.
func notice() -> void:
	_emit("spots", {"names": ["guard", "garage"]})
	record("notice", "钥匙移交：行政楼五楼校长办公室。保安岗留有停车记录和备用手电；车库位于校园西侧。", "事实", "教学楼一楼 · 讲台移交单")
	record("carTheory", "如果找到钥匙、核对停车记录，也许能开车离开。车库黑影怕持续照射，开门前先看清车道。", "推测", "移交单背面的手写字")
	record("timePressure", "最好当天找到出口。首日晚间起异象越来越密，常驻巡察持续巡逻；第二天起危险区更耗精神，休息也更难恢复。睡觉不会让校园恢复安全；已拿到的通关物品还在。", "事实", "移交单 · 留校提醒")
	var s := supply_site()
	record("supply", "临时补给箱移至%s。可领取一份药片；封条能慢慢拆，也可投一枚硬币解锁。" % ("保安岗柜台" if s["site"] == "guard1" else "食堂售货机旁"), "事实", "讲台移交单 · 补给附注")
	_pending = {"kind": "notice"}
	_emit("choice", {"text": "钥匙移交给了行政楼五楼校长室。底联在保安岗柜台，柜台下有备用手电。两处地点和留校规定已记进笔记。",
		"labels": ["阅读登记规定（次日起开放）" if int(_c.get("day", 1)) == 1 else "登记外出，记下移交事项", "拿讲台上的粉笔"]})


func supply_site() -> Dictionary:
	if not supply.has("site") or not ["guard1", "canteen1"].has(String(supply["site"])):
		supply = {"site": "guard1" if _rng.randf() < 0.5 else "canteen1", "taken": false}
	return supply


## At the supply box's place (the guard counter or the vending machine) once the note is read.
## True when the choice opened; the caller goes on with the facility after "continue".
func supply_offer(room: String) -> bool:
	if not visible("notice"):
		return false
	var s := supply_site()
	if s["site"] != room or bool(s["taken"]):
		return false
	_pending = {"kind": "supply"}
	_emit("choice", {"text": "旁边有一只封好的临时补给箱。一次领取一份药片；硬币还可以留作买饭或车库诱饵。",
		"labels": ["拆封领取（游戏时间 6 分钟）", "投币领取（消耗 1 枚硬币）", "先不取，继续查看设施"]})
	return true


func _take(pay: bool) -> void:
	if supply.get("taken", false):
		_emit("say", {"text": "箱里的补给已经被领走了。"})
		return
	if bool(_c.get("bag_full", false)) or bool(_c.get("has_pill", false)):
		_emit("say", {"text": "我：先腾个位置。药片会留在箱里。"})
		return
	if pay and not bool(_c.get("has_coin", false)):
		_emit("say", {"text": "我：没有硬币，可以慢慢拆开。"})
		return
	supply["taken"] = true
	_emit("supply", {"pay": pay})
	record("supplyTaken", "已领取临时补给箱的药片。" + ("用了一个硬币，省下拆封时间。" if pay else "花了六分钟拆封，保留了硬币。"), "验证")
	_emit("save")


func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	match String(p.get("kind", "")):
		"stair_voice":
			if index not in [0, 1]: return
			var line := DESK_RECORDS["landing:knock" if index == 0 else "landing:star"] as String
			record("landing:knock" if index == 0 else "landing:star", line, "事实", "教学楼西梯 · 二楼扶手")
			_emit("stair_promise")
			_emit("say", {"text": line})
			_emit("save")
		"paper_sample":
			if index not in [0, 1] or not paper_sample().is_empty(): return
			var letter := "甲" if index == 0 else "乙"
			var line := "打孔杆咔哒一声锁住了。四·二号的%s纸上边掉下一小片，另一张完好。我在这里看不到北门的实物。" % letter
			record("paper:lesson:A" if index == 0 else "paper:lesson:B", line, "验证", "实验楼一楼 · 第四节纸样")
			_emit("say", {"text": line})
			_emit("save")
		"notice":
			if index == 0:
				_emit("outing")
				record("outing", "第二天起讲台可登记外出，不消耗物品；第一天禁手动和自动登记。许可跨越普通课堂，另外承担下一次检查的到场责任；错过约定检查会被持续追踪。17:50 后的责任是次日 12:50，熄灯仍回宿舍；校长室、考试和夜间不受许可保护。", "事实", "讲台 · 外出登记")
				_emit("save")
			elif index == 1:
				_emit("chalk")
				_emit("save")
		"supply":
			if index == 0 or index == 1:
				_take(index == 1)
			else:
				_emit("continue")


func car_name(c: int, r: int) -> String:
	return "鄂A·" + "DFHKM".substr((c + r) % 5, 1) + str(3100 + c * 31 + r)


# ---- the goal and the route progress ----

func _radio_lead() -> String:
	var next: String = _c.get("radio_goal", "")
	if next.is_empty() and (visible("broadcastBook") or visible("broadcastTeacher")):
		return "去行政楼二楼广播站，查阅播音记录本里的通知稿来源。"
	return next


func routes() -> Array:
	var out: Array = []
	if not _paper_lead().is_empty(): out.append(["identity", "底联核验"])
	if visible("parking") or visible("notice") or bool(_c.get("has_key", false)) or int(_c.get("car_tried", 0)) > 0:
		out.append(["car", "车辆"])
	if _face_discovered():
		out.append(["face", "白名单"])
	var po: Dictionary = _c.get("portal", {})
	if bool(po.get("diary", false)) or bool(po.get("sketch", false)) or bool(po.get("open", false)):
		out.append(["portal", "造门"])
	if bool(_c.get("has_phone", false)) or bool(_c.get("cyber", {}).get("initialized", false)):
		out.append(["cyber", "网安仙人"])
	if not _radio_lead().is_empty():
		out.append(["dismissal", "放学广播"])
	if not String(_c.get("exchange_goal", "")).is_empty():
		out.append(["international", "交流团"])
	return out


func current_focus() -> String:
	var known := routes()
	var preferred: String = pins.get(_c.get("reader", "solo"), "")
	var lead := "identity" if focus in ["", "car"] and not _paper_lead().is_empty() else focus
	for id: String in [preferred, lead, "portal", "dismissal", "international"]:
		if not id.is_empty() and known.any(func(r: Array) -> bool: return r[0] == id): return id
	return "car" if known.is_empty() else String(known[0][0])


func set_focus(id: String) -> bool:
	if not routes().any(func(r: Array) -> bool: return r[0] == id):
		return false
	pins[_c.get("reader", "solo")] = id
	return true


func goal(route: String = "") -> String:
	var f := current_focus() if route.is_empty() else route
	var cy: Dictionary = _c.get("cyber", {})
	var po: Dictionary = _c.get("portal", {})
	if f == "identity": return _paper_lead()
	if f == "dismissal": return _radio_lead()
	if f == "international": return _c["exchange_goal"]
	if f == "cyber":
		if String(cy.get("term", "")) == "accepted":
			return "停机请求已提交。保持存活，手机可查看任务状态。"
		return "连接实验楼三楼任意电脑，阅读维护终端中的资料。" if String(cy.get("download", "")) == "complete" else "用手机接入学校无线网络，等待模拟容器安装。"
	if f == "portal" and (bool(po.get("diary", false)) or bool(po.get("sketch", false)) or bool(po.get("open", false))):
		if bool(po.get("open", false)):
			return "装置已启动，可以返回物理实验室的基座。"
		if bool(po.get("sketch", false)):
			return "对照图纸准备材料。" + String(po.get("need", ""))
		return "对照日记，调查实验楼二、四、五楼教师台；已得到 %d/3 张图纸。" % int(po.get("count", 0)) if visible("portalDiary") else "造门调查还没结束；日记的文字记不清了，可以回隧道重读。"
	if f == "face" and _face_discovered():
		if bool(_c.get("data", false)):
			return "数据已同步，前往西小门完成闸机验证。"
		return "网络中心已写入，前往行政楼三楼同步数据。" if bool(_c.get("hacked", false)) else "调查实验楼三楼的网络中心；留意门锁和终端旁的说明。"
	if bool(_c.get("has_key", false)) and not visible("notice") and not visible("parking"):
		return "已经有车钥匙。在背包中使用它，读清环上的牌号，再去车辆旁核对。"
	if not visible("parking") and not visible("notice"):
		if visible("desk"): return "去保安岗柜台核对签名。出教室前，也可以顺手看看讲台上的钥匙移交单。"
		return OpeningStory.FIRST_LEAD + ("起身前可以低头看名牌，决定怎么应到。" if _c.get("desk_ok", false) else "")
	var car: Dictionary = _c.get("car", {})
	if not bool(car.get("ok", false)):
		if visible("parking"): return "底联拿到了。去行政楼五楼校长室取车钥匙。"
		return "钥匙被收到行政楼五楼校长办公室；出发前可以去保安岗取手电、查看停车记录。"
	if car.get("via") == "hotwire":
		if not visible("parking"):
			return "我会搭线，不用钥匙。保安岗的停车登记能缩小范围；搭线要在车门边蹲一阵，先处理车道上的黑影。"
		return "去西侧车库，按停车登记的排号找车；搭线要蹲一阵，先用手电或诱饵处理车道上的黑影。"
	if not visible("parking"):
		return "已有开车的办法。保安岗停车记录能缩小范围，钥匙上的牌号可供核对。"
	return "去西侧车库核对车牌；先用手电或诱饵处理车道上的黑影，再试车门。"


func _paper_lead() -> String:
	if _c.get("paper_debt", false): return "空座替我答过到。我得亲自去北门旁的保安岗柜台，核对那张签着我名字的底联。"
	if _c.get("paper_trial", false): return ""
	var lead: String = _c.get("paper_goal", "")
	if lead.is_empty() and _c.get("reader", "solo") != "solo" and visible("parking"):
		return "队友翻过了登记簿。去北门旁的保安岗柜台，我自己的底联还在那里。"
	return lead


func _face_discovered() -> bool:
	return visible("westTrial") or bool(_c.get("paper_trial", false)) or bool(_c.get("spot_comp", false)) or bool(_c.get("spot_data", false)) or bool(_c.get("hacked", false))


## A known destination, shown only when its lead is the reader's current investigation.
func paper_landmark() -> String:
	var tracked := current_focus()
	if tracked == "identity": return "保安岗" if String(_c.get("paper_goal", "")).is_empty() else "西小门"
	if tracked == "car" and not visible("notice") and not visible("parking") and not _c.get("has_key", false): return "保安岗"
	return ""


func map_focus(selection: String) -> String:
	var known := routes()
	for id: String in [selection, pins.get(_c.get("reader", "solo"), "")]:
		if known.any(func(r: Array) -> bool: return r[0] == id): return id
	var tracked := current_focus()
	return tracked if tracked == "identity" or known.size() < 2 else ""


## A building or gate the discovered lead currently points to on the campus plan.
func map_destination(route: String) -> String:
	match route:
		"identity": return "guard" if String(_c.get("paper_goal", "")).is_empty() else "gate_w"
		"car":
			var car: Dictionary = _c.get("car", {})
			var has_key := bool(_c.get("has_key", false))
			var needs_record: bool = car.get("via") == "hotwire" or (not visible("notice") and not has_key)
			if not visible("parking") and needs_record:
				return "guard"
			return "garw" if has_key or car.get("ok", false) else "admin"
		"face":
			if _c.get("data", false): return "gate_w"
			return "admin" if _c.get("hacked", false) else "lab"
		"portal":
			var portal: Dictionary = _c.get("portal", {})
			if portal.get("open", false) or (visible("portalDiary") and not portal.get("sketch", false)): return "lab"
		"cyber":
			var cyber: Dictionary = _c.get("cyber", {})
			if cyber.get("term") != "accepted" and cyber.get("download") == "complete": return "lab"
	return ""


## [[route, text, done]]
func progress() -> Array:
	var out: Array = []
	if _c.get("paper_trial", false):
		out.append(["底联核验", "已试走西小门，白线外又接回校园。", true])
	var car: Dictionary = _c.get("car", {})
	var tried := int(_c.get("car_tried", 0))
	if visible("parking") or visible("notice") or bool(_c.get("has_key", false)) or tried > 0:
		var state := "已驶离车库" if bool(_c.get("car_used", false)) else ("有钥匙，能够试车门" if car.get("via") == "key" else ("会搭线，能够试车" if bool(car.get("ok", false)) else "尚无开车办法"))
		out.append(["车辆", "%s；已试 %d 辆。" % [state, tried], bool(_c.get("car_used", false))])
	if _face_discovered():
		var done := int(_c.get("face_done", -1))
		out.append(["白名单", "%s；%s%s。" % ["网络中心已写入" if bool(_c.get("hacked", false)) else "网络中心尚未写入", "行政楼数据已同步" if bool(_c.get("data", false)) else "行政楼尚未同步", "；闸机验证 %d/3" % done if done >= 0 else ""],
			bool(_c.get("data", false)) and done >= 3])
	var cy: Dictionary = _c.get("cyber", {})
	if bool(cy.get("initialized", false)):
		var t := String(cy.get("term", ""))
		out.append(["网安仙人", "服务器已接受请求，保持存活。" if t == "accepted" else ("容器就绪，前往机房终端。" if String(cy.get("download", "")) == "complete" else ("已接入学校网络。" if bool(cy.get("network", false)) else "用手机接入学校网络。")), t == "completed"])
	var po: Dictionary = _c.get("portal", {})
	if bool(po.get("diary", false)) or bool(po.get("sketch", false)) or bool(po.get("open", false)):
		var text := ""
		if bool(po.get("open", false)):
			text = "装置已启动"
		elif bool(po.get("sketch", false)):
			text = "图纸齐全；" + String(po.get("need", "")).strip_edges()
		else:
			text = "已获得 %d/3 张图纸" % int(po.get("count", 0)) + ("；还需调查实验楼 %s 楼教师台" % "、".join((po.get("floors_left", []) as Array).map(func(f: Variant) -> String: return str(f))) if visible("portalDiary") else "；日记的文字已模糊，可以回去重读")
		out.append(["造门", text + "。", bool(po.get("open", false))])
	var radio := _radio_lead()
	if not radio.is_empty(): out.append(["放学广播", radio, false])
	if not String(_c.get("exchange_goal", "")).is_empty(): out.append(["交流团", _c["exchange_goal"], false])
	return out


## The notes page rows: {id, text, kind, source, day} grouped by kind, optionally filtered by a search text.
func list(query: String = "") -> Dictionary:
	var q := query.strip_edges().to_lower()
	var groups := {}
	var found := 0
	for kind: String in KINDS:
		groups[kind] = []
	var ids: Array = entries.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = entries[id]
		if q != "" and (String(e["text"]) + " " + String(e["source"])).to_lower().find(q) < 0:
			continue
		var row := e.duplicate()
		row["id"] = id
		(groups[e["kind"]] as Array).append(row)
		found += 1
	var latest: Array = []
	if q == "":
		for i in range(recent.size() - 1, -1, -1):
			if entries.has(recent[i]) and latest.size() < 3:
				var r2: Dictionary = (entries[recent[i]] as Dictionary).duplicate()
				r2["id"] = recent[i]
				latest.append(r2)
	return {"groups": groups, "recent": latest, "found": found}
