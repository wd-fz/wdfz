class_name MazePhysics
extends RefCounted
## Physical solids from the original voxel field and smooth walk surfaces. No global floor:
## the holes in the visual maze must really be holes, including below the lower level.


static func build(body: StaticBody3D, geometry: MazeGeometry) -> void:
	for box: AABB in geometry.solid_boxes():
		var shape := BoxShape3D.new()
		shape.size = box.size
		var collider := CollisionShape3D.new()
		collider.name = "VoxelSolid"
		collider.shape = shape
		collider.position = box.get_center()
		collider.set_meta("kind", "maze_voxel")
		body.add_child(collider)
	for surface: Dictionary in geometry.walks:
		var points := PackedVector3Array()
		for offset: float in [0.0, -0.3]:
			for x: float in [float(surface["x0"]), float(surface["x1"])]:
				for z: float in [float(surface["z0"]), float(surface["z1"])]:
					points.append(Vector3(x, MazeGeometry.surface_height(surface, x, z) + offset, z))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collider := CollisionShape3D.new()
		collider.name = String(surface["id"])
		collider.shape = shape
		collider.set_meta("kind", "maze_walk")
		body.add_child(collider)
