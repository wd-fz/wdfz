class_name CooperativeItems
extends RefCounted
## Shared containers and stable instance IDs; each bag remains a personal module.
var ground: Array = []
## Protected overflow from death/departure, drained as soon as a ground slot opens.
var stash: Array = []
var owners: Dictionary = {}
var containers := {"desk_used": {}, "pending_loot": {}, "key_miss": 0, "hw_taken": false, "rng_seed": "1", "rng_state": "1"}
var searches: Dictionary = {}
var serial := 0
var revision := 0


func reconcile(a: CooperativeActor) -> void:
	while not stash.is_empty() and ground.size() < InventoryModule.GROUND_MAX:
		ground.append(stash.pop_front())
		revision += 1
	if not owners.has(a.id): owners[a.id] = {}
	var own: Dictionary = owners[a.id]
	for item: String in own.keys():
		if not a.bag().has(item): own.erase(item)
	for item: String in a.bag().bag:
		if not own.has(item):
			serial += 1
			own[item] = "item-%d" % serial
	a.bag().ground = ground


func prepare_search(a: CooperativeActor) -> void:
	var b := a.bag()
	b.desk_used = containers["desk_used"]
	b.pending_loot = containers["pending_loot"]
	b.key_miss = int(containers["key_miss"])
	b.hw_taken = bool(containers["hw_taken"])
	b._rng.seed = int(containers["rng_seed"])
	b._rng.state = int(containers["rng_state"])


func finish_search(a: CooperativeActor) -> void:
	var b := a.bag()
	containers = {"desk_used": b.desk_used, "pending_loot": b.pending_loot, "key_miss": b.key_miss, "hw_taken": b.hw_taken, "rng_seed": str(b._rng.seed), "rng_state": str(b._rng.state)}
	if not b.searching(): release(a.id)
	reconcile(a)


func search(a: CooperativeActor, scene: String, c: int, r: int, at: Vector2) -> bool:
	var key := "%s:%d:%d" % [scene, c, r]
	if searches.has(key) and searches[key] != a.id: return false
	prepare_search(a)
	a.bag().start_search(scene, c, r, at)
	if a.bag().searching(): searches[key] = a.id
	return true


func release(id: String) -> void:
	for key: String in searches.keys():
		if searches[key] == id: searches.erase(key)


func drop(a: CooperativeActor, item: String) -> bool:
	reconcile(a)
	if not a.bag().has(item) or ground.size() >= InventoryModule.GROUND_MAX: return false
	var p: Array = a.pose["position"]
	ground.append({"uid": owners[a.id][item], "id": item, "world": a.location(), "x": float(p[0]), "y": float(p[1]), "z": float(p[2])})
	a.bag().remove(item)
	owners[a.id].erase(item)
	revision += 1
	return true


func pickup(a: CooperativeActor, uid: String, reachable: Callable) -> bool:
	for i in ground.size():
		var entry: Dictionary = ground[i]
		if entry["uid"] != uid: continue
		var p: Array = a.pose["position"]
		var dist := Vector2(float(p[0]) - float(entry["x"]), float(p[2]) - float(entry["z"])).length()
		if entry["world"] != a.location() or dist > InventoryModule.PICK_REACH or absf(float(p[1]) - float(entry["y"])) > InventoryModule.PICK_RISE: return false
		if not reachable.call(a, entry) or a.bag().has(entry["id"]) or not a.bag().add(entry["id"]): return false
		if not owners.has(a.id): owners[a.id] = {}
		owners[a.id][entry["id"]] = uid
		ground.remove_at(i)
		revision += 1
		return true
	return false


func recover(a: CooperativeActor) -> void:
	reconcile(a)
	for item: String in a.bag().bag.duplicate():
		if drop(a, item): continue
		var p: Array = a.pose["position"]
		stash.append({"uid": owners[a.id][item], "id": item, "world": a.location(), "x": p[0], "y": p[1], "z": p[2]})
		a.bag().remove(item)
		owners[a.id].erase(item)
		revision += 1


func transfer(a: CooperativeActor, b: CooperativeActor, item: String) -> bool:
	reconcile(a)
	reconcile(b)
	if a.id == b.id or a.location() != b.location() or b.fate().over() or not a.bag().has(item) or b.bag().has(item): return false
	var p: Array = a.pose["position"]
	var q: Array = b.pose["position"]
	if Vector3(p[0], p[1], p[2]).distance_to(Vector3(q[0], q[1], q[2])) > 2.0 or not b.bag().add(item): return false
	owners[b.id][item] = owners[a.id][item]
	owners[a.id].erase(item)
	a.bag().remove(item)
	revision += 1
	return true


func capture() -> Dictionary:
	return {"ground": ground.duplicate(true), "stash": stash.duplicate(true), "owners": owners.duplicate(true), "containers": containers.duplicate(true), "searches": searches.duplicate(), "serial": serial, "revision": revision}


func restore(data: Dictionary) -> void:
	ground = data["ground"].duplicate(true)
	stash = data["stash"].duplicate(true)
	owners = data["owners"].duplicate(true)
	containers = data["containers"].duplicate(true)
	searches = data["searches"].duplicate()
	serial = int(data["serial"])
	revision = int(data["revision"])
