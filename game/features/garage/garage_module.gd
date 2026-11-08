class_name GarageModule
extends FeatureModule
## The garage and the car route, ported from the Web version (reference wd-fz.github.io@0bf508a):
## systems.js ROAM / roamTick / roamGuardsCar / roamLit (the thing in the driveway), items.js
## throwCoin (the coin lure), story.js carRightCell / useCar / carDrive, investigation.js carName /
## inspectCar, car-chase.js (start / fail / tick) with domain/car-chase.js in CarChaseRules.
## Context in, events out (notice / toast / san / kill / choice / step / drive / ending); the app applies them.
## Talents (hot-wiring without a key) are not ported: only the key starts a car.

const STATE_VERSION := 1
const LIT_NEED := 1.6
const REACH := 26.0
const GUARD_CAR := 200.0
const KEY_SEC := 1.6
const JOB_SLIP := 5.0
const ROOM := "garage1"

var roam: Dictionary = {}
var lure: Variant = null          # {x, y, t}
var car_right := ""               # "c:r", picked once per run
var car_tried: Dictionary = {}
var car_used := false
var chase: Variant = null         # CarChaseRules state while driving
var job: Variant = null           # {cell, x, y, t, dur}
var events: Array = []

var _room: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _c: Dictionary = {}
var _pending: Dictionary = {}


func _init(garage_room: Dictionary = {}) -> void:
	_room = garage_room


func module_id() -> StringName:
	return &"garage.world"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	roam = _fresh_roam()
	lure = null
	car_right = ""
	car_tried = {}
	car_used = false
	chase = null
	job = null
	events = []
	_pending = {}


func set_seed(value: int) -> void:
	_rng.seed = value


func _fresh_roam() -> Dictionary:
	return {"on": false, "x": 0.0, "y": 0.0, "cd": 0.0, "seen": false, "litAcc": 0.0, "stage": "approach", "waitT": 0.0,
		"lureTold": false, "toldSpot": false, "goneTold": false, "backTold": false}


func capture() -> Dictionary:
	return {"roam": roam.duplicate(), "lure": lure, "car_right": car_right, "car_tried": car_tried.duplicate(), "car_used": car_used,
		"chase": (chase as Dictionary).duplicate() if chase != null else null, "seed": _rng.seed, "rng": _rng.state}


func validate(data: Dictionary) -> String:
	if not (data.get("roam") is Dictionary) or not (data.get("car_tried") is Dictionary) or not (data.get("car_used") is bool):
		return "车库状态无效"
	if not (data.get("car_right") is String):
		return "车库状态无效"
	var right := String(data["car_right"])
	if right != "" and not _cars().has(right):
		return "车库状态无效：车位不存在"
	var ch: Variant = data.get("chase")
	if ch != null:
		if not (ch is Dictionary) or not SaveSchema.number_in(ch.get("distance"), 0, CarChaseRules.DISTANCE + 50.0) or not SaveSchema.is_integer(ch.get("hp"), 0, 3):
			return "驾驶状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	roam = _fresh_roam()
	for k: String in roam:
		if (data["roam"] as Dictionary).has(k):
			roam[k] = data["roam"][k]
	lure = data.get("lure") if data.get("lure") is Dictionary else null
	car_right = String(data["car_right"])
	car_tried = (data["car_tried"] as Dictionary).duplicate()
	car_used = bool(data["car_used"])
	chase = (data["chase"] as Dictionary).duplicate() if data.get("chase") is Dictionary else null
	if data.get("seed") is float or data.get("seed") is int:
		_rng.seed = int(data["seed"])
	if data.get("rng") is float or data.get("rng") is int:
		_rng.state = int(data["rng"])


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


func _here() -> Vector2:
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0)))


func _rnd(a: float, b: float) -> float:
	return a + _rng.randf() * (b - a)


# ---- cars ----

func _cars() -> Array:
	var out: Array = []
	if _room.is_empty():
		return out
	var grid: Array = _room["grid"]
	for r in grid.size():
		for c in String(grid[r]).length():
			if String(grid[r]).substr(c, 1) == "V":
				out.append("%d:%d" % [c, r])
	return out


## story.js carRightCell: one of the far half of the cars (the entrance is at the east end).
func car_right_cell() -> String:
	if car_right != "":
		return car_right
	var cars := _cars()
	cars.sort_custom(func(a: String, b: String) -> bool: return int(a.split(":")[0]) < int(b.split(":")[0]) or (int(a.split(":")[0]) == int(b.split(":")[0]) and int(a.split(":")[1]) < int(b.split(":")[1])))
	var far := cars.slice(0, maxi(1, cars.size() / 2))
	car_right = String(far[int(floor(_rng.randf() * far.size()))])
	return car_right


## investigation.js carName: 鄂A· + letter + four digits from the cell.
static func car_name(c: int, r: int) -> String:
	return "鄂A·" + "DFHKM".substr((c + r) % 5, 1) + str(3100 + c * 31 + r)


func car_hint(c: int, r: int) -> String:
	return car_name(c, r) + (" · 已试，不匹配" if car_tried.has("%d:%d" % [c, r]) else " · 查看车辆")


## The key's ring names the plate of the right car (items.js 'key' use / Investigation.carKey).
func key_label() -> String:
	var cell := car_right_cell().split(":")
	return car_name(int(cell[0]), int(cell[1]))


## investigation.js inspectCar: a choice between trying the key and stepping back.
func inspect_car(c: int, r: int) -> void:
	var tried := car_tried.has("%d:%d" % [c, r])
	_emit("record", {"id": "vehicle:%d:%d" % [c, r], "text": car_name(c, r) + ("：钥匙不匹配。" if tried else "：已看清车牌，尚未验证钥匙。"),
		"kind": "验证" if tried else "事实", "source": "车库 · 第 %d 排" % (r + 1)})
	_pending = {"kind": "car", "c": c, "r": r}
	_emit("choice", {"text": car_name(c, r) + ("，这辆已经试过，钥匙不匹配。" if tried else "。车窗上倒映着身后的车道。"),
		"labels": ["试钥匙 / 接线（原地 1.6 秒）", "退开观察车道"]})


func choose(index: int) -> void:
	var p := _pending
	_pending = {}
	if p.get("kind") == "car" and index == 0:
		use_car(int(p["c"]), int(p["r"]))


## The thing is still in the driveway and close: opening a door now is fatal.
func guards_car() -> bool:
	return bool(roam["on"]) and roam["stage"] == "approach" and _here().distance_to(Vector2(float(roam["x"]), float(roam["y"]))) < GUARD_CAR


## story.js useCar.
func use_car(c: int, r: int) -> void:
	var via := "key" if bool(_c.get("has_key", false)) else ("hotwire" if bool(_c.get("hotwire", false)) else "")
	if via == "":
		_say("我：车门锁着。")
		return
	if car_used:
		_say("我：已经开过一辆了。")
		return
	if guards_car():
		_emit("kill", {"msg": "你拉开车门，钻进去，摸到钥匙孔。后视镜里，它就站在后座上，弯着腰，脸贴着车顶。", "fx": "grip", "source": "car_entry"})
		return
	var cell := "%d:%d" % [c, r]
	if car_tried.has(cell):
		_say("我：这辆试过了。不是它。")
		return
	if job != null:
		return
	var me := _here()
	var wire := via == "hotwire"
	job = {"cell": cell, "x": me.x, "y": me.y, "t": 0.0, "dur": TalentModule.HOTWIRE_SEC if wire else KEY_SEC, "wire": wire}
	_say("我：我弯下腰去摸方向盘底下的线……这要一会儿。" if wire else "我：我把钥匙插进锁孔，慢慢地拧……")


func job_progress() -> float:
	return clampf(float(job["t"]) / float(job["dur"]), 0.0, 1.0) if job != null else 0.0


func _job_tick(dt: float) -> void:
	if job == null:
		return
	var j: Dictionary = job
	if bool(_c.get("dead", false)) or String(_c.get("scene", "")) != ROOM or _here().distance_to(Vector2(float(j["x"]), float(j["y"]))) > JOB_SLIP:
		job = null
		_say("我：手一松，钥匙从锁孔里滑了出来。")
		return
	j["t"] = float(j["t"]) + dt
	if float(j["t"]) < float(j["dur"]):
		return
	job = null
	var wired := bool(j.get("wire", false))
	if guards_car():
		_emit("kill", {"msg": "我还蹲在方向盘底下捏着两根线，车窗上就贴上来一张脸。" if wired else "钥匙还插在锁孔里，车窗上就贴上来一张脸。", "fx": "grip", "source": "car_entry"})
		return
	var cell := String(j["cell"])
	if cell != car_right_cell():
		car_tried[cell] = true
		var tc := cell.split(":")
		_emit("record", {"id": "vehicle:" + cell, "text": car_name(int(tc[0]), int(tc[1])) + ("：已试，搭线打不着。" if wired else "：已试，钥匙不匹配。"), "kind": "验证", "source": "车库"})
		var lines := ["我：线碰上了，仪表盘一点反应都没有。不是这辆。", "我：电瓶是死的。下一辆。", "我：火花跳了一下就没了。不是它。"] if wired else ["我：钥匙插进去，拧不动。不是这辆。", "我：锁孔是对的，钥匙齿不对。下一辆。", "我：车门开了一条缝，又自己合上了。不是它。"]
		_say("%s（试过 %d 辆）" % [lines[_rng.randi() % lines.size()], car_tried.size()])
		_emit("save")
		return
	_drive()


## story.js carDrive.
func _drive() -> void:
	if bool(_c.get("busy", false)):
		_say("我：现在走不开，先解决眼前的事。")
		return
	_emit("fact", {"what": "drive", "tried": car_tried.size()})
	_say("我：引擎着了。车往前冲了出去。")
	start_chase()


# ---- the driveway (systems.js roamTick) ----

func _blocked(p: Vector2) -> bool:
	var can: Callable = _c.get("can_stand", Callable())
	return can.is_valid() and not bool(can.call(p))


func _move(dx: float, dy: float) -> void:
	var n := maxi(1, int(ceil(Vector2(dx, dy).length() / 1.25)))
	dx /= n
	dy /= n
	for _i in n:
		if not _blocked(Vector2(float(roam["x"]) + dx, float(roam["y"]))):
			roam["x"] = float(roam["x"]) + dx
		if not _blocked(Vector2(float(roam["x"]), float(roam["y"]) + dy)):
			roam["y"] = float(roam["y"]) + dy


func _reset_roam() -> void:
	roam = _fresh_roam()
	roam["x"] = float(_room["ox"]) + float(_room["cols"]) * float(_room["tw"]) * 0.42
	roam["y"] = float(_room["oy"]) + float(_room["rows"]) * float(_room["th"]) * 0.5
	roam["cd"] = 6.5
	roam["on"] = true


func lit() -> bool:
	if not bool(_c.get("torch", false)):
		return false
	var d := Vector2(float(roam["x"]), float(roam["y"])) - _here()
	if d.length_squared() > 260.0 * 260.0:
		return false
	return CampusGeometry.ang_diff(atan2(d.y, d.x), float(_c.get("ang", 0.0))) < PI / 3.0


## Is the thing standing somewhere it can be seen (for the presentation).
func roam_visible() -> bool:
	return bool(roam["on"]) and float(roam["x"]) > -1e5


func tick(dt: float) -> void:
	if not (dt > 0.0):
		return
	_job_tick(dt)
	if chase != null:
		return
	if String(_c.get("scene", "")) != ROOM or _room.is_empty() or bool(_c.get("dead", false)):
		roam["on"] = false
		lure = null
		return
	if not bool(roam["on"]):
		_reset_roam()
	if lure != null:
		lure["t"] = float(lure["t"]) - dt
		if float(lure["t"]) <= 0.0:
			lure = null
	var is_lit := lit()
	roam["litAcc"] = float(roam["litAcc"]) + dt if is_lit else maxf(0.0, float(roam["litAcc"]) - dt * 0.35)
	if float(roam["litAcc"]) >= LIT_NEED:
		_emit("fact", {"what": "torch"})
		roam["litAcc"] = 0.0
		roam["stage"] = "wait"
		roam["waitT"] = _rnd(4.5, 8.0)
		roam["x"] = -1e6
		roam["y"] = -1e6
		if not bool(roam["goneTold"]):
			roam["goneTold"] = true
			_say("我：光扫过去，它就没了。")
		return
	if roam["stage"] == "wait":
		if is_lit:
			roam["waitT"] = 0.0
		roam["waitT"] = float(roam["waitT"]) - dt
		if float(roam["waitT"]) <= 0.0:
			_reappear()
		return
	roam["cd"] = float(roam["cd"]) - dt
	var me := _here()
	var pos := Vector2(float(roam["x"]), float(roam["y"]))
	if is_lit:
		roam["cd"] = maxf(float(roam["cd"]), 0.55)
		var away := (pos - me).normalized() if pos != me else Vector2.RIGHT
		_move(away.x * 13.0 * dt, away.y * 13.0 * dt)
	elif float(roam["cd"]) <= 0.0:
		var near := me.distance_to(pos) < 220.0
		roam["cd"] = _rnd(0.55, 0.95) if bool(_c.get("run", false)) or near else _rnd(0.9, 1.5)
		var target := Vector2(float(lure["x"]), float(lure["y"])) if lure != null else me
		var to := target - pos
		var dl := maxf(to.length(), 0.0001)
		var stride := minf(34.0, dl)
		_move(to.x / dl * stride, to.y / dl * stride)
		_emit("step", {"x": float(roam["x"]), "y": float(roam["y"])})
		if lure != null and not bool(roam["lureTold"]):
			roam["lureTold"] = true
			_say("我：那东西停了一下，脚步朝硬币落地的方向去了。")
	var dist := me.distance_to(Vector2(float(roam["x"]), float(roam["y"])))
	if dist < 150.0:
		_emit("san", {"amount": -1.1 * dt * float(_c.get("drain_mul", 1.0)), "min": 0.0})
		if not bool(roam["seen"]):
			roam["seen"] = true
			_say("我：车道那头有东西。它不是走路的姿势。")
	if dist < 230.0 and not bool(roam["toldSpot"]):
		roam["toldSpot"] = true
		_say("我：车道中间有个高的东西站着。它没在动。")
	if dist < REACH and not is_lit and float(roam["litAcc"]) < LIT_NEED * 0.5 and float(_c.get("enter_cool", 0.0)) <= 0.0:
		_emit("kill", {"msg": "你在黑暗里撞上了它。它很高，很冷，一直站在车道中间，等你自己走过去。", "fx": "grip", "source": "garage"})


func _reappear() -> void:
	var me := _here()
	var ox := float(_room["ox"])
	var oy := float(_room["oy"])
	var w := float(_room["cols"]) * float(_room["tw"])
	var h := float(_room["rows"]) * float(_room["th"])
	var found := false
	var b := Vector2.ZERO
	for _t in 12:
		var a := _rnd(0.0, TAU)
		var far := _rnd(300.0, 460.0)
		b = Vector2(clampf(me.x + cos(a) * far, ox + 24.0, ox + w - 24.0), clampf(me.y + sin(a) * far, oy + 24.0, oy + h - 24.0))
		if b.distance_squared_to(me) > 250.0 * 250.0 and not _blocked(b):
			found = true
			break
	if not found:
		var best := -1.0
		for row in range(1, int(_room["rows"]) - 1):
			for col in range(1, int(_room["cols"]) - 1):
				var p := Vector2(ox + (col + 0.5) * float(_room["tw"]), oy + (row + 0.5) * float(_room["th"]))
				var d := p.distance_squared_to(me)
				if d > best and not _blocked(p):
					best = d
					b = p
					found = true
	if not found:
		roam["waitT"] = 1.0
		return
	roam["x"] = b.x
	roam["y"] = b.y
	roam["stage"] = "approach"
	if not bool(roam["backTold"]):
		roam["backTold"] = true
		_say("我：……后面又有脚步声了。")


## story.js elixir / survival: the thing steps back after a rescue.
func rescued() -> void:
	if bool(roam["on"]):
		roam["stage"] = "wait"
		roam["waitT"] = 8.0
		roam["x"] = -1e6
		roam["y"] = -1e6
		roam["litAcc"] = 0.0


# ---- the coin (items.js throwCoin) ----

## Returns true when the coin was thrown (and must be removed from the bag).
func throw_coin() -> bool:
	if String(_c.get("scene", "")) != ROOM:
		_say("我：要买饭就去打饭窗口，要买东西就去售货机。" if String(_c.get("scene", "")) == "canteen1" else "我：扔在这儿没意义。留着，食堂能用。")
		return false
	var a := float(_c.get("ang", 0.0)) + _rnd(-0.4, 0.4)
	var far := _rnd(60.0, 120.0)
	var me := _here()
	var p := me
	var d := 9.0
	while d <= far:
		var n := me + Vector2(cos(a), sin(a)) * d
		if _blocked(n):
			break
		p = n
		d += 9.0
	lure = {"x": p.x, "y": p.y, "t": 8.0}
	roam["lureTold"] = false
	_say("我：硬币在地上滚了很远。")
	_emit("step", {"x": p.x, "y": p.y})
	return true


# ---- the drive (car-chase.js) ----

func start_chase() -> void:
	car_used = true
	chase = CarChaseRules.new_state()
	roam["on"] = false
	_emit("drive")
	_say("我：按住前进，避开障碍。看清路牌，再选路。")


func driving() -> bool:
	return chase != null


## One driving step. input: {throttle, braking, steering}.
func chase_step(dt: float, input: Dictionary) -> void:
	if chase == null or bool(_c.get("dead", false)):
		return
	var d: Dictionary = chase
	var result := CarChaseRules.step(d, input, dt)
	for e: Dictionary in result["events"]:
		if e["type"] == "hit":
			_emit("toast", {"text": "撞上路障"})
		elif e["type"] == "fork":
			_emit("save")
	if result.has("failure"):
		var f: Dictionary = result["failure"]
		CarChaseRules.reset_to(d, float(f["checkpoint"]))
		_emit("kill", {"msg": f["message"], "fx": "grip", "source": "car_chase"})
		_emit("crash")
		return
	if result.get("won", false):
		chase = null
		_emit("ending", {"id": "car"})


## After a death the run either ends or wakes up: the car and the drive are given back (CarChase.cancel).
func cancel_chase() -> void:
	chase = null
	car_used = false
	job = null
