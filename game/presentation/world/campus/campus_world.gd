class_name CampusWorld
extends Node3D
## A campus region's presentation + physics. Static geometry can remain resident across visits;
## the region ID is a rules/save boundary, not a reason to reload its meshes at every doorway.
## Geometry is the glb exported from the old game's own builders; collision boxes are the old
## game's own static collision rectangles (tools/export_scenes). Rendering-only spatial
## batches, mesh cells and occluders keep the original full-detail surfaces and collision.

const WALL_TOP := 10.0     # the bell tower top platform is at 6.4 m
const WALL_BOTTOM := -0.5
const BOUNDARY := 1.0

@export var scene_id := "out"

var layout: Dictionary = {}
## The anomaly module's leftovers at the moment a world is built (set by the app before the world exists).
static var pending_traces: Array = []
var banner: DayBanner
var chalk: ChalkNotes
var phantoms: Phantoms
var traces: Traces
## Dropped items on this scene's floor (InventoryModule.ground_in); the app syncs them every frame.
var ground_items: GroundItems
var _traces_seen := -1
var _trace_data: Array=[]
var broadcast_props: BroadcastProps
var _west_display: Label3D
var _west_cleared := false
var mirror_view: MirrorView
var canteen_view: CanteenView
var lighting: CampusLighting
var _door_bodies: Dictionary = {}   # key -> CollisionShape3D
var _door_leaves: Dictionary = {}   # key -> {"closed": Node3D, "open": Node3D}
var _preview_doors: Dictionary = {} # key -> all neighbouring views of that door
var _preview_lifts: Array[Dictionary] = []
var _open_doors: Dictionary = {}
var _lift_leaves: Array[Node3D] = []
var _lift_bodies: Array[CollisionShape3D] = []
var _lift_amount := -1.0
var anomaly_fx: AnomalyFx
var atmos_fx: AtmosFx
var duty: DutyRoster
var visual_tier := -1
var render_options: Dictionary = {}
var visual_ground:=VisualGround.new()
## Authority worlds use exactly the same collision geometry, without loading any meshes.
var collision_only := false
var resident := false
var space: CampusSpace
var shells: Dictionary = {}
var runtime_active := false
var geometry_ready := false
## Set by the router: previews are prepared on its worker instead of blocking a movement frame.
var preview_request: Callable
var entry_views := PackedStringArray()
var entry_height := -1.0
var _patrol_asset: PackedScene


func _ready() -> void:
	set_process(false)
	layout = CampusData.layout(scene_id)
	if collision_only:
		_build_collision()
		return
	prepare_geometry()
	if resident: return
	activate()


func activate() -> void:
	if runtime_active: return
	runtime_active = true
	set_process(true)
	_build_lighting()
	if scene_id == "out":
		var reader := preload("res://game/presentation/world/campus/west_gate_reader.tscn").instantiate() as Node3D
		var centre := CampusGeometry.gate_center(CampusData.campus(), "w") + Vector2(RollcallCard.EXIT_OFFSET, -RollcallCard.EXIT_NORTH)
		var p := CampusGeometry.to_scene(null, centre)
		reader.position = Vector3(p.x, visual_ground.height(p.x, p.y), p.y)
		reader.get_node("WhiteLine").scale.z = RollcallCard.EXIT_HALF_WIDTH * 2.0 * CampusGeometry.U2M
		add_child(reader)
		_west_display = reader.get_node("Reader/Display")
		_west_cleared = false
	anomaly_fx = AnomalyFx.new()
	anomaly_fx.particle_quality=int(render_options.get("particle_detail",-1))
	anomaly_fx.ground_height=visual_ground.height
	anomaly_fx.name = "AnomalyFx"
	add_child(anomaly_fx)
	chalk = ChalkNotes.new()
	add_child(chalk)
	phantoms = Phantoms.new()
	add_child(phantoms)
	traces = Traces.new()
	traces.ground_height=visual_ground.height
	traces.name = "Traces"
	add_child(traces)
	traces.build(scene_id, layout if is_room() else null, CampusWorld.pending_traces)
	_traces_seen = CampusWorld.pending_traces.size()
	_trace_data=CampusWorld.pending_traces.duplicate(true)
	ground_items = GroundItems.new()
	ground_items.ground_height = visual_ground.height
	add_child(ground_items)
	if is_room():
		broadcast_props = BroadcastProps.new()
		broadcast_props.name = "BroadcastProps"
		add_child(broadcast_props)
		broadcast_props.build(layout)
		if scene_id == BodyModule.CLINIC["room"]:
			_build_clinic()
		if scene_id == CanteenView.ROOM:
			canteen_view = CanteenView.new()
			canteen_view.name = "CanteenView"
			add_child(canteen_view)
			canteen_view.build(layout)
		if String(layout.get("host", "")) == "teach":
			mirror_view = MirrorView.new()
			mirror_view.name = "MirrorView"
			add_child(mirror_view)
	if not is_room():
		_ready_banner()
	if is_room():
		atmos_fx = AtmosFx.new()
		atmos_fx.name = "AtmosFx"
		add_child(atmos_fx)
		atmos_fx.setup(layout)
		if ClassmatesModule.eligible(layout):
			duty = DutyRoster.new()
			duty.name = "DutyRoster"
			add_child(duty)
			duty.setup(layout)


func show_west_clearance(accepted: bool) -> void:
	if accepted == _west_cleared or not is_instance_valid(_west_display): return
	_west_cleared = accepted
	_west_display.text = "本人已核验\n请越线离校" if accepted else "西小门\n请递底联"
	_west_display.modulate = Color("#8ef4b1") if accepted else Color("#e0d4ad")


func deactivate() -> void:
	if not runtime_active: return
	runtime_active = false
	set_process(false)
	for child: Node in get_children():
		if child.name not in ["Model", "Collision", "Doors"]:
			remove_child(child)
			child.free()
	for key: String in ["lighting", "anomaly_fx", "chalk", "phantoms", "traces", "ground_items", "broadcast_props", "mirror_view", "canteen_view", "banner", "atmos_fx", "duty",
		"_silhouettes", "_scatter"]:
		set(key, null)
	_silhouette_key = ""


func set_collision_enabled(value: bool) -> void:
	for name: String in ["Collision", "Doors"]:
		var body := get_node_or_null(name) as CollisionObject3D
		if body != null: body.collision_layer = 1 if value else 0


## Detached static work only. The stream prepares this before activation; lights, viewports,
## effects and other live adapters are created on the main thread by _ready.
func prepare_geometry() -> void:
	if geometry_ready:
		return
	layout = CampusData.layout(scene_id)
	# Preserve the startup loader's figure warm-up; the first patrol must not introduce
	# a fresh disk read in the middle of an otherwise smooth walk.
	if ResourceLoader.exists(PATROL_FIGURE):
		_patrol_asset = load(PATROL_FIGURE) as PackedScene
	_build_model()
	_build_collision()
	if resident:
		geometry_ready = true
		return
	if is_room():
		_build_link_preview()
	_build_stair_preview()
	_build_door_preview()
	_build_gallery_view()
	# The view back through the entry must be ready with the region itself, not appear
	# several frames after crossing. Other outdoor entrances remain distance-driven.
	for view: Node3D in door_previews:
		if entry_views.has(String(view.get_meta("preview_scene", ""))):
			_ensure_door_preview(view)
	if entry_height >= 0.0:
		update_shaft_previews(entry_height)
	var seeds := get_node_or_null("VisualSeeds")
	if seeds != null:
		seeds.free()
	geometry_ready = true


## A worker can reuse a resident region's already processed meshes. Duplicate nodes on the
## main thread, then clip privately off-tree; never read or reparent a live node on the worker.
func seed_visual(id: String, source: Node3D) -> void:
	var seeds := get_node_or_null("VisualSeeds")
	if seeds == null:
		seeds = Node3D.new()
		seeds.name = "VisualSeeds"
		add_child(seeds)
	if seeds.has_node(NodePath(id)):
		return
	var copy := source.duplicate() as Node3D
	copy.name = id
	for occluder: Node in copy.find_children("*", "OccluderInstance3D", true, false):
		occluder.free()
	seeds.add_child(copy)


## Transfer, never duplicate, expensive geometry to a dormant region. Effects are left on the
## outgoing world and freed with it, so cached rooms cannot resurrect a previous anomaly or death.
func release_geometry() -> CampusWorld:
	var next := CampusWorld.new()
	for property: String in ["scene_id", "layout", "visual_tier", "render_options", "visual_ground", "geometry_ready", "_patrol_asset",
		"_door_bodies", "_door_leaves", "_preview_doors", "_preview_lifts", "_open_doors", "_lift_leaves", "_lift_bodies", "_lift_amount",
		"link_previews", "stair_previews", "door_previews", "gallery_campus", "_shaft_levels"]:
		next.set(property, get(property))
	var nodes: Array[Node3D] = _visual_models()
	for key: String in ["Collision", "Doors"]:
		var node := get_node_or_null(key) as Node3D
		if node != null:
			nodes.append(node)
	for node: Node3D in nodes:
		remove_child(node)
		next.add_child(node)
		# An asynchronous preview belonged to the old live adapter, not to this cached geometry.
		node.remove_meta("stream_pending")
	return next


func _ready_banner() -> void:
	banner = DayBanner.new()
	banner.name = "DayBanner"
	add_child(banner)
	banner.setup(layout)


## The scenes a scene shows through openings as it is built (built by _load_visual): the campus seen from an
## outside corridor or through a door to the outside (the start seat in teach1 is near one, and the campus
## is the heaviest model of all), the stairwells and the linked building seen through doorways. From
## outside, the rooms' door previews load on approach and are not listed.
static func visual_ids(id: String) -> PackedStringArray:
	var want := PackedStringArray()
	var rooms := CampusData.rooms()
	if id == "out" or not rooms.has(id):
		return want
	var layout := CampusData.layout(id)
	if bool(layout.get("flags", {}).get("gallery", false)):
		want.append("out")
	for d: Dictionary in CampusData.campus().get("campus_doors", {}).get("doors", []):
		if String(d["room"]) == id and not want.has("out"):
			want.append("out")
	for st: Dictionary in CampusData.campus().get("stair_layout", []):
		if id != String(st["id"]) and (st["rooms"] as Array).has(id):
			want.append(String(st["id"]))
	for v: Dictionary in CampusPortals.link_ports(CampusData.campus().get("campus_link", {}), rooms, id):
		want.append(String(v["peer"]["room"]))
	return want


## The model files a scene loads as it is built (its own model, the visual_ids, the patroller's figure),
## so a loading screen can read them on worker threads first. Only files that exist are returned.
static func asset_paths(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if id != "out" and not CampusData.rooms().has(id):
		return out
	for scene: String in [id] + Array(visual_ids(id)):
		var path := CampusData.scene_path(scene)
		if ResourceLoader.exists(path) and not out.has(path):
			out.append(path)
	if ResourceLoader.exists(PATROL_FIGURE):
		out.append(PATROL_FIGURE)
	return out


func is_room() -> bool:
	return scene_id != "out"


## The clinic's wall cabinet in the first office of the administration building (modules/body/injury.js, presentation): white, a red cross.
func _build_clinic() -> void:
	var rm := layout
	var p := CampusGeometry.to_scene(rm, Vector2(float(rm["ox"]) + 6.0 * float(rm["tw"]), float(rm["oy"]) + 16.0 * float(rm["th"])))
	var cab := MeshInstance3D.new()
	cab.name = "ClinicCabinet"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.7, 0.22)
	cab.mesh = bm
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("#eef0ee")
	white.emission_enabled = true
	white.emission = Color("#2c2e2c")
	RenderMaterials.set_override(cab, white)
	cab.position = Vector3(p.x, 1.55, p.y - 0.12)
	add_child(cab)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("#c02a2a")
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for dims: Vector3 in [Vector3(0.2, 0.06, 0.01), Vector3(0.06, 0.2, 0.01)]:
		var bar := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = dims
		bar.mesh = rb
		RenderMaterials.set_override(bar, red)
		bar.position = Vector3(p.x, 1.6, p.y - 0.235)
		add_child(bar)


## The corridor bridges seen from both ends (modules/campus-link/link-view.js): the neighbouring room's model placed by the rigid
## transform of the port pair (CampusPortals.link_between), under the same campus daylight.
## Visual only: no collision, nothing advances. Standing at the west end of the second floor you see the whole bridge.
var link_previews: Array[Node3D] = []
var stair_previews: Array[Node3D] = []
var door_previews: Array[Node3D] = []
var gallery_campus: Node3D
const GALLERY_RISE := 3.2


## The open outside corridors of the teaching building, floors 2–5 (modules/campus-link/gallery.js): the real campus outside is hung into the
## scene shifted by the building's offset and dropped by the floor's height, so from the corridor you see the campus, the people below and the
## stair towers in front of the building. Visual only; the collision still stops you at the rail.
func _build_gallery_view() -> void:
	if not is_room() or not bool(layout.get("flags", {}).get("gallery", false)):
		return
	var model := _load_visual("out")
	if model == null:
		return
	var sh := CampusGeometry.shift_of(layout)
	var f := int(layout.get("floor", 2))
	model.name = "GalleryCampus"
	model.position = Vector3(-(sh.x + float(layout["cx"])) * CampusGeometry.U2M, -float(f - 1) * GALLERY_RISE, -(sh.y + float(layout["cy"])) * CampusGeometry.U2M)
	add_child(model)
	# The exterior is a view beyond the open gallery, not a second set of interior walls.
	CampusPreview.clip(model, Plane(Vector3.BACK, _extent().end.y - float(layout["th"]) * CampusGeometry.U2M))
	gallery_campus = model
var _shaft_levels: Dictionary = {}      # level → the preview of the floor beyond that level's door


## In a stairwell: the floors beyond the doors of the level you are on and the next one (StairView.refresh). level from the height.
func update_shaft_previews(height: float) -> void:
	if resident: return
	var st: Dictionary = {}
	for e: Dictionary in CampusData.campus().get("stair_layout", []):
		if String(e["id"]) == scene_id:
			st = e
	if st.is_empty():
		return
	var rise := float(st["rise"])
	var rooms_list: Array = st["rooms"]
	var level := clampi(roundi(height / rise), 0, rooms_list.size() - 1)
	var want: Array = [level]
	if level < rooms_list.size() - 1:
		want.append(level + 1)
	elif level > 0:
		want.append(level - 1)
	for l: int in _shaft_levels.keys():
		if not want.has(l):
			(_shaft_levels[l] as Node3D).queue_free()
			_shaft_levels.erase(l)
	var rooms := CampusData.rooms()
	var outside := CampusData.layout("out")
	for f: int in want:
		if _shaft_levels.has(f):
			_ensure_door_preview(_shaft_levels[f])
			continue
		var id := String(rooms_list[f])
		var port := CampusPortals.stair_port(st, f, rooms, outside)
		if port.is_empty():
			continue
		var model := Node3D.new() if preview_request.is_valid() else _load_visual(id)
		if model == null:
			continue
		var pp := CampusGeometry.to_scene(rooms[id] if id != "out" else null, port["p"])
		var theta := CampusPortals.stair_turn(port["n"])
		model.name = "ShaftPreview_%d" % f
		model.rotation.y = theta
		model.position = Vector3(-(cos(theta) * pp.x + sin(theta) * pp.y), float(f) * rise, -2.8 - (-sin(theta) * pp.x + cos(theta) * pp.y))
		add_child(model)
		var plane := Plane(Vector3.FORWARD, 2.8)
		if preview_request.is_valid():
			model.set_meta("preview_scene", id)
			model.set_meta("preview_plane", plane)
			preview_request.call(self, model, id, plane)
		else:
			CampusPreview.clip(model, plane)
		_shaft_levels[f] = model


func _load_visual(id: String) -> Node3D:
	var model := get_node_or_null(NodePath("VisualSeeds/" + id)) as Node3D
	if model != null:
		model.get_parent().remove_child(model)
	else:
		model = build_visual(id, material_quality())
	if model == null:
		return null
	_register_preview_doors(model, id)
	return model


## A scene's visual model, processed for display (instances, materials, batches, spatial cells). It only
## touches a detached node tree and static helpers, so it may run on a worker thread.
static func build_visual(id: String, quality: int) -> Node3D:
	var path := CampusData.scene_path(id)
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			_to_multimesh(mesh)
	SceneMaterials.apply(model, quality)
	if id != "garage1":
		CampusBatches.optimize(model)
		CampusMeshCells.apply(model)
	return model


func _register_preview_doors(model: Node3D, id: String) -> void:
	for holder: Node in model.get_children():
		var extras: Dictionary = holder.get_meta("extras", {})
		if extras.has("door_key"):
			var key := String(extras["door_key"])
			var entries: Array = _preview_doors.get(key, [])
			entries = entries.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry["node"]))
			entries.append({"node": holder, "state": String(extras["state"])})
			_preview_doors[key] = entries
			(holder as Node3D).visible = _open_doors.has(key) == (extras["state"] == "open")
		if extras.get("liftLeaf", false):
			_preview_lifts.append({"node": holder, "scene": id, "closed": (holder as Node3D).position})


static func _preview_plane(point: Vector2, outward: Vector2) -> Plane:
	return Plane(Vector3(outward.x, 0.0, outward.y), outward.dot(point))


## A closed, distant portal must not instantiate a second campus (or every ground
## floor). Keep the portal transform/clip metadata, load on approach, retain at most
## two interiors. Door/lift bindings are restored by _load_visual when materialized.
func _door_visual(id: String) -> Node3D:
	if not CampusBatches.enabled: return _load_visual(id)
	var placeholder := Node3D.new()
	placeholder.set_meta("preview_scene",id)
	return placeholder


func _ensure_door_preview(model: Node3D) -> void:
	if not model.has_meta("preview_scene") or model.get_child_count() > 0: return
	if preview_request.is_valid():
		preview_request.call(self, model, String(model.get_meta("preview_scene")), model.get_meta("preview_plane"))
		return
	var contents := _load_visual(String(model.get_meta("preview_scene")))
	if contents == null: return
	model.add_child(contents)
	CampusPreview.clip(model,model.get_meta("preview_plane"))
	_trim_door_previews(model)


func install_streamed_preview(model: Node3D, contents: Node3D, id: String) -> void:
	model.remove_meta("stream_pending")
	if model.get_child_count() > 0:
		contents.free()
		return
	_register_preview_doors(contents, id)
	model.add_child(contents)
	if door_previews.has(model):
		_trim_door_previews(model)


func _trim_door_previews(model: Node3D) -> void:
	var cached: Array[Node3D] = []
	for other: Node3D in door_previews:
		if other != model and other.has_meta("preview_scene") and other.get_child_count() > 0: cached.append(other)
	while cached.size() > 1:
		var old := cached.pop_front() as Node3D
		for child in old.get_children(): child.free()
		old.hide()


## The campus doors seen through (modules/campus-link/doors.js views): from outside the ground-floor room behind each door of
## the building, from a room the outdoors through its door; placed by the same shift as the seamless crossing. Visual only.
func _build_door_preview() -> void:
	var rooms := CampusData.rooms()
	var doors: Array = CampusData.campus().get("campus_doors", {}).get("doors", [])
	if scene_id == "out":
		for d: Dictionary in doors:
			var rid := String(d["room"])
			if not rooms.has(rid):
				continue
			var r: Dictionary = rooms[rid]
			var model := _door_visual(rid)
			if model == null:
				continue
			var c := Vector2(float(r["cx"]), float(r["cy"])) + CampusGeometry.shift_of(r)
			model.name = "DoorPreview_" + rid
			model.position = Vector3(c.x * CampusGeometry.U2M, 0.0, c.y * CampusGeometry.U2M)
			add_child(model)
			var port := CampusGeometry.door_port(r, d)
			var threshold := ((port["p"] as Vector2) + CampusGeometry.shift_of(r)) * CampusGeometry.U2M
			var plane := _preview_plane(threshold, -(port["n"] as Vector2))
			model.set_meta("preview_plane",plane)
			CampusPreview.clip(model,plane)
			model.set_meta("door_threshold", threshold)
			model.hide()
			door_previews.append(model)
		return
	for d: Dictionary in doors:
		if String(d["room"]) != scene_id:
			continue
		var model := _door_visual("out")
		if model == null:
			return
		var c := Vector2(float(layout["cx"]), float(layout["cy"])) + CampusGeometry.shift_of(layout)
		model.name = "DoorPreview_out"
		model.position = Vector3(-c.x * CampusGeometry.U2M, 0.0, -c.y * CampusGeometry.U2M)
		add_child(model)
		var port := CampusGeometry.door_port(layout, d)
		var threshold := CampusGeometry.to_scene(layout, port["p"])
		var plane := _preview_plane(threshold, port["n"])
		model.set_meta("preview_plane",plane)
		CampusPreview.clip(model,plane)
		model.set_meta("door_threshold", threshold)
		model.hide()
		door_previews.append(model)
		return


## The stairwell shafts seen through their doorways (fx/stairwell-view.js): every stair that serves this scene, its shaft model placed
## 2.8 m beyond the port, dropped by the level's height, turned by the port's normal. Visual only.
func _build_stair_preview() -> void:
	var rooms := CampusData.rooms()
	var outside := CampusData.layout("out")
	for st: Dictionary in CampusData.campus().get("stair_layout", []):
		if scene_id == String(st["id"]):
			continue
		var level := (st["rooms"] as Array).find(scene_id)
		if level < 0:
			continue
		var path := CampusData.scene_path(String(st["id"]))
		if not ResourceLoader.exists(path):
			continue
		var port := CampusPortals.stair_port(st, level, rooms, outside)
		if port.is_empty():
			continue
		var shaft := _load_visual(String(st["id"]))
		shaft.name = "StairPreview_" + String(st["id"])
		var pos := CampusGeometry.to_scene(layout if is_room() else null, port["p"])
		var n: Vector2 = port["n"]
		shaft.position = Vector3(pos.x + 2.8 * n.x, -float(level) * float(st["rise"]), pos.y + 2.8 * n.y)
		shaft.rotation.y = -CampusPortals.stair_turn(n)
		add_child(shaft)
		CampusPreview.clip(shaft, _preview_plane(pos, n))
		stair_previews.append(shaft)


func _build_link_preview() -> void:
	var rooms := CampusData.rooms()
	var cfg: Dictionary = CampusData.campus().get("campus_link", {})
	for v: Dictionary in CampusPortals.link_ports(cfg, rooms, scene_id):
		var peer_id := String(v["peer"]["room"])
		if not rooms.has(peer_id) or not ResourceLoader.exists(CampusData.scene_path(peer_id)):
			continue
		var model := _load_visual(peer_id)
		model.name = "LinkPreview_" + peer_id
		var t := CampusPortals.link_between(v["peer"], v["self"])
		var peer_room: Dictionary = rooms[peer_id]
		var phi := float(t["phi"])
		var c_there := Vector2(float(peer_room["cx"]), float(peer_room["cy"]))
		var c_here := Vector2(float(layout["cx"]), float(layout["cy"]))
		var p := (c_there.rotated(phi) + (t["t"] as Vector2) - c_here) * CampusGeometry.U2M
		model.rotation.y = -phi
		model.position = Vector3(p.x, 0.0, p.y)
		add_child(model)
		CampusPreview.clip(model, _preview_plane(CampusGeometry.to_scene(layout, v["self"]["p"]), v["self"]["n"]))
		link_previews.append(model)


# ---- model ----

## All visible scene models, including the neighbours seen through stairs and doors.
func _visual_models() -> Array[Node3D]:
	var models: Array[Node3D] = []
	models.append_array(link_previews)
	models.append_array(stair_previews)
	models.append_array(door_previews)
	for node: Node3D in _shaft_levels.values():
		models.append(node)
	models.append(gallery_campus)
	models.append(get_node_or_null("Model"))
	return models.filter(func(model: Node3D) -> bool: return is_instance_valid(model))


## Update surfaces even when the selected quality keeps the current model tier.
func apply_material_quality() -> void:
	for model: Node3D in _visual_models():
		SceneMaterials.apply(model, material_quality())


func material_quality() -> int:
	return int(render_options.get("lighting_detail",CampusLighting.quality))


func configure_rendering(options: Dictionary, camera: Camera3D = null) -> void:
	var previous:=material_quality()
	render_options=options.duplicate()
	if anomaly_fx!=null: anomaly_fx.particle_quality=int(options.get("particle_detail",-1))
	if previous!=material_quality(): apply_material_quality()
	if lighting!=null:
		lighting.options=render_options
		lighting.apply_quality(camera)
		lighting.update(0,lighting.clock_minutes,camera)
		lighting._select_local_lights(camera)


## Replace rendering nodes while physics, interactions and rule modules remain alive.
func reload_models(player_position: Vector3) -> void:
	if visual_tier == CampusData.tier:
		return
	var doors := _open_doors.duplicate()
	var lift_amount := _lift_amount
	for model: Node3D in _visual_models():
		model.free()
	link_previews.clear()
	stair_previews.clear()
	door_previews.clear()
	_shaft_levels.clear()
	gallery_campus = null
	_door_leaves.clear()
	_lift_leaves.clear()
	_preview_doors.clear()
	_preview_lifts.clear()
	_lift_amount = -1.0
	_build_model()
	if resident:
		apply_doors(doors)
		set_lift_doors(maxf(0.0, lift_amount))
		if lighting != null: lighting.rebind_model(get_node_or_null("Model"))
		return
	if is_room():
		_build_link_preview()
	_build_stair_preview()
	_build_door_preview()
	_build_gallery_view()
	update_shaft_previews(player_position.y)
	apply_doors(doors)
	set_lift_doors(maxf(0.0, lift_amount))
	set_player_scene(player_position)
	if lighting != null:
		lighting.rebind_model(get_node_or_null("Model"))
	if traces!=null: traces.build(scene_id,layout if is_room() else null,_trace_data)


func _build_model() -> void:
	var packed := load(CampusData.scene_path(scene_id)) as PackedScene
	if packed == null:
		push_error("校园模型缺失：%s" % scene_id)
		return
	var model := packed.instantiate() as Node3D
	visual_tier = CampusData.tier
	model.name = "Model"
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			_to_multimesh(mesh)
	if resident and scene_id in ["lift_teach", "lift_lab"]:
		CampusPreview.clip(model, Plane(Vector3.BACK, -1.04))
		CampusShell.carve_box(model,AABB(Vector3(-.49,0,-1.1),Vector3(.98,2.4,.3)))
		_car_leaves(model)
	elif resident and is_room():
		var cut := space.cabin_cut(scene_id)
		if cut.has_area(): CampusShell.carve_box(model, AABB(Vector3(cut.position.x,-.4,cut.position.y),Vector3(cut.size.x,space.floor_height(scene_id)+.5,cut.size.y)))
	if resident and layout.get("flags", {}).get("stairwell", false):
		CampusPreview.clip(model, Plane(Vector3.BACK, -2.8))
	if resident and scene_id == "teach6":
		CampusShell.carve_box(model, AABB(Vector3(-2.85,0,7.5),Vector3(1.7,4,3)))
	for holder: Node in model.get_children():
		var extras: Variant = holder.get_meta("extras") if holder.has_meta("extras") else null
		if extras is Dictionary and extras.get("liftLeaf", false):
			holder.set_meta("closed_position", (holder as Node3D).position)
			_lift_leaves.append(holder)
		if extras is Dictionary and extras.has("door_key"):
			var key := String(extras["door_key"])
			if not _door_leaves.has(key):
				_door_leaves[key] = {}
			_door_leaves[key][String(extras["state"])] = holder
	for key: String in _door_leaves:
		set_door_open(key, false)
	SceneMaterials.apply(model, material_quality())
	# The open garage has almost no hidden geometry from its normal view. Profiling
	# showed partitioning/CPU occlusion added overhead there; preserve its batches.
	if scene_id != "garage1":
		CampusBatches.optimize(model)
		if resident and scene_id == "out":
			shells = CampusShell.partition(model, space)
			var lining := StandardMaterial3D.new()
			lining.albedo_color = Color("667278")
			lining.roughness = .96
			for bounds: AABB in space.lift_walls():
				var panel := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = bounds.size
				box.material = lining
				panel.mesh = box
				panel.position = bounds.get_center()
				model.add_child(panel)
		CampusMeshCells.apply(model)
		if not (resident and scene_id == "out"): CampusBatches.add_occluder(model)
	visual_ground.set_model(model)


## Instances were kept as one prototype + per-instance transforms/colours in glTF extras.
static func _to_multimesh(source: MeshInstance3D) -> void:
	var extras: Dictionary = source.get_meta("extras")
	var xf := Marshalls.base64_to_raw(String(extras["wdfz_instances"])).to_float32_array()
	var count := xf.size() / 12
	var colors := PackedFloat32Array()
	if extras.has("wdfz_colors"):
		colors = Marshalls.base64_to_raw(String(extras["wdfz_colors"])).to_float32_array()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() >= count * 3
	mm.mesh = source.mesh
	mm.instance_count = count
	for i in count:
		var o := i * 12
		var basis := Basis(Vector3(xf[o], xf[o + 1], xf[o + 2]), Vector3(xf[o + 3], xf[o + 4], xf[o + 5]), Vector3(xf[o + 6], xf[o + 7], xf[o + 8]))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(xf[o + 9], xf[o + 10], xf[o + 11])))
		if mm.use_colors:
			mm.set_instance_color(i, Color(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2]))
	if mm.use_colors and source.mesh != null:
		for s in source.mesh.get_surface_count():
			var mat := source.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true
	var node := MultiMeshInstance3D.new()
	node.name = source.name
	node.multimesh = mm
	node.transform = source.transform
	node.set_meta("campus_transforms", xf)
	node.set_meta("campus_colors", colors)
	source.get_parent().add_child(node)
	source.get_parent().remove_child(source)
	source.free()


func set_door_open(key: String, open: bool) -> void:
	if open:
		_open_doors[key] = true
	else:
		_open_doors.erase(key)
	if _door_leaves.has(key):
		var leaves: Dictionary = _door_leaves[key]
		if leaves.has("closed"):
			(leaves["closed"] as Node3D).visible = not open
		if leaves.has("open"):
			(leaves["open"] as Node3D).visible = open
	if _door_bodies.has(key):
		(_door_bodies[key] as CollisionShape3D).set_deferred("disabled", open)
	for entry: Dictionary in _preview_doors.get(key, []):
		if is_instance_valid(entry["node"]):
			(entry["node"] as Node3D).visible = open == (entry["state"] == "open")


func apply_doors(open_doors: Dictionary) -> void:
	if _open_doors == open_doors:
		return
	for key: String in _open_doors.keys():
		if not open_doors.has(key):
			set_door_open(key, false)
	for key: String in open_doors:
		if not _open_doors.has(key):
			set_door_open(key, true)


func apply_lift_doors(lift: ElevatorModule) -> void:
	set_lift_doors(float(lift.lifts.get(scene_id.trim_prefix("lift_"), {}).get("door", 0)) if resident and scene_id in ["lift_teach", "lift_lab"] else lift.door_amount_in(scene_id))
	_preview_lifts = _preview_lifts.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry["node"]))
	for entry: Dictionary in _preview_lifts:
		var leaf: Node3D = entry["node"]
		var amount := lift.door_amount_in(String(entry["scene"]))
		var smooth := amount * amount * (3.0 - 2.0 * amount)
		var extras: Dictionary = leaf.get_meta("extras")
		leaf.position = (entry["closed"] as Vector3) + Vector3(float(extras.get("ox", 0.0)) * smooth, 0.0, float(extras.get("oz", 0.0)) * smooth)


## Elevator doors (model/lift.js LiftDoors + Elevator.doorDepth): leaves slide by smoothstep of the
## opening; both door panels block the doorway until the opening reaches 0.9.
func set_lift_doors(amount: float) -> void:
	if is_equal_approx(amount, _lift_amount):
		return
	_lift_amount = amount
	var e := amount * amount * (3.0 - 2.0 * amount)
	for leaf: Node3D in _lift_leaves:
		var extras: Dictionary = leaf.get_meta("extras")
		var base: Vector3 = leaf.get_meta("closed_position")
		leaf.position = base + Vector3(float(extras.get("ox", 0.0)) * e, 0.0, float(extras.get("oz", 0.0)) * e)
	for shape: CollisionShape3D in _lift_bodies:
		shape.set_deferred("disabled", amount >= 0.9)


## Inspection silhouettes (InspectionView, fx/inspection-fx.js): the old figure, black. When the check ends they scatter:
## away from the player at 1.5 m/s, fading out over 0.8 s (scatter_t).
var _silhouettes: Node3D
var _silhouette_key := ""
var _silhouette_dirs: Array = []
var _scatter: Node3D
var _scatter_t := 0.0
var _scatter_dirs: Array = []
const SCATTER_SECONDS := 0.8
const SCATTER_SPEED := 1.5


func _process(delta: float) -> void:
	if _scatter == null or not is_instance_valid(_scatter):
		return
	_scatter_t += delta
	var alpha := maxf(0.0, 1.0 - _scatter_t / SCATTER_SECONDS)
	var i := 0
	for f: Node3D in _scatter.get_children():
		var dir: Vector2 = _scatter_dirs[i]
		f.position += Vector3(dir.x, 0.0, dir.y) * delta * SCATTER_SPEED
		FigureGait.step(f, delta * SCATTER_SPEED, delta)
		for mi: Node in f.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = alpha
		i += 1
	if _scatter_t >= SCATTER_SECONDS:
		_scatter.queue_free()
		_scatter = null


func sync_ground_items(list: Array, focus: int) -> void:
	if ground_items == null:
		return
	ground_items.sync(list)
	ground_items.set_focus(focus)


## Rebuild the leftovers when an anomaly has just left one (the list of AnomalyModule.traces).
func sync_traces(list: Array) -> void:
	if traces == null or (list.size() == _traces_seen and list==_trace_data):
		return
	_traces_seen = list.size()
	_trace_data=list.duplicate(true)
	traces.build(scene_id, layout if is_room() else null, list)


func scattering() -> bool:
	return _scatter != null and is_instance_valid(_scatter)


func show_silhouettes(points: Array, room: Variant, height: float) -> void:
	var key := str(points)
	if key == _silhouette_key:
		return
	_silhouette_key = key
	if is_instance_valid(_silhouettes):
		if points.is_empty() and not _silhouette_dirs.is_empty():
			# The check is over: they scatter instead of vanishing.
			if is_instance_valid(_scatter):
				_scatter.queue_free()
			_scatter = _silhouettes
			_scatter_t = 0.0
			_scatter_dirs = _silhouette_dirs.duplicate()
			for f: Node in _scatter.get_children():
				for mi: Node in f.find_children("*", "MeshInstance3D", true, false):
					var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
					if m != null:
						m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			_silhouettes.queue_free()
	_silhouettes = null
	if points.is_empty():
		return
	_silhouettes = Node3D.new()
	_silhouettes.name = "InspectionSilhouettes"
	add_child(_silhouettes)
	for xy: Array in points:
		var s := CampusGeometry.to_scene(room, Vector2(xy[0], xy[1]))
		var fig := FigureModel.make("person", Color("030405"), true, 1.0, Color.BLACK, true, false, null, true)
		fig.position = Vector3(s.x, height, s.y)
		fig.rotation.y = PI
		_silhouettes.add_child(fig)
	_silhouette_dirs = _scatter_dirs_of(_silhouettes,room)


## Directions (x, z) from the player to each figure; the player is where the camera looks from (the first person).
var _player_scene := Vector3.ZERO


func set_player_scene(p: Vector3) -> void:
	_player_scene = p
	# CampusDoor.frame: only the nearest entrance is previewed, with 12/15 m hysteresis.
	# Rendering every interior while crossing the campus was both misleading and expensive.
	var nearest: Node3D
	var distance := INF
	var here := Vector2(p.x, p.z)
	for model: Node3D in door_previews:
		var at: Vector2 = model.get_meta("door_threshold")
		var d := here.distance_to(at)
		if d < distance:
			distance = d
			nearest = model
	var show_nearest := nearest != null and distance <= (15.0 if nearest.visible else 12.0)
	if nearest != null and distance <= 13.0: _ensure_door_preview(nearest)
	for model: Node3D in door_previews:
		model.visible = model == nearest and show_nearest


func _scatter_dirs_of(group: Node3D, _room: Variant) -> Array:
	var out: Array = []
	for f: Node3D in group.get_children():
		var dx := f.position.x - _player_scene.x
		var dz := f.position.z - _player_scene.z
		var len := maxf(0.001, sqrt(dx * dx + dz * dz))
		out.append(Vector2(dx / len, dz / len))
	return out


## The pose follows the visible patrol's observed heading and authoritative behaviour.
var _patrol_figure: OtherworldFigure
const PATROL_FIGURE := "res://assets/campus/figures/otherworld/patroller.glb"


func show_patrol(visible_now: bool, scene_pos: Vector2, height: float, toward: Vector3, behavior: String = "patrol", dt: float = 0.0) -> void:
	if not visible_now:
		if is_instance_valid(_patrol_figure): _patrol_figure.hide()
		return
	if not is_instance_valid(_patrol_figure):
		_patrol_figure = OtherworldFigure.make("patroller", _patrol_asset)
		_patrol_figure.name = "Patroller"
		add_child(_patrol_figure)
		_patrol_figure.hide()
	var next := Vector3(scene_pos.x, height, scene_pos.y)
	var distance := _patrol_figure.position.distance_to(next) if _patrol_figure.visible else 0.0
	_patrol_figure.position = next
	var forward := Vector2(toward.x-scene_pos.x,toward.z-scene_pos.y)
	if forward.length_squared()>.00001: _patrol_figure.rotation.y = atan2(-forward.x,-forward.y)
	_patrol_figure.show()
	_patrol_figure.patrol_pose(dt,distance,behavior)


var _garage_shadow: OtherworldFigure


func show_garage_shadow(visible_now: bool, scene_pos: Vector2, height: float) -> void:
	if not visible_now:
		if is_instance_valid(_garage_shadow): _garage_shadow.hide()
		return
	if not is_instance_valid(_garage_shadow):
		_garage_shadow = OtherworldFigure.make("roam")
		_garage_shadow.name = "GarageShadow"
		add_child(_garage_shadow)
	_garage_shadow.position = Vector3(scene_pos.x,height,scene_pos.y)
	_garage_shadow.rotation.y = atan2(scene_pos.x-_player_scene.x,scene_pos.y-_player_scene.z)
	_garage_shadow.face.rotation = Vector3(-.28, .20, -.24)
	_garage_shadow.show()


## The opened door of the portal route (portal.js): a ring of coloured light in front of the physics bench.
var _portal_dev: PortalDevice


## The checkup day in admin1 (checkup.js, placeholder): height rule, scale and eye chart in the
## office's front aisle, a sign by the door, and five people queueing in the corridor facing the
## wall; the queue blocks the way (its own collision) while it stands.
var _checkup: Node3D
var _checkup_queue: StaticBody3D
var _checkup_line := ""


func show_checkup(on: bool, queue: bool, line: String) -> void:
	if not on or scene_id != "admin1":
		if is_instance_valid(_checkup):
			_checkup.queue_free()
		_checkup = null
		return
	if is_instance_valid(_checkup) and _checkup_line != line:
		_checkup.queue_free()
		_checkup = null
	if not is_instance_valid(_checkup):
		_checkup_line = line
		_checkup = Node3D.new()
		_checkup.name = "CheckupDay"
		add_child(_checkup)
		var room := CampusData.layout("admin1")
		var at := func(c: float, r: float) -> Vector3:
			var w := Vector2(float(room["ox"]) + c * float(room["tw"]), float(room["oy"]) + r * float(room["th"]))
			var sp := CampusGeometry.to_scene(room, w)
			return Vector3(sp.x, 0.0, sp.y)
		var props := CheckupProps.new()
		props.build(room,line)
		_checkup.add_child(props)
		_checkup_queue = StaticBody3D.new()
		_checkup_queue.name = "Queue"
		_checkup_queue.collision_layer = 1
		_checkup_queue.collision_mask = 0
		_checkup.add_child(_checkup_queue)
		var k := 0
		for q: Vector2 in [Vector2(1.45, 17.32), Vector2(2.22, 17.32), Vector2(3.0, 17.32), Vector2(3.78, 17.32), Vector2(4.55, 17.32)]:
			var p: Vector3 = at.call(q.x, q.y)
			var fig := FigureModel.make("person",Color("4a5668"),false,.96+.03*float((k*37)%3),Color("252b35"))
			fig.position = p
			_checkup_queue.add_child(fig)
			var shape := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.48 * float(room["tw"]) * CampusGeometry.U2M, 1.8, 0.34 * float(room["th"]) * CampusGeometry.U2M)
			shape.shape = bs
			shape.position = p + Vector3(0, 0.9, 0)
			_checkup_queue.add_child(shape)
			k += 1
	_checkup_queue.visible = queue
	_checkup_queue.collision_layer = 1 if queue else 0


func checkup_shown() -> bool:
	return is_instance_valid(_checkup)


func checkup_queue_blocks() -> bool:
	return is_instance_valid(_checkup_queue) and _checkup_queue.collision_layer == 1


## A revisit's note on the floor (fx/dread-fx.js note): a sheet of exercise paper 1.3–2.1 m ahead,
## one handwritten line, faintly lit so it can be read in the dark. Empty text removes it.
var _dread_note: Node3D


func show_dread_note(text: String, seed: float, pose: Dictionary) -> void:
	if is_instance_valid(_dread_note):
		_dread_note.queue_free()
	_dread_note = null
	if text == "" or not is_room():
		return
	var p: Array = pose["position"]
	var yaw := float(pose["yaw"])
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_dread_note = Node3D.new()
	_dread_note.name = "DreadNote"
	var paper := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.34, 0.234)
	paper.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.74)
	mat.emission_enabled = true
	mat.emission = Color(0.54, 0.52, 0.47) * 0.6
	RenderMaterials.set_override(paper, mat)
	_dread_note.add_child(paper)
	var label := Label3D.new()
	label.text = text
	label.font_size = 44
	label.pixel_size = 0.0006
	label.modulate = Color(0.17, 0.15, 0.13)
	label.outline_size = 0
	label.width = 520.0
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.rotation.x = -PI * 0.5
	label.position.y = 0.006
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_dread_note.add_child(label)
	_dread_note.position = Vector3(float(p[0]), float(p[1]) + 0.006, float(p[2])) + fwd * (1.3 + fmod(seed * 7.0, 1.0) * 0.8)
	_dread_note.rotation.y = seed * TAU
	add_child(_dread_note)


## A sheet or a chalk line on a wall (2026-11-14 horror plan): "board" is a revisit's chalk line, "notice" the
## academic office's corridor notice (black lines, one in red ink without the stamp). pos is the wall face in
## scene metres, yaw faces the reader. Empty lines remove it.
var _wall_text: Node3D


func show_wall_text(kind: String, lines: Array, pos: Vector3, yaw: float) -> void:
	if is_instance_valid(_wall_text):
		_wall_text.queue_free()
	_wall_text = null
	if lines.is_empty() or not is_room():
		return
	_wall_text = Node3D.new()
	_wall_text.name = "WallText_" + kind
	_wall_text.set_meta("kind", kind)
	_wall_text.set_meta("lines", lines.duplicate(true))
	var notice := kind == "notice"
	if notice:
		var paper := MeshInstance3D.new()
		paper.name = "Paper"
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.66)
		paper.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.84, 0.77)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.48, 0.43) * 0.5
		RenderMaterials.set_override(paper, mat)
		_wall_text.add_child(paper)
	var rows: Array = [{"text": "教务处通知", "color": Color(0.12, 0.11, 0.1), "size": 70}] if notice else []
	for l: Variant in lines:
		var d: Dictionary = l if l is Dictionary else {"text": String(l)}
		var red := bool(d.get("fake", false))
		rows.append({"text": String(d["text"]), "color": Color(0.62, 0.06, 0.05) if red else (Color(0.1, 0.12, 0.2) if notice else Color(0.9, 0.9, 0.86, 0.85)), "size": 48 if notice else 110})
	if notice:
		rows.append({"text": "教务处（章）", "color": Color(0.62, 0.1, 0.08), "size": 42})
	var y := 0.24 if notice else 0.0
	for r: Dictionary in rows:
		var label := Label3D.new()
		label.text = String(r["text"])
		label.font_size = int(r["size"])
		label.pixel_size = 0.0007 if notice else 0.0012
		label.modulate = r["color"]
		label.outline_size = 0
		label.width = 520.0 if notice else 900.0
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		label.position = Vector3(0.0, y, 0.004)
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_wall_text.add_child(label)
		y -= 0.115 if notice else 0.16
	_wall_text.position = pos
	_wall_text.rotation.y = yaw
	add_child(_wall_text)


func wall_text_kind() -> String:
	return String(_wall_text.get_meta("kind", "")) if is_instance_valid(_wall_text) else ""


func wall_text_lines() -> Array:
	return _wall_text.get_meta("lines", []) if is_instance_valid(_wall_text) else []


func wall_text_position() -> Variant:
	return _wall_text.position if is_instance_valid(_wall_text) and _wall_text.is_inside_tree() else null


func dread_note_text() -> String:
	if not is_instance_valid(_dread_note):
		return ""
	return (_dread_note.get_child(1) as Label3D).text


func show_portal(open_now: bool, sketch_now: bool = false) -> void:
	# The rig stands on the lab's first bench tile in every stage (PortalDevice.sync): bare, sockets lit once the plans are
	# complete, door open.
	if scene_id != "lab1":
		if is_instance_valid(_portal_dev):
			_portal_dev.visible = false
		return
	if not is_instance_valid(_portal_dev):
		var spot := PortalDevice.bench_spot(CampusData.layout("lab1"))
		_portal_dev = PortalDevice.new()
		_portal_dev.build()
		_portal_dev.position = Vector3(spot.x, 0.0, spot.y)
		add_child(_portal_dev)
	_portal_dev.visible = true
	var st := "open" if open_now else ("ready" if sketch_now else "base")
	if _portal_dev.state != st:
		_portal_dev.set_state(st, 1.0)


## Hide the rig for a cutscene that brings its own.
func hide_portal() -> void:
	if is_instance_valid(_portal_dev):
		_portal_dev.visible = false


func portal_shown() -> bool:
	return is_instance_valid(_portal_dev) and _portal_dev.visible and _portal_dev.state == "open"


func garage_shadow_shown() -> bool:
	return is_instance_valid(_garage_shadow) and _garage_shadow.visible


func patrol_figure_shown() -> bool:
	return is_instance_valid(_patrol_figure) and _patrol_figure.visible


func silhouette_count() -> int:
	return _silhouettes.get_child_count() if is_instance_valid(_silhouettes) else 0


func lift_leaf_count() -> int:
	return _lift_leaves.size()


func door_keys() -> PackedStringArray:
	return PackedStringArray(_door_bodies.keys())


# ---- collision ----

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var extent := _extent()
	var rules := CampusData.rules()
	if scene_id == "lift_dream":
		MazePhysics.build(body, CampusData.maze_geometry())
		return
	if resident and scene_id in ["lift_teach", "lift_lab"]:
		_build_resident_car(body)
		return
	if rules.is_stairwell(scene_id):
		_build_stairwell(body, rules.stair_surfaces(scene_id))
		return
	var floors: Array[Rect2] = [extent if resident and is_room() else Rect2(extent.position - Vector2.ONE * 2, extent.size + Vector2.ONE * 4)]
	if resident and scene_id == "out": floors = CampusSpace.subtract_rect(floors[0], space.garage_hole())
	for floor_rect: Rect2 in floors: _add_box(body, floor_rect, -0.12 if resident else -1.0, 0.0, "floor")
	if is_room():
		var cut := space.cabin_cut(scene_id) if resident else Rect2()
		for b: Dictionary in layout["walls"] + layout["boxes"]:
			if cut.has_area():
				for part: Rect2 in CampusSpace.subtract_rect(_rect_of(b), cut): _add_box(body, part, WALL_BOTTOM, _wall_top(), String(b["k"]))
			else: _add_rect(body, b)
		if layout["flags"].get("spiral", false):
			_build_spiral(body, CampusData.campus()["spiral"])
		var doorways := rules.stair_doorways(scene_id)
		for b: Dictionary in layout["stairs"]:
			for part: Rect2 in _cut_doorways(_rect_of(b), doorways):
				_add_box(body, part, WALL_BOTTOM, _wall_top(), "stair")
		_room_boundary(body, extent)
		var doors := StaticBody3D.new()
		doors.name = "Doors"
		doors.collision_layer = 1
		doors.collision_mask = 0
		add_child(doors)
		for d: Dictionary in layout["doors"]:
			_door_bodies[String(d["key"])] = _add_rect(doors, d)
		var lift_rects := CampusData.lift_geometry().door_rects(scene_id)
		if resident and lift_rects.size() > 1: lift_rects.resize(1)
		for r: Rect2 in lift_rects:
			_lift_bodies.append(_add_box(doors, r, WALL_BOTTOM, _wall_top(), "lift_door"))
	else:
		var cuts: Array[Rect2] = []
		var bridges: Array[AABB] = []
		if resident:
			cuts = space.shaft_footprints()
			bridges = space.bridge_volumes()
			for wall: AABB in space.lift_walls():
				_add_box(body,Rect2(wall.position.x,wall.position.z,wall.size.x,wall.size.z),wall.position.y,wall.end.y,"lift_shaft")
		for b: Dictionary in layout["boxes"]:
			if resident and b.k=="building" and space.has_building(String(b.get("id",""))): continue
			var parts: Array[Rect2]=[_rect_of(b)]
			for cut in cuts:
				if not _rect_of(b).intersects(cut): continue
				var remaining: Array[Rect2]=[]
				for part in parts: remaining.append_array(CampusSpace.subtract_rect(part,cut))
				parts=remaining
			for bridge: AABB in bridges:
				var opening:=Rect2(bridge.position.x,bridge.position.z,bridge.size.x,bridge.size.z)
				if not _rect_of(b).intersects(opening): continue
				var remaining: Array[Rect2]=[]
				for part in parts:
					var below:=part.intersection(opening)
					if below.has_area(): _add_box(body,below,WALL_BOTTOM,bridge.position.y,b.k)
					remaining.append_array(CampusSpace.subtract_rect(part,opening))
				parts=remaining
			for part in parts: _add_box(body,part,WALL_BOTTOM,WALL_TOP,b.k)
		var bd: Dictionary = layout["bound"]
		var inner := Rect2(Vector2(bd["x0"], bd["z0"]), Vector2(float(bd["x1"]) - float(bd["x0"]), float(bd["z1"]) - float(bd["z0"])))
		_ring(body, inner, [])


func _extent() -> Rect2:
	if is_room():
		var w := int(layout["cols"]) * float(layout["tw"]) * CampusGeometry.U2M
		var h := int(layout["rows"]) * float(layout["th"]) * CampusGeometry.U2M
		return Rect2(-w * 0.5, -h * 0.5, w, h)
	var bd: Dictionary = layout["bound"]
	return Rect2(Vector2(bd["x0"], bd["z0"]), Vector2(float(bd["x1"]) - float(bd["x0"]), float(bd["z1"]) - float(bd["z0"])))


func _rect_of(b: Dictionary) -> Rect2:
	return Rect2(Vector2(b["x0"], b["z0"]), Vector2(float(b["x1"]) - float(b["x0"]), float(b["z1"]) - float(b["z0"])))


func _add_rect(parent: Node3D, b: Dictionary) -> CollisionShape3D:
	return _add_box(parent, _rect_of(b), WALL_BOTTOM, _wall_top(), String(b["k"]))


func _wall_top() -> float:
	return space.floor_height(scene_id) - 0.15 if resident and scene_id != "out" and scene_id != "bell1" else WALL_TOP


## Old rule (collision.js + StairWorld.doorwayFree): a stair cell is solid except the 1.7 m doorway
## the body fits through; the shaft threshold is crossed in the middle of that cell.
func _cut_doorways(r: Rect2, doorways: Array[Dictionary]) -> Array[Rect2]:
	var parts: Array[Rect2] = [r]
	for d: Dictionary in doorways:
		var c: Vector2 = d["center"]
		var n: Vector2 = d["normal"]
		var lateral: Vector2 = d["lateral"]
		var half := float(d["half"])
		# portalAt accepts body centres -0.85 < depth < 0.5 metres. Expand
		# that interval by the body radius to construct the physical opening.
		# In particular, do not cut through the second row of roof stair cells.
		var radius := CampusGeometry.PRAD * CampusGeometry.U2M
		var a := c + n * (-0.85 - radius) - lateral * half
		var b := c + n * (10.0 if resident else (0.5 + radius)) + lateral * half
		var cut := Rect2(a.min(b), (b - a).abs())
		var next: Array[Rect2] = []
		for q: Rect2 in parts:
			var overlap := q.intersection(cut)
			if not overlap.has_area():
				next.append(q)
				continue
			for piece: Rect2 in [
				Rect2(q.position, Vector2(q.size.x, overlap.position.y - q.position.y)),
				Rect2(Vector2(q.position.x, overlap.end.y), Vector2(q.size.x, q.end.y - overlap.end.y)),
				Rect2(Vector2(q.position.x, overlap.position.y), Vector2(overlap.position.x - q.position.x, overlap.size.y)),
				Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(q.end.x - overlap.end.x, overlap.size.y))]:
				if piece.has_area():
					next.append(piece)
		parts = next
	return parts


## Stairwell: only StairGeometry.surfaces are walkable (stairwell.js depth). Slabs and ramps carry
## the body; walls keep it from stepping off where the old rule found no surface.
func _build_stairwell(body: StaticBody3D, surfaces: Array[Dictionary]) -> void:
	var top := 0.0
	for s: Dictionary in surfaces:
		top = maxf(top, maxf(float(s["h0"]), float(s["h1"])))
		_add_slab(body, s)
	var y0 := -1.0
	var y1 := top + 3.5
	var walls: Array[Rect2] = [
		Rect2(-3.2, -1.2, 1.0, 8.4), Rect2(2.2, -1.2, 1.0, 8.4),          # outer side walls
		Rect2(-3.2, 7.2, 6.4, 1.0),                                        # back wall
		Rect2(-3.2, -2.2, 2.35, 1.0), Rect2(0.85, -2.2, 2.35, 1.0),       # front wall beside the corridor
		Rect2(-1.85, -4.5, 1.0, 3.3), Rect2(0.85, -4.5, 1.0, 3.3),        # corridor walls
		Rect2(-1.85, -4.5, 3.7, 1.0),                                      # corridor end
		Rect2(-0.3, 0.8, 0.6, 4.8),                                        # slot between the two flights
	]
	if resident:
		# The old 2D adapter inflated outer walls by a metre. That reaches into
		# the neighbouring bridge in a shared 3D world; use the visible shell.
		walls = [Rect2(-2.32,-1.2,.12,8.4),Rect2(2.2,-1.2,.12,8.4),
			Rect2(-2.32,7.2,4.64,.12),Rect2(-2.32,-1.32,1.47,.12),Rect2(.85,-1.32,1.47,.12),
			Rect2(-.97,-2.8,.12,1.6),Rect2(.85,-2.8,.12,1.6),Rect2(-.3,.8,.6,4.8)]
	for r: Rect2 in walls:
		_add_box(body, r, y0, y1, "stairwell")
	# Under the first upper flight (level 0, x 0.3..2.2) there is no surface at ground height.
	_add_box(body, Rect2(0.3, 0.8, 1.9, 4.8), y0, 1.4, "stairwell")
	# Top landing: the down-going flight side has no flight above it.
	_add_box(body, Rect2(-2.2, 0.8, 1.9, 0.1), top, top + 2.5, "stairwell")


## Bell tower spiral (spiral.js + content/spiral-data.js). The old game tracks ground/stair/top
## states on a flat grid; physically: the first turn is solid underneath (only the entry angles
## step on), the second turn is a slab, rails run outside, the top ring leaves the stair hole open
## and fences its far edge (spiralSolid).
func _build_spiral(body: StaticBody3D, sp: Dictionary) -> void:
	var c := Vector2(sp["cx"], sp["cz"])
	var r_in := float(sp["rIn"])
	var r_out := float(sp["rOut"])
	var turn_h := float(sp["turnH"])
	var amax := float(sp["amax"])
	var top_h := float(sp["topH"])
	var th0 := float(sp["th0"])
	var hole := float(sp["hole"])
	var column := CylinderShape3D.new()
	column.radius = r_in
	column.height = top_h + 4.0
	var col_node := CollisionShape3D.new()
	col_node.shape = column
	col_node.position = Vector3(c.x, column.height * 0.5 - 0.5, c.y)
	col_node.set_meta("kind", "spiral")
	body.add_child(col_node)
	var seg := 48
	var n := int(round(amax / TAU * seg))
	for i in n:
		var a0 := i * TAU / seg
		var a1 := (i + 1) * TAU / seg
		var h0 := a0 / TAU * turn_h
		var h1 := a1 / TAU * turn_h
		var bottom0 := -0.5 if a1 <= TAU + 1e-6 else h0 - 0.18
		var bottom1 := -0.5 if a1 <= TAU + 1e-6 else h1 - 0.18
		_convex(body, [_polar(c, th0 + a0, r_in, h0), _polar(c, th0 + a0, r_out, h0), _polar(c, th0 + a1, r_in, h1), _polar(c, th0 + a1, r_out, h1),
			_polar(c, th0 + a0, r_in, bottom0), _polar(c, th0 + a0, r_out, bottom0), _polar(c, th0 + a1, r_in, bottom1), _polar(c, th0 + a1, r_out, bottom1)])
		if a1 > 0.35:
			_convex(body, [_polar(c, th0 + a0, r_out, h0 - 0.3), _polar(c, th0 + a0, r_out + 0.12, h0 - 0.3), _polar(c, th0 + a1, r_out, h1 - 0.3), _polar(c, th0 + a1, r_out + 0.12, h1 - 0.3),
				_polar(c, th0 + a0, r_out, h0 + 1.3), _polar(c, th0 + a0, r_out + 0.12, h0 + 1.3), _polar(c, th0 + a1, r_out, h1 + 1.3), _polar(c, th0 + a1, r_out + 0.12, h1 + 1.3)])
	var base := th0 + amax
	var platform := TAU - hole
	var k := int(ceil(platform / (TAU / seg)))
	for i in k:
		var u0 := platform * i / k
		var u1 := platform * (i + 1) / k
		_convex(body, [_polar(c, base + u0, r_in, top_h), _polar(c, base + u0, r_out, top_h), _polar(c, base + u1, r_in, top_h), _polar(c, base + u1, r_out, top_h),
			_polar(c, base + u0, r_in, top_h - 0.16), _polar(c, base + u0, r_out, top_h - 0.16), _polar(c, base + u1, r_in, top_h - 0.16), _polar(c, base + u1, r_out, top_h - 0.16)])
	for i in seg:
		var t0 := i * TAU / seg
		var t1 := (i + 1) * TAU / seg
		_convex(body, [_polar(c, t0, r_out, top_h), _polar(c, t0, r_out + 0.12, top_h), _polar(c, t1, r_out, top_h), _polar(c, t1, r_out + 0.12, top_h),
			_polar(c, t0, r_out, top_h + 1.2), _polar(c, t0, r_out + 0.12, top_h + 1.2), _polar(c, t1, r_out, top_h + 1.2), _polar(c, t1, r_out + 0.12, top_h + 1.2)])
	var fence := base + platform
	_convex(body, [_polar(c, fence, r_in, top_h), _polar(c, fence, r_out, top_h), _polar(c, fence + 0.03, r_in, top_h), _polar(c, fence + 0.03, r_out, top_h),
		_polar(c, fence, r_in, top_h + 1.2), _polar(c, fence, r_out, top_h + 1.2), _polar(c, fence + 0.03, r_in, top_h + 1.2), _polar(c, fence + 0.03, r_out, top_h + 1.2)])


static func _polar(c: Vector2, a: float, r: float, y: float) -> Vector3:
	return Vector3(c.x + cos(a) * r, y, c.y + sin(a) * r)


func _convex(body: StaticBody3D, points: Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(points)
	var node := CollisionShape3D.new()
	node.shape = shape
	node.set_meta("kind", "spiral")
	body.add_child(node)


func _add_slab(body: StaticBody3D, s: Dictionary) -> void:
	var t := 0.12
	var dz := float(s["z1"]) - float(s["z0"])
	var dh := float(s["h1"]) - float(s["h0"])
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(s["x1"]) - float(s["x0"]), t, sqrt(dz * dz + dh * dh))
	var basis := Basis(Vector3.RIGHT, -atan2(dh, dz))
	var mid := Vector3((float(s["x0"]) + float(s["x1"])) * 0.5, (float(s["h0"]) + float(s["h1"])) * 0.5, (float(s["z0"]) + float(s["z1"])) * 0.5)
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = Transform3D(basis, mid - basis.y * (t * 0.5))
	node.set_meta("kind", "stair_surface")
	body.add_child(node)


func _add_box(parent: Node3D, r: Rect2, y0: float, y1: float, kind: String) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(r.size.x, 0.001), y1 - y0, maxf(r.size.y, 0.001))
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = Vector3(r.position.x + r.size.x * 0.5, (y0 + y1) * 0.5, r.position.y + r.size.y * 0.5)
	node.set_meta("kind", kind)
	parent.add_child(node)
	return node


## Old rule (collision.js): outside the room grid is wall, except the annex of a seamless door,
## which lets the body centre reach the threshold line where the scene switches.
func _room_boundary(body: StaticBody3D, extent: Rect2) -> void:
	var gaps: Array = []
	var campus := CampusData.campus()
	var cfg: Dictionary = campus.get("campus_doors", {})
	for d: Dictionary in cfg.get("doors", []):
		if d["room"] != scene_id:
			continue
		var port := CampusGeometry.door_port(layout, d)
		var p := CampusGeometry.to_scene(layout, port["p"])
		var n: Vector2 = port["n"]
		var half := CampusGeometry.door_half(d, float(cfg.get("width", 3))) * CampusGeometry.U2M
		var depth := float(cfg.get("annex", 1.5)) * CampusGeometry.TTILE * CampusGeometry.U2M + CampusGeometry.PRAD * CampusGeometry.U2M
		gaps.append({"edge": d["edge"], "center": p, "half": half})
		if not resident: _annex(body, p, n, half, depth)
	# The cabin behind a floor's elevator doors lies outside the grid (Elevator.annexAt); its walls are
	# exported props, so only the boundary opens there.
	var cabin := CampusData.lift_geometry().cabin_gap(scene_id)
	if not cabin.is_empty():
		gaps.append(cabin)
	# Corridor bridges (campus-link/link.js) open the same kind of gap.
	for g: Dictionary in CampusData.rules().link_doorways(scene_id):
		gaps.append(g)
		if not resident: _annex(body, g["center"], g["normal"], float(g["half"]), float(g["depth"]) + CampusGeometry.PRAD * CampusGeometry.U2M)
	if resident:
		for stair: Dictionary in campus.get("stair_layout", []):
			var level := (stair["rooms"] as Array).find(scene_id)
			if level < 0: continue
			var port := CampusPortals.stair_port(stair, level, CampusData.rooms(), CampusData.layout("out"))
			var normal: Vector2 = port["n"]
			gaps.append({"edge": "s" if normal.y > 0 else ("n" if normal.y < 0 else ("e" if normal.x > 0 else "w")),
				"center": CampusGeometry.to_scene(layout, port["p"]), "half": CampusPortals.DOOR_HALF})
	_ring(body, extent, gaps)


## Annex side walls and end wall outside the grid, beyond a threshold the body centre may cross.
func _annex(body: StaticBody3D, p: Vector2, n: Vector2, half: float, depth: float) -> void:
	var lateral := Vector2(-n.y, n.x)
	for side: float in [-1.0, 1.0]:
		var a := p + lateral * side * half
		var b := a + n * depth + lateral * side * BOUNDARY
		_add_box(body, Rect2(a, Vector2.ZERO).expand(b), WALL_BOTTOM, WALL_TOP, "annex")
	var e0 := p + n * depth - lateral * half
	var e1 := p + n * (depth + BOUNDARY) + lateral * half
	_add_box(body, Rect2(e0, Vector2.ZERO).expand(e1), WALL_BOTTOM, WALL_TOP, "annex")


func _ring(body: StaticBody3D, r: Rect2, gaps: Array) -> void:
	var t := 0.12 if resident else BOUNDARY
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	_edge(body, "n", Vector2(x0 - t, z0 - t), Vector2(x1 + t, z0), gaps)
	_edge(body, "s", Vector2(x0 - t, z1), Vector2(x1 + t, z1 + t), gaps)
	_edge(body, "w", Vector2(x0 - t, z0), Vector2(x0, z1), gaps)
	_edge(body, "e", Vector2(x1, z0), Vector2(x1 + t, z1), gaps)


func _edge(body: StaticBody3D, edge: String, a: Vector2, b: Vector2, gaps: Array) -> void:
	var horizontal := edge in ["n", "s"]
	var spans: Array = [[a.x, b.x] if horizontal else [a.y, b.y]]
	for g: Dictionary in gaps:
		if g["edge"] != edge:
			continue
		var c: Vector2 = g["center"]
		var lo := (c.x if horizontal else c.y) - float(g["half"])
		var hi := (c.x if horizontal else c.y) + float(g["half"])
		var next: Array = []
		for s: Array in spans:
			if hi <= s[0] or lo >= s[1]:
				next.append(s)
				continue
			if lo > s[0]:
				next.append([s[0], lo])
			if hi < s[1]:
				next.append([hi, s[1]])
		spans = next
	for s: Array in spans:
		var rect := Rect2(Vector2(s[0], a.y), Vector2(s[1] - s[0], b.y - a.y)) if horizontal \
			else Rect2(Vector2(a.x, s[0]), Vector2(b.x - a.x, s[1] - s[0]))
		_add_box(body, rect, WALL_BOTTOM, _wall_top(), "boundary")


# ---- lighting (lighting.js port in CampusLighting) ----

func _build_lighting() -> void:
	lighting = CampusLighting.new()
	lighting.options=render_options
	lighting.name = "Lighting"
	add_child(lighting)
	var rise := 0.0
	for s: Dictionary in CampusData.campus().get("stair_layout", []):
		if s["id"] == scene_id:
			rise = float(s["rise"])
	lighting.setup(scene_id, layout if is_room() else null, get_node_or_null("Model"), rise)


func update_lighting(dt: float, tsec: float, camera: Camera3D, patrol_flick: float = 0.0, patrol_red: float = 0.0, blackout: bool = false, overcast: float = 0.0) -> void:
	if lighting != null:
		lighting.patrol_flick = patrol_flick
		lighting.patrol_red = patrol_red
		lighting.blackout = blackout
		lighting.overcast_target = overcast
		lighting.update(dt, tsec, camera)


func _build_placeholder_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.65) if not is_room() else Color(0.05, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.86, 0.88)
	env.ambient_light_energy = 0.55 if is_room() else 0.7
	var world_env := WorldEnvironment.new()
	world_env.name = "PlaceholderEnvironment"
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "PlaceholderSun" if not is_room() else "PlaceholderCeiling"
	sun.rotation_degrees = Vector3(-55, 30, 0) if not is_room() else Vector3(-90, 0, 0)
	sun.light_energy = 0.9 if not is_room() else 0.45
	add_child(sun)


func _build_resident_car(body: StaticBody3D) -> void:
	# Only the car moves. The hallway and landing door belong to each storey.
	_add_box(body, Rect2(-.85,-1.03,1.7,1.58),-.12,0,"floor")
	_add_box(body, Rect2(-.85,-1.03,.10,1.58),0,2.65,"car_wall")
	_add_box(body, Rect2(.75,-1.03,.10,1.58),0,2.65,"car_wall")
	_add_box(body, Rect2(-.85,.45,1.7,.10),0,2.65,"car_wall")
	var doors := StaticBody3D.new()
	doors.name = "Doors"
	doors.collision_layer = 1
	doors.collision_mask = 0
	add_child(doors)
	_lift_bodies.append(_add_box(doors, Rect2(-.47,-1.07,.94,.08),0,2.4,"car_door"))


func _car_leaves(model: Node3D) -> void:
	for side: int in [-1,1]:
		var holder := Node3D.new()
		holder.name = "CarDoorLeft" if side < 0 else "CarDoorRight"
		holder.position = Vector3(side * .235,1.2,-1.03)
		holder.set_meta("extras", {"liftLeaf":true,"ox":side * .65,"oz":0.0})
		var leaf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.47,2.4,.06)
		leaf.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(.22,.25,.27)
		mat.roughness = .85
		RenderMaterials.set_override(leaf,mat)
		holder.add_child(leaf)
		model.add_child(holder)
