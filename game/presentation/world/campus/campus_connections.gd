class_name CampusConnections
extends RefCounted
## Streaming hints in scene metres. Region IDs and portal transforms remain the save/network contract.
## A doorway is prepared while approaching it, including the next landing while climbing stairs.

const LOOK_AHEAD := 42.0
const NEIGHBOURS := 2


## Both labels of a walk-through connection view the same physical threshold.
static func resident_portals(space: CampusSpace) -> Array[Dictionary]:
	var portals: Array[Dictionary] = []
	for door: Dictionary in space.campus.get("campus_doors", {}).get("doors", []):
		var id := String(door["room"])
		var room: Dictionary = space.rooms[id]
		var port := CampusGeometry.door_port(room, door)
		var normal: Vector2 = port["n"]
		var inward := space.frame(id).basis * Vector3(-normal.x, 0, -normal.y)
		portals.append({"a": "out", "b": id, "at": _school_point(space, id, port["p"]), "toward_b": inward})
	for stair: Dictionary in space.campus.get("stair_layout", []):
		var id := String(stair["id"])
		var levels: Array = stair["rooms"]
		for level in levels.size():
			var at := space.frame(id) * Vector3(0, level * float(stair["rise"]), CampusPortals.THRESHOLD_Z)
			portals.append({"a": id, "b": String(levels[level]), "at": at, "toward_b": space.frame(id).basis * Vector3.FORWARD})
	var links: Dictionary = space.campus.get("campus_link", {})
	for bridge: String in CampusSpace.BRIDGES:
		for link: Dictionary in CampusPortals.link_ports(links, space.rooms, bridge):
			var normal: Vector2 = link["self"]["n"]
			portals.append({"a": bridge, "b": String(link["peer"]["room"]), "at": _school_point(space, bridge, link["self"]["p"]), "toward_b": Vector3(normal.x, 0, normal.y)})
	for host: String in ElevatorModule.HOSTS:
		for floor in range(1, 6):
			var id := host + str(floor)
			var landing := CampusData.lift_geometry().frame(id)
			if not landing.is_empty():
				var normal: Vector2 = landing["out"]
				portals.append({"a": "lift_" + host, "b": id, "at": _school_point(space, id, landing["j"]), "toward_b": Vector3(normal.x, 0, normal.y)})
	return portals


static func _school_point(space: CampusSpace, id: String, point: Vector2) -> Vector3:
	var local := CampusGeometry.to_scene(space.rooms.get(id), point)
	return space.frame(id) * Vector3(local.x, 0, local.y)


static func nearby(id: String, position: Vector3, distance_limit: float = LOOK_AHEAD) -> PackedStringArray:
	var rooms := CampusData.rooms()
	if id != "out" and not rooms.has(id):
		return PackedStringArray()
	var campus := CampusData.campus()
	var distances := {}
	for door: Dictionary in campus.get("campus_doors", {}).get("doors", []):
		var target := String(door["room"])
		if id != "out" and id != target:
			continue
		var room: Dictionary = rooms[target]
		var port := CampusGeometry.door_port(room, door)
		var p := CampusGeometry.to_scene(room, port["p"])
		var threshold := Vector3(p.x, 0, p.y)
		if id == "out": threshold = CampusGeometry.campus_frame(room) * threshold
		_offer(distances, target if id == "out" else "out", position.distance_to(threshold))
	for stair: Dictionary in campus.get("stair_layout", []):
		var levels: Array = stair["rooms"]
		if id == String(stair["id"]):
			for level in levels.size():
				# Weight vertical distance: prepare this landing and the next one, not every storey.
				var distance := Vector3(position.x, (position.y - level * float(stair["rise"])) * 3.0, position.z + 2.8).length()
				_offer(distances, String(levels[level]), distance)
		elif levels.has(id):
			var port := CampusPortals.stair_port(stair, levels.find(id), rooms, CampusData.layout("out"))
			if not port.is_empty():
				var p := CampusGeometry.to_scene(rooms.get(id), port["p"])
				_offer(distances, String(stair["id"]), position.distance_to(Vector3(p.x, 0, p.y)))
	if id == "out":
		for building: Dictionary in CampusData.layout("out").objects:
			var target: String = CampusModule.ENTRY_ROOMS.get(building.id, "")
			if target.is_empty() or building.get("door_world") == null: continue
			var door: Dictionary = building.door_world
			var p := CampusGeometry.to_scene(null, Vector2(door.x, door.y))
			_offer(distances, target, position.distance_to(Vector3(p.x, 0, p.y)))
	else:
		var landing := CampusData.lift_geometry().frame(id)
		if not landing.is_empty() and not id.begins_with("lift_"):
			var p := CampusGeometry.to_scene(rooms[id], landing.j)
			_offer(distances, "lift_" + String(rooms[id].host), position.distance_to(Vector3(p.x, 0, p.y)))
		for link: Dictionary in CampusPortals.link_ports(campus.get("campus_link", {}), rooms, id):
			var p := CampusGeometry.to_scene(rooms[id], link["self"]["p"])
			_offer(distances, String(link["peer"]["room"]), position.distance_to(Vector3(p.x, 0, p.y)))
	var order := distances.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return float(distances[a]) < float(distances[b]))
	var result := PackedStringArray()
	for target: String in order:
		if float(distances[target]) <= distance_limit and result.size() < NEIGHBOURS:
			result.append(target)
	return result


static func _offer(distances: Dictionary, id: String, distance: float) -> void:
	distances[id] = minf(float(distances.get(id, INF)), distance)
