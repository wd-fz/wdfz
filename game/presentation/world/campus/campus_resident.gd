class_name CampusResident
extends Node3D
## One school in one World3D. Regions never leave the tree at a doorway.
var regions: Dictionary = {}
var space: CampusSpace
var configure: Callable
var active := ""
var builds := 0
## Physics stays resident everywhere. Android loads detail near the player and keeps
## the outdoor facades visible until the replacement models are ready.
var nearby_visuals := OS.get_name() == "Android"
var _retry_after: Dictionary = {}
var _visibility_acc := 0.0


func _make(id: String) -> CampusWorld:
	var world := CampusWorld.new()
	world.name = id
	world.scene_id = id
	world.resident = true
	world.space = space
	if configure.is_valid(): configure.call(world)
	world.transform = space.frame(id)
	return world


func _accept(world: CampusWorld) -> void:
	regions[world.scene_id] = world
	add_child(world)
	builds += 1


func prepare(id: String, with_model: bool = true) -> CampusWorld:
	var world := regions.get(id) as CampusWorld
	var fresh := world == null
	if fresh: world = _make(id)
	if with_model and not world.geometry_ready: world.prepare_geometry()
	world.prepare_collision()
	if fresh: _accept(world)
	return world


func select(id: String) -> CampusWorld:
	if regions.has(active):
		(regions[active] as CampusWorld).deactivate()
	active = id
	var world := prepare(id)
	world.activate()
	return world


func suspend() -> void:
	if regions.has(active): (regions[active] as CampusWorld).deactivate()
	active = ""
	hide()
	# Special spaces have their own collision, far from the physical school.
	for world: CampusWorld in regions.values(): world.set_collision_enabled(false)


func resume() -> void:
	show()
	for world: CampusWorld in regions.values(): world.set_collision_enabled(true)


func near_view(id: String, at: Vector3, focus: String, margin: float = 0.0) -> bool:
	if id == "out" or id == focus: return true
	var local := space.frame(id).affine_inverse() * at
	var point := Vector2(local.x, local.z)
	var rect := space.local_bounds(id)
	var distance := point.distance_to(point.clamp(rect.position, rect.end))
	if space.rooms[id].get("flags", {}).get("stairwell", false):
		return distance < 35.0 + margin
	return distance < 26.0 + margin and absf(local.y) < 5.0 + margin * .2


func update_view(at: Vector3, dt: float = 0.0) -> void:
	_visibility_acc += dt
	if dt > 0.0 and _visibility_acc < 0.2: return
	_visibility_acc = 0.0
	var outside := regions.get("out") as CampusWorld
	var loaded_one := false
	for id: String in regions:
		var world: CampusWorld = regions[id]
		var detail := near_view(id, at, active)
		var shell := outside.shells.get(id) as Node3D if outside != null else null
		if nearby_visuals:
			if not world.geometry_ready and not loaded_one and near_view(id, at, active, 5.0) and Time.get_ticks_msec() >= int(_retry_after.get(id, 0)):
				world.prepare_geometry()
				loaded_one = true
				if not world.geometry_ready: _retry_after[id] = Time.get_ticks_msec() + 10000
			elif world.geometry_ready and not near_view(id, at, active, 22.0):
				world.discard_resident_model()
		elif shell == null:
			detail = true
		var model := world.get_node_or_null("Model") as Node3D
		if model != null: model.visible = detail
		if shell != null: shell.visible = not detail or model == null


func update_lifts(lifts: ElevatorModule) -> void:
	space.update_lifts(lifts)
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
