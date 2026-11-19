class_name CooperativePhysics
extends Node
## One renderless school shared by all actors. Special spaces remain isolated.
var zones: Dictionary = {}
var bodies: Dictionary = {}
var body_worlds: Dictionary = {}
var _last_seen: Dictionary = {}
var _time := 0.0
var space: CampusSpace
var school_view: SubViewport
var geometry: Dictionary = {}


func _view(id: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = "Authority_" + id
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.size = Vector2i(2, 2)
	view.gui_disable_input = true
	add_child(view)
	return view


static func private_world(id: String) -> bool:
	return id in [MazeModule.ROOM, InceptionModule.ROOM]

static func instance_key(a: CooperativeActor) -> String:
	return a.location() + "@" + a.id if private_world(a.location()) else a.location()

func zone(id: String, instance: String = "") -> SubViewport:
	var key := id + "@" + instance if private_world(id) and not instance.is_empty() else id
	if zones.has(key): return zones[key]
	if space == null: space = CampusSpace.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	if space.contains(id):
		if school_view == null:
			school_view = _view("School")
			for region: String in space.frames:
				var world := CampusWorld.new()
				world.name = region
				world.scene_id = region
				world.collision_only = true
				world.resident = true
				world.space = space
				world.transform = space.frame(region)
				geometry[region] = world
				school_view.add_child(world)
		zones[id] = school_view
	else:
		var view := _view(key)
		var world := CampusWorld.new()
		world.name = "Geometry"
		world.scene_id = id
		world.collision_only = true
		geometry[key] = world
		view.add_child(world)
		zones[key] = view
	return zones[key]


func place(a: CooperativeActor, preserve_motion: bool = false) -> CharacterBody3D:
	zone(a.location(), a.id)
	var frame: Node3D = geometry[instance_key(a)]
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
		frame.add_child(body)
		bodies[a.id] = body
	elif body_worlds.get(a.id, "") != a.location():
		body.reparent(frame, false)
		if not preserve_motion: body.velocity = Vector3.ZERO
	body_worlds[a.id] = a.location()
	var p: Array = a.pose["position"]
	var position := Vector3(p[0], p[1], p[2])
	if body.position != position:
		body.position = position
	_last_seen[instance_key(a)] = _time
	return body


func advance(a: CooperativeActor, dt: float) -> void:
	var body := place(a)
	a.pose["yaw"] = a.input["yaw"]
	a.pose["pitch"] = a.input["pitch"]
	var blocked := (a.feature(&"story.knife") as KnifeModule).captured() or (a.feature(&"story.paper_plane") as PaperPlaneModule).phase() in ["read", "flight"] or not a.activities.game.is_empty() or a.vehicle or a.fate().over() or a.school().seated or bool(a.watcher().hide["on"]) or not a.choice.is_empty() or a.terminal or (a.feature(&"body.injury") as BodyModule).fall != null
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
	var maze: MazeModule = a.feature(&"campus.maze") if a.location() == MazeModule.ROOM else null
	body.floor_snap_length = float(maze.geometry.cfg["snap"]) if maze != null else 0.25
	CharacterMotor.advance(body, axis, float(a.pose["yaw"]) + body.get_parent().global_rotation.y, a.running, multiplier, dt, float(maze.geometry.cfg["gravity"]) if maze != null else 9.8, float(maze.geometry.cfg["maxFall"]) if maze != null else INF)
	a.moving = Vector2(body.position.x - before.x, body.position.z - before.z).length() > 0.0001 / 9.0
	if not a.moving: a.running = false
	a.pose["position"] = [body.position.x, body.position.y, body.position.z]


func sync_doors(rules: CampusModule, lifts: ElevatorModule, engines: Dictionary = {}) -> void:
	if space != null:
		for host: String in ElevatorModule.HOSTS:
			space.update_lifts(engines.get(host, lifts), host)
			var id := "lift_" + host
			var cabin := geometry.get(id) as CampusWorld
			var frame := space.frame(id)
			if cabin != null and cabin.transform != frame:
				cabin.transform = frame
	for world: CampusWorld in geometry.values():
		world.apply_doors(rules._open_doors)
		if not world._lift_bodies.is_empty():
			world.apply_lift_doors(lifts)


func maintain(dt: float, active: Array) -> void:
	_time += dt
	for key: String in zones.keys():
		if key in active: _last_seen[key] = _time
		elif _time - float(_last_seen.get(key, _time)) > 10.0:
			if zones[key] != school_view:
				zones[key].queue_free()
				geometry.erase(key)
			zones.erase(key)
			_last_seen.erase(key)


func actor_position(a: CooperativeActor) -> Vector3:
	var p: Array = a.pose["position"]
	var local := Vector3(p[0], p[1], p[2])
	return space.frame(a.location()) * local if space != null and space.contains(a.location()) else local


func actor_distance(a: CooperativeActor, b: CooperativeActor) -> float:
	if a.id != b.id and (private_world(a.location()) or private_world(b.location())): return INF
	if a.location() != b.location() and (space == null or not space.contains(a.location()) or not space.contains(b.location())): return INF
	return actor_position(a).distance_to(actor_position(b))


func can_exchange(a: CooperativeActor, b: CooperativeActor) -> bool:
	if actor_distance(a, b) > 2.0: return false
	var from := actor_position(a) + Vector3.UP * 1.1
	var to := actor_position(b) + Vector3.UP * 1.1
	if from.distance_squared_to(to) < .0001: return true
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	return zone(a.location()).find_world_3d().direct_space_state.intersect_ray(query).is_empty()


func sees_point(a: CooperativeActor, point: Dictionary, radius: float) -> bool:
	var region := String(point.get("scene", ""))
	if space == null or not space.contains(a.location()) or not space.contains(region): return false
	var local := CampusGeometry.to_scene(CampusData.rooms().get(region), Vector2(point["x"], point["y"]))
	var target := space.frame(region) * Vector3(local.x, float(point.get("fy", 0)), local.y) + Vector3.UP * 1.1
	var origin := actor_position(a) + Vector3.UP * 1.1
	if origin.distance_to(target) > radius: return false
	if origin.distance_squared_to(target) < .0001: return true
	return school_view.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target, 3)).is_empty()


func remove_actor(id: String) -> void:
	if bodies.has(id):
		bodies[id].queue_free()
		bodies.erase(id)
		body_worlds.erase(id)
