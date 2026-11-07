class_name CampusModule
extends FeatureModule
## Formal campus rules ported from the Web version (reference wd-fz.github.io@0bf508a):
## door open/close and locks (interact.js, items.js OPENDOORS / DOOR_LOCKS), leaving through
## an exit cell and entering buildings by E (interact.js tryInteract, world.js doEnterRoom /
## doExitRoom / doorWorld), and the seamless campus doors (modules/campus-link/doors.js).
##
## Rules only: the layout dictionaries come in through the constructor (no file access),
## results are returned as plain data and the app performs world switches.

const STATE_VERSION := 1
## interact.js tryInteract: outdoor E entries. Seamless hosts answer "门开着" instead.
const ENTRY_ROOMS := {
	"teach": "teach1", "admin": "admin1", "lab": "lab1", "canteen": "canteen1",
	"dormN": "dorm1", "dormS": "dorm4", "garage": "garage1", "garw": "garage1",
	"trash": "trash1", "guard": "guard1", "gear": "gear1", "bell": "bell1",
}
const OPEN_LINES := ["我：门开了。", "我：门开了。合页的声音拖得很长。", "我：门开了。里面比外面冷。"]
## interact.js TILE_HINT (static texts); tiles without an entry are searched ('翻找').
const TILE_HINT := {"H": "躲进柜子", "Q": "看服务器终端", "S": "沿楼梯行走", "j": "打开门", "u": "翻看日记", "c": "上车",
	"X": "钻进去", "Z": "放开单摆", "C": "开离心机", "N": "看显微镜", "Y": "转地球仪", "p": "弹琴", "U": "撞钟", "A": "看供桌",
	"x": "看挂图", "B": "隔间", "G": "隔间", "w": "洗把脸", "b": "床", "n": "用电脑", "M": "售货机", "k": "看柜台", "t": "看餐桌",
	"V": "看车牌", "D": "使用终端", "K": "看实验台", "L": ""}
const SEARCHABLE := "dfRq"

signal door_changed(key: String, open: bool)

var _rooms: Dictionary = {}
var _outside: Dictionary = {}
var _campus: Dictionary = {}
var _open_doors: Dictionary = {}
var _line := 0
## Plate and tried state for the 'V' hint (the garage module).
var car_hint: Callable
## Facility hints and the outdoor rest (the facilities module).
var facility_hint: Callable
var rest_out: Callable
## Classmates blocking a door (the classmates module).
var door_blocked: Callable
## Whether a desk is occupied by a classmate (no searching it).
var desk_taken: Callable
const FACILITY := "ZCNYKQujxUABGMpbktwn"
## Inventory query (items.js hasItem), wired by the app to the bag module.
var has_item := func(_id: String) -> bool: return false


func _init(rooms: Dictionary = {}, outside: Dictionary = {}, campus: Dictionary = {}) -> void:
	_rooms = rooms
	_outside = outside
	_campus = campus


func module_id() -> StringName:
	return &"campus.world"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	_open_doors.clear()
	_line = 0


func capture() -> Dictionary:
	var keys := _open_doors.keys()
	keys.sort()
	return {"open_doors": keys}


func validate(data: Dictionary) -> String:
	var keys: Variant = data.get("open_doors")
	if not keys is Array:
		return "开门记录无效"
	for key: Variant in keys:
		if not key is String or not _is_door(key):
			return "开门记录引用了不存在的门：%s" % key
	return ""


func restore(data: Dictionary) -> void:
	_open_doors.clear()
	for key: String in data["open_doors"]:
		_open_doors[key] = true


func knows(world_id: String) -> bool:
	return world_id == "out" or _rooms.has(world_id)


func room(world_id: String) -> Variant:
	return _rooms.get(world_id)


func is_open(key: String) -> bool:
	return _open_doors.has(key)


## dreamWake: back at 11:40 every opened door is closed again (OPENDOORS = {}).
## Close one door (the classmates standing in it).
func force_close(key: String) -> void:
	if _open_doors.has(key):
		_open_doors.erase(key)
		door_changed.emit(key, false)


func close_all_doors() -> void:
	for key: String in _open_doors.keys():
		door_changed.emit(key, false)
	_open_doors.clear()


func open_doors() -> Dictionary:
	return _open_doors.duplicate()


func _is_door(key: String) -> bool:
	var parts := key.split(":")
	if parts.size() != 3 or not _rooms.has(parts[0]):
		return false
	for d: Dictionary in _rooms[parts[0]]["doors"]:
		if d["key"] == key:
			return true
	return false


func _campus_doors(room_id: String) -> Array:
	var result: Array = []
	var cfg: Dictionary = _campus.get("campus_doors", {})
	for d: Dictionary in cfg.get("doors", []):
		if room_id.is_empty() or d["room"] == room_id:
			result.append(d)
	return result


func _door_width() -> float:
	return float(_campus.get("campus_doors", {}).get("width", 3))


func _annex() -> float:
	return float(_campus.get("campus_doors", {}).get("annex", 1.5))


func _continuous_host(host: String) -> bool:
	for d: Dictionary in _campus_doors(""):
		if d["host"] == host:
			return true
	return false


## The exported pose of the old start: the player's own seat in teach1, standing up into the aisle
## exactly where world.js leaveSeat puts them (sitting itself is part of the schedule port).
func start_pose() -> Dictionary:
	var start: Dictionary = _rooms[_campus["start_room"]]["start"]["stand"]
	return _pose(Vector2(start["scene_x"], start["scene_z"]), float(start["ang"]))


func start_world() -> String:
	return String(_campus["start_room"])


func default_spawn(room_id: String) -> Dictionary:
	var s: Dictionary = _rooms[room_id]["spawn"]
	var ang: Variant = s.get("ang")
	return _pose(Vector2(s["scene_x"], s["scene_z"]), PI * 0.5 if ang == null else float(ang))


func _pose(scene: Vector2, ang: float, pitch: float = 0.0, height: float = 0.05) -> Dictionary:
	return {"position": [scene.x, height, scene.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": pitch}


func _stair_layout() -> Array:
	return _campus.get("stair_layout", [])


func is_stairwell(world_id: String) -> bool:
	return not CampusPortals.stair_config(_stair_layout(), world_id).is_empty()


## Stairwell metres: the scene coordinates of a stairwell world are its shaft coordinates.
func stair_surfaces(world_id: String) -> Array[Dictionary]:
	var s := CampusPortals.stair_config(_stair_layout(), world_id)
	if s.is_empty():
		return []
	return CampusPortals.stair_surfaces((s["rooms"] as Array).size(), float(s["rise"]))


## Stair doorways in a floor scene (scene metres): centre, lateral axis and half width.
func stair_doorways(world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in _stair_layout():
		var level := (s["rooms"] as Array).find(world_id)
		if level < 0 or world_id == "out":
			continue
		var port := CampusPortals.stair_port(s, level, _rooms, _outside)
		var n: Vector2 = port["n"]
		out.append({"center": CampusGeometry.to_scene(_rooms[world_id], port["p"]), "normal": n, "lateral": Vector2(n.y, -n.x), "half": CampusPortals.DOOR_HALF})
	return out


func link_doorways(world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Dictionary in CampusPortals.link_ports(_campus.get("campus_link", {}), _rooms, world_id):
		var me: Dictionary = v["self"]
		out.append({"edge": _edge_of(me["n"]), "center": CampusGeometry.to_scene(_rooms[world_id], me["p"]), "half": float(me["half"]) * CampusGeometry.U2M,
			"depth": float(_campus["campus_link"].get("annex", 1.5)) * CampusGeometry.TTILE * CampusGeometry.U2M, "normal": me["n"]})
	return out


func _edge_of(n: Vector2) -> String:
	if n.y < 0:
		return "n"
	if n.y > 0:
		return "s"
	return "w" if n.x < 0 else "e"


## Stairwell walk (stairwell.js moved/enter/exit) and corridor bridges (link.js cross).
func _portal_crossing(world_id: String, pose: Dictionary, ang: float) -> Dictionary:
	var p: Array = pose["position"]
	var pitch := float(pose["pitch"])
	var layout := _stair_layout()
	var s := CampusPortals.stair_config(layout, world_id)
	if not s.is_empty():
		var q := Vector2(float(p[0]), float(p[2]))
		var y := float(p[1])
		var rise := float(s["rise"])
		var level := int(round(y / rise))
		if q.y < CampusPortals.EXIT_Z and absf(y - level * rise) < CampusPortals.LEVEL_TOLERANCE and level >= 0 and level < (s["rooms"] as Array).size():
			var port := CampusPortals.stair_port(s, level, _rooms, _outside)
			var w := CampusPortals.from_shaft(port, q)
			var target := String(port["scene"])
			var room_data: Variant = null if target == "out" else _rooms[target]
			return {"world": target, "pose": _pose(CampusGeometry.to_scene(room_data, w), ang + CampusPortals.stair_turn(port["n"]), pitch), "seamless": true}
		return {}
	var room_data2: Variant = null if world_id == "out" else _rooms.get(world_id)
	var me := CampusGeometry.to_world(room_data2, float(p[0]), float(p[2]))
	var a := CampusPortals.stair_portal_at(layout, world_id, me, _rooms, _outside)
	if not a.is_empty() and (a["q"] as Vector2).y > CampusPortals.ENTER_Z:
		var sp: Dictionary = a["s"]
		var q2: Vector2 = a["q"]
		var h := int(a["level"]) * float(sp["rise"])
		return {"world": sp["id"], "pose": _pose(q2, ang - CampusPortals.stair_turn(a["port"]["n"]), pitch, h + 0.05), "seamless": true}
	if world_id == "out":
		return {}
	for v: Dictionary in CampusPortals.link_ports(_campus.get("campus_link", {}), _rooms, world_id):
		var me_port: Dictionary = v["self"]
		var lq := CampusGeometry.door_local(me_port, me)
		if lq.x > 0.0 and absf(lq.y) < float(me_port["half"]):
			var t := CampusPortals.link_between(me_port, v["peer"])
			var dest := CampusPortals.link_apply(t, me)
			var peer_room: Dictionary = _rooms[v["peer"]["room"]]
			return {"world": v["peer"]["room"], "pose": _pose(CampusGeometry.to_scene(peer_room, dest), ang + float(t["phi"]), pitch), "seamless": true}
	return {}


## Seamless door crossing after a movement step (campus-link/doors.js cross()).
## Returns {"world": id, "pose": pose} or an empty dictionary.
func crossing(world_id: String, pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var ang := CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	var portal := _portal_crossing(world_id, pose, ang)
	if not portal.is_empty():
		return portal
	if is_stairwell(world_id):
		return {}
	var inside := world_id != "out"
	var list := _campus_doors(world_id) if inside else _campus_doors("")
	for d: Dictionary in list:
		var r: Dictionary = _rooms[d["room"]]
		var s := CampusGeometry.shift_of(r)
		var port := CampusGeometry.door_port(r, d)
		var me := CampusGeometry.to_world(r if inside else null, float(p[0]), float(p[2]))
		if not inside:
			port["p"] = (port["p"] as Vector2) + s
		var q := CampusGeometry.door_local(port, me)
		if absf(q.y) >= CampusGeometry.door_half(d, _door_width()):
			continue
		if inside and q.x > 0.0:
			return {"world": "out", "pose": _pose(CampusGeometry.to_scene(null, me + s), ang, float(pose["pitch"])), "seamless": true}
		if not inside and q.x < 0.0 and q.x > -_annex() * CampusGeometry.TTILE:
			return {"world": d["room"], "pose": _pose(CampusGeometry.to_scene(r, me - s), ang, float(pose["pitch"])), "seamless": true}
	return {}


## GATE_HINT: the gate within 70 units of a campus position (north, west, south).
func gate_at(w: Vector2) -> String:
	var gates: Dictionary = _campus.get("gates", {})
	for key: String in ["n", "w", "s"]:
		if gates.has(key) and Vector2(float(gates[key]["x"]) * 2.0, float(gates[key]["y"]) * 2.0).distance_to(w) < 70.0:
			return key
	return ""


## Prompt shown for the current spot (subset of interact.js interactHint that is ported).
func hint(world_id: String, pose: Dictionary) -> String:
	var p: Array = pose["position"]
	var ang := CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	if world_id == "out":
		var here_w := CampusGeometry.to_world(null, float(p[0]), float(p[2]))
		var nb := CampusGeometry.near_building(_outside, here_w)
		if nb.is_empty():
			var act := String(rest_out.call(here_w)) if rest_out.is_valid() else ""
			if act != "":
				return FacilitiesModule.rest_hint(act)
			var gate := gate_at(here_w)
			return RoutesModule.gate_name(gate) if gate != "" else ""
		if _continuous_host(nb["obj"]["id"]):
			return ""
		return "沿楼梯下到车库" if nb["obj"]["id"] == "garw" else "进入 " + String(nb["obj"]["name"])
	if is_stairwell(world_id):
		return ""
	var r: Dictionary = _rooms[world_id]
	var hit := CampusGeometry.near_tile(r, CampusGeometry.to_world(r, float(p[0]), float(p[2])), ang, CampusGeometry.NEAR_ROOM, _open_doors)
	if hit.is_empty():
		return ""
	var ch := String(hit["ch"])
	if FACILITY.contains(ch) and facility_hint.is_valid():
		var fh := String(facility_hint.call(r, ch))
		if fh != "":
			return fh
	match ch:
		"=":
			var key := CampusGeometry.door_key(r, hit["c"], hit["r"])
			var locks: Dictionary = _campus.get("door_locks", {})
			if locks.has(key) and not has_item.call(String(locks[key]["item"])):
				return "开门（锁着）"
			return "关门" if is_open(key) else "开门"
		"J":
			return "走向门" if world_id == "lift_dream" else "电梯"
		"P":
			var own: Dictionary = _campus.get("own_seat", {})
			return "坐到自己的座位" if world_id == own.get("room") and int(hit["c"]) == int(own.get("col", -1)) and int(hit["r"]) == int(own.get("row", -1)) else "坐下（非本人座位）"
		"T":
			var podium: Array = _campus.get("own_podium", [])
			if world_id == "teach1" and podium.size() == 2 and int(podium[0]) == int(hit["c"]) and int(podium[1]) == int(hit["r"]):
				return "看移交单"
			return "拿粉笔" if world_id == "teach1" else "看讲台"
		"D":
			return "门禁管理终端" if world_id == "lab3" else "使用终端"
		"K":
			return "看办公桌" if r.get("host") == "admin" else "看实验台"
		"k":
			return "查看值班台" if r.get("host") == "guard" else "看柜台"
		"O":
			return "" if _exit_is_open(r, hit["w"]) else "出去"
		"V":
			return car_hint.call(int(hit["c"]), int(hit["r"])) if car_hint.is_valid() else "看车牌"
	if SEARCHABLE.contains(ch) or not TILE_HINT.has(ch):
		return "翻找"
	return String(TILE_HINT[ch])


func _exit_is_open(r: Dictionary, w: Vector2) -> bool:
	for d: Dictionary in _campus_doors(r["id"]):
		var q := CampusGeometry.door_local(CampusGeometry.door_port(r, d), w)
		if q.x > -CampusGeometry.TTILE and q.x <= 0.0 and absf(q.y) < CampusGeometry.door_half(d, _door_width()):
			return true
	return false


## Press E without a physical interactable in front (interact.js tryInteract, ported branches).
## Returns {"notice": String, "travel": {"world", "pose"}?, "door": {"key", "open"}?}.
func interact_at(world_id: String, pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var ang := CampusGeometry.ang_from_yaw(float(pose["yaw"]))
	if world_id == "out":
		var me := CampusGeometry.to_world(null, float(p[0]), float(p[2]))
		var nb := CampusGeometry.near_building(_outside, me)
		if nb.is_empty():
			var act := String(rest_out.call(me)) if rest_out.is_valid() else ""
			if act != "":
				return {"notice": "", "rest": act}
			var gate := gate_at(me)
			if gate != "":
				return {"notice": "", "gate": gate}
			return {"notice": "我：这里摸不到什么。"}
		var id := String(nb["obj"]["id"])
		if id == "garw":
			return {"notice": "我：入口就在前面，沿台阶走下去。"}
		if ENTRY_ROOMS.has(id) and _continuous_host(id):
			return {"notice": "我：门开着，直接走进去就行。"}
		if ENTRY_ROOMS.has(id):
			var target := String(ENTRY_ROOMS[id])
			return {"notice": String(_rooms[target]["name"]), "travel": {"world": target, "pose": default_spawn(target)}}
		return {"notice": ""}
	if is_stairwell(world_id):
		return {"notice": ""}
	var r: Dictionary = _rooms[world_id]
	var me_in := CampusGeometry.to_world(r, float(p[0]), float(p[2]))
	var hit := CampusGeometry.near_tile(r, me_in, ang, CampusGeometry.NEAR_ROOM, _open_doors)
	if hit.is_empty():
		return {"notice": "我：这里什么都没有。"}
	match hit["ch"]:
		"=":
			return _toggle_door(r, hit, me_in)
		"O":
			if _exit_is_open(r, hit["w"]):
				return {"notice": "我：门开着，直接走出去就行。"}
			var floor_value: Variant = r.get("floor")
			if floor_value != null and int(floor_value) > 1:
				return {"notice": "我：这是%d楼。这边的窗子封死了。" % int(floor_value)}
			var exit: Variant = r.get("exit_world")
			if exit == null:
				return {"notice": ""}
			var outside_pos := Vector2(exit["x"], exit["y"])
			return {"notice": "武大附中 · 校园", "travel": {"world": "out", "pose": _pose(CampusGeometry.to_scene(null, outside_pos), ang, float(pose["pitch"]))}}
		"J":
			return {"notice": "", "elevator": true}
		"P":
			return {"notice": "", "seat": [hit["c"], hit["r"]]}
		"D":
			return {"notice": "", "terminal": true}
		"X":
			return {"notice": "", "trash": true}
		"V":
			return {"notice": "", "car": [hit["c"], hit["r"]]}
		"H":
			return {"notice": "", "hide": [hit["c"], hit["r"]]}
		"T":
			return {"notice": "", "podium": [hit["c"], hit["r"]]}
		"d", "f", "R", "q":
			if hit["ch"] == "d" and desk_taken.is_valid() and bool(desk_taken.call(world_id, int(hit["c"]), int(hit["r"]))):
				return {"notice": "我：他坐在这儿。我不能翻他的抽屉。"}
			return {"notice": "", "search": [hit["c"], hit["r"]]}
		"S":
			# interact.js stairGo: shafts are walked; a room without one (canteen) has its stair as a way out.
			for st: Dictionary in _stair_layout():
				if (st["rooms"] as Array).has(world_id):
					return {"notice": "沿台阶走到下一层，门外就是走廊。"}
			var ex: Variant = r.get("exit_world")
			if ex == null:
				return {"notice": ""}
			return {"notice": "武大附中 · 校园", "travel": {"world": "out", "pose": _pose(CampusGeometry.to_scene(null, Vector2(ex["x"], ex["y"])), ang, float(pose["pitch"]))}}
	if FACILITY.contains(String(hit["ch"])):
		return {"notice": "", "facility": [String(hit["ch"]), hit["c"], hit["r"]]}
	return {"notice": "（Godot 版尚未移植这里的交互：%s）" % hit["ch"]}


func _toggle_door(r: Dictionary, hit: Dictionary, me: Vector2) -> Dictionary:
	var key := CampusGeometry.door_key(r, hit["c"], hit["r"])
	if door_blocked.is_valid() and bool(door_blocked.call(String(r["id"]), int(hit["c"]), int(hit["r"]))):
		return {"notice": "我：他们堵在门口。没有人让开。"}
	var locks: Dictionary = _campus.get("door_locks", {})
	if locks.has(key) and not is_open(key) and not has_item.call(String(locks[key]["item"])):
		return {"notice": "我：门锁着。锁孔是圆的，很新。", "toast": "需要「%s」· 校长办公室可能有" % locks[key]["name"]}
	if not is_open(key):
		_open_doors[key] = true
		var line: String = OPEN_LINES[_line % OPEN_LINES.size()]
		_line += 1
		door_changed.emit(key, true)
		return {"notice": line, "door": {"key": key, "open": true}}
	var w: Vector2 = hit["w"]
	if absf(me.x - w.x) < float(r["tw"]) * 0.5 + CampusGeometry.PRAD and absf(me.y - w.y) < float(r["th"]) * 0.5 + CampusGeometry.PRAD:
		return {"notice": "我：先让开门口。"}
	_open_doors.erase(key)
	door_changed.emit(key, false)
	return {"notice": "", "door": {"key": key, "open": false}}
