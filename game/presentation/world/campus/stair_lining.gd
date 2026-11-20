class_name StairLining
extends RefCounted
## The floor GLBs omit S tiles and the stair GLBs start their front wall at z=-1.2.
## Each region owns its side of the shared threshold so previews can still be clipped there.

const THRESHOLD := CampusPortals.THRESHOLD_Z
const FRONT := -1.2
const HALF_TILE := CampusGeometry.TTILE * CampusGeometry.U2M * 0.5
const OUTER_HALF_WIDTH := HALF_TILE * 2.0
const DOOR_HALF := CampusPortals.DOOR_HALF
const JAMB := OUTER_HALF_WIDTH - DOOR_HALF
const WALL_HEIGHT := 3.0
const CAP := 0.12
## The plaster albedo used by the exported staircases.
const PLASTER := preload("res://assets/campus/textures/17dd50066a40793f.png")


static func shaft_panels(stair: Dictionary) -> Array[AABB]:
	var rise := float(stair.rise)
	var levels: Array = stair.rooms
	var height := (levels.size() - 1) * rise + WALL_HEIGHT
	var panels: Array[AABB] = []
	for x: float in [-OUTER_HALF_WIDTH, DOOR_HALF]:
		panels.append(AABB(Vector3(x, 0, THRESHOLD), Vector3(JAMB, height, FRONT - THRESHOLD)))
	for level in levels.size():
		if levels[level] == "out": continue
		panels.append(AABB(Vector3(-DOOR_HALF, level * rise + WALL_HEIGHT - CAP, THRESHOLD),
			Vector3(DOOR_HALF * 2.0, CAP, FRONT - THRESHOLD)))
	return panels


static func floor_jambs(doorways: Array[Dictionary]) -> Array[AABB]:
	var panels: Array[AABB] = []
	for door: Dictionary in doorways:
		var threshold: Vector2 = door.center
		var normal: Vector2 = door.normal
		var lateral: Vector2 = door.lateral
		for side: float in [-1.0, 1.0]:
			var a := threshold - normal * HALF_TILE + lateral * side * DOOR_HALF
			var b := threshold + lateral * side * OUTER_HALF_WIDTH
			var start := a.min(b)
			var size := (b - a).abs()
			panels.append(AABB(Vector3(start.x, 0, start.y), Vector3(size.x, WALL_HEIGHT, size.y)))
	return panels


static func add_to_model(model: Node3D, id: String) -> void:
	var stair := CampusPortals.stair_config(CampusData.campus().stair_layout, id)
	var panels := shaft_panels(stair) if not stair.is_empty() else floor_jambs(CampusData.rules().stair_doorways(id))
	if panels.is_empty(): return
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color("b0b3ac")
	plaster.albedo_texture = PLASTER
	plaster.roughness = 1.0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(plaster)
	var box := BoxMesh.new()
	for panel: AABB in panels:
		box.size = panel.size
		var arrays := box.get_mesh_arrays()
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][index]
			var point: Vector3 = panel.get_center() + arrays[Mesh.ARRAY_VERTEX][index]
			# Tile plaster in metres; the long shaft faces span several storeys.
			var uv := Vector2(point.x if absf(normal.z) > 0.5 else point.z, -point.y)
			if absf(normal.y) > 0.5: uv = Vector2(point.x, point.z)
			surface.set_uv(uv * 0.65)
			surface.set_normal(normal)
			surface.add_vertex(point)
	surface.index()
	var lining := MeshInstance3D.new()
	lining.name = "StairEntranceLining"
	lining.mesh = surface.commit()
	model.add_child(lining)
