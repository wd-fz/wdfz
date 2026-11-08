class_name LegacySave
extends RefCounted
## Reads a save of the old Web build (game3d/js/save.js: the JSON in localStorage under "wdfz3d", reference
## wd-fz.github.io@0bf508a). Validate the envelope and migrate the old continuous clock;
## LegacyState translates individual modules before a candidate run is installed.

const LIMITS := {"san": [0, 100], "viol": [0, 100], "stam": [0, 100], "tt": [0, 100]}


## Returns {"error": ""} plus the plan, or {"error": "why"}.
static func plan(d: Variant, known_rooms: Dictionary, known_items: Dictionary, talents: Array) -> Dictionary:
	if not (d is Dictionary):
		return {"error": "不是旧版存档（要一个 JSON 对象）"}
	var s: Dictionary = d
	if not SaveSchema.is_json_value(s):
		return {"error": "旧存档包含非法数据"}
	if s.has("v") and not SaveSchema.is_integer(s["v"], 1, 1):
		return {"error": "不支持的旧存档版本"}
	if s.has("clockVersion") and not SaveSchema.is_integer(s["clockVersion"], 1, 2):
		return {"error": "不支持的时钟版本"}
	for k: String in ["x", "y", "tsec"]:
		if not _num(s.get(k)):
			return {"error": "存档位置或时间无效"}
	var tsec := float(s["tsec"])
	if tsec < 0.0 or tsec > 1500.0:
		return {"error": "存档位置或时间无效"}
	if not SaveSchema.is_integer(s.get("day", 1), 1, 100000):
		return {"error": "存档天数无效"}
	var day := int(s.get("day", 1))
	if s.has("mode") and not s["mode"] is String or s.has("room") and s["room"] != null and not s["room"] is String:
		return {"error": "存档位置模式无效"}
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
		"diff": "hard" if s.get("diff") is String and s["diff"] == "hard" else "easy", "talent": s.get("talent", "none") if s.get("talent", "none") is String else "none", "dropped": []}
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
	out["source"] = s.duplicate(true)
	out["original"] = s.duplicate(true)
	if int(s.get("clockVersion", 1)) != 2:
		if tsec < 60.0:
			out["tsec"] = tsec + 1440.0
		var now := SchoolClock.continuous(day, float(out["tsec"]))
		for field: String in ["actCool", "anCool"]:
			if not s.get(field, {}) is Dictionary:
				return {"error": "旧存档冷却时间无效"}
			for key: String in s.get(field, {}):
				if _num(s[field][key]):
					out["source"][field][key] = now + maxf(0.0, float(s[field][key]) - (day * 1440.0 + tsec)) if field == "actCool" else now - fposmod(float(out["tsec"]) - float(s[field][key]) + 1440.0, 1440.0)
	return out


static func _num(v: Variant) -> bool:
	return (v is int or v is float) and not is_nan(float(v)) and not is_inf(float(v))
