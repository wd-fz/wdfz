class_name CooperativeRoom
extends RefCounted
## Network-independent room lifecycle. Peer IDs and credentials belong to the adapter.

const MAX_MEMBERS := 4
const RESERVATION_SECONDS := 60.0
const PAUSE_SECONDS := 120.0
const ENDINGS := ["face", "car", "portal", "dismissal", "cyber", "international"]
var epoch := ""
var phase := "lobby"
var members: Dictionary = {}
var host_id := ""
var capacity := MAX_MEMBERS
var minimum_loaded := 2
var difficulty := "easy"
var tick := 0
var revision := 0
var paused_left := 0.0
var ending := ""
var ending_offer: Dictionary = {}
var debug_run := false
var _results: Dictionary = {}


func add_member(id: String, nickname: String, is_host: bool = false) -> String:
	if phase != "lobby": return "游戏已开始，仅原成员可以重连。"
	if id.is_empty() or members.has(id): return "成员身份重复。"
	if members.size() >= capacity: return "房间已满。"
	members[id] = {"name": nickname.strip_edges().left(24), "ready": false, "talent": "none", "state": "lobby", "connected": true, "remaining": RESERVATION_SECONDS}
	if is_host: host_id = id
	return ""


func ready(id: String, value: bool, talent: String) -> bool:
	if phase != "lobby" or not members.has(id): return false
	members[id]["ready"] = value
	members[id]["talent"] = talent
	return true


func can_start() -> bool:
	if phase != "lobby": return false
	var present := 0
	for member: Dictionary in members.values():
		if member["state"] == "departed": continue
		if not member["connected"] or not member["ready"]: return false
		present += 1
	return present >= minimum_loaded


func begin(new_epoch: String) -> bool:
	if not can_start() or new_epoch.is_empty(): return false
	epoch = new_epoch
	phase = "loading"
	for member: Dictionary in members.values():
		if member["state"] != "departed": member["state"] = "loading"
	return true


func loaded(id: String) -> void:
	if phase != "loading" or not members.has(id): return
	members[id]["state"] = "alive"
	check_loaded()


func check_loaded() -> void:
	if phase != "loading": return
	var present := 0
	for member: Dictionary in members.values():
		if member["state"] == "departed": continue
		if member["state"] != "alive" or not member["connected"]: return
		present += 1
	if present >= minimum_loaded: phase = "playing"


func disconnect_member(id: String) -> void:
	if not members.has(id): return
	if phase == "lobby":
		members.erase(id)
		return
	members[id]["connected"] = false
	members[id]["remaining"] = RESERVATION_SECONDS
	ending_offer.clear()
	check_loaded()


func reconnect(id: String) -> bool:
	if not members.has(id) or members[id]["state"] == "departed" or members[id]["connected"]: return false
	members[id]["connected"] = true
	members[id]["remaining"] = RESERVATION_SECONDS
	return true


func remove(id: String) -> void:
	if not members.has(id) or id == host_id: return
	if phase == "lobby": members.erase(id)
	else:
		members[id]["state"] = "departed"
		members[id]["connected"] = false
	ending_offer.clear()
	if phase == "playing" and alive_ids().is_empty(): phase = "ended"


func alive_ids() -> Array:
	var ids: Array = []
	for id: String in members:
		if members[id]["state"] == "alive": ids.append(id)
	ids.sort()
	return ids


## Simulation time spent connected, retained across reconnects and checkpoints.
## Offline reservation and menus after the result are not participation time.
func record_participation(dt: float) -> void:
	if phase != "playing" or paused_left > 0.0: return
	for m: Dictionary in members.values():
		if not m["connected"] or m["state"] not in ["alive", "dead"]: continue
		if not m.has("participation"):
			m["participation"] = {"first_tick": tick, "last_tick": tick, "seconds": 0.0, "alive_seconds": 0.0}
		var record: Dictionary = m["participation"]
		record["last_tick"] = tick
		record["seconds"] += dt
		if m["state"] == "alive": record["alive_seconds"] += dt


func elapsed(dt: float) -> Array:
	var departed: Array = []
	if not is_finite(dt) or dt <= 0.0: return departed
	paused_left = maxf(0.0, paused_left - dt)
	for id: String in members:
		var m: Dictionary = members[id]
		if m["connected"] or m["state"] == "departed": continue
		m["remaining"] = maxf(0.0, float(m["remaining"]) - dt)
		if m["remaining"] <= 0.0:
			m["state"] = "departed"
			departed.append(id)
	if phase == "playing" and alive_ids().is_empty(): phase = "ended"
	return departed


func pause(id: String, value: bool) -> bool:
	if phase != "playing" or not members.has(id) or not members[id]["connected"]: return false
	if value and id != host_id: return false
	paused_left = PAUSE_SECONDS if value else 0.0
	return true


func offer_ending(id: String, route: String, eligible: Array) -> bool:
	if phase != "playing" or route not in ENDINGS or id not in alive_ids(): return false
	var alive := alive_ids()
	for who: String in alive:
		if who not in eligible or not members[who]["connected"]: return false
	ending_offer = {"route": route, "members": alive, "confirmed": [id]}
	return true


func confirm_ending(id: String, accept: bool) -> bool:
	if ending_offer.is_empty() or id not in ending_offer["members"]: return false
	if not accept:
		ending_offer.clear()
		return false
	if id not in ending_offer["confirmed"]: ending_offer["confirmed"].append(id)
	for who: String in ending_offer["members"]:
		if not members[who]["connected"] or members[who]["state"] != "alive" or who not in ending_offer["confirmed"]: return false
	ending = String(ending_offer["route"])
	phase = "ended"
	return true


func death(id: String) -> void:
	if not members.has(id): return
	members[id]["state"] = "dead"
	ending_offer.clear()
	if alive_ids().is_empty(): phase = "ended"


func cached(id: String, sequence: int) -> Variant:
	return _results.get(id, {}).get(sequence)


func remember(id: String, sequence: int, result: Dictionary) -> void:
	if not _results.has(id): _results[id] = {}
	_results[id][sequence] = result.duplicate(true)
	while _results[id].size() > 256: _results[id].erase(_results[id].keys()[0])


func public_state() -> Dictionary:
	return {"revision": revision, "epoch": epoch, "phase": phase, "members": members.duplicate(true), "host": host_id, "capacity": capacity, "difficulty": difficulty, "tick": tick, "paused": paused_left, "ending": ending, "offer": ending_offer.duplicate(true), "debug": debug_run}
