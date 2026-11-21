class_name CampusConnections
extends RefCounted
## Streaming hints in scene metres. Region IDs and portal transforms remain the save/network contract.
## A doorway is prepared while approaching it, including the next landing while climbing stairs.

const LOOK_AHEAD := 42.0
const NEIGHBOURS := 2


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
		var p: Vector2 = port["p"]
		p = (p + CampusGeometry.shift_of(room)) * CampusGeometry.U2M if id == "out" else CampusGeometry.to_scene(room, p)
		_offer(distances, target if id == "out" else "out", position.distance_to(Vector3(p.x, 0, p.y)))
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
