class_name CampusSpace
extends RefCounted
## One physical campus; region-local coordinates remain the save/rules contract.
## Explicit frames put all ordinary rooms in metres in the same physics world.

const SEPARATE := ["dream_top", "lift_dream", "portal_tunnel"]
var frames: Dictionary = {"out": Transform3D.IDENTITY}
var rooms: Dictionary
var outside: Dictionary
var campus: Dictionary


func _init(room_data: Dictionary = {}, out_data: Dictionary = {}, campus_data: Dictionary = {}) -> void:
	rooms = room_data
	outside = out_data
	campus = campus_data
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		if id in SEPARATE or r.get("host", "") == "lift" or r.get("flags", {}).get("stairwell", false): continue
		var shift := CampusGeometry.shift_of(r)
		var rise := 3.0 if r["host"] in ["dormN", "dormS"] else 3.2
		frames[id] = Transform3D(Basis.IDENTITY, Vector3((float(r["cx"]) + shift.x) / 9.0,
			maxi(0, int(r.get("floor", 1)) - 1) * rise, (float(r["cy"]) + shift.y) / 9.0))
	for stair: Dictionary in campus.get("stair_layout", []):
		var levels: Array = stair["rooms"]
		var level := levels.find("out") if levels.has("out") else 0
		var port := CampusPortals.stair_port(stair, level, rooms, outside)
		if port.is_empty(): continue
		var parent: Transform3D = frames[levels[level]]
		var p := CampusGeometry.to_scene(rooms.get(levels[level]), port["p"])
		var n: Vector2 = port["n"]
		var basis := Basis(Vector3.UP, -CampusPortals.stair_turn(n))
		var origin := parent * Vector3(p.x + n.x * 2.8, -level * float(stair["rise"]), p.y + n.y * 2.8)
		frames[stair["id"]] = Transform3D(parent.basis * basis, origin)
		# The old roof and underground floor use different origins. Their landing
		# must meet the real shaft, not teleport across the building at the door.
		for i in levels.size():
			var id := String(levels[i])
			if id not in ["teach6", "garage1"]: continue
			var door := CampusPortals.stair_port(stair, i, rooms, outside)
			var local := CampusGeometry.to_scene(rooms[id], door["p"])
			var target: Vector3 = frames[stair["id"]] * Vector3(0, i * float(stair["rise"]), -2.8)
			frames[id] = Transform3D(Basis.IDENTITY, target - Vector3(local.x, 0, local.y))
	# The old bridge annex overlaps the laboratory stair shaft by one metre.
	# Move the physical bridge within the existing 3 m doorway overlap.
	if frames.has("link2"): frames["link2"].origin.x += 1.0
	var lifts := ElevatorModule.new(rooms)
	lifts.reset()
	update_lifts(lifts)


func contains(id: String) -> bool:
	return frames.has(id)


func frame(id: String) -> Transform3D:
	return frames.get(id, Transform3D.IDENTITY)


func global_pose(id: String, pose: Dictionary) -> Dictionary:
	return transform_pose(frame(id), pose)


func local_pose(id: String, pose: Dictionary) -> Dictionary:
	return transform_pose(frame(id).affine_inverse(), pose)


static func transform_pose(t: Transform3D, pose: Dictionary) -> Dictionary:
	var result := pose.duplicate(true)
	var p: Array = pose["position"]
	var at := t * Vector3(p[0], p[1], p[2])
	result["position"] = [at.x, at.y, at.z]
	result["yaw"] = wrapf(float(pose["yaw"]) + t.basis.get_euler().y, -PI, PI)
	return result


func update_lifts(lifts: ElevatorModule, only_host: String = "") -> void:
	for host: String in ElevatorModule.HOSTS:
		if only_host != "" and host != only_host: continue
		var car := "lift_" + host
		var floor_id := host + "1"
		if not rooms.has(car) or not frames.has(floor_id): continue
		var car_f := lifts.frame(car)
		var floor_f := lifts.frame(floor_id)
		if car_f.is_empty() or floor_f.is_empty(): continue
		var a: Vector2 = car_f["out"]
		var b: Vector2 = floor_f["out"]
		var yaw := atan2(a.y, a.x) - atan2(b.y, b.x)
		var basis := Basis(Vector3.UP, yaw)
		var from := CampusGeometry.to_scene(rooms[car], car_f["j"])
		var to := CampusGeometry.to_scene(rooms[floor_id], floor_f["j"])
		var floor_value := float(lifts.lifts.get(host, {}).get("floor", 1))
		if lifts.ride.get("host") == host and lifts.ride.get("phase") == "moving":
			var first := float(lifts.ride["origin"])
			var last := float(lifts.ride["target"])
			var duration := float(ElevatorModule.CFG["travel"]) + absf(last - first) * float(ElevatorModule.CFG["per_floor"])
			floor_value = lerpf(first, last, clampf(1.0 - float(lifts.ride["remaining"]) / duration, 0, 1))
		frames[car] = frame(floor_id) * Transform3D(basis,
			Vector3(to.x, (floor_value - 1) * 3.2, to.y) - basis * Vector3(from.x, 0, from.y))


func local_bounds(id: String) -> Rect2:
	if id == "out":
		var b: Dictionary = outside["bound"]
		return Rect2(Vector2(b["x0"], b["z0"]), Vector2(b["x1"] - b["x0"], b["z1"] - b["z0"]))
	if rooms[id].get("flags", {}).get("stairwell", false): return Rect2(-2.6, -3.6, 5.2, 11.2)
	var r: Dictionary = rooms[id]
	var size := Vector2(float(r["cols"]) * float(r["tw"]), float(r["rows"]) * float(r["th"])) / 9.0
	return Rect2(-size * 0.5, size)


func floor_height(id: String) -> float:
	return 3.0 if rooms.get(id, {}).get("host", "") in ["dormN", "dormS"] else 3.2


func has_building(host: String) -> bool:
	for id: String in frames:
		if rooms.has(id) and rooms[id].get("host") == host: return true
	return false


func garage_hole() -> Rect2:
	var t := frame("stair_garage")
	var a := t * Vector3(-2.7, 0, -2.8)
	var b := t * Vector3(2.7, 0, 7.8)
	return Rect2(Vector2(minf(a.x,b.x), minf(a.z,b.z)), Vector2(absf(b.x-a.x),absf(b.z-a.z)))


static func subtract_rect(rect: Rect2, hole: Rect2) -> Array[Rect2]:
	var cut := rect.intersection(hole)
	if not cut.has_area(): return [rect]
	var parts: Array[Rect2] = []
	for part: Rect2 in [Rect2(rect.position, Vector2(cut.position.x-rect.position.x,rect.size.y)),
		Rect2(Vector2(cut.end.x,rect.position.y), Vector2(rect.end.x-cut.end.x,rect.size.y)),
		Rect2(Vector2(cut.position.x,rect.position.y), Vector2(cut.size.x,cut.position.y-rect.position.y)),
		Rect2(Vector2(cut.position.x,cut.end.y), Vector2(cut.size.x,rect.end.y-cut.end.y))]:
		if part.has_area(): parts.append(part)
	return parts


func stair_bounds(id: String) -> Rect2:
	var t := frame(id)
	var a := t * Vector3(-2.4,0,-2.3)
	var b := t * Vector3(2.4,0,7.3)
	return Rect2(Vector2(minf(a.x,b.x),minf(a.z,b.z)),Vector2(absf(b.x-a.x),absf(b.z-a.z)))


func replaces_outside_rect(rect: Rect2) -> bool:
	for stair: Dictionary in campus.get("stair_layout", []):
		var bounds := stair_bounds(stair.id)
		if bounds.intersects(rect): return true
	for id: String in ["lift_teach", "lift_lab"]:
		if lift_bounds(id).intersects(rect): return true
	return false


func lift_bounds(id: String) -> Rect2:
	var t := frame(id)
	var a := t * Vector3(-1.2,0,-1.0)
	var b := t * Vector3(1.2,0,1.0)
	return Rect2(Vector2(minf(a.x,b.x),minf(a.z,b.z)),Vector2(absf(b.x-a.x),absf(b.z-a.z)))


func cabin_cut(id: String) -> Rect2:
	var lift := ElevatorModule.new(rooms)
	var f := lift.frame(id)
	if f.is_empty() or id.begins_with("lift_"): return Rect2()
	var a := CampusGeometry.to_scene(rooms[id], lift.world(id,-3,-2))
	var b := CampusGeometry.to_scene(rooms[id], lift.world(id,-.5,2))
	return Rect2(a.min(b),(b-a).abs())


func bridge_volumes() -> Array[AABB]:
	var result: Array[AABB] = []
	for id: String in ["link1","link2"]:
		var rect := local_bounds(id)
		result.append(frame(id) * AABB(Vector3(rect.position.x,-.15,rect.position.y),Vector3(rect.size.x,floor_height(id)+.15,rect.size.y)))
	return result
