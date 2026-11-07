class_name InvestigationModule
extends FeatureModule
## The investigation notebook, ported from the Web version (reference wd-fz.github.io@0bf508a,
## investigation.js): what the player found out, written only by real interactions, reread from the
## handbook's notes page. Records have a kind (事实 / 推测 / 验证 / 线索), the place and the day they
## were found; the most recent eight are remembered; the "current investigation" card names the goal of
## the route the player follows (car / white-list / portal / cyber), and a progress block lists each
## route. It also owns the three flows that start the first route: the parking ticket in the own desk (R),
## the handover note on the own classroom's podium and the temporary supply box.
## Events out: say {text}, choice {text, labels}, save, outing, chalk, spots {names}, supply {pay},
## continue (the supply choice was declined: go on with the facility), record is silent.

const STATE_VERSION := 1
const KINDS := ["事实", "推测", "验证", "线索"]
const RECENT_MAX := 8

var entries: Dictionary = {}   # id → {text, kind, source, day}
var recent: Array = []
var focus := ""
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
	supply = {}
	events = []
	_pending = {}


func capture() -> Dictionary:
	return {"entries": entries.duplicate(true), "recent": recent.duplicate(), "focus": focus, "supply": supply.duplicate()}


func validate(data: Dictionary) -> String:
	if not (data.get("entries", {}) is Dictionary) or not (data.get("recent", []) is Array) or not (data.get("supply", {}) is Dictionary):
		return "调查笔记无效"
	for v: Variant in (data["entries"] as Dictionary).values():
		if not (v is Dictionary) or not (v.get("text") is String) or not KINDS.has(String(v.get("kind", ""))):
			return "调查笔记无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	entries = (data.get("entries", {}) as Dictionary).duplicate(true)
	recent = (data.get("recent", []) as Array).filter(func(id: Variant) -> bool: return id is String and entries.has(id)).slice(-RECENT_MAX)
	focus = String(data.get("focus", ""))
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
	recent = recent.filter(func(k: String) -> bool: return k != id)
	recent.append(id)
	recent = recent.slice(-RECENT_MAX)


func visible(id: String) -> bool:
	return entries.has(id)


# ---- the parking ticket, the handover note, the supply box ----

## R at the own seat in teach1: the parking ticket. False when it is not available (the lesson opens instead).
func open_desk() -> bool:
	if not bool(_c.get("desk_ok", false)) or visible("desk"):
		return false
	record("desk", "桌肚里夹着一张停车单，背面写着：「钥匙又被收走了。讲台上的移交单还没撕。」", "事实", "自己的课桌")
	_emit("say", {"text": "我：停车单背面写着「讲台上的移交单还没撕」。先去教室前面的讲台看看。手册的笔记页能重读。", "keep": true})
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
	_emit("choice", {"text": "移交单：钥匙在行政楼五楼校长办公室；保安岗有停车记录和备用手电。车库在西侧。第一天不开放外出登记；第二天起许可可跨越普通课堂，但必须参加约定的下一次检查，缺席会被持续追踪。12:50、17:50 回教室集合，熄灯回宿舍。校长室、网络中心黄线报警区、考试和夜间仍要小心。尽量当天离校，第二天起校园更危险，休息效果也会减弱。",
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

func routes() -> Array:
	var out: Array = []
	if visible("notice") or bool(_c.get("has_key", false)) or int(_c.get("car_tried", 0)) > 0:
		out.append(["car", "车辆"])
	if bool(_c.get("spot_comp", false)) or bool(_c.get("spot_data", false)) or bool(_c.get("hacked", false)):
		out.append(["face", "白名单"])
	var po: Dictionary = _c.get("portal", {})
	if bool(po.get("diary", false)) or bool(po.get("sketch", false)) or bool(po.get("open", false)):
		out.append(["portal", "造门"])
	if bool(_c.get("has_phone", false)) or bool(_c.get("cyber", {}).get("initialized", false)):
		out.append(["cyber", "网安仙人"])
	return out


func current_focus() -> String:
	if focus != "":
		return focus
	var po: Dictionary = _c.get("portal", {})
	if bool(po.get("diary", false)) or bool(po.get("sketch", false)) or bool(po.get("open", false)):
		return "portal"
	return "face" if bool(_c.get("hacked", false)) else "car"


func set_focus(id: String) -> bool:
	if not routes().any(func(r: Array) -> bool: return r[0] == id):
		return false
	focus = id
	return true


func goal() -> String:
	var f := current_focus()
	var cy: Dictionary = _c.get("cyber", {})
	var po: Dictionary = _c.get("portal", {})
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
	if f == "face" and (bool(_c.get("spot_comp", false)) or bool(_c.get("spot_data", false)) or bool(_c.get("hacked", false))):
		if bool(_c.get("data", false)):
			return "数据已同步，前往西小门完成闸机验证。"
		return "网络中心已写入，前往行政楼三楼同步数据。" if bool(_c.get("hacked", false)) else "调查实验楼三楼的网络中心；留意门锁和终端旁的说明。"
	if bool(_c.get("has_key", false)) and not visible("notice"):
		return "已经有车钥匙。在背包中使用它，读清环上的牌号，再去车辆旁核对。"
	if not visible("desk") and not visible("notice"):
		return "先看看自己课桌上的停车单（靠近自己的座位，按 R），也可以自由探索。"
	if not visible("notice"):
		return "停车单提到了教室前方的讲台。走近后交互，看看移交单。"
	var car: Dictionary = _c.get("car", {})
	if not bool(car.get("ok", false)):
		return "钥匙被收到行政楼五楼校长办公室；出发前可以去保安岗取手电、查看停车记录。"
	if car.get("via") == "hotwire":
		if not visible("parking"):
			return "我会搭线，不用钥匙。保安岗的停车登记能缩小范围；搭线要在车门边蹲一阵，先处理车道上的黑影。"
		return "去西侧车库，按停车登记的排号找车；搭线要蹲一阵，先用手电或诱饵处理车道上的黑影。"
	if not visible("parking"):
		return "已有开车的办法。保安岗停车记录能缩小范围，钥匙上的牌号可供核对。"
	return "去西侧车库核对车牌；先用手电或诱饵处理车道上的黑影，再试车门。"


## [[route, text, done]]
func progress() -> Array:
	var out: Array = []
	var car: Dictionary = _c.get("car", {})
	var tried := int(_c.get("car_tried", 0))
	if visible("notice") or bool(_c.get("has_key", false)) or tried > 0:
		var state := "已驶离车库" if bool(_c.get("car_used", false)) else ("有钥匙，能够试车门" if car.get("via") == "key" else ("会搭线，能够试车" if bool(car.get("ok", false)) else "尚无开车办法"))
		out.append(["车辆", "%s；已试 %d 辆。" % [state, tried], bool(_c.get("car_used", false))])
	if bool(_c.get("spot_comp", false)) or bool(_c.get("spot_data", false)) or bool(_c.get("hacked", false)):
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
