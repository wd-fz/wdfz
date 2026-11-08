class_name Speedrun
extends RefCounted
## Speedrun mode, ported from the Web version (reference wd-fz.github.io@0bf508a, speedrun.js):
## idle → ready (difficulty and talent chosen) → running (from the first frame the player can act)
## → finished / invalid / failed / abandoned. Invalidating a run leaves the clock running.
## The clock keeps running through pauses, the bag and cutscenes;
## the larger of the monotonic and the wall clock is used. Records: the last 20 runs and the
## personal best per rules version · difficulty · route, in a side file next to the save. Speedruns
## do not write the normal save slot. Hidden routes appear in the table only after a record exists.

const RULES := 6
const ROUTES := {"dismissal": "《放学》", "international": "《外国语学生》", "cyber": "《网安仙人》", "car": "《闸门》", "face": "《白名单》", "portal": "《门》", "beast":"《先辈》"}
const DIFF_NAME := {"easy": "预知梦", "hard": "梦魇"}

var run: Dictionary = {}


static func fmt(ms: int) -> String:
	ms = maxi(0, ms)
	return "%02d:%02d:%02d.%02d" % [ms / 3600000, (ms / 60000) % 60, (ms / 1000) % 60, (ms / 10) % 100]


func active() -> bool:
	return not run.is_empty() and run["status"] in ["ready", "running"]


func arm(diff: String) -> void:
	run = {"id": "%x%x" % [Time.get_ticks_usec(), randi() % 1000000], "diff": "hard" if diff == "hard" else "easy", "status": "ready", "route": "", "reason": "", "ms": 0, "p0": 0, "w0": 0.0}


func disarm() -> void:
	run = {}


func invalidate(reason: String) -> void:
	if active() and String(run.get("reason", "")).is_empty():
		run["reason"] = reason


static func reason_text(reason: String) -> String:
	return {"debug": "用了调试面板", "ending_direct": "没有经过正常路线", "load": "读了存档"}.get(reason, reason)


func start() -> void:
	if not run.is_empty() and run["status"] == "ready":
		run["status"] = "running"
		run["p0"] = Time.get_ticks_msec()
		run["w0"] = Time.get_unix_time_from_system()


func elapsed() -> int:
	if run.is_empty():
		return 0
	if run["status"] != "running":
		return int(run["ms"])
	return maxi(Time.get_ticks_msec() - int(run["p0"]), int((Time.get_unix_time_from_system() - float(run["w0"])) * 1000.0))


## A route reached its ending. Returns the record with "pb" and "best", or {}.
func finish(route: String, record: Dictionary) -> Dictionary:
	if run.is_empty() or run["status"] != "running" or not ROUTES.has(route):
		return {}
	run["ms"] = elapsed()
	run["route"] = route
	run["status"] = "finished" if String(run.get("reason", "")).is_empty() else "invalid"
	return _save(record)


func fail(status: String, record: Dictionary) -> Dictionary:
	if not active():
		return {}
	if run["status"] == "ready":
		run = {}
		return {}
	run["ms"] = elapsed()
	run["status"] = status
	return _save(record)


static func key(diff: String, route: String) -> String:
	return "r%d|%s|%s" % [RULES, diff, route]


## record: the stored {"version", "recent", "best"} (edited in place).
func _save(record: Dictionary) -> Dictionary:
	if not record.has("recent"):
		record["version"] = 1
		record["recent"] = []
		record["best"] = {}
	var rec := {"runId": run["id"], "diff": run["diff"], "route": run["route"], "ms": int(run["ms"]), "status": run["status"], "reason": run.get("reason", ""), "rules": RULES, "at": int(Time.get_unix_time_from_system())}
	var recent: Array = record["recent"]
	recent.push_front(rec)
	record["recent"] = recent.slice(0, 20)
	var pb := false
	if rec["status"] == "finished":
		var k := key(String(rec["diff"]), String(rec["route"]))
		var old: Variant = (record["best"] as Dictionary).get(k)
		if old == null or int(rec["ms"]) < int(old["ms"]):
			record["best"][k] = {"ms": rec["ms"], "runId": rec["runId"], "at": rec["at"]}
			pb = true
	return {"rec": rec, "pb": pb, "best": int(record["best"].get(key(String(rec["diff"]), String(rec["route"])), {"ms": 0})["ms"])}


## Lines for the records list.
static func rows(record: Dictionary) -> Array:
	var out: Array = []
	for diff: String in ["easy", "hard"]:
		for route: String in ROUTES:
			var b: Variant = (record.get("best", {}) as Dictionary).get(key(diff, route))
			if route == "beast" and b == null:
				continue
			out.append({"text": "%s · %s　%s" % [DIFF_NAME[diff], ROUTES[route], fmt(int(b["ms"])) if b != null else "—"], "on": b != null, "memo": ""})
	for r: Dictionary in record.get("recent", []):
		var what: String = {"finished": "完成", "failed": "失败", "abandoned": "放弃"}.get(String(r["status"]), String(r["status"]))
		if r["status"] == "invalid":
			what = "无效（%s）" % reason_text(String(r.get("reason", "")))
		out.append({"text": "最近 · %s · %s · %s · %s" % [DIFF_NAME.get(r["diff"], r["diff"]), ROUTES.get(r["route"], "—"), what, fmt(int(r["ms"]))], "on": r["status"] == "finished", "memo": ""})
	return out
