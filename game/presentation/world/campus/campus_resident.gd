class_name CampusResident
extends Node3D
## The World3D and collision stay live through every ordinary campus crossing.
const INDOOR_VIEW_DISTANCE := 10.0
const PORTAL_TRANSITION_DISTANCE := 2.0
const PORTAL_VIEW_HEIGHT := 1.5
const MODEL_RETRY_MS := 10000
const EVICTION_INTERVAL_MS := 400
const DETAIL_LIMIT := 12

var regions: Dictionary = {}
var space: CampusSpace
var configure: Callable
var active := ""
var builds := 0
var nearby_visuals := OS.get_name() == "Android"
var _portals: Array[Dictionary] = []
var _visible_neighbours := PackedStringArray()
var _preview_lights: Dictionary = {}
var _wanted := PackedStringArray()
var _retry_after: Dictionary = {}
var _worker: Thread
var _staging: CampusWorld
var _staging_tier := -1
var _lift_landing := ""
var _view_at := Vector3.ZERO
var _shelter := -1.0
var _evict_at := 0
var _light_time := 0.0
var _overcast := 0.0


func _ready() -> void:
	_portals = CampusConnections.resident_portals(space)


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
	var previous := regions.get(active) as CampusWorld
	if previous != null and id != active:
		_light_time = previous.lighting.time
		_overcast = previous.lighting.overcast
		previous.deactivate(true)
		_preview_lights[active] = previous
	var world := prepare(id, not ready_only)
	var changed := active != id
	active = id
	_preview_lights.erase(id)
	if not world.geometry_ready:
		_wanted = PackedStringArray([id])
	_refresh_visibility()
	world.activate()
	if changed:
		world.lighting.time = _light_time
		world.lighting.overcast = _overcast
	return world


func suspend() -> void:
	var previous := regions.get(active) as CampusWorld
	if previous != null:
		_light_time = previous.lighting.time
		_overcast = previous.lighting.overcast
		previous.deactivate()
	for world: CampusWorld in _preview_lights.values(): world.clear_lighting()
	_preview_lights.clear()
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
	_view_at = at
	var nearby_portals: Array[Dictionary] = []
	var thresholds: Array[Dictionary] = []
	for portal: Dictionary in _portals:
		var offset: Vector3 = at - portal["at"]
		if absf(offset.y) > PORTAL_VIEW_HEIGHT: continue
		var distance := Vector2(offset.x, offset.z).length_squared()
		if distance <= INDOOR_VIEW_DISTANCE * INDOOR_VIEW_DISTANCE: nearby_portals.append(portal)
		if distance <= PORTAL_TRANSITION_DISTANCE * PORTAL_TRANSITION_DISTANCE: thresholds.append(portal)
	# Treat the two labels at a threshold as one viewpoint. Farther away only
	# show directly connected areas so rooms behind unrelated walls stay culled.
	var sides := {active: true}
	var size := 0
	while sides.size() != size:
		size = sides.size()
		for portal: Dictionary in thresholds:
			if not sides.has(portal["a"]) and not sides.has(portal["b"]): continue
			sides[portal["a"]] = true
			sides[portal["b"]] = true
	var visible_regions := {}
	for portal: Dictionary in nearby_portals:
		if not sides.has(portal["a"]) and not sides.has(portal["b"]): continue
		visible_regions[portal["a"]] = true
		visible_regions[portal["b"]] = true
	_visible_neighbours = PackedStringArray(visible_regions.keys())
	_shelter = _threshold_shelter(at, thresholds, sides)
	_refresh_visibility()
	if not nearby_visuals: return
	_wanted = PackedStringArray([active])
	if not _lift_landing.is_empty(): _wanted.append(_lift_landing)
	_wanted.append_array(_visible_neighbours)
	var local := space.frame(active).affine_inverse() * at
	_wanted.append_array(CampusConnections.nearby(active, local))


func _threshold_shelter(at: Vector3, thresholds: Array[Dictionary], sides: Dictionary) -> float:
	var shelter := -1.0
	var nearest := INF
	for portal: Dictionary in thresholds:
		if not sides.has(portal["a"]): continue
		var a_open := _open_air(portal["a"])
		if a_open == _open_air(portal["b"]): continue
		var offset: Vector3 = at - portal["at"]
		var distance := offset.length_squared()
		if distance >= nearest: continue
		nearest = distance
		var toward_b: Vector3 = portal["toward_b"]
		var inside := offset.dot(toward_b) * (1.0 if a_open else -1.0)
		shelter = smoothstep(-PORTAL_TRANSITION_DISTANCE, PORTAL_TRANSITION_DISTANCE, inside)
	return shelter


func _open_air(id: String) -> bool:
	return id in ["out", "teach6"] or bool(space.rooms.get(id, {}).get("flags", {}).get("gallery", false))


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


func view_lighting() -> Array[CampusWorld]:
	for id: String in _preview_lights.keys():
		if _visible_neighbours.has(id): continue
		(_preview_lights[id] as CampusWorld).clear_lighting()
		_preview_lights.erase(id)
	var lit: Array[CampusWorld] = []
	for id: String in regions:
		var world: CampusWorld = regions[id]
		if id == active:
			lit.append(world)
		elif _visible_neighbours.has(id):
			if not _preview_lights.has(id):
				world._build_lighting(false)
				_preview_lights[id] = world
			lit.append(world)
	return lit


## Fade into the garage's dedicated palette on the way down the shaft.
func garage_depth() -> float:
	if active not in ["garage1", "stair_garage"] and not _visible_neighbours.has("stair_garage"): return -1.0
	return smoothstep(0.0, -space.frame("garage1").origin.y, -_view_at.y)


func light_shelter() -> float:
	var depth := garage_depth()
	return depth if depth >= 0.0 else _shelter


func _refresh_visibility() -> void:
	var outside := regions.get("out") as CampusWorld
	for id: String in regions:
		var world: CampusWorld = regions[id]
		var model := world.get_node_or_null("Model") as Node3D
		var near_portal := _visible_neighbours.has(id)
		var detail := permanent_model(id) or id == active or near_portal
		if model != null and model.visible != detail: model.visible = detail
		world.set_fixed_props_visible(detail)
		if model == null and detail:
			world.show_cold_geometry()
		elif not detail:
			var cold := world.get_node_or_null("ColdGeometry")
			if cold != null: cold.free()
		if outside == null: continue
		var facade := outside.shells.get(id) as Node3D
		if facade == null or id.begins_with("stair_"): continue
		# Street views retain the exterior. At a portal, select it using physical
		# occupancy so both labels draw the same wall from the same position.
		var inside := id == active
		if near_portal:
			var p := space.frame(id).affine_inverse() * _view_at
			inside = p.y >= -.15 and p.y < space.floor_height(id) - .15 and space.local_bounds(id).has_point(Vector2(p.x, p.z))
		var show_facade := not inside or model == null
		if facade.visible != show_facade: facade.visible = show_facade


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
