class_name CampusSpace
extends RefCounted
## One physical campus; region-local coordinates remain the save/rules contract.
## Explicit frames put all ordinary rooms in metres in the same physics world.

const BRIDGES := ["link1", "link2"]
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
		var rise := 3.0 if r["host"] in ["dormN", "dormS"] else 3.2
		var footprint := CampusGeometry.campus_frame(r)
		footprint.origin.y = maxi(0, int(r.get("floor", 1)) - 1) * rise
		frames[id] = footprint
	for stair: Dictionary in campus.get("stair_layout", []):
		var levels: Array = stair["rooms"]
		var level := levels.find("out") if levels.has("out") else 0
		var port := CampusPortals.stair_port(stair, level, rooms, outside)
		if port.is_empty(): continue
		var parent: Transform3D = frames[levels[level]]
		var p := CampusGeometry.to_scene(rooms.get(levels[level]), port["p"])
		var n: Vector2 = port["n"]
		var basis := Basis(Vector3.UP, -CampusPortals.stair_turn(n))
		var origin := parent * Vector3(p.x - n.x * CampusPortals.THRESHOLD_Z, -level * float(stair["rise"]), p.y - n.y * CampusPortals.THRESHOLD_Z)
		frames[stair["id"]] = Transform3D(parent.basis * basis, origin)
		# The old roof and underground floor use different origins. Their landing
		# must meet the real shaft, not teleport across the building at the door.
		for i in levels.size():
			var id := String(levels[i])
			if id not in ["teach6", "garage1"]: continue
			var door := CampusPortals.stair_port(stair, i, rooms, outside)
			var local := CampusGeometry.to_scene(rooms[id], door["p"])
			var target: Vector3 = frames[stair["id"]] * Vector3(0, i * float(stair["rise"]), CampusPortals.THRESHOLD_Z)
			frames[id] = Transform3D(Basis.IDENTITY, target - Vector3(local.x, 0, local.y))
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


## At street level only the narrow entry slab and the switchback replace the pavement.
## Cutting the shaft's bounding box also removes the ground beside both door jambs.
func garage_openings() -> Array[Rect2]:
	var shaft := frame("stair_garage")
	return [
		_footprint(shaft, CampusPortals.DOOR_HALF, CampusPortals.THRESHOLD_Z, CampusPortals.SHAFT_FRONT),
		_footprint(shaft, CampusPortals.SHAFT_HALF_WIDTH, CampusPortals.SHAFT_FRONT, CampusPortals.SHAFT_BACK),
	]


static func _footprint(t: Transform3D, half_width: float, front: float, back: float) -> Rect2:
	var a := t * Vector3(-half_width, 0, front)
	var b := t * Vector3(half_width, 0, back)
	return Rect2(Vector2(a.x, a.z), Vector2(b.x - a.x, b.z - a.z)).abs()


## Older saves can have feet below the missing pavement or even below the basement.
## All three regions save floor-relative coordinates. A legitimate basement pose has y near zero.
func garage_resume_pose(id: String, pose: Dictionary) -> Dictionary:
	if id not in ["out", "stair_garage", "garage1"]: return pose
	var p: Array = pose["position"]
	if float(p[1]) >= -0.15: return pose
	var safe := Vector3(0, 0.05, 0) # bottom landing in shaft-local coordinates
	if id == "out":
		# A still-falling player can have moved away from the opening below the school.
		if float(p[1]) >= frame("garage1").origin.y - 0.15 and not stair_bounds("stair_garage").grow(2.0).has_point(Vector2(p[0], p[2])): return pose
		safe = frame("stair_garage") * Vector3(0, 0, CampusPortals.ENTRY_START - 0.75)
		safe.y = 0.05
	elif id == "garage1":
		var spawn: Dictionary = rooms[id]["spawn"]
		safe = Vector3(spawn.scene_x, 0.05, spawn.scene_z)
	var restored := pose.duplicate()
	restored["position"] = [safe.x, safe.y, safe.z]
	return restored


func resume_pose(id: String, pose: Dictionary) -> Dictionary:
	var restored := garage_resume_pose(id, pose)
	return outdoor_resume_pose(restored) if id == "out" else restored


## Old outdoor coordinates may now lie inside a relocated ground-floor room.
func outdoor_resume_pose(pose: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var at := Vector2(p[0], p[2])
	var scale_m := float(outside["SC"]) * CampusGeometry.U2M
	for building: Dictionary in outside["objects"]:
		if not building.id in ["gear", "admin", "lab", "dormN", "dormS", "canteen"]: continue
		var plot := Rect2(building.x * scale_m, building.y * scale_m, building.w * scale_m, building.h * scale_m)
		if not plot.grow(-.05).has_point(at): continue
		var entrance: Dictionary = building.door_world
		var safe := pose.duplicate(true)
		safe["position"] = [entrance.x * CampusGeometry.U2M, .05, entrance.y * CampusGeometry.U2M]
		return safe
	return pose


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
	return _footprint(frame(id), 2.4, -2.3, 7.3)


## The exporter rounds footprints to four decimals. Cut only the part replaced
## by a real shaft; obstacles which straddle its edge still block on the outside.
func shaft_footprints() -> Array[Rect2]:
	var cuts: Array[Rect2]=[]
	for stair: Dictionary in campus.get("stair_layout", []):
		cuts.append(stair_bounds(stair.id).grow(.001))
	for host: String in ElevatorModule.HOSTS:
		cuts.append(lift_bounds("lift_"+host).grow(.001))
	return cuts


## Fixed shaft walls surround the travelling car. Each landing's floor model
## supplies its own door on the open (-Z) side. Bounds also drive the rendering.
func lift_walls() -> Array[AABB]:
	var walls: Array[AABB]=[]
	for host: String in ElevatorModule.HOSTS:
		var ground:=frame("lift_"+host)
		ground.origin.y=frame(host+"1").origin.y
		var height:=frame(host+"5").origin.y+floor_height(host+"5")-ground.origin.y
		for rect: Rect2 in [Rect2(-1.15,-1.0,.12,1.98),Rect2(1.03,-1.0,.12,1.98),Rect2(-1.03,.86,2.06,.12)]:
			walls.append(ground*AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,height,rect.size.y)))
	return walls


func lift_bounds(id: String) -> Rect2:
	return _footprint(frame(id), 1.2, -1.0, 1.0)


func cabin_cut(id: String) -> Rect2:
	var lift := ElevatorModule.new(rooms)
	var f := lift.frame(id)
	if f.is_empty() or id.begins_with("lift_"): return Rect2()
	var a := CampusGeometry.to_scene(rooms[id], lift.world(id,-3,-2))
	var b := CampusGeometry.to_scene(rooms[id], lift.world(id,-.5,2))
	return Rect2(a.min(b),(b-a).abs())


func bridge_volumes() -> Array[AABB]:
	var result: Array[AABB] = []
	for id: String in BRIDGES:
		var rect := local_bounds(id)
		result.append(frame(id) * AABB(Vector3(rect.position.x,-.15,rect.position.y),Vector3(rect.size.x,floor_height(id)+.15,rect.size.y)))
	return result


## The visual windows and brickwork can sit just past the physical bridge edge.
## Give every real doorway a narrow overlap into its adjoining building.
func bridge_openings() -> Array[AABB]:
	var openings: Array[AABB] = []
	var config: Dictionary = campus.get("campus_link", {})
	for id: String in BRIDGES:
		for connection: Dictionary in CampusPortals.link_ports(config, rooms, id):
			var portal: Dictionary = connection.self
			var center := CampusGeometry.to_scene(rooms[id], portal.p)
			var outward: Vector2 = portal.n
			var side := Vector2(-outward.y, outward.x)
			var half := float(portal.half) * CampusGeometry.U2M
			var a := center - side * half - outward * .16
			var b := center + side * half + outward * .28
			var corner := a.min(b)
			var size := (a - b).abs()
			openings.append(frame(id) * AABB(Vector3(corner.x, -.02, corner.y), Vector3(size.x, 2.42, size.y)))
	return openings
