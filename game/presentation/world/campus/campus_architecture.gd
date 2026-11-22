class_name CampusArchitecture
extends RefCounted
## Shared art for the playable campus, streamed neighbours and menu photograph.
const COURTYARD := preload("res://assets/campus/architecture/courtyard.glb")
const GALLERY := preload("res://assets/campus/architecture/gallery.glb")
const ORANGE_WALK := preload("res://assets/campus/architecture/orange_walk.glb")
const FURNITURE := preload("res://assets/campus/architecture/furnishings.glb")
const COURTYARD_COLLISION := preload("res://assets/campus/architecture/courtyard_collision.tscn")
const RENDER_FINISH := preload("res://assets/campus/textures/17dd50066a40793f.png")
# The source export uses content-addressed albedo maps at three texture resolutions.
const MASONRY := ["a7cd8310", "f46d9424", "efacbb1c"]


static func bridge_scene(id: String) -> PackedScene:
	return ORANGE_WALK if id == "link2" else GALLERY


static func refit(model: Node3D, id: String) -> Node3D:
	if id in CampusSpace.BRIDGES:
		var bridge := bridge_scene(id).instantiate() as Node3D
		# Keep the game's two ceiling-mounted emergency signs and their live faces.
		for old: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var bounds := old.get_aabb()
			if bounds.position.y < 2.5 or bounds.end.y > 2.97 or bounds.size.x > 1.2: continue
			var local := CampusShell._transform(old, model)
			old.owner = null
			old.get_parent().remove_child(old)
			old.transform = local
			bridge.add_child(old)
		model.free()
		return bridge
	if id == "out":
		_finish_walls(model)
	elif id.begins_with("teach") or id.begins_with("dorm") or id in ["lab1", "lab2", "lab3", "canteen1"]:
		_fit_furniture(model, id)
	return model


static func _finish_walls(model: Node3D) -> void:
	var footprints: Array[Rect2] = []
	var finishes: Array[Color] = []
	var palette := {"teach":"f3b29b","lab":"e4a48f","admin":"ecb09b",
		"dormN":"ede3cc","dormS":"ede3cc","canteen":"d8dcd0"}
	var outside := CampusData.layout("out")
	var scale_m := float(outside.SC) * float(outside.U2M)
	for obj: Dictionary in outside.objects:
		if not palette.has(obj.id): continue
		footprints.append(Rect2(obj.x*scale_m, obj.y*scale_m, obj.w*scale_m, obj.h*scale_m).grow(.6))
		finishes.append(Color(palette[obj.id]).srgb_to_linear())
	for node: MeshInstance3D in model.find_children("outdoor_m*", "MeshInstance3D", true, false):
		var mesh := node.mesh
		if mesh == null or mesh.get_surface_count() != 1: continue
		var old := mesh.surface_get_material(0) as BaseMaterial3D
		if old == null or old.albedo_texture == null: continue
		if old.albedo_texture.resource_path.get_file().left(8) not in MASONRY: continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in vertices.size():
			var point := Vector2(vertices[i].x, vertices[i].z)
			for j in footprints.size():
				if footprints[j].has_point(point):
					var shade := .86 + .14 * clampf(colors[i].get_luminance(), 0, 1)
					colors[i] = Color(finishes[j] * shade, 1.0)
					break
		arrays[Mesh.ARRAY_COLOR] = colors
		var plaster := StandardMaterial3D.new()
		plaster.resource_name = "CampusRoughcast"
		plaster.albedo_texture = RENDER_FINISH
		plaster.vertex_color_use_as_albedo = true
		var skin := ArrayMesh.new()
		skin.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		skin.surface_set_material(0, plaster)
		node.mesh = skin


## The exported furniture is split by material and render cell. Components of a
## single furniture piece share its frame; books, actors and signs have their own.
static func _fit_furniture(model: Node3D, id: String) -> void:
	var room := CampusData.layout(id)
	var library := FURNITURE.instantiate() as Node3D
	var fittings := Node3D.new()
	fittings.name = "Furnishings"
	var groups := {}
	var table_textures := {}
	for source: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = source.get_meta("extras", {})
		if not extras.has("wdfz_instances"): continue
		var xf := Marshalls.base64_to_raw(extras.wdfz_instances).to_float32_array()
		var kind := _furniture_at(room, Vector3(xf[9], xf[10], xf[11]))
		if kind.is_empty(): continue
		if kind == "CanteenTable":
			var old := source.mesh.surface_get_material(0) as BaseMaterial3D
			if old != null: table_textures[old.albedo_texture] = true
		if not groups.has(kind): groups[kind] = {}
		var places: Dictionary = groups[kind]
		for i in range(0, xf.size(), 12):
			var origin := Vector3(xf[i+9], xf[i+10], xf[i+11])
			places[origin] = Transform3D(Vector3(xf[i], xf[i+1], xf[i+2]), Vector3(xf[i+3], xf[i+4], xf[i+5]),
				Vector3(xf[i+6], xf[i+7], xf[i+8]), origin)
		source.free()
	if id == "canteen1":
		_complete_canteen(model, room, groups, table_textures)
	elif id == "lab3":
		groups["Workstation"] = _grid_frames(room, "n")
	if groups.has("ChemistryBench"):
		var hoods := {}
		for at: Vector3 in groups["ChemistryBench"]:
			# Each pair of bench rows shares the overhead installation.
			var row := floori(at.z + float(room.rows)*.5)
			if row % 4 == 2: hoods[at] = groups["ChemistryBench"][at]
		groups["Extractor"] = hoods
	for kind: String in groups:
		var template := library.find_child(kind, true, false) as MeshInstance3D
		var places: Dictionary = groups[kind]
		if places.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = template.mesh
		mm.instance_count = places.size()
		var transforms := PackedFloat32Array()
		var index := 0
		for transform: Transform3D in places.values():
			mm.set_instance_transform(index, transform)
			var b := transform.basis
			var p := transform.origin
			transforms.append_array(PackedFloat32Array([b.x.x,b.x.y,b.x.z,b.y.x,b.y.y,b.y.z,b.z.x,b.z.y,b.z.z,p.x,p.y,p.z]))
			index += 1
		var batch := MultiMeshInstance3D.new()
		batch.name = kind
		batch.multimesh = mm
		batch.set_meta("campus_transforms", transforms)
		fittings.add_child(batch)
	if fittings.get_child_count() > 0:
		model.add_child(fittings)
	else:
		fittings.free()
	library.free()


static func _grid_frames(room: Dictionary, tile: String) -> Dictionary:
	var places := {}
	for r in int(room.rows):
		for c in int(room.cols):
			if String(room.grid[r]).substr(c, 1) != tile: continue
			var center := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, c, r))
			var at := Vector3(center.x, 0, center.y)
			places[at] = Transform3D(Basis.IDENTITY, at)
	return places


## Small export cells have individual dining tables baked into a static mesh.
## Remove their original triangles before fitting the same benches as the batched cells.
static func _complete_canteen(model: Node3D, room: Dictionary, groups: Dictionary, textures: Dictionary) -> void:
	var existing: Dictionary = groups.get("CanteenTable", {})
	var tables := _grid_frames(room, "t")
	var holes := {}
	for at: Vector3 in tables:
		if existing.has(at): continue
		var bounds := AABB(at+Vector3(-.45,-.012,-.67), Vector3(.90,.79,1.34))
		for z in range(floori(bounds.position.z), floori(bounds.end.z)+1):
			holes[Vector2i(floori(at.x),z)] = bounds
	if not holes.is_empty():
		for node: MeshInstance3D in model.find_children("canteen1_m*", "MeshInstance3D", true, false):
			var mesh := node.mesh
			var mat := mesh.surface_get_material(0) as BaseMaterial3D
			if mat == null or not textures.has(mat.albedo_texture): continue
			var arrays := mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var kept := PackedInt32Array()
			for i in range(0,indices.size(),3):
				var a := verts[indices[i]]
				var hole: AABB = holes.get(Vector2i(floori(a.x),floori(a.z)), AABB())
				if hole.has_volume() and hole.has_point(a) and hole.has_point(verts[indices[i+1]]) and hole.has_point(verts[indices[i+2]]): continue
				kept.append(indices[i])
				kept.append(indices[i+1])
				kept.append(indices[i+2])
			if kept.size() == indices.size(): continue
			if kept.is_empty():
				node.free()
				continue
			var rest := ArrayMesh.new()
			rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, CampusShell._compact(arrays,kept))
			rest.surface_set_material(0,mat)
			node.mesh = rest
	groups["CanteenTable"] = tables
	var kitchen := _grid_frames(room,"k")
	var bays := {}
	for at: Vector3 in kitchen:
		if not kitchen.has(at + Vector3.BACK): bays[at] = kitchen[at]
	groups["ServingBay"] = bays


static func _furniture_at(room: Dictionary, p: Vector3) -> String:
	if absf(p.y) > .015: return ""
	var grid_pos := Vector2(p.x + float(room.cols)*.5, p.z + float(room.rows)*.5)
	var cell := Vector2i(grid_pos.floor())
	if cell.x < 0 or cell.x >= int(room.cols) or cell.y < 0 or cell.y >= int(room.rows): return ""
	var tile := String(room.grid[cell.y]).substr(cell.x, 1)
	var offset := grid_pos - Vector2(cell)
	match tile:
		"d":
			if room.host != "teach" or absf(absf(offset.y-.5)-.11) > .025: return ""
			if absf(offset.x-.4) < .025: return "Desk"
			if absf(offset.x-.8) < .025: return "LanguageChair" if room.floor == 3 else "BlueChair"
		"b":
			if absf(offset.x-.5) < .025 and absf(absf(offset.y-.5)-.39) < .025: return "Bunk"
		"q", "l", "t":
			if offset.distance_to(Vector2(.5,.5)) > .025: return ""
			if tile == "q": return "PhysicsBench"
			if tile == "l": return "ChemistryBench"
			return "CanteenTable"
	return ""


static func add_courtyard(model: Node3D, resident: bool) -> void:
	if not resident:
		var space := CampusSpace.new(CampusData.rooms(), CampusData.layout("out"), CampusData.campus())
		# Resident worlds do this in CampusShell.partition and display the actual bridge regions.
		for volume in space.bridge_volumes():
			CampusShell.carve_box(model, volume)
		for id: String in CampusSpace.BRIDGES:
			var bridge := bridge_scene(id).instantiate() as Node3D
			SceneMaterials.apply(bridge, 0)
			bridge.transform = space.frame(id)
			model.add_child(bridge)
	var courtyard := COURTYARD.instantiate()
	SceneMaterials.apply(courtyard, 0)
	model.add_child(courtyard)


static func add_courtyard_collision(body: StaticBody3D) -> void:
	var shapes := COURTYARD_COLLISION.instantiate()
	for shape in shapes.get_children():
		shape.owner = null
		shapes.remove_child(shape)
		shape.set_meta("kind", "scenery")
		body.add_child(shape)
	shapes.free()
