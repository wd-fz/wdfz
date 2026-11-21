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
	world._ensure_door_preview(preview)
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
	var first := world.door_previews[0]
	var threshold: Vector2 = first.get_meta("door_threshold")
	world.set_player_scene(Vector3(threshold.x, 0, threshold.y + 11.0))
	var entries: Array = world._preview_doors.get(key, [])
	check(entries.size() == 2, "approaching a portal registers both classroom door variants")
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


## The old geometry had collision but daylight came through laterally at the threshold.
func test_stair_entrances() -> void:
	var space := CampusSpace.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	for stair: Dictionary in space.campus.stair_layout:
		var world := CampusWorld.new()
		world.scene_id = stair.id
		world.space = space
		world.resident = true
		root.add_child(world)
		await _frames(2)
		var lining := world.get_node_or_null("Model/StairEntranceLining") as MeshInstance3D
		check(lining != null, "the resident shaft has a visible lining: " + String(stair.id))
		if lining != null:
			var mesh := lining.mesh.generate_triangle_mesh()
			for level in stair.rooms.size():
				var eye := Vector3(0, level * float(stair.rise) + 1.58, -2.0)
				for side: float in [-1.0, 1.0]:
					var outside := eye + Vector3.RIGHT * 1.4 * side
					for ray: Array in [[eye, outside], [outside, eye]]:
						var physics := PhysicsRayQueryParameters3D.create(ray[0], ray[1], 1)
						var solid := not world.get_world_3d().direct_space_state.intersect_ray(physics).is_empty()
						check(solid and not mesh.intersect_segment(ray[0], ray[1]).is_empty(), "%s %s side %s has a solid, visible return" % [stair.id, level, side])
				if stair.rooms[level] != "out":
					var below := Vector3(0, level * float(stair.rise) + 2.20, -2.0)
					var above := below + Vector3.UP * .25
					var head := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(below, above, 1))
					check(not head.is_empty() and not mesh.intersect_segment(below, above).is_empty(), "the doorway lintel meets the baked shaft at 2.30 m")
				var start := Vector3(0, eye.y, -3.2)
				var end := Vector3(0, eye.y, -0.8)
				check(mesh.intersect_segment(start, end).is_empty() and world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1)).is_empty(), "the centre passage stays clear at %s %s" % [stair.id, level])
		world.queue_free()
		await _frames(2)
	var initial_tier := CampusData.tier
	for tier: int in CampusData.tiers_available():
		CampusData.tier = tier
		var floor_model := CampusWorld.build_visual("teach1", tier)
		var lining := floor_model.get_node_or_null("StairEntranceLining") as MeshInstance3D
		check(lining != null, "streamed teaching floor has jambs at tier %d" % tier)
		if lining != null:
			var mesh := lining.mesh.generate_triangle_mesh()
			for door: Dictionary in CampusData.rules().stair_doorways("teach1"):
				var mid: Vector2 = door.center - door.normal * .25
				var a := Vector3(mid.x, 1.58, mid.y)
				var lateral := Vector3(door.lateral.x, 0, door.lateral.y)
				for side: float in [-1.0, 1.0]:
					check(not mesh.intersect_segment(a, a + lateral * side * 1.4).is_empty(), "both teaching entrances have visible floor-side jambs at tier %d" % tier)
		floor_model.free()
	CampusData.tier = initial_tier


## A separate room preview cannot reproduce a far facade obstructing a resident room.
func test_resident_doorways() -> void:
	var original_tier := CampusData.tier
	CampusData.tier = 0
	var campus := CampusResident.new()
	campus.space = CampusSpace.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
	campus.nearby_visuals = true
	root.add_child(campus)
	var hall := campus.prepare("teach1")
	var outside := campus.prepare("out")
	for link: String in CampusSpace.BRIDGES: campus.prepare(link)
	var shaft := campus.prepare("stair_teach_e")
	var facade: Node3D = outside.shells.teach1
	var tower: Node3D = outside.shells.stair_teach_e
	campus.select("out")
	campus.update_view(hall.global_transform * Vector3(28, 1.2, 14))
	check(facade.visible and tower.visible, "warm indoor details keep the brick facades visible from the street")
	check(not shaft.get_node("Model").visible, "stairs away from an entrance do not expose interior surfaces outside")
	for link: String in CampusSpace.BRIDGES:
		var bridge: CampusWorld = campus.regions[link]
		check(bridge.get_node("Model").is_visible_in_tree(), "the single playable bridge is always visible: " + link)
		var a := bridge.global_position
		check(_mesh_hit(bridge, a - Vector3.UP * .4, a + Vector3.UP * .05), "the real bridge has a visible underside: " + link)
		check(not _mesh_hit(outside, a + Vector3.UP * 3.4, a + Vector3.UP * 13.0), "no extra outdoor decks above the playable bridge: " + link)
	campus.select("teach1")
	var frame := hall.global_transform
	await _frames(2)
	# Force the loading overlap and test the actual outdoor triangles from both sides.
	facade.show()
	tower.show()
	var body := hall.get_world_3d().direct_space_state
	for height: float in [.45, 1.58]:
		var paths := [[Vector3(23.6, height, 8.45), Vector3(27, height, 8.45)],
			[Vector3(24.5, height, 8.5), Vector3(24.5, height, 12.2)]]
		for path: Array in paths:
			var a: Vector3 = frame * path[0]
			var b: Vector3 = frame * path[1]
			check(not _mesh_hit(outside, a, b) and not _mesh_hit(outside, b, a), "outdoor models leave the drinking fountain corridor and east stairs clear at %s m" % height)
			check(body.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty(), "no invisible collider across the same passage")
	for stair: Dictionary in campus.space.campus.stair_layout:
		var transform := campus.space.frame(stair.id)
		var proxy: Node3D = outside.shells[stair.id]
		var levels: Array = stair.rooms
		proxy.show()
		for level in levels.size():
			var floor_proxy := outside.shells.get(levels[level]) as Node3D
			if floor_proxy != null: floor_proxy.show()
			for h: float in [.45, 1.58]:
				for x: float in [-.55, 0.0, .55]:
					var a := transform * Vector3(x, level * float(stair.rise) + h, -4.15)
					var b := transform * Vector3(x, level * float(stair.rise) + h, -1.0)
					var clear := not _mesh_hit(proxy, a, b) and not _mesh_hit(proxy, b, a)
					if clear and floor_proxy != null:
						clear = not _mesh_hit(floor_proxy, a, b) and not _mesh_hit(floor_proxy, b, a)
					check(clear, "outdoor stair entrance open at %s / %s (x %.2f, h %.2f)" % [stair.id, levels[level], x, h])
	campus.select(shaft.scene_id)
	check(tower.visible, "the stair exterior stays with the building when entering a shaft")
	var door: Dictionary = hall.layout.doors[0]
	for opened: bool in [false, true, false]:
		hall.set_door_open(door.key, opened)
		await _frames(2)
		for pose: bool in [false, true]:
			var rect := CampusGeometry.door_leaf_rect(door, pose)
			var middle := rect.get_center()
			var side := Vector3.RIGHT if pose else Vector3.BACK
			var a: Vector3 = frame * (Vector3(middle.x, 1.0, middle.y) - side * .12)
			var b: Vector3 = frame * (Vector3(middle.x, 1.0, middle.y) + side * .12)
			var leaves: Dictionary = hall._door_leaves[door.key]
			var mesh: Node3D = leaves["open" if pose else "closed"]
			var solid := not body.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty()
			check(solid == (pose == opened) and _mesh_hit(mesh, a, b) == solid, "rendered door panel and physical panel agree for %s / %s" % [opened, pose])
	campus.queue_free()
	await _frames(2)
	CampusData.tier = original_tier


func _mesh_hit(node: Node3D, from: Vector3, to: Vector3) -> bool:
	for child: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
		if not child.is_visible_in_tree(): continue
		if child is MeshInstance3D:
			if _mesh_segment(child.mesh, child.global_transform, from, to): return true
		elif child is MultiMeshInstance3D:
			for i in child.multimesh.instance_count:
				if _mesh_segment(child.multimesh.mesh, child.global_transform * CampusPreview.instance_transform(child, i), from, to): return true
	return false


func _mesh_segment(mesh: Mesh, transform: Transform3D, from: Vector3, to: Vector3) -> bool:
	if mesh == null or is_zero_approx(transform.basis.determinant()): return false
	var inv := transform.affine_inverse()
	var a := inv * from
	var b := inv * to
	if mesh.get_aabb().grow(.001).intersects_segment(a, b) == null: return false
	var triangles := mesh.generate_triangle_mesh()
	return triangles != null and not triangles.intersect_segment(a, b).is_empty()
