class_name RunRecords
extends RefCounted
## The clear records (modules/run-record/records.js, reference wd-fz.github.io@0bf508a). Metadata
## clears.json: {version, list [records], grades {F: {first, count, best}}}; at most 50 records, the oldest
## dropped — but each route × difficulty keeps its highest grade and fastest time; the "grade obtained"
## summary is never deleted (the CG archive's result screens read it). Replays are stored one file per
## record (clear_<id>.json): only the 10 most recent and the "bests"; if a write fails the oldest replay goes
## first. Debug-panel records (source "debug") are marked, never ranked, never "best", never count towards
## achievements or light up a real grade.

const VERSION := 1
const CLEARS_MAX := 50
const REPLAYS_MAX := 10

var dir: String
var _cache: Dictionary = {}


func _init(directory: String = "user://records") -> void:
	dir = directory


func _clears_path() -> String:
	return dir + "/clears.json"


func _replay_path(id: String) -> String:
	return "%s/clear_%s.json" % [dir, id]


func _blank() -> Dictionary:
	return {"version": VERSION, "list": [], "grades": {}}


func reset_cache() -> void:
	_cache = {}


func read() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var out := _blank()
	if FileAccess.file_exists(_clears_path()):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_clears_path()))
		if d is Dictionary and int(d.get("version", 0)) == VERSION:
			for x: Variant in d.get("list", []):
				if x is Dictionary and x.get("id") is String and ScoreRules.grade_index(String(x.get("grade", ""))) >= 0:
					out["list"].append(x)
			var gd: Variant = d.get("grades", {})
			if gd is Dictionary:
				for g: Dictionary in ScoreRules.GRADES:
					var v: Variant = gd.get(g["g"])
					if v is Dictionary:
						out["grades"][g["g"]] = {"first": float(v.get("first", 0)), "count": int(v.get("count", 0)), "best": v.get("best") if v.get("best") is String else null}
	_cache = out
	return out


func write() -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_clears_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(read()))
	f.close()
	return true


static func is_real(x: Dictionary) -> bool:
	return x.get("source", "play") != "debug"


## The base game: real and not a DLC mode (variant): bests, speedrun rankings and grades only look at these.
static func is_base(x: Dictionary) -> bool:
	return is_real(x) and String(x.get("variant", "")) == ""


## The "bests": per route × difficulty the highest grade score and the fastest time (real ones only).
func _best_ids(list: Array) -> Dictionary:
	var keep := {}
	var by_key := {}
	for x: Dictionary in list:
		if not is_real(x):
			continue
		var k := "%s|%s|%s" % [x["route"], x["diff"], x.get("variant", "")]
		var b: Dictionary = by_key.get(k, {"g": null, "t": null})
		if b["g"] == null or float(x["gradeScore"]) > float(b["g"]["gradeScore"]):
			b["g"] = x
		if b["t"] == null or float(x["time"]["used"]) < float(b["t"]["time"]["used"]):
			b["t"] = x
		by_key[k] = b
	for k: String in by_key:
		keep[by_key[k]["g"]["id"]] = true
		keep[by_key[k]["t"]["id"]] = true
	return keep


func _replay_keep(list: Array) -> Dictionary:
	var keep := _best_ids(list)
	var recent := list.duplicate()
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) > float(b["at"]))
	for x: Dictionary in recent.slice(0, REPLAYS_MAX):
		keep[x["id"]] = true
	return keep


func _remove_replay(id: String) -> void:
	if FileAccess.file_exists(_replay_path(id)):
		DirAccess.remove_absolute(_replay_path(id))


func _trim(d: Dictionary) -> void:
	var keep := _best_ids(d["list"])
	while (d["list"] as Array).size() > CLEARS_MAX:
		var oldest: Variant = null
		for x: Dictionary in d["list"]:
			if keep.has(x["id"]):
				continue
			if oldest == null or float(x["at"]) < float(oldest["at"]):
				oldest = x
		if oldest == null:
			break
		(d["list"] as Array).erase(oldest)
		_remove_replay(String(oldest["id"]))
	var rk := _replay_keep(d["list"])
	for x: Dictionary in d["list"]:
		if int(x.get("replay", 0)) != 0 and not rk.has(x["id"]):
			_remove_replay(String(x["id"]))
			x["replay"] = 0


func _save_replay(d: Dictionary, id: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var text := JSON.stringify(data)
	for _i in 12:
		var f := FileAccess.open(_replay_path(id), FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			return true
		var old: Variant = null
		for x: Dictionary in d["list"]:
			if int(x.get("replay", 0)) != 0 and x["id"] != id and (old == null or float(x["at"]) < float(old["at"])):
				old = x
		if old == null:
			return false
		_remove_replay(String(old["id"]))
		old["replay"] = 0
	return false


## Add a record (a copy of meta) with its replay pack; returns the id.
func add(meta: Dictionary, replay: Dictionary = {}) -> String:
	var d := read()
	var rec: Dictionary = meta.duplicate(true)
	rec["id"] = "c%d%04d" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]
	rec["replay"] = 0
	(d["list"] as Array).append(rec)
	if is_base(rec):
		var gr: Dictionary = d["grades"].get(rec["grade"], {"first": rec["at"], "count": 0, "best": null})
		gr["count"] = int(gr["count"]) + 1
		if float(gr["first"]) == 0.0:
			gr["first"] = rec["at"]
		var cur: Variant = null
		if gr["best"] != null:
			for x: Dictionary in d["list"]:
				if x["id"] == gr["best"]:
					cur = x
		if cur == null or float(rec["gradeScore"]) >= float(cur["gradeScore"]):
			gr["best"] = rec["id"]
		d["grades"][rec["grade"]] = gr
	if replay.has("track"):
		rec["replay"] = 1 if _save_replay(d, String(rec["id"]), replay) else 0
	_trim(d)
	write()
	return String(rec["id"])


func get_record(id: String) -> Dictionary:
	for x: Dictionary in read()["list"]:
		if x["id"] == id:
			return x
	return {}


func replay(id: String) -> Dictionary:
	if FileAccess.file_exists(_replay_path(id)):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_replay_path(id)))
		if d is Dictionary and int(d.get("v", 0)) == 1:
			return d
	return {}


func remove(id: String) -> bool:
	var d := read()
	var x := get_record(id)
	if x.is_empty():
		return false
	(d["list"] as Array).erase(x)
	_remove_replay(id)
	for g: String in d["grades"]:
		if d["grades"][g]["best"] == id:
			d["grades"][g]["best"] = null
	write()
	return true


func remove_debug() -> int:
	var n := 0
	for x: Dictionary in (read()["list"] as Array).duplicate():
		if not is_real(x) and remove(String(x["id"])):
			n += 1
	return n


## The speedrun ranking: real, speedrun mode, with an RTA; by "time" or "grade"; at most 10.
func ranking(diff: String, route: String, by: String = "time") -> Array:
	var rows: Array = []
	for x: Dictionary in read()["list"]:
		if is_base(x) and x.get("mode") == "speedrun" and x["time"].get("rta") != null and float(x["time"]["rta"]) > 0.0 and x["diff"] == diff and x["route"] == route:
			rows.append(x)
	if by == "grade":
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var d := ScoreRules.grade_index(String(b["grade"])) - ScoreRules.grade_index(String(a["grade"]))
			return float(a["time"]["rta"]) < float(b["time"]["rta"]) if d == 0 else d < 0)
	else:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]["rta"]) < float(b["time"]["rta"]))
	return rows.slice(0, 10)


func best_grade(diff: String, route: String, mode: String = "") -> String:
	var best := ""
	for x: Dictionary in read()["list"]:
		if is_base(x) and x["diff"] == diff and x["route"] == route and (mode == "" or x.get("mode") == mode):
			if best == "" or ScoreRules.grade_index(String(x["grade"])) > ScoreRules.grade_index(best):
				best = String(x["grade"])
	return best


func list() -> Array:
	return (read()["list"] as Array).duplicate()


func grades() -> Dictionary:
	return read()["grades"]
