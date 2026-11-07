class_name ExplorationModule
extends FeatureModule
## The walked-floor sketches, ported from the Web version (reference wd-fz.github.io@0bf508a,
## exploration-map.js): what the player has actually seen of each room. Every 0.3 s the tiles within
## 6 tiles that the eye can reach (walls and closed doors block the line) are marked seen. Saved per room
## as a string of 6-bit characters (a whole school is a few KB, not a key per tile).
## The sketch only shows what was seen: furniture letters mean "seen", never "searched".

const STATE_VERSION := 1
const B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const RADIUS := 6
const STEP := 0.3

var _rooms: Dictionary = {}
var _bits: Dictionary = {}       # room id → PackedByteArray (cols × rows)
var _acc := 0.0
var _c: Dictionary = {}


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"campus.exploration"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	_bits = {}
	_acc = 0.0


func capture() -> Dictionary:
	var out := {}
	for id: String in _bits:
		out[id] = pack(_bits[id])
	return {"seen": out}


func validate(data: Dictionary) -> String:
	var seen: Variant = data.get("seen", {})
	if not (seen is Dictionary):
		return "探索记录无效"
	for id: String in seen:
		var r: Dictionary = _rooms.get(id, {})
		if r.is_empty() or not (seen[id] is String):
			return "探索记录无效"
		var s := String(seen[id])
		if s.length() > (int(r["cols"]) * int(r["rows"]) + 5) / 6:
			return "探索记录无效"
		for i in s.length():
			if B64.find(s.substr(i, 1)) < 0:
				return "探索记录无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	var seen: Dictionary = data.get("seen", {})
	for id: String in seen:
		_bits[id] = unpack(String(seen[id]), _rooms[id])


## ctx: scene, x, y (world), door_open Callable(c, r) -> bool.
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	return []


static func pack(bits: PackedByteArray) -> String:
	var out := ""
	var i := 0
	while i < bits.size():
		var q := 0
		for k in 6:
			if i + k < bits.size() and bits[i + k] != 0:
				q |= 1 << k
		out += B64.substr(q, 1)
		i += 6
	return out.rstrip("A")


static func unpack(text: String, room: Dictionary) -> PackedByteArray:
	var n := int(room["cols"]) * int(room["rows"])
	var b := PackedByteArray()
	b.resize(n)
	for i in text.length():
		var q := B64.find(text.substr(i, 1))
		if q < 0:
			continue
		for k in 6:
			if (q & (1 << k)) != 0 and i * 6 + k < n:
				b[i * 6 + k] = 1
	return b


func seen(id: String) -> PackedByteArray:
	if not _bits.has(id):
		var r: Dictionary = _rooms.get(id, {})
		if r.is_empty():
			return PackedByteArray()
		var b := PackedByteArray()
		b.resize(int(r["cols"]) * int(r["rows"]))
		_bits[id] = b
	return _bits[id]


func has(room: Dictionary, c: int, r: int) -> bool:
	var id := String(room["id"])
	if not _bits.has(id) or c < 0 or r < 0 or c >= int(room["cols"]) or r >= int(room["rows"]):
		return false
	return _bits[id][r * int(room["cols"]) + c] != 0


func count(id: String) -> int:
	var n := 0
	for v: int in _bits.get(id, PackedByteArray()):
		n += v
	return n


## Rooms with a sketch, in the order of the room list (a white space is never drawn).
func rooms() -> Array:
	var out: Array = []
	var ids: Array = _rooms.keys()
	ids.sort()
	for id: String in ids:
		if not bool(_rooms[id].get("flags", {}).get("noMap", false)) and count(id) > 0:
			out.append(id)
	return out


## Walls and closed doors hide the tiles behind them.
func visible(room: Dictionary, c: int, r: int, tc: int, tr: int) -> bool:
	var dx := tc - c
	var dy := tr - r
	var n := maxi(absi(dx), absi(dy)) * 2
	var grid: Array = room["grid"]
	var open: Callable = _c.get("door_open", Callable())
	for i in range(1, n):
		var x := floori(c + 0.5 + float(dx) * i / n)
		var y := floori(r + 0.5 + float(dy) * i / n)
		if x == tc and y == tr:
			break
		var ch := String(grid[y]).substr(x, 1) if y >= 0 and y < grid.size() else ""
		if ch == "#" or (ch == "=" and not (open.is_valid() and bool(open.call(x, y)))):
			return false
	return true


func observe() -> bool:
	var id := String(_c.get("scene", ""))
	var room: Dictionary = _rooms.get(id, {})
	if room.is_empty() or bool(room.get("flags", {}).get("noMap", false)):
		return false
	var b := seen(id)
	var cols := int(room["cols"])
	var rows := int(room["rows"])
	var c := floori((float(_c.get("x", 0.0)) - float(room["ox"])) / float(room["tw"]))
	var r := floori((float(_c.get("y", 0.0)) - float(room["oy"])) / float(room["th"]))
	var changed := false
	for y in range(maxi(0, r - RADIUS), mini(rows - 1, r + RADIUS) + 1):
		for x in range(maxi(0, c - RADIUS), mini(cols - 1, c + RADIUS) + 1):
			var i := y * cols + x
			if b[i] == 0 and Vector2(x - c, y - r).length() <= RADIUS and visible(room, c, r, x, y):
				b[i] = 1
				changed = true
	return changed


## Real seconds in normal play.
func tick(dt: float) -> void:
	_acc += dt
	if _acc >= STEP:
		_acc = 0.0
		observe()


## Walkable tiles seen / walkable tiles (the percentage on the sketch).
func percent(id: String) -> int:
	var room: Dictionary = _rooms.get(id, {})
	if room.is_empty():
		return 0
	var b := seen(id)
	var grid: Array = room["grid"]
	var cols := int(room["cols"])
	var walk := 0
	var got := 0
	for i in b.size():
		if String(grid[i / cols]).substr(i % cols, 1) != "#":
			walk += 1
			got += b[i]
	return roundi(float(got) / float(walk) * 100.0) if walk > 0 else 0
