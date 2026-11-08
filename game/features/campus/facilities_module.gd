class_name FacilitiesModule
extends FeatureModule
## Campus facilities, ported from the Web version (reference wd-fz.github.io@0bf508a):
## interact.js SAN_ACTS / sanActFor / doSanAct (rest), useFacility (pendulum, centrifuge,
## microscope, globe, benches), the server coil, useGeoMap, useBell, useAltar, guardSupplies;
## items.js canteenWindow / useVending / useCompass / atlas / map / memo; story.js SPOTS / spotMark /
## useStall (its public part); portal.js (the tunnel, the diary, the three blueprints, the bench, 《门》).
## Context in, events out; the app applies them. Item changes go through the bag callables in the context.

const STATE_VERSION := 1
const SAN_ACTS := {
	"run": {"n": "沿跑道跑两圈", "san": 14.0, "min": 12.0, "cd": 90.0, "msg": "我：跑完两圈。肺很疼，脑子清楚了一点。"},
	"shoot": {"n": "投几个球", "san": 10.0, "min": 8.0, "cd": 70.0, "msg": "我：球砸在框上，弹回来。声音很空。"},
	"eat": {"n": "吃饭", "san": 18.0, "min": 20.0, "cd": 140.0, "msg": "我：饭是凉的。但我还是吃完了。"},
	"sleep": {"n": "躺一会儿", "san": 26.0, "min": 45.0, "cd": 200.0, "msg": "我：我闭了一下眼睛。醒来的时候，上铺的床板往下压着一个人的形状。"},
	"wash": {"n": "洗把脸", "san": 8.0, "min": 4.0, "cd": 50.0, "msg": "我：水很凉。镜子里那个人也洗了把脸。"},
	"piano": {"n": "弹一会儿琴", "san": 16.0, "min": 10.0, "cd": 120.0, "msg": "我：我弹了一段。走廊里没有人过来。"},
	"pc": {"n": "玩一会儿电脑", "san": 12.0, "min": 15.0, "cd": 100.0, "msg": "我：机房里只有我这一台亮着。屏幕右下角的时钟在走。"},
	"view": {"n": "看看远处", "san": 6.0, "min": 6.0, "cd": 40.0, "msg": "我：从这里能看见半个校园。都在雾里。雾的边上，一直是同一栋楼。"},
}
const FAC_CD := {"Z": 70.0, "C": 90.0, "N": 45.0, "Y": 200.0, "K": 0.0}
const VEND_POOL := [["snack", 24], ["battery", 18], ["pill", 14], ["seal", 10], ["watch", 7], ["elixir", 6], ["torch", 5], [null, 16]]
## story.js SPOTS (public ones): id, name, map rect (map units).
const SPOTS := [
	["guard", "保安岗", 552, 142, 56, 40], ["gate", "北门", 480, 100, 80, 50], ["data", "数据终端", 400, 515, 270, 90],
	["comp", "机房", 400, 670, 270, 100], ["garage", "车库", 285, 510, 62, 58], ["trash", "垃圾房", 740, 1060, 56, 62],
	["wall", "东围墙", 790, 400, 40, 500], ["climb", "攀爬点", 572, 210, 36, 165], ["stall", "第三个隔间", 452, 865, 218, 120],
	["office", "办公室", 400, 515, 270, 90], ["front", "前台", 452, 865, 218, 120], ["portal", "实验台上的草图", -9999, -9999, 1, 1]]
const SPOT_ROOM := {"guard": ["guard"], "garw": ["garage"], "trash": ["trash"], "admin": ["data"], "lab": ["comp"]}
const PORTAL_PARTS := ["coil", "lens", "vial", "battery"]
const BLUEPRINT_FLOORS := [2, 4, 5]
const OBSERVATIONS := {
	2: {"text": "教师台上是分层试管与操作记录：静置后，发光的重液沉在底部；上层透明。图纸夹在记录后面，要求先圈出应保留的那一层。",
		"options": ["保留上层透明液", "保留底层发光液", "把两层倒回去混合"], "answer": 1, "why": "发光重液会沉底；离心机的试剂来自底层。",
		"note": "二楼图纸：发光重液沉底。离心机能够分离出造门用的试剂。"},
	4: {"text": "教师台的校园挂图标着「北 ↑」。纸角画了实验楼一楼的门框，镜片在左，电池在右；背面要求抄出：面朝北时，左边是什么方向？",
		"options": ["东", "南", "西"], "answer": 2, "why": "面朝北时，左西右东。先确认参照方向，再读图。",
		"note": "四楼图纸：朝北读图，左西右东；透镜应面向门框。装置并不是在打开学校的校门。"},
	5: {"text": "教师台上的谱页被裁成接线顺序。三个标签写着：「先把线圈接入；再安装透镜；最后接通电池」。纸夹只需依次按下正确标签。",
		"options": ["电池", "线圈", "透镜"], "order": [1, 2, 0], "note": "五楼图纸：线圈 → 透镜 → 电池。最后才接电，免得门朝向尚未确定就启动。"},
}

var act_cool: Dictionary = {}
var flags: Dictionary = {}
var spots: Dictionary = {}
var portal: Dictionary = {}
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _c: Dictionary = {}
var _pending: Dictionary = {}
var _rooms: Dictionary = {}
var _outside: Dictionary = {}
var _items: Dictionary = {}


func _init(rooms: Dictionary = {}, outside: Dictionary = {}, campus: Dictionary = {}) -> void:
	_rooms = rooms
	_outside = outside
	_items = campus.get("items", {})


func module_id() -> StringName:
	return &"campus.facilities"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	act_cool = {}
	flags = {}
	spots = {}
	portal = {"diary": false, "blueprints": {}, "work": {}, "sketch": false, "open": false, "ret": null}
	events = []
	_pending = {}


func set_seed(value: int) -> void:
	_rng.seed = value


func capture() -> Dictionary:
	return {"act_cool": act_cool.duplicate(), "flags": flags.duplicate(), "spots": spots.duplicate(), "portal": portal.duplicate(true), "seed": _rng.seed, "rng": _rng.state}


func validate(data: Dictionary) -> String:
	for k: String in ["act_cool", "flags", "spots", "portal"]:
		if not (data.get(k) is Dictionary):
			return "设施状态无效"
	for k: String in data["act_cool"]:
		if not SAN_ACTS.has(k) and not FAC_CD.has(k.trim_prefix("fac")):
			return "设施冷却无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	act_cool = (data["act_cool"] as Dictionary).duplicate()
	flags = (data["flags"] as Dictionary).duplicate()
	spots = (data["spots"] as Dictionary).duplicate()
	portal.merge((data["portal"] as Dictionary).duplicate(true), true)
	var bp: Dictionary = {}
	for k: Variant in portal["blueprints"]:
		bp[int(k)] = true
	portal["blueprints"] = bp
	var work: Dictionary = {}
	for k: Variant in portal["work"]:
		work[int(k)] = int(portal["work"][k])
	portal["work"] = work
	if data.get("seed") is float or data.get("seed") is int:
		_rng.seed = int(data["seed"])
	if data.get("rng") is float or data.get("rng") is int:
		_rng.state = int(data["rng"])


## ctx: scene, x, y, ang, tsec, clock (game minutes), meal, rest_mul, night, has / add / remove (Callables),
## anomaly {active, id, pre, warn_ok, minutes, cn}, busy.
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


func _say(text: String) -> void:
	_emit("notice", {"text": text})


func _toast(text: String) -> void:
	_emit("toast", {"text": text})


func _san(amount: float) -> void:
	_emit("san", {"amount": amount, "max": 100.0, "min": 0.0})


func _has(id: String) -> bool:
	var f: Callable = _c.get("has", Callable())
	return f.is_valid() and bool(f.call(id))


func _add(id: String) -> bool:
	var f: Callable = _c.get("add", Callable())
	return f.is_valid() and bool(f.call(id))


func _remove(id: String) -> void:
	var f: Callable = _c.get("remove", Callable())
	if f.is_valid():
		f.call(id)


func _name(id: String) -> String:
	return String(_items.get(id, {}).get("n", id))


func _clock() -> float:
	return float(_c.get("clock", 0.0))


func _roll(n: int) -> int:
	var r := _rng.randf()
	var r2 := _rng.randf()
	if _has("goggles"):
		r = minf(r, r2)
	return int(floor(r * n))


# ---- rest (sanActFor / doSanAct) ----

## Which rest this tile offers (indoor), or "".
func rest_for(room: Variant, ch: String) -> String:
	if room == null:
		return ""
	var host := String(room.get("host", ""))
	if host == "canteen" and (ch == "k" or ch == "t") and bool(_c.get("meal", false)):
		return "eat"
	if (host == "dormN" or host == "dormS") and ch == "b":
		return "sleep"
	if host == "lab" and ch == "p":
		return "piano"
	if host == "lab" and ch == "n":
		return "pc"
	if host == "teach" and ch == "w":
		return "wash"
	return ""


## Outdoor rest at an old world point (sanActFor in 'out' mode).
func rest_out(w: Vector2) -> String:
	var m := w / 2.0
	for o: Dictionary in _outside.get("objects", []):
		if not (m.x > float(o["x"]) and m.x < float(o["x"]) + float(o["w"]) and m.y > float(o["y"]) and m.y < float(o["y"]) + float(o["h"])):
			continue
		match String(o.get("k", "")):
			"field", "track":
				return "run"
			"court":
				return "shoot"
			"garden":
				return "view"
	return ""


static func rest_hint(key: String) -> String:
	var a: Dictionary = SAN_ACTS[key]
	return "%s（%d 分钟）" % [a["n"], int(a["min"])]


func rest(key: String) -> void:
	var a: Dictionary = SAN_ACTS.get(key, {})
	if a.is_empty():
		return
	if (_c.get("closed", []) as Array).has(key):
		_say(DayModule.CLOSED_MSG.get(key, "我：门锁着。"))
		return
	if act_cool.has(key) and _clock() < float(act_cool[key]):
		_say("我：刚做过。现在没那个心情。")
		return
	_emit("advance", {"minutes": float(a["min"])})
	var gain := snappedf(float(a["san"]) * float(_c.get("rest_mul", 1.0)), 0.1)
	_san(gain)
	act_cool[key] = _clock() + float(a["min"]) + float(a["cd"])
	_emit("fact", {"key": key})
	_emit("stamina", {"amount": 25.0})
	_emit("skip", {"minutes": float(a["min"]), "name": String(a["n"])})
	_say(String(a["msg"]))
	_toast(String(a["n"]) + " · 休息结束")


# ---- hints for tiles whose text depends on state ----

func hint(room: Variant, ch: String) -> String:
	var r := rest_for(room, ch)
	if r != "":
		return rest_hint(r)
	var host := String(room.get("host", "")) if room != null else ""
	match ch:
		"k":
			if host == "guard":
				return "查看值班台"
			return _canteen_hint(host)
		"t":
			return _canteen_hint(host)
		"M":
			return "投币（售货机）" if _has("coin") else "售货机"
		"b":
			return "床"
	return ""


func _canteen_hint(host: String) -> String:
	if host == "canteen" and not bool(_c.get("meal", false)):
		return "投币买饭" if _has("coin") else "打饭窗口"
	return "翻找"


# ---- tiles ----

## One E press on a facility tile. room: the layout dictionary of the current scene.
func use(room: Dictionary, ch: String, c: int, r: int) -> void:
	var host := String(room.get("host", ""))
	var key := rest_for(room, ch)
	if key != "":
		rest(key)
		return
	match ch:
		"Z", "C", "N", "Y", "K":
			_facility(room, ch)
		"Q":
			_server()
		"u":
			_read_diary()
		"j":
			_leave_tunnel(r)
		"x":
			_geo_map()
		"U":
			_bell()
		"A":
			_altar()
		"B", "G":
			_stall(String(room.get("id", "")))
		"M":
			_vending()
		"p":
			if float(_c.get("tsec", 0.0)) < SchoolClock.EVENING:
				_say("我：现在弹琴，走廊里的人都听得见。")
			_say("我：是《月光》。第一乐章。可是钢琴没有人在弹。")
		"b":
			_say("我：床。可是现在不能睡。")
		"k", "t":
			if ch == "k" and host == "guard":
				_guard()
			elif host == "canteen":
				_canteen_window()
			else:
				_say("我：没有能吃的。")
		"w":
			_san(4.0)
			_say("我：洗了把脸。")
		_:
			_say("我：用不上。")


func _facility(room: Dictionary, ch: String) -> void:
	if ch == "K" and _collect_blueprint(room):
		return
	var key := "fac" + ch
	if act_cool.has(key) and _clock() < float(act_cool[key]):
		_say("我：刚弄过。等一会儿。")
		return
	var rolled := false
	match ch:
		"Z":
			rolled = true
			var an: Dictionary = _c.get("anomaly", {})
			if not bool(an.get("active", false)) and String(an.get("pre", "")) != "" and bool(an.get("warn_ok", false)):
				_emit("anomaly_lock")
				_say("我：我把摆拉开、松手。它没有来回摆，而是慢慢停在一个方向上，像被什么吸住了。\n秤盘上的砝码排成了几个字——「%s」。还有大约 %d 分钟。" % [an.get("cn", ""), int(an.get("minutes", 1))])
				_toast("预报：%s" % an.get("cn", ""))
				_emit("clue", {"id": "pendulum"})
			elif bool(an.get("active", false)):
				_san(-4.0)
				_say("我：摆在乱转，转得越来越快。它在说：已经来了。")
			else:
				_san(5.0)
				_say("我：摆停在正中，一动不动。它没有给出危险预警。")
			_emit("advance", {"minutes": 3.0})
		"C":
			rolled = true
			var v2 := _roll(100)
			if v2 < 46 and not bool(flags.get("vial", false)):
				if not _add("vial"):
					return
				flags["vial"] = true
				_say("我：转子转起来，液体分成两层。最底下沉着一线发光的东西，我把它倒进一支空管里。")
			elif v2 < 46:
				_san(7.0)
				_say("我：转子转起来，液体分成两层。白的在上。")
				_toast("转子停稳了")
			elif v2 < 72:
				_san(2.0)
				_say("我：离心机停了。管子里的东西还在转。")
				_toast("液面平静下来")
			else:
				_san(-5.0)
				_say("我：配平没配好，整台机器在桌上跳。")
				_toast("机器猛烈震动")
			_emit("advance", {"minutes": 5.0})
		"N":
			rolled = true
			if not bool(flags.get("lens", false)):
				if _add("lens"):
					flags["lens"] = true
					_say("我：镜片里有一只眼睛，它眨了一下，物镜就松了。我把它拧了下来，攥在手里是凉的。")
					act_cool[key] = _clock() + float(FAC_CD[ch])
				return
			var v3 := _roll(100)
			if v3 < 58:
				_san(4.0)
				_say("我：调焦旋钮是热的。视野里有东西在慢慢游。")
				_toast("重新看清了")
			else:
				_san(-4.0)
				_say("我：镜片里有一只眼睛。它先眨了一下。")
				_toast("镜片里有只眼睛")
		"Y":
			rolled = true
			_emit("clue", {"id": "geo"})
			if not _has("compass") and not bool(flags.get("compass", false)):
				if not _add("compass"):
					return
				flags["compass"] = true
				_say("我：地球仪上，学校的位置被铅笔描了很多遍，纸都描破了。底座的抽屉里有个罗盘。")
			else:
				_say("我：我转了一下地球仪。它转回来，停在原来那一面。")
			_san(2.0)
		"K":
			var floor_n := int(room.get("floor", 1))
			if room.get("host") == "admin":
				_say("我：办公桌上摊着一叠表格。最上面那张的名字被涂掉了。")
				if not bool(flags.get("admin_desk", false)):
					flags["admin_desk"] = true
					_emit("clue", {"id": "office"})
					_toast("办公室 · 线索 +1")
			elif floor_n == 1:
				_bench()
				return
			else:
				if floor_n == 5:
					_say("我：讲台上摊着谱子。第三乐章那一页被折了角。")
				elif floor_n == 3:
					_say("我：教师台上摊着一本「机房钥匙借用登记」。最后一页是空的。")
				else:
					_say("我：教师台上还留着上一节课的东西。烧杯里的水是温的。")
				if floor_n == 2 and not bool(flags.get("goggles", false)):
					if _has("goggles"):
						_say("我：台上还有一副护目镜，我已经带了一副。")
					elif _add("goggles"):
						flags["goggles"] = true
	if rolled:
		act_cool[key] = _clock() + float(FAC_CD[ch])


func _server() -> void:
	_emit("clue", {"id": "server"})
	if not bool(flags.get("coil", false)):
		if _add("coil"):
			flags["coil"] = true
			_say("我：服务器在响，像很多人一起压着嗓子呼气。机柜背板松了，里面一卷铜线圈烫得发红——我把它抽了出来，机柜一下子安静了。")
		return
	_say("我：服务器在响，像很多人一起压着嗓子呼气。屏幕上滚着门禁记录——每一行的时间都是 11:40。")


## items.js dropSelected: the unique door parts can be taken again after being dropped.
func dropped(id: String) -> void:
	if id in ["coil", "lens", "vial"]:
		flags[id] = false


func _geo_map() -> void:
	var maps := int(flags.get("geo_maps", 0))
	var left: Array = []
	for sp: Array in SPOTS:
		if not spots.has(sp[0]):
			left.append(sp)
	if left.is_empty() or maps >= 4:
		_say("我：挂图上的路我都走过了。有一条是我没见过的——它通到围墙外面，然后被撕掉了。")
		return
	var sp: Array = left[_rng.randi() % left.size()]
	flags["geo_maps"] = maps + 1
	spots[sp[0]] = true
	_say("我：挂图是很多年前的校园平面图。有一处被红笔圈了好几圈，旁边写着「%s」。" % sp[1])
	_toast("记下了：%s" % sp[1])


func _bell() -> void:
	var an: Dictionary = _c.get("anomaly", {})
	if bool(an.get("active", false)) and an.get("id") == "bell13":
		_say("我：我抱住撞木，用力撞了一下。钟声和那第十三下撞在一起——两边都没了。")
		_san(8.0)
		_emit("anomaly_end")
		return
	_emit("clue", {"id": "bell"})
	if bool(_c.get("exam", false)):
		_say("我：钟还在嗡嗡地响。今天剩下的课，都是考试了。")
		return
	_emit("exam_start")


func _altar() -> void:
	_emit("clue", {"id": "altar"})
	if not bool(flags.get("altar_coin", false)):
		if _has("coin"):
			_say("我：香炉底下压着一枚硬币。我已经带了一枚。")
			return
		if not _add("coin"):
			return
		flags["altar_coin"] = true
		_say("我：供桌上的饭还冒着气，筷子竖插在正中。照片上那张脸被剪掉了，校服是我们学校的。香炉底下压着一枚硬币。")
		return
	_san(-2.0)
	_say("我：照片里那个人的手，好像比刚才抬高了一点。")


func _stall(room_id: String) -> void:
	spots["stall"] = true
	_emit("clue", {"id": "stall"})
	if room_id == "teach1":
		_say("我：第三个隔间的门从里面锁着。门缝底下很暗，暗得不像有地面。")
	else:
		_say("我：隔间的门在里面锁着。门缝底下很暗，暗得不像有地面。")


func _guard() -> void:
	if not bool(flags.get("guard_told", false)):
		flags["guard_told"] = true
		_emit("clue", {"id": "keys"})
		_parking_records()
		var light := _has("torch") or _add("torch")
		_say("我：钥匙已上交行政楼五楼校长办公室。停车记录和避险便签记在手册里了。" + ("抽屉里的手电带好了，去车库前记得打开。" if light else "手电还在抽屉里，装不下了，腾出一格再来拿。"))
		_emit("save")
		return
	if not _has("torch"):
		_parking_records()
		if _add("torch"):
			_say("我：柜台下面还有一把手电筒。去车库之前，把它带上。")
		return
	_parking_records()
	_say("我：登记写着「靠西侧，第 %d 排」。旁边的便签说：手电能暂时照退黑影，硬币能把它引开，开门前先确认车道。" % int(_c.get("car_row", 1)))
	_emit("save")


## investigation.js parking: the register and the guard's note (the same two records every time).
func _parking_records() -> void:
	_record("parking", "停车登记：可用车辆在车库靠西侧，第 %d 排。记录的签名与教室停车单相同，离校栏却始终空着。" % int(_c.get("car_row", 1)), "事实", "保安岗 · 停车登记")
	_record("garageSafety", "车道上的黑影会靠近。手电持续照射能暂时逼退它；硬币可把它引开。拉车门前，先确认它离开车辆。", "事实", "保安岗 · 值班便签")


## A notebook record (the app writes it into InvestigationModule).
func _record(id: String, text: String, kind: String, source: String) -> void:
	_emit("record", {"id": id, "text": text, "kind": kind, "source": source})


func _canteen_window() -> void:
	if not _has("coin"):
		_say("我：窗口里的人头也不抬：「饭点过了。要吃，拿钱来。」")
		return
	_pending = {"kind": "meal"}
	_emit("choice", {"text": "窗口里还剩一点饭菜。「一个硬币一份。」", "labels": ["投一枚硬币买饭（游戏时间 10 分钟）", "算了"]})


func _vending() -> void:
	if not _has("coin"):
		_say("我：售货机的灯管一闪一闪。投币口旁边贴着：「只收硬币」。")
		return
	_remove("coin")
	var tot := 0
	for v: Array in VEND_POOL:
		tot += int(v[1])
	var roll := _rng.randf() * tot
	var got: Variant = null
	for v: Array in VEND_POOL:
		roll -= int(v[1])
		if roll < 0:
			got = v[0]
			break
	if got != null and _has(String(got)):
		got = null
	if got == null:
		_say("我：硬币吞进去了。机器里咔哒响了一声，什么也没掉下来。玻璃后面，有一排东西转过来对着我。")
		return
	_say("我：咔哒一声，掉下来一样东西——「%s」。" % _name(String(got)))
	_add(String(got))


# ---- items that read the map ----

## items.js ITEM_USE for compass / atlas / map / memo and the door parts. Returns true when handled.
func use_item(id: String) -> bool:
	match id:
		"atlas":
			for sp: Array in SPOTS:
				if sp[0] != "stall":
					spots[sp[0]] = true
			_emit("clue", {"id": "atlas"})
			_say("我：总览图上用红笔圈了三处：行政楼五楼「校长办公室」，实验楼一楼「物理实验室」，还有钟楼——旁边写着「顶上能看见整个学校」。")
			_emit("map")
			return true
		"map":
			for k: String in ["guard", "garage", "trash", "wall"]:
				spots[k] = true
			_say("我：平面图上有几个地方被反复描过：保安岗、车库、垃圾房、东围墙。")
			_emit("map")
			return true
		"memo":
			spots["data"] = true
			spots["comp"] = true
			_say("我：纸条上是一行潦草的字：「实验楼 3F 网络中心 → 行政楼 3F 门禁机 → 西小门。钥匙收到校长室去了。」最后一个字被划得很深。")
			_toast("记下了：机房 · 数据终端")
			return true
		"compass":
			_compass()
			return true
		"coil", "lens", "vial":
			_say("我：%s。%s%s" % [_name(id), String(_items.get(id, {}).get("d", "")), portal_need_text()])
			return true
	return false


func _compass() -> void:
	var me := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))
	var target: Variant = null
	var what := ""
	var scene := String(_c.get("scene", ""))
	if scene != "out" and _rooms.has(scene):
		var r: Dictionary = _rooms[scene]
		var best := INF
		var grid: Array = r["grid"]
		for row in grid.size():
			for col in String(grid[row]).length():
				var ch := String(grid[row]).substr(col, 1)
				if not ch in ["O", "S", "L", "="]:
					continue
				var p := Vector2(float(r["ox"]) + (col + 0.5) * float(r["tw"]), float(r["oy"]) + (row + 0.5) * float(r["th"]))
				var d := p.distance_squared_to(me)
				if d < best and d > 81.0:
					best = d
					target = p
					what = {"S": "楼梯", "O": "出口", "L": "连廊", "=": "门"}[ch]
	elif scene == "out":
		var bd := INF
		for sp: Array in SPOTS:
			if spots.has(sp[0]):
				continue
			var p := Vector2((float(sp[2]) + float(sp[4]) / 2.0) * 2.0, (float(sp[3]) + float(sp[5]) / 2.0) * 2.0)
			var d := p.distance_squared_to(me)
			if d < bd:
				bd = d
				target = p
				what = "某个我还没去过的地方"
	if target == null:
		_say("我：指针在原地打转。")
		return
	var t: Vector2 = target
	var rel := wrapf(atan2(t.y - me.y, t.x - me.x) - float(_c.get("ang", 0.0)), -PI, PI)
	var dirs := ["正前方", "右前方", "右边", "右后方", "正后方", "左后方", "左边", "左前方"]
	var k := posmod(roundi(rel / (PI / 4.0)), 8)
	_toast("罗盘 → %s · 约 %d 米" % [dirs[k], roundi(me.distance_to(t) * CampusGeometry.U2M)])
	_say("我：指针在抖，最后停在%s——%s。" % [dirs[k], what])


## story.js spotMark from where the player stands (indoors by building, outdoors by the map rects).
func spot_tick() -> void:
	var scene := String(_c.get("scene", ""))
	if scene == "out":
		var m := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0))) / 2.0
		for sp: Array in SPOTS:
			if sp[0] == "stall" or spots.has(sp[0]):
				continue
			if m.x > float(sp[2]) and m.x < float(sp[2]) + float(sp[4]) and m.y > float(sp[3]) and m.y < float(sp[3]) + float(sp[5]):
				spots[sp[0]] = true
	elif _rooms.has(scene):
		var host := String(_rooms[scene].get("host", ""))
		for id: String in SPOT_ROOM.get(host, []):
			spots[id] = true


## story.js IDEAS (the public ones): escape ideas unlocked by the places the player has marked.
const IDEAS := [["key", "拿那串车钥匙", "guard", "car"], ["car", "开车走", "garage", "car"], ["white", "走闸机白名单", "data", "face"],
	["bin", "钻进第三个垃圾桶", "trash", "trash"], ["front", "从正门走", "front", "trap_out"], ["climb", "翻墙", "climb", "trap_wall"],
	["beg", "去东围墙等一个路过的人", "wall", "trap_beg"], ["portal", "在物理实验室造一扇门", "portal", "portal"]]


func ideas() -> Array:
	return IDEAS.filter(func(it: Array) -> bool: return spots.has(it[2]))


## Open the ideas list (the H panel) as a choice.
func think() -> void:
	var list := ideas()
	if list.is_empty():
		_say("我：还没有头绪。先去看看学校里有什么。")
		return
	_pending = {"kind": "idea", "ids": list.map(func(it: Array) -> String: return it[0])}
	_emit("choice", {"text": "逃生思路（只是想法，不保证可行）", "labels": list.map(func(it: Array) -> String: return it[1])})


func _trap_where(route: String) -> String:
	var scene := String(_c.get("scene", ""))
	var m := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0))) / 2.0
	var out := scene == "out"
	if route == "trap_out":
		var gn: Dictionary = _c.get("gate_n_map", {"x": 514, "y": 95})
		return "" if out and m.distance_to(Vector2(float(gn["x"]), float(gn["y"]))) < 60.0 else "我：正门在北边。要走，得先走到北门的闸机前面。"
	if route == "trap_wall":
		for sp: Array in SPOTS:
			if sp[0] == "climb":
				var inside: bool = m.x > float(sp[2]) - 20.0 and m.x < float(sp[2]) + float(sp[4]) + 20.0 and m.y > float(sp[3]) - 20.0 and m.y < float(sp[3]) + float(sp[5]) + 20.0
				return "" if out and inside else "我：得先到车棚后面那段矮墙（攀爬点）去。"
	return "" if out and m.x > float(_c.get("bound_x1", 830.0)) - 70.0 else "我：得先走到东边的围墙底下。"


func _choose_idea(id: String) -> void:
	for it: Array in IDEAS:
		if it[0] != id:
			continue
		var route := String(it[3])
		if route.begins_with("trap_"):
			var where := _trap_where(route)
			if where != "":
				_say(where)
				return
			_pending = {"kind": "trap", "route": route}
			_emit("choice", {"text": "「%s」——真的要这么做吗？" % it[1], "labels": ["再想想", "就这么办"]})
			return
		match route:
			"car":
				if not _has("key"):
					_say("我：我没有钥匙。")
				elif String(_c.get("scene", "")) != "garage1":
					_say("我：得先下到车库去。")
				else:
					_say("我：牌号对得上的那两辆，油表不是零。")
			"face", "trash":
				_emit("route_hint", {"route": route})
			"portal":
				_say("我：%s" % ("门还在物理实验室的实验台前面。" if bool(portal["open"]) else ("图纸分散在实验楼二、四、五楼的教师台。" if bool(portal["diary"]) and not bool(portal["sketch"]) else ("物理实验室的实验台后面似乎有条隧道。" if not bool(portal["sketch"]) else "还差" + portal_need_text().strip_edges()))))


## Marked spots for the map list, in table order.
func spot_rows() -> Array:
	var out: Array = []
	for sp: Array in SPOTS:
		if sp[0] == "portal" and not spots.has("portal"):
			continue
		out.append({"name": sp[1], "on": spots.has(sp[0])})
	return out


# ---- the portal (portal.js) ----

func blueprint_count() -> int:
	return BLUEPRINT_FLOORS.filter(func(f: int) -> bool: return (portal["blueprints"] as Dictionary).has(f)).size()


func portal_missing() -> Array:
	return PORTAL_PARTS.filter(func(k: String) -> bool: return not _has(k))


func portal_need_text() -> String:
	if bool(portal["diary"]) and not bool(portal["sketch"]):
		return "　图纸还差 %d 张，在实验楼二、四、五楼的教师台。" % (BLUEPRINT_FLOORS.size() - blueprint_count())
	if not bool(portal["sketch"]):
		return ""
	if bool(portal["open"]):
		return "　门已经打开，回物理实验室的实验台。"
	var m := portal_missing()
	return "　还差：" + "".join(m.map(func(k: String) -> String: return "「%s」" % _name(k))) if not m.is_empty() else "　东西齐了，回物理实验室的实验台。"


func _bench() -> void:
	if bool(portal["open"]):
		_ask_walk("那个圈还在实验台前面。")
		return
	if not bool(portal["sketch"]):
		_pending = {"kind": "tunnel"}
		_emit("choice", {"text": "实验台后的隧道还在。图纸找到 %d / 3 张。" % blueprint_count() if bool(portal["diary"]) else "实验台后有一条覆着黑色黏液的狭窄隧道。", "labels": ["进入隧道", "先离开"]})
		return
	var m := portal_missing()
	if not m.is_empty():
		_say("我：草图上的四样，我还差%s。" % "".join(m.map(func(k: String) -> String: return "「%s」" % _name(k))))
		return
	_pending = {"kind": "assemble"}
	_emit("choice", {"text": "四样东西摆在实验台上。线圈在发烫，试剂在发光。", "labels": ["把它们接起来", "先不"]})


func _ask_walk(text: String) -> void:
	_pending = {"kind": "walk"}
	_emit("choice", {"text": text, "labels": ["走进去", "再等一下"]})


## PortalExploration.enter: the tunnel behind the bench (not during an anomaly, a chase or a check).
func _enter_tunnel() -> void:
	if String(_c.get("scene", "")) != "lab1":
		return
	if bool(_c.get("busy", false)):
		_say("我：现在没法进去，先解决眼前的事。")
		return
	portal["ret"] = {"x": float(_c.get("x", 0.0)), "y": float(_c.get("y", 0.0)), "ang": float(_c.get("ang", 0.0))}
	var t: Dictionary = _rooms.get("portal_tunnel", {})
	if t.is_empty():
		return
	_emit("travel", {"world": "portal_tunnel", "x": float(t["ox"]) + 3.5 * float(t["tw"]), "y": float(t["oy"]) + 21.5 * float(t["th"]), "ang": -PI * 0.5})


func _leave_tunnel(row: int) -> void:
	if String(_c.get("scene", "")) != "portal_tunnel":
		return
	var an: Dictionary = _c.get("anomaly", {})
	if bool(an.get("active", false)):
		_say("我：现在打不开门。")
		return
	if row == 0:
		portal["base_seen"] = true
		_say("我：门后是物理实验室的实验台。那是装置的基座。")
	var ret: Variant = portal.get("ret")
	if ret is Dictionary:
		_emit("travel", {"world": "lab1", "x": float(ret["x"]), "y": float(ret["y"]), "ang": float(ret["ang"])})
	else:
		_emit("travel", {"world": "lab1"})


func _read_diary() -> void:
	if String(_c.get("scene", "")) != "portal_tunnel":
		return
	if not bool(portal["diary"]):
		_emit("clue", {"id": "portalDiary"})
	_record("portalDiary", "前人的日记：图纸在实验楼二、四、五楼教师台，基座在一楼。页边写着：「名单把我认回来了，却没有告诉我墙外是什么。」", "事实", "隧道日记")
	portal["diary"] = true
	spots["portal"] = true
	_say("我：日记里写着：「我把造门的图纸分开放在实验楼二楼、四楼和五楼的教师台。基座留在物理实验室。」")
	_emit("save")


func _collect_blueprint(room: Dictionary) -> bool:
	var floor_n := int(room.get("floor", 0))
	if room.get("host") != "lab" or not bool(portal["diary"]) or bool(portal["sketch"]) or not BLUEPRINT_FLOORS.has(floor_n):
		return false
	if (portal["blueprints"] as Dictionary).has(floor_n):
		return false
	_challenge(floor_n)
	return true


func _challenge(floor_n: int) -> void:
	var task: Dictionary = OBSERVATIONS[floor_n]
	var step := clampi(int((portal["work"] as Dictionary).get(floor_n, 0)), 0, 2)
	var labels: Array = (task["options"] as Array).duplicate()
	labels.append("放下，稍后再看")
	_pending = {"kind": "blueprint", "floor": floor_n, "step": step}
	_emit("choice", {"text": String(task["text"]) + ("（已正确操作 %d/3 步）" % step if task.has("order") else ""), "labels": labels})


func _award(floor_n: int) -> void:
	if (portal["blueprints"] as Dictionary).has(floor_n):
		return
	portal["blueprints"][floor_n] = true
	var lab: Dictionary = _rooms.get(String(_c.get("scene", "")), {})
	_record("blueprint:%d" % floor_n, String(OBSERVATIONS[floor_n]["note"]), "验证", "%s · 教师台" % String(lab.get("name", "实验楼")))
	if blueprint_count() == BLUEPRINT_FLOORS.size():
		portal["sketch"] = true
		spots["portal"] = true
		_emit("clue", {"id": "portal"})
		_say("我：三张图纸拼在一起：铜线圈、透镜、荧光试剂和电池，接到物理实验室的基座上。")
	else:
		_say("我：教师台夹着一张造门图纸。已经找到 %d / %d 张。" % [blueprint_count(), BLUEPRINT_FLOORS.size()])
	_emit("save")


## The open choice was answered (index -1: dismissed).
func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	match String(p.get("kind", "")):
		"tunnel":
			if index == 0:
				_enter_tunnel()
		"meal":
			if index == 0 and _has("coin"):
				_remove("coin")
				_san(24.0)
				_emit("stamina", {"amount": 30.0})
				_emit("advance", {"minutes": 10.0})
				_say("我：硬币落进铁盒子里，响了很久。饭是热的——这里第一次有热的东西。")
				_toast("吃过热饭了")
		"assemble":
			if index == 0 and portal_missing().is_empty():
				for k: String in PORTAL_PARTS:
					_remove(k)
				portal["open"] = true
				_emit("bell")
				_say("我：电池一接上，透镜里的光就漏了出来，在实验台前面撑开一个圈。圈里面——是有颜色的。")
				_emit("later", {"seconds": 2.6, "what": "portal_ask"})
		"walk":
			if index == 0:
				_emit("ending", {"id": "portal"})
			elif index >= 0:
				_say("我：圈还在。它不会等太久。")
		"idea":
			if index >= 0 and index < (p["ids"] as Array).size():
				_choose_idea(String(p["ids"][index]))
		"trap":
			if index == 1:
				match String(p["route"]):
					"trap_out":
						_emit("kill", {"msg": "你从门缝里挤了出去。外面是一条很长的马路，路尽头有一扇校门。你走进去——衣服上还有雨，教学楼里，铃刚刚响。", "fx": "slit", "source": "trap_out"})
					"trap_wall":
						_emit("kill", {"msg": "你翻上了墙头。墙外面还有一道墙。再外面，还有一道。你一直翻，翻到手指不再是手指的形状。", "fx": "squeeze", "source": "trap_wall"})
					_:
						_emit("kill", {"msg": "路过的那个人停了下来。他慢慢转过头——他没有脸，只有一个很大的、在笑的洞。然后他从墙里直接走了进来。", "fx": "face", "source": "trap_beg"})
		"blueprint":
			var floor_n := int(p["floor"])
			var task: Dictionary = OBSERVATIONS[floor_n]
			if index < 0 or index >= (task["options"] as Array).size() or (portal["blueprints"] as Dictionary).has(floor_n):
				_emit("save")
				return
			var step := int(p["step"])
			var right: int = int(task["order"][step]) if task.has("order") else int(task["answer"])
			if index == right:
				if task.has("order") and step < 2:
					portal["work"][floor_n] = step + 1
					_emit("save")
					_challenge(floor_n)
					return
				_award(floor_n)
				return
			portal["work"][floor_n] = 0
			_say("我：%s可以再看一次记录。" % String(task.get("why", "顺序不对。标签要求先线圈、再透镜，最后通电。")))
			_emit("save")


## The delayed question after the door opened (Lifecycle timeout 2.6 s), only if still in lab1 and free.
func portal_ask() -> void:
	if bool(portal["open"]) and String(_c.get("scene", "")) == "lab1":
		_ask_walk("那个圈在等我。")
