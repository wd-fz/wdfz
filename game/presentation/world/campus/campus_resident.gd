class_name CampusResident
extends Node3D
## The World3D and collision stay live through every ordinary campus crossing.
const INDOOR_VIEW_DISTANCE := 10.0
const MODEL_RETRY_MS := 10000
const EVICTION_INTERVAL_MS := 400
const DETAIL_LIMIT := 12

var regions: Dictionary = {}
var space: CampusSpace
var configure: Callable
var active := ""
var builds := 0
var nearby_visuals := OS.get_name() == "Android"
var _visible_neighbours := PackedStringArray()
var _wanted := PackedStringArray()
var _retry_after: Dictionary = {}
var _worker: Thread
var _staging: CampusWorld
var _staging_tier := -1
var _lift_landing := ""
var _view_at := Vector3.ZERO
var _evict_at := 0


func _make(id: String) -> CampusWorld:
	var world := CampusWorld.new()
	world.name = id
	world.scene_id = id
	world.resident = true
	world.streamed_detail = nearby_visuals and not permanent_model(id)
	world.space = space
	if configure.is_valid(): configure.call(world)
	world.transform = space.frame(id)
	return world


static func permanent_model(id: String) -> bool:
	return id == "out" or id in CampusSpace.BRIDGES


func prepare(id: String, with_model: bool = true) -> CampusWorld:
	var world := regions.get(id) as CampusWorld
	var fresh := world == null
	if fresh: world = _make(id)
	var loading_detail := with_model and not world.geometry_ready
	if loading_detail: world.prepare_geometry()
	world.prepare_collision()
	if fresh:
		regions[id] = world
		add_child(world)
		world.set_collision_enabled(visible)
		builds += 1
	if loading_detail and world.geometry_ready:
		_refresh_visibility()
	return world


func select(id: String, ready_only: bool = false) -> CampusWorld:
	if id != active and regions.has(active): (regions[active] as CampusWorld).deactivate()
	var world := prepare(id, not ready_only)
	if id != active: _visible_neighbours = PackedStringArray([active]) if not active.is_empty() else PackedStringArray()
	active = id
	if not world.geometry_ready:
		world.show_cold_geometry()
		_wanted = PackedStringArray([id])
	_refresh_visibility()
	world.activate()
	return world


func suspend() -> void:
	if regions.has(active): (regions[active] as CampusWorld).deactivate()
	active = ""
	_wanted.clear()
	_visible_neighbours.clear()
	hide()
	for world: CampusWorld in regions.values(): world.set_collision_enabled(false)


func resume() -> void:
	if visible: return
	show()
	for world: CampusWorld in regions.values(): world.set_collision_enabled(true)


## Select models for initial loading and retain familiar areas with a wider cache radius.
func near_view(id: String, at: Vector3, focus: String, margin: float = 0.0) -> bool:
	if permanent_model(id) or id == focus: return true
	var local := space.frame(id).affine_inverse() * at
	var point := Vector2(local.x, local.z)
	var rect := space.local_bounds(id)
	var distance := point.distance_to(point.clamp(rect.position, rect.end))
	if space.rooms[id].get("flags", {}).get("stairwell", false):
		return distance < 35.0 + margin
	return distance < 26.0 + margin and absf(local.y) < 5.0 + margin * .2


func update_view(at: Vector3) -> void:
	if active.is_empty(): return
	var local := space.frame(active).affine_inverse() * at
	_visible_neighbours = CampusConnections.nearby(active, local, INDOOR_VIEW_DISTANCE)
	_refresh_visibility()
	if not nearby_visuals: return
	_wanted = PackedStringArray([active])
	if not _lift_landing.is_empty(): _wanted.append(_lift_landing)
	_wanted.append_array(CampusConnections.nearby(active, local))
	_view_at = at


func _release_distant_model() -> bool:
	var now := Time.get_ticks_msec()
	if now < _evict_at: return false
	_evict_at = now + EVICTION_INTERVAL_MS
	var count := 0
	var candidate: CampusWorld
	var farthest := -1.0
	for id: String in regions:
		var world: CampusWorld = regions[id]
		if not world.geometry_ready or permanent_model(id): continue
		count += 1
		if _wanted.has(id) or id == active: continue
		var distance := world.position.distance_squared_to(_view_at)
		if not near_view(id, _view_at, active, 22.0): distance += 1e6
		if distance > farthest:
			candidate = world
			farthest = distance
	if candidate == null: return false
	if count <= DETAIL_LIMIT and near_view(candidate.scene_id, _view_at, active, 22.0): return false
	# Releasing a model also frees GPU resources. Limit it to one outside the crossing.
	candidate.discard_resident_model()
	return true


func _refresh_visibility() -> void:
	var outside := regions.get("out") as CampusWorld
	for id: String in regions:
		var world: CampusWorld = regions[id]
		var model := world.get_node_or_null("Model") as Node3D
		var detail := permanent_model(id) or id == active or _visible_neighbours.has(id)
		if model != null and model.visible != detail: model.visible = detail
		if outside == null: continue
		var facade := outside.shells.get(id) as Node3D
		# From the street a warm room still needs its exterior. Only the current
		# interior takes precedence over any opaque legacy geometry on its own floor.
		var show_facade := id.begins_with("stair_") or id != active or model == null
		if facade != null and facade.visible != show_facade: facade.visible = show_facade


func _process(_delta: float) -> void:
	if _worker != null:
		if _worker.is_alive(): return
		var model := _worker.wait_to_finish() as Node3D
		_worker = null
		_accept_model(model)
		return
	if active.is_empty() or not nearby_visuals: return
	if _release_distant_model(): return
	for id: String in _wanted:
		var world := regions.get(id) as CampusWorld
		if world == null or world.geometry_ready or Time.get_ticks_msec() < int(_retry_after.get(id, 0)): continue
		_staging = _make(id)
		_staging.layout = world.layout
		_staging_tier = CampusData.tier
		# A detached tree is safe on the Vulkan worker. The headless renderer's
		# mesh storage runs on the same thread, so engine tests step the queue here.
		if DisplayServer.get_name() == "headless":
			_accept_model(_staging._prepare_visual(_staging_tier))
		else:
			_worker = Thread.new()
			if _worker.start(_staging._prepare_visual.bind(_staging_tier), Thread.PRIORITY_LOW) != OK:
				_worker = null
				_accept_model(null)
		return


func _accept_model(model: Node3D) -> void:
	var id := _staging.scene_id
	_staging.free()
	_staging = null
	if model == null:
		_retry_after[id] = Time.get_ticks_msec() + MODEL_RETRY_MS
		return
	var world: CampusWorld = regions[id]
	if _staging_tier != CampusData.tier or world.geometry_ready or not _wanted.has(id):
		model.free()
		return
	# Bind just before attaching: doors and the lift may have moved during the load.
	model.visible = id == active or _visible_neighbours.has(id)
	world._install_model(model, _staging_tier)
	world.geometry_ready = true
	_refresh_visibility()


func _exit_tree() -> void:
	if _worker == null: return
	while _worker.is_alive():
		RenderingServer.force_sync()
		OS.delay_usec(100)
	var model := _worker.wait_to_finish() as Node3D
	if model != null: model.free()
	_staging.free()
	_staging = null
	_worker = null


func update_lifts(lifts: ElevatorModule) -> void:
	space.update_lifts(lifts)
	_lift_landing = ""
	if not lifts.ride.is_empty() and active == "lift_" + String(lifts.ride.get("host", "")):
		_lift_landing = "%s%d" % [lifts.ride.host, int(lifts.ride.get("target", 0))]
	for world: CampusWorld in regions.values():
		if not world._lift_bodies.is_empty() or not world._lift_leaves.is_empty(): world.apply_lift_doors(lifts)
	for id: String in ["lift_teach", "lift_lab"]:
		var cabin := regions.get(id) as CampusWorld
		var frame := space.frame(id)
		if cabin != null and cabin.transform != frame:
			cabin.transform = frame


func apply_doors(doors: Dictionary) -> void:
	for world: CampusWorld in regions.values():
		world.apply_doors(doors)


func configure_graphics(options: Dictionary, camera: Camera3D) -> void:
	for world: CampusWorld in regions.values():
		world.configure_rendering(options, camera)
		if world.geometry_ready and world.visual_tier != CampusData.tier: world.reload_models(world.to_local(camera.global_position))
	update_view(camera.global_position)
