class_name CampusStream
extends RefCounted
## Bounded, per-router residency. Heavy geometry is prepared off-tree on one worker;
## entering a region adopts it without loading, clipping or rebuilding meshes at the threshold.
## Only geometry/collision survives a visit: effects and gameplay adapters always start fresh.

const CACHE_LIMIT := 3  # in addition to the current region
const FLUSH_BUDGET_USEC := 2000
var cached: Dictionary = {}
var builds := 0
var hits := 0
var allow_headless := false
var _queue: Array[Dictionary] = []
var _worker: Thread
var _job: Dictionary = {}
var _generation := 0
var _serial := 0
var _wanted := PackedStringArray()


func automatic() -> bool:
	return allow_headless or DisplayServer.get_name() != "headless"


func has(id: String) -> bool:
	return cached.has(id)


func pending(id: String) -> bool:
	if _job.get("kind") == "region" and _job.get("id") == id:
		return true
	return _queue.any(func(job: Dictionary) -> bool: return job.get("kind") == "region" and job.get("id") == id)


func want(ids: PackedStringArray) -> void:
	_wanted = ids
	# Drop speculative work that is no longer on the player's route.
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].get("kind") == "region" and not ids.has(String(_queue[i]["id"])):
			(_queue[i]["world"] as CampusWorld).free()
			_queue.remove_at(i)


func prepare(world: CampusWorld) -> void:
	if has(world.scene_id) or pending(world.scene_id):
		world.free()
		return
	var job := {"kind": "region", "id": world.scene_id, "world": world, "generation": _generation}
	# Build the real region first so a pending doorway preview can reuse its processed meshes.
	for i in _queue.size():
		if _queue[i].get("kind") == "preview" and _queue[i].get("id") == world.scene_id:
			_queue.insert(i, job)
			return
	_queue.append(job)


func request_preview(owner: CampusWorld, holder: Node3D, id: String, plane: Plane) -> void:
	if holder.get_meta("stream_pending", false):
		return
	_serial += 1
	holder.set_meta("stream_pending", _serial)
	_queue.push_front({"kind": "preview", "id": id, "owner": weakref(owner), "holder": weakref(holder),
		"transform": holder.transform, "plane": plane, "quality": owner.material_quality(), "generation": _generation, "ticket": _serial})


func take(id: String) -> CampusWorld:
	if not cached.has(id):
		return null
	var world: CampusWorld = cached[id]
	cached.erase(id)
	hits += 1
	return world


func keep(world: CampusWorld) -> void:
	if cached.has(world.scene_id):
		(cached[world.scene_id] as CampusWorld).free()
		cached.erase(world.scene_id)
	cached[world.scene_id] = world
	while cached.size() > CACHE_LIMIT:
		var oldest := String(cached.keys()[0])
		for id: String in cached:
			if not _wanted.has(id):
				oldest = id
				break
		(cached[oldest] as CampusWorld).free()
		cached.erase(oldest)


func poll() -> void:
	if _worker != null:
		# Mesh reads need the rendering server to flush. Never spend the old 80 ms slice
		# on a gameplay frame; the worker progresses over several ordinary frames.
		var begin := Time.get_ticks_usec()
		while _worker.is_alive() and Time.get_ticks_usec() - begin < FLUSH_BUDGET_USEC:
			RenderingServer.force_sync()
			OS.delay_usec(20)
		if _worker.is_alive():
			return
		_accept(_worker.wait_to_finish())
		_worker = null
		_job = {}
	if _queue.is_empty():
		return
	_job = _queue.pop_front()
	if _job["kind"] == "preview":
		var owner: CampusWorld = _job["owner"].get_ref()
		if _job["holder"].get_ref() == null or owner == null or not owner.is_inside_tree():
			_dispose(_job)
			_job = {}
			return
	if _job["kind"] == "preview" and cached.has(_job["id"]):
		# The approaching building is usually resident already. Share its processed meshes;
		# only the clipped view's node tree/edge meshes are private, not a second mesh build.
		var source := (cached[_job["id"]] as CampusWorld).get_node_or_null("Model")
		if source != null:
			_job["source"] = source.duplicate()
			for occluder: Node in (_job["source"] as Node).find_children("*", "OccluderInstance3D", true, false):
				occluder.free()
	if DisplayServer.get_name() == "headless":
		# Dummy mesh storage is not thread-safe. Tests exercise the same queue/adoption synchronously.
		_accept(_build(_job))
		_job = {}
	else:
		_worker = Thread.new()
		if _worker.start(_build.bind(_job), Thread.PRIORITY_LOW) != OK:
			_worker = null
			_dispose(_job)
			_job = {}


static func _build(job: Dictionary) -> Node3D:
	if job["kind"] == "region":
		var world: CampusWorld = job["world"]
		world.prepare_geometry()
		return world
	var model: Node3D = job.get("source")
	if model == null:
		model = CampusWorld.build_visual(String(job["id"]), int(job["quality"]))
	if model == null:
		return null
	var holder := Node3D.new()
	holder.transform = job["transform"]
	holder.add_child(model)
	CampusPreview.clip(holder, job["plane"])
	holder.remove_child(model)
	holder.free()
	return model


func _accept(result: Node3D) -> void:
	if _job.get("kind") == "preview":
		_reset_preview(_job)
	if result == null:
		return
	if int(_job["generation"]) != _generation:
		result.free()
		return
	if _job["kind"] == "region":
		builds += 1
		keep(result as CampusWorld)
	else:
		var owner: CampusWorld = _job["owner"].get_ref()
		var holder: Node3D = _job["holder"].get_ref()
		if is_instance_valid(owner) and is_instance_valid(holder) and owner.is_inside_tree():
			owner.install_streamed_preview(holder, result, String(_job["id"]))
		else:
			result.free()


func _dispose(job: Dictionary) -> void:
	if job["kind"] == "region":
		(job["world"] as CampusWorld).free()
	else:
		if job.has("source"):
			(job["source"] as Node).free()
		_reset_preview(job)


func _reset_preview(job: Dictionary) -> void:
	var holder: Node3D = job["holder"].get_ref()
	# A cached holder may already belong to a new live adapter and a newer request.
	if holder != null and holder.get_meta("stream_pending", 0) == job["ticket"]:
		holder.remove_meta("stream_pending")


## Drain before synchronous loads, quality changes or destruction. No abandoned thread can
## later insert an old run's meshes. Ordinary prepared crossings never take this path.
func finish() -> void:
	if _worker == null:
		return
	while _worker.is_alive():
		RenderingServer.force_sync()
		OS.delay_usec(100)
	_accept(_worker.wait_to_finish())
	_worker = null
	_job = {}


func clear() -> void:
	_generation += 1
	for job: Dictionary in _queue:
		_dispose(job)
	_queue.clear()
	finish()
	for world: CampusWorld in cached.values():
		world.free()
	cached.clear()
	_wanted.clear()
