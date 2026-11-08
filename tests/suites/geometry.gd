extends "res://tests/support/test_suite.gd"
## Rendered geometry and real physics must agree at scene joins. These checks use the exported
## campus models, including the brick wall that used to cut through the east teaching corridor.


func test_clipping() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3(2, 2, 2)
	var material := StandardMaterial3D.new()
	cube.material = material
	var original := cube.get_faces()
	var mesh := CampusPreview.clip_mesh(cube, Plane(Vector3.RIGHT, 0))
	var faces := mesh.get_faces()
	var beyond := true
	var has_edge := false
	for p: Vector3 in faces:
		beyond = beyond and p.x >= -0.0001
		has_edge = has_edge or absf(p.x) < 0.0001
	check(not faces.is_empty() and beyond and has_edge, "preview cuts crossing triangles exactly at the threshold")
	check(cube.get_faces() == original and mesh.surface_get_material(0) == material, "preview trimming preserves the original mesh and material")
	var arrays := mesh.surface_get_arrays(0)
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	check((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() == count and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == count
		and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == count * 4, "cut edges preserve aligned normal, UV and tangent attributes")
	check(CampusPreview.clip_mesh(cube, Plane(Vector3.RIGHT, 2.0)).get_surface_count() == 0, "a preview wholly behind the threshold renders nothing")
	var parent := Node3D.new()
	var piece := MeshInstance3D.new()
	piece.mesh = cube
	piece.position = Vector3(0.5, 0, 0)
	parent.add_child(piece)
	parent.rotation.y = PI * 0.5
	CampusPreview.clip(parent, Plane(Vector3.FORWARD, 0))
	var correct := true
	for p: Vector3 in piece.mesh.get_faces():
		correct = correct and (parent.transform * piece.transform * p).z <= 0.0001
	check(correct, "rotated neighbouring buildings clip in the current scene's coordinates")
	parent.free()


func test_instances() -> void:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	var values := PackedFloat32Array()
	for x: float in [-2.0, 0.0, 2.0]:
		values.append_array(PackedFloat32Array([1,0,0,0,1,0,0,0,1,x,0,0]))
	node.multimesh = mm
	node.set_meta("campus_transforms", values)
	node.set_meta("campus_colors", PackedFloat32Array([1,0,0,0,1,0,0,0,1]))
	CampusPreview.clip(node, Plane(Vector3.RIGHT, 0))
	check(node.multimesh.instance_count == 1 and node.get_child_count() == 1, "preview keeps the outside instance, clips the crossing one, removes the inside one")
	check(CampusPreview.instance_transform(node, 0).origin == Vector3(2,0,0), "surviving instances retain their real transforms even with a headless renderer")
	var edge := node.get_child(0) as MeshInstance3D
	var colors: PackedColorArray = edge.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(not colors.is_empty() and colors[0] == Color.GREEN, "a cut instance keeps its instance tint")
	check(mm.instance_count == 3, "preview filtering never changes the original instance buffer")
	node.free()


func test_campus_joins() -> void:
	var world := CampusWorld.new()
	world.scene_id = "teach1"
	root.add_child(world)
	await _frames()
	var from := Vector3(24.2, 1.65, 8.5)
	var to := Vector3(26.8, 1.65, 8.5)
	var preview := world.get_node("DoorPreview_out") as Node3D
	preview.show() # Verify geometry itself, independently of the near-door visibility gate.
	check(not _mesh_hit(preview, from, to) and not _mesh_hit(preview, to, from), "teaching corridor has no one-sided exterior brick wall across its walkable passage")
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	check(world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "the repaired corridor retains the original open collision passage")
	var body: PlayerController = preload("res://game/presentation/actors/player.tscn").instantiate()
	root.add_child(body)
	body.position = Vector3(from.x, 0.05, from.z)
	await _frames()
	var hit := body.move_and_collide(to - from)
	check(hit == null and absf(body.position.x - to.x) < 0.01, "the actual player capsule traverses the repaired passage (position %s)" % body.position)
	# Actual interior walls still stop movement from both faces; no global cull/collision override.
	var room := CampusData.layout("teach1")
	var north := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, 54, 15))
	for direction: float in [-1.0, 1.0]:
		var a := Vector3(north.x, 1.0, north.y + direction * 1.1)
		var b := Vector3(north.x, 1.0, north.y - direction * 1.1)
		check(not world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty(),
			"solid classroom wall blocks from face %s" % direction)
	body.queue_free()
	world.queue_free()
	await _frames()
	# Views of a room must show the same door state before and after entering it.
	world = CampusWorld.new()
	world.scene_id = "out"
	root.add_child(world)
	await _frames()
	var key := "teach1:10:15"
	var entries: Array = world._preview_doors.get(key, [])
	check(entries.size() == 2, "outside preview registers both classroom door variants")
	var first := world.door_previews[0]
	var threshold: Vector2 = first.get_meta("door_threshold")
	world.set_player_scene(Vector3(threshold.x, 0, threshold.y + 11.0))
	check(first.visible and world.door_previews.filter(func(model: Node3D) -> bool: return model.visible).size() == 1, "only the closest doorway draws an interior within 12 metres")
	world.set_player_scene(Vector3(threshold.x, 0, threshold.y + 14.0))
	check(first.visible, "a visible doorway stays visible until 15 metres, without flicker at 12 metres")
	world.set_player_scene(Vector3(threshold.x, 0, threshold.y + 16.0))
	check(not first.visible, "distant interiors stop rendering when leaving the entrance")
	for open: bool in [false, true, false]:
		world.apply_doors({key: true} if open else {})
		var agrees := true
		for entry: Dictionary in entries:
			agrees = agrees and (entry["node"] as Node3D).visible == (open == (entry["state"] == "open"))
		check(agrees, "preview door state agrees with saved/current open state: %s" % open)
	world.queue_free()
	await _frames()


func _mesh_hit(node: Node3D, from: Vector3, to: Vector3) -> bool:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var inv := mesh.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		var faces := mesh.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i + 1], faces[i + 2]) != null:
				return true
	return false
