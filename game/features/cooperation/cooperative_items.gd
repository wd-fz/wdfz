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
var phones_by_uid: Dictionary = {}


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
	_sync_phone(a, String(own.get("phone", "")))
	a.bag().ground = ground
	var facility := a.feature(&"campus.facilities") as FacilitiesModule
	for material: String in ["coil", "lens", "vial"]:
		var exists := ground.any(func(e: Dictionary) -> bool: return e["id"] == material) or stash.any(func(e: Dictionary) -> bool: return e["id"] == material)
		for bag: Dictionary in owners.values(): exists = exists or bag.has(material)
		if not facility.portal.get("open", false): facility.flags[material] = exists


func _sync_phone(a: CooperativeActor, next: String) -> void:
	var phone := a.feature(&"phone.network") as PhoneModule
	if a.phone_uid != next:
		if not a.phone_uid.is_empty(): phones_by_uid[a.phone_uid] = phone.device.duplicate(true)
		if phones_by_uid.has(next):
			var saved := phone.capture()
			saved["device"] = phones_by_uid[next].duplicate(true)
			phone.restore(saved)
		elif not a.phone_uid.is_empty(): phone.device = PhoneEnergy.fresh()
		if not a.phone_uid.is_empty() or phones_by_uid.has(next):
			phone.connection = null
			phone.terminal_open = false
			a.terminal = false
		a.phone_uid = next
	if not next.is_empty():
		phone.device["deviceId"] = next
		phones_by_uid[next] = phone.device.duplicate(true)


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


func drop(a: CooperativeActor, item: String, site: Dictionary = {}) -> bool:
	reconcile(a)
	if not a.bag().has(item) or ground.size() >= InventoryModule.GROUND_MAX: return false
	var p: Array = site.get("pose", a.pose)["position"]
	ground.append({"uid": owners[a.id][item], "id": item, "world": site.get("world", a.location()), "x": float(p[0]), "y": float(p[1]), "z": float(p[2])})
	a.bag().remove(item)
	if item == "medkit": (a.feature(&"body.injury") as BodyModule).treat = null
	if item == "phone": _sync_phone(a, "")
	owners[a.id].erase(item)
	revision += 1
	return true


func pickup(a: CooperativeActor, uid: String, reachable: Callable) -> bool:
	for i in ground.size():
		var entry: Dictionary = ground[i]
		if entry["uid"] != uid: continue
		if not reachable.call(a, entry) or a.bag().has(entry["id"]) or not a.bag().add(entry["id"]): return false
		if not owners.has(a.id): owners[a.id] = {}
		owners[a.id][entry["id"]] = uid
		if entry["id"] == "phone": _sync_phone(a, uid)
		ground.remove_at(i)
		revision += 1
		return true
	return false


func recover(a: CooperativeActor) -> void:
	reconcile(a)
	var site := _recovery_site(a)
	for item: String in a.bag().bag.duplicate():
		if drop(a, item, site): continue
		var p: Array = site.get("pose", a.pose)["position"]
		stash.append({"uid": owners[a.id][item], "id": item, "world": site.get("world", a.location()), "x": p[0], "y": p[1], "z": p[2]})
		a.bag().remove(item)
		owners[a.id].erase(item)
		revision += 1


func _recovery_site(a: CooperativeActor) -> Dictionary:
	# A private instance disappears with its owner. Keep team items at its campus entrance.
	var world := ""
	var origin := {}
	if a.location() == MazeModule.ROOM:
		world = String(a.special_return.get("host", "teach")) + str(int(a.special_return.get("origin", 1)))
	elif a.location() == InceptionModule.ROOM:
		origin = (a.feature(&"story.inception") as InceptionModule).dream.get("from", {})
		world = String(origin.get("room", "dorm1"))
	if world.is_empty(): return {}
	var campus := a.feature(&"campus.world") as CampusModule
	var pose := campus.default_spawn(world)
	if origin.get("x") != null and origin.get("y") != null:
		var p := CampusGeometry.to_scene(campus.room(world), Vector2(origin["x"], origin["y"]))
		pose["position"] = [p.x, origin.get("floorY", 0), p.y]
	a.event("notice", {"text": "特殊空间消失了，随身物品留在校园入口，队友可以取回。"})
	return {"world": world, "pose": pose}


func transfer(a: CooperativeActor, b: CooperativeActor, item: String, reachable: Callable = Callable()) -> bool:
	reconcile(a)
	reconcile(b)
	if a.id == b.id or a.fate().over() or b.fate().over() or not a.bag().has(item) or b.bag().has(item): return false
	var p: Array = a.pose["position"]
	var q: Array = b.pose["position"]
	var near: bool = reachable.call(a, b) if reachable.is_valid() else a.location() == b.location() and Vector3(p[0], p[1], p[2]).distance_to(Vector3(q[0], q[1], q[2])) <= 2.0
	if not near or not b.bag().add(item): return false
	owners[b.id][item] = owners[a.id][item]
	if item == "phone":
		_sync_phone(a, "")
		_sync_phone(b, String(owners[b.id][item]))
	if item == "medkit": (a.feature(&"body.injury") as BodyModule).treat = null
	owners[a.id].erase(item)
	a.bag().remove(item)
	revision += 1
	return true


func capture() -> Dictionary:
	var devices := {}
	for own: Dictionary in owners.values():
		if own.has("phone"): devices[own["phone"]] = true
	for entry: Dictionary in ground + stash:
		if entry["id"] == "phone": devices[entry["uid"]] = true
	for uid: String in phones_by_uid.keys():
		if not devices.has(uid): phones_by_uid.erase(uid)
	return {"phones": phones_by_uid.duplicate(true), "ground": ground.duplicate(true), "stash": stash.duplicate(true), "owners": owners.duplicate(true), "containers": containers.duplicate(true), "searches": searches.duplicate(), "serial": serial, "revision": revision}


func restore(data: Dictionary) -> void:
	phones_by_uid = data.get("phones", {}).duplicate(true)
	ground = data["ground"].duplicate(true)
	stash = data["stash"].duplicate(true)
	owners = data["owners"].duplicate(true)
	containers = data["containers"].duplicate(true)
	searches = data["searches"].duplicate()
	serial = int(data["serial"])
	revision = int(data["revision"])
