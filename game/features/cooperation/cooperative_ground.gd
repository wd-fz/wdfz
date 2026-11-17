class_name CooperativeGround
extends RefCounted
## Project legacy region-local ground entries into the viewer's continuous school frame.
static func local_entries(entries: Array, viewer: String, space: CampusSpace) -> Array:
	var out: Array = []
	for i in entries.size():
		var source: Dictionary = entries[i]
		var world := String(source["world"])
		if world != viewer and (space == null or not space.contains(world) or not space.contains(viewer)): continue
		var e := source.duplicate()
		var p := Vector3(e["x"], e["y"], e["z"])
		if world != viewer: p = space.frame(viewer).affine_inverse() * (space.frame(world) * p)
		e.merge({"world": viewer, "x": p.x, "y": p.y, "z": p.z, "index": i}, true)
		out.append(e)
	return out

static func target(entries: Array, feet: Vector3, eye: Vector3, look: Vector3) -> int:
	var best := -1
	var angle := InventoryModule.PICK_AIM
	for e: Dictionary in entries:
		var p := Vector3(e["x"], e["y"], e["z"])
		if absf(p.y - feet.y) > InventoryModule.PICK_RISE or Vector2(p.x - feet.x, p.z - feet.z).length() > InventoryModule.PICK_REACH: continue
		var candidate := look.angle_to(p - eye)
		if candidate < angle:
			angle = candidate
			best = int(e["index"])
	return best
