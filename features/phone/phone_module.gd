class_name PhoneModule
extends FeatureModule
## The phone, the school network and the 《网安仙人》 route, ported from the Web version (reference
## wd-fz.github.io@0bf508a): modules/phone-network/network.js (Mechanics run seed and attempt,
## PhoneNetwork device / connection / wireless / download, WhitelistSync from the phone, Termination),
## modules/cyber-route/terminal-ui.js (the lab3 computer menu and the terminal) with
## domain/phone-energy.js (PhoneEnergy) and domain/campus-terminal.js (CampusTerminal).
## The paper-plane game and the camera app are not ported. Context in, events out.

const STATE_VERSION := 1
const SURVIVE := 600.0
const CONNECT_REACH := 26.0

var run_seed := ""
var attempt_id := 1
var device: Dictionary = {}
var connection: Variant = null      # {x, y} of the lab3 computer
var puzzle: Dictionary = {}
var termination: Dictionary = {}
var terminal_open := false
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _c: Dictionary = {}


func module_id() -> StringName:
	return &"phone.network"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	device = PhoneEnergy.fresh()
	connection = null
	attempt_id = 1
	if run_seed == "":
		run_seed = CampusTerminal.base36(_rng.randi())
	puzzle = CampusTerminal.fresh(run_seed, attempt_id)
	termination = {"status": "idle", "requestId": null, "remaining": 0.0}
	terminal_open = false
	events = []


func set_seed(value: int) -> void:
	_rng.seed = value
	run_seed = CampusTerminal.base36(int(_rng.randi()))
	puzzle = CampusTerminal.fresh(run_seed, attempt_id)


func capture() -> Dictionary:
	return {"run_seed": run_seed, "attempt_id": attempt_id, "device": device.duplicate(true), "puzzle": puzzle.duplicate(true),
		"termination": termination.duplicate(), "rng": _rng.state}


func validate(data: Dictionary) -> String:
	if not (data.get("run_seed") is String) or String(data["run_seed"]).length() > 64 or not SaveSchema.is_integer(data.get("attempt_id"), 1, 1000000):
		return "手机状态无效"
	if not (data.get("device") is Dictionary) or not (data.get("termination") is Dictionary):
		return "手机状态无效"
	var t: Dictionary = data["termination"]
	if t.get("status") == "accepted":
		if t.get("requestId") != "%s:%d:shutdown" % [data["run_seed"], int(data["attempt_id"])] or not SaveSchema.number_in(t.get("remaining"), 0, SURVIVE):
			return "非法停机请求"
	return ""


func restore(data: Dictionary) -> void:
	run_seed = String(data["run_seed"])
	attempt_id = int(data["attempt_id"])
	var d := PhoneEnergy.fresh()
	var src: Dictionary = data["device"]
	d["initialized"] = bool(src.get("initialized", false))
	d["battery"] = clampf(float(src.get("battery", 0.0)), 0.0, 100.0)
	d["powered"] = bool(src.get("powered", false))
	d["warn20"] = bool(src.get("warn20", false))
	d["warn5"] = bool(src.get("warn5", false))
	for k: String in ["wireless", "download"]:
		var q: Variant = src.get(k)
		if q is Dictionary and q.get("status") in ["idle", "running", "paused", "complete"]:
			var target := 60.0 if k == "download" else clampf(float(q.get("target", 0.0)), 0.0, 600.0)
			if k == "download" or target >= 180.0:
				d[k] = {"status": q["status"], "target": target, "elapsed": clampf(float(q.get("elapsed", 0.0)), 0.0, target)}
				if d[k]["status"] == "complete" and float(d[k]["elapsed"]) < target:
					d[k]["status"] = "paused"
	d["network"] = bool(src.get("network", false)) and d["wireless"]["status"] == "complete"
	if not bool(d["network"]):
		d["download"] = {"status": "idle", "elapsed": 0.0, "target": 60.0}
	device = d
	connection = null
	puzzle = (data["puzzle"] as Dictionary).duplicate(true) if data.get("puzzle") is Dictionary and data["puzzle"].get("runSeed") == run_seed else CampusTerminal.fresh(run_seed, attempt_id)
	termination = {"status": "idle", "requestId": null, "remaining": 0.0}
	var t: Dictionary = data["termination"]
	if t.get("status") == "accepted":
		termination = {"status": "accepted", "requestId": t["requestId"], "remaining": float(t["remaining"])}
	if data.get("rng") is float or data.get("rng") is int:
		_rng.state = int(data["rng"])
	terminal_open = false


## ctx: held (has the phone), classroom (in the own classroom), scene, x, y, dead.
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


func _toast(text: String) -> void:
	_emit("toast", {"text": text})


func acquire() -> void:
	if bool(_c.get("held", false)) and not bool(device["initialized"]):
		device["initialized"] = true
		device["deviceId"] = run_seed + ":phone"


func available() -> bool:
	acquire()
	return bool(_c.get("held", false)) and bool(device["initialized"]) and bool(device["powered"]) and float(device["battery"]) > 0.0


func connected_computer() -> bool:
	if connection is Dictionary:
		var here := Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))
		if String(_c.get("scene", "")) != "lab3" or not bool(_c.get("held", false)) or here.distance_to(Vector2(float(connection["x"]), float(connection["y"]))) > CONNECT_REACH:
			connection = null
	return connection != null


func connect_at(x: float, y: float) -> bool:
	if not bool(_c.get("held", false)):
		_toast("需要一部手机")
		return false
	if String(_c.get("scene", "")) != "lab3":
		return false
	acquire()
	connection = {"x": x, "y": y}
	_toast("手机已接入电脑 · 离开附近会自动断开")
	return true


func disconnect_phone() -> void:
	connection = null
	terminal_open = false
	_toast("手机已断开")


func toggle_wireless() -> void:
	if not available():
		return
	var w: Dictionary = device["wireless"]
	if w["status"] == "complete":
		return
	if w["status"] == "running":
		w["status"] = "paused"
	else:
		if w["status"] == "idle":
			w["target"] = 180.0 + _rng.randf() * 420.0
			w["elapsed"] = 0.0
		w["status"] = "running"
	_emit("save")


func toggle_download() -> void:
	if not available() or not bool(device["network"]):
		return
	var t: Dictionary = device["download"]
	if t["status"] != "running" and t["status"] != "paused":
		return
	t["status"] = "paused" if t["status"] == "running" else "running"
	_emit("save")


func tick(dt: float) -> void:
	if not (dt > 0.0):
		return
	acquire()
	var held := bool(_c.get("held", false))
	var computer := held and connected_computer()
	for e: String in PhoneEnergy.advance(device, dt, {"held": held, "tech": bool(_c.get("tech", false)), "classroom": held and bool(_c.get("classroom", false)), "computer": computer}):
		match e:
			"wirelessSignal":
				_emit("reveal")
				_toast("无线破解暴露了当前位置 · 巡察者正在调查，尽快转移")
			"connected":
				_toast("手机：无线接入成功，开始安装容器")
			"downloaded":
				_toast("手机：容器已就绪，可连接机房电脑")
			"low20":
				_toast("手机电量不足 20%")
			"low5":
				_toast("手机电量不足 5%")
			"off":
				terminal_open = false
				_toast("手机电量耗尽")
			"on":
				_toast("手机已恢复开机")
	if termination["status"] == "accepted":
		termination["remaining"] = maxf(0.0, float(termination["remaining"]) - dt)
		if float(termination["remaining"]) <= 1e-7 and not bool(_c.get("dead", false)):
			termination["status"] = "completed"
			termination["remaining"] = 0.0
			terminal_open = false
			_emit("ending", {"id": "cyber"})
	if terminal_open and (not available() or not connected_computer()):
		terminal_open = false


## Status line of the phone (the phone shell header).
func status_text() -> String:
	if not bool(_c.get("held", false)):
		return "没有手机"
	acquire()
	var w: Dictionary = device["wireless"]
	var d: Dictionary = device["download"]
	var wl: String = {"idle": "未开始", "running": "破解中 %d%%" % roundi(float(w["elapsed"]) / maxf(1.0, float(w["target"])) * 100.0), "paused": "已暂停", "complete": "已接入"}[w["status"]]
	var dl: String = {"idle": "未开始", "running": "下载中 %d%%" % roundi(float(d["elapsed"]) / 60.0 * 100.0), "paused": "已暂停", "complete": "已就绪"}[d["status"]]
	var tail := " · 服务器剩余 %d 秒" % ceili(float(termination["remaining"])) if termination["status"] == "accepted" else ""
	return "电量 %d%%%s · 无线 %s · 容器 %s%s" % [floori(float(device["battery"])), "" if bool(device["powered"]) else "（关机）", wl, dl, tail]


## The phone apps as one choice (PHONE.selectApp).
func phone_menu() -> void:
	if not available():
		_toast("手机已断电 · 充到 5% 后自动开机" if bool(_c.get("held", false)) else "没有手机")
		return
	var w: Dictionary = device["wireless"]
	var d: Dictionary = device["download"]
	_emit("choice", {"menu": "phone", "text": "校园手机\n" + status_text(), "labels": [
		"无线接入 · " + ("已完成" if w["status"] == "complete" else ("暂停破解" if w["status"] == "running" else "开始破解")),
		"巡察查询", "门禁同步", "容器 · " + ("已就绪" if d["status"] == "complete" else ("暂停下载" if d["status"] == "running" else ("继续下载" if d["status"] == "paused" else "等待网络"))), "收起手机"]})


func phone_choose(index: int) -> void:
	match index:
		0:
			toggle_wireless()
		1:
			_emit("location")
		2:
			if not available() or not bool(device["network"]):
				_toast("手机需要电量与学校网络连接")
			else:
				_emit("sync")
		3:
			toggle_download()


## The lab3 computer (PhoneNetwork.computerMenu).
func computer_menu(x: float, y: float) -> void:
	_emit("choice", {"menu": "computer", "x": x, "y": y, "text": "机房电脑", "labels": ["玩贪吃蛇", "连接手机", "打开服务器终端", "断开手机"]})


func computer_choose(index: int, x: float, y: float) -> void:
	match index:
		0:
			_emit("rest_pc")
		1:
			connect_at(x, y)
		2:
			open_terminal(x, y)
		3:
			disconnect_phone()


func open_terminal(x: float, y: float) -> bool:
	if not connected_computer():
		connect_at(x, y)
	if not connected_computer():
		_toast("请先在机房电脑旁连接手机")
		return false
	if not available() or not bool(device["network"]) or device["download"]["status"] != "complete":
		_toast("需要手机有电、接入网络并完成容器下载")
		return false
	terminal_open = true
	if (puzzle["history"] as Array).is_empty():
		puzzle["history"].append("模拟维护环境已连接。输入 help 或 cat /school/README。")
	_emit("terminal")
	return true


## One line in the terminal (TerminalUI.execute). Returns the printed result.
func run_line(line: String) -> String:
	if not terminal_open:
		return ""
	if not available() or not connected_computer():
		terminal_open = false
		return ""
	if line.strip_edges() == "":
		return ""
	var result := CampusTerminal.run(puzzle, line)
	if result.get("request") == "shutdown" and not _submit():
		result = {"text": "请求未被接受，请重新校验。", "error": true}
	puzzle["history"].append("%s $ %s" % [puzzle["cwd"], line])
	puzzle["history"].append(String(result["text"]))
	puzzle["history"] = (puzzle["history"] as Array).slice(-40)
	_emit("save")
	return String(result["text"])


func _submit() -> bool:
	if termination["status"] == "accepted":
		return true
	if termination["status"] != "idle" or puzzle["validated"] == null:
		return false
	var id := "%s:%d:shutdown" % [run_seed, attempt_id]
	termination = {"status": "accepted", "requestId": id, "remaining": SURVIVE}
	puzzle["acceptedRequestId"] = id
	return true


## Mechanics.dream: a dream wake is a new attempt; the device and the puzzle start over.
func dream() -> void:
	attempt_id += 1
	device = PhoneEnergy.fresh()
	connection = null
	terminal_open = false
	acquire()
	puzzle = CampusTerminal.fresh(run_seed, attempt_id)
	termination = {"status": "idle", "requestId": null, "remaining": 0.0}
