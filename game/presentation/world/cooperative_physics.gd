class_name CooperativePhysics
extends Node
## Isolated, renderless physics spaces. Local room coordinates never overlap.
var zones: Dictionary = {}
var bodies: Dictionary = {}
var body_worlds: Dictionary = {}
var _last_seen: Dictionary = {}
var _time := 0.0


func zone(id: String) -> SubViewport:
	if zones.has(id): return zones[id]
	var view := SubViewport.new()
	view.name = "Authority_" + id
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.size = Vector2i(2, 2)
	view.gui_disable_input = true
	add_child(view)
	var world := CampusWorld.new()
	world.name = "Geometry"
	world.scene_id = id
	world.collision_only = true
	view.add_child(world)
	zones[id] = view
	return view


func place(a: CooperativeActor) -> CharacterBody3D:
	var view := zone(a.location())
	var body: CharacterBody3D = bodies.get(a.id)
	if body == null:
		body = CharacterBody3D.new()
		body.name = "Body_" + a.id
		body.collision_layer = 4
		body.collision_mask = 3
		body.floor_snap_length = 0.25
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3333
		shape.height = 1.75
		collider.shape = shape
		collider.position.y = 0.875
		body.add_child(collider)
		view.add_child(body)
		bodies[a.id] = body
	elif body_worlds.get(a.id, "") != a.location():
		body.reparent(view, false)
		body.velocity = Vector3.ZERO
	body_worlds[a.id] = a.location()
	var p: Array = a.pose["position"]
	body.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	_last_seen[a.location()] = _time
	return body


func advance(a: CooperativeActor, dt: float) -> void:
	var body := place(a)
	a.processed_sequence = a.input_sequence
	a.pose["yaw"] = a.input["yaw"]
	a.pose["pitch"] = a.input["pitch"]
	var blocked := a.vehicle or a.fate().over() or a.school().seated or bool(a.watcher().hide["on"]) or not a.choice.is_empty() or a.terminal or (a.feature(&"body.injury") as BodyModule).fall != null
	if blocked:
		body.velocity = Vector3.ZERO
		a.moving = false
		a.running = false
		return
	var axis := Vector2(float(a.input["x"]), float(a.input["y"])).limit_length()
	a.running = bool(a.input["run"]) and axis.length() > 0.08 and a.school().can_run(a.bag().snack_active())
	var limbs := a.feature(&"body.injury") as BodyModule
	if limbs != null: a.running = a.running and limbs.can_run()
	var multiplier := (1.5 if a.bag().snack_active() else 1.0) * (limbs.speed_mul() if limbs != null else 1.0)
	var before := body.position
	CharacterMotor.advance(body, axis, float(a.pose["yaw"]), a.running, multiplier, dt)
	a.moving = Vector2(body.position.x - before.x, body.position.z - before.z).length() > 0.0001 / 9.0
	if not a.moving: a.running = false
	a.pose["position"] = [body.position.x, body.position.y, body.position.z]


func sync_doors(rules: CampusModule, lifts: ElevatorModule) -> void:
	for view: SubViewport in zones.values():
		var world := view.get_node("Geometry") as CampusWorld
		world.apply_doors(rules._open_doors)
		world.apply_lift_doors(lifts)


func maintain(dt: float, active: Array) -> void:
	_time += dt
	for key: String in zones.keys():
		if key in active: _last_seen[key] = _time
		elif _time - float(_last_seen.get(key, _time)) > 10.0:
			zones[key].queue_free()
			zones.erase(key)
			_last_seen.erase(key)


func remove_actor(id: String) -> void:
	if bodies.has(id):
		bodies[id].queue_free()
		bodies.erase(id)
		body_worlds.erase(id)
