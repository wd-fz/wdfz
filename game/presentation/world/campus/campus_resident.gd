class_name CampusResident
extends Node3D
## One school in one World3D. Regions never leave the tree at a doorway.
var regions: Dictionary = {}
var space: CampusSpace
var configure: Callable
var active := ""
var builds := 0
## Initial geometry is built one region per loading-screen frame. Mesh clipping
## reads renderer buffers; keeping it on the main thread avoids thousands of
## worker/render-server round trips. Ordinary play performs no geometry work.
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


func prepare(id: String) -> CampusWorld:
	if regions.has(id): return regions[id]
	var world := _make(id)
	world.prepare_geometry()
	_accept(world)
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


func update_view(at: Vector3, dt: float = 0.0) -> void:
	_visibility_acc += dt
	if dt > 0.0 and _visibility_acc < 0.2: return
	_visibility_acc = 0.0
	for id: String in regions:
		var world: CampusWorld = regions[id]
		var local := world.to_local(at)
		var rect := space.local_bounds(id)
		var nearest := Vector2(clampf(local.x, rect.position.x, rect.end.x), clampf(local.z, rect.position.y, rect.end.y))
		var distance := Vector2(local.x, local.z).distance_to(nearest)
		var detail := id == "out" or id == active or (distance < 26.0 and absf(local.y) < 5.0)
		if world.layout.get("flags", {}).get("stairwell", false): detail = distance < 35.0
		var model := world.get_node_or_null("Model") as Node3D
		if model != null: model.visible = detail
		var outside := regions.get("out") as CampusWorld
		if outside != null and outside.shells.has(id): (outside.shells[id] as Node3D).visible = not detail


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
		if world.visual_tier != CampusData.tier: world.reload_models(world.to_local(camera.global_position))
	update_view(camera.global_position)
