class_name LegacySave
extends RefCounted
## Reads a save of the old Web build (game3d/js/save.js: the JSON in localStorage under "wdfz3d", reference
## wd-fz.github.io@0bf508a) and plans what of it can be carried into a new Godot run. A new run is started (difficulty,
## talent) and then the player's own state is put on it: where you stand and face, the clock and the day, SAN, violation,
## stamina, assimilation, the bag and the hotbar. Everything else — the anomaly in progress, the routes and their clues, the
## story flags, doors, marks — starts fresh (it lives in the Godot modules in another shape). The run is rated "from an old save":
## what happened before is not on record (RunScoreModule.legacy). Nothing is read from it unvalidated: a bad file is refused whole.

const LIMITS := {"san": [0, 100], "viol": [0, 100], "stam": [0, 100], "tt": [0, 100]}


## Returns {"error": ""} plus the plan, or {"error": "why"}.
static func plan(d: Variant, known_rooms: Dictionary, known_items: Dictionary, talents: Array) -> Dictionary:
	if not (d is Dictionary):
		return {"error": "不是旧版存档（要一个 JSON 对象）"}
	var s: Dictionary = d
	if s.has("clockVersion") and not (int(s["clockVersion"]) == 1 or int(s["clockVersion"]) == 2):
		return {"error": "不支持的时钟版本"}
	for k: String in ["x", "y", "tsec"]:
		if not _num(s.get(k)):
			return {"error": "存档位置或时间无效"}
	var tsec := float(s["tsec"])
	if tsec < 0.0 or tsec > 1500.0:
		return {"error": "存档位置或时间无效"}
	var day := int(s.get("day", 1)) if _num(s.get("day", 1)) else 0
	if day < 1 or day > 100000:
		return {"error": "存档天数无效"}
	var mode := String(s.get("mode", "out"))
	var room := String(s.get("room", "")) if s.get("room") != null else ""
	var world := "out"
	if mode == "in":
		if not known_rooms.has(room):
			return {"error": "存档里的房间（%s）在这个版本里不存在" % room}
		world = room
	elif mode != "out":
		return {"error": "存档位置模式无效"}
	var out := {"error": "", "world": world, "x": float(s["x"]), "y": float(s["y"]), "ang": float(s.get("ang", 0.0)) if _num(s.get("ang", 0.0)) else 0.0,
		"pitch": clampf(float(s.get("pitch", 0.0)) if _num(s.get("pitch", 0.0)) else 0.0, -1.4, 1.4), "tsec": tsec, "day": day,
		"diff": "hard" if String(s.get("diff", "easy")) == "hard" else "easy", "talent": String(s.get("talent", "none")), "dropped": []}
	if not talents.has(out["talent"]):
		out["talent"] = "none"
	for k: String in LIMITS:
		var v: Variant = s.get(k, 100.0 if k != "viol" and k != "tt" else 0.0)
		out[k] = clampf(float(v) if _num(v) else 0.0, float(LIMITS[k][0]), float(LIMITS[k][1]))
	var bag: Array = []
	var raw: Variant = s.get("bag", [])
	if raw is Array:
		for id: Variant in raw:
			if id is String and known_items.has(id) and bag.size() < 8:
				bag.append(id)
			else:
				(out["dropped"] as Array).append(str(id))
	out["bag"] = bag
	var hot: Array = [null, null]
	var rh: Variant = s.get("hot", [])
	if rh is Array:
		for i in mini(2, (rh as Array).size()):
			if rh[i] is String and bag.has(rh[i]):
				hot[i] = rh[i]
	out["hot"] = hot
	return out


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and not is_nan(float(v)) and not is_inf(float(v))
