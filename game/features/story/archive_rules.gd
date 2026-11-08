class_name ArchiveRules
extends RefCounted
## Original death-archive.js rules. Catalogue and profile are independent from a run.
var catalogue: Dictionary
var state: Dictionary
var entries := {}
var death_ids := {}

func _init(content: Dictionary) -> void:
	catalogue = content
	for group: String in ["deaths", "cuts"]:
		for entry: Dictionary in content[group]:
			entries[entry["id"]] = entry
			if group == "deaths": death_ids[entry["id"]] = true
	state = blank()

static func blank() -> Dictionary:
	return {"version":1,"unlocked":{},"first":{},"count":{},"legacy":{},"granted":{},"seen":{},"pending":0,"migrated":0}

func restore(raw: Variant) -> void:
	state = blank()
	if not raw is Dictionary or raw.get("version") != 1: return
	for key: String in ["unlocked","first","count","legacy"]:
		if not raw.get(key) is Dictionary: continue
		for id: String in raw[key]:
			if death_ids.has(id): state[key][id] = raw[key][id]
	var extension := RegEx.create_from_string("^x\\.[A-Za-z0-9_.-]{1,40}$")
	if raw.get("granted") is Dictionary:
		for id: String in raw["granted"]:
			if (entries.has(id) or extension.search(id) != null) and raw["granted"][id]: state["granted"][id] = 1
	if raw.get("seen") is Dictionary:
		for id: String in raw["seen"]:
			if entries.get(id,{}).get("seen",false) and raw["seen"][id]: state["seen"][id] = 1
	if typeof(raw.get("pending")) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(raw["pending"])): state["pending"] = maxi(0,int(raw["pending"]))
	state["migrated"] = 1 if raw.get("migrated",false) else 0

func migrate(log: Dictionary) -> void:
	if state["migrated"]: return
	state["migrated"] = 1
	var known := 0
	var total := 0
	var sources: Dictionary = log.get("sources",{}) if log.get("sources",{}) is Dictionary else {}
	for id: String in sources:
		var n := maxi(0,int(sources[id]))
		if n == 0 or not death_ids.has(id): continue
		known += n
		if not state["unlocked"].get(id,false):
			state["unlocked"][id] = true
			state["legacy"][id] = 1
		state["count"][id] = maxi(int(state["count"].get(id,0)),n)
	var counts: Dictionary = log.get("counts",{}) if log.get("counts",{}) is Dictionary else {}
	for n: Variant in counts.values(): total += maxi(0,int(n))
	state["pending"] = maxi(0,total-known)

func record(source: Variant, fx: String, debug: bool, replay: bool, context: Variant, at: int) -> String:
	if debug or replay or context == "debug": return ""
	var id := String(source) if source != null else ""
	if id == "" and fx == "laugh": id = "laugh"
	if not death_ids.has(id): return ""
	var fresh := not bool(state["unlocked"].get(id,false))
	state["count"][id] = int(state["count"].get(id,0))+1
	if fresh:
		state["unlocked"][id] = true
		state["first"][id] = at
	return id if fresh else ""

func real(entry: Dictionary, ends: Dictionary, opening: bool) -> bool:
	var id: String = entry["id"]
	if entry.has("cut"):
		if entry.get("seen",false): return bool(state["seen"].get(id,false))
		return bool(ends.get(entry["end"],false)) if entry.has("end") else opening
	return bool(state["unlocked"].get(id,false))

func is_open(entry: Dictionary, ends: Dictionary = {}, opening: bool = false) -> bool:
	return bool(state["granted"].get(entry["id"],false)) or real(entry,ends,opening)

func visible(group: String, ends: Dictionary = {}, opening: bool = false) -> Array:
	return catalogue[group].filter(func(e: Dictionary) -> bool: return not e.get("secret",false) or is_open(e,ends,opening))

func locked(ends: Dictionary = {}, opening: bool = false) -> Array:
	return entries.values().filter(func(e: Dictionary) -> bool: return not is_open(e,ends,opening)).map(func(e: Dictionary) -> String: return e["id"])

func grant(ids: Array) -> void:
	for id: String in ids: state["granted"][id] = 1

func mark_seen(id: String, replay: bool = false) -> bool:
	if replay or not entries.get(id,{}).get("seen",false) or state["seen"].has(id): return false
	state["seen"][id] = 1
	return true
