class_name CampusWorld
extends Node3D
## Presentation + physics adapter for one Web-version scene (a room or the campus outside).
## Geometry is the glb exported from the old game's own builders; collision boxes are the old
## game's own static collision rectangles (tools/export_scenes). No geometry is redrawn here.

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
var _traces_seen := -1
var broadcast_props: BroadcastProps
var mirror_view: MirrorView
var canteen_view: CanteenView
var lighting: CampusLighting
var _door_bodies: Dictionary = {}   # key -> CollisionShape3D
var _door_leaves: Dictionary = {}   # key -> {"closed": Node3D, "open": Node3D}
var _lift_leaves: Array[Node3D] = []
var _lift_bodies: Array[CollisionShape3D] = []
var _lift_amount := -1.0
var anomaly_fx: AnomalyFx
var atmos_fx: AtmosFx
var duty: DutyRoster


func _ready() -> void:
	layout = CampusData.layout(scene_id)
	_build_model()
	_build_collision()
	_build_lighting()
	anomaly_fx = AnomalyFx.new()
	anomaly_fx.name = "AnomalyFx"
	add_child(anomaly_fx)
	chalk = ChalkNotes.new()
	add_child(chalk)
	phantoms = Phantoms.new()
	add_child(phantoms)
	traces = Traces.new()
	traces.name = "Traces"
	add_child(traces)
	traces.build(scene_id, layout if is_room() else null, CampusWorld.pending_traces)
	_traces_seen = CampusWorld.pending_traces.size()
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
	else:
		_build_link_preview()
	_build_stair_preview()
	_build_door_preview()
	_build_gallery_view()
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


func _ready_banner() -> void:
	banner = DayBanner.new()
	banner.name = "DayBanner"
	add_child(banner)
	banner.setup(layout)


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
	cab.material_override = white
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
		bar.material_override = red
		bar.position = Vector3(p.x, 1.6, p.y - 0.235)
		add_child(bar)


## The corridor bridges seen from both ends (modules/campus-link/link-view.js): the neighbouring room's model placed by the rigid
## transform of the port pair (CampusPortals.link_between), plus a lamp 3 m inside its doorway so the far end is not black.
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
	gallery_campus = model
var _shaft_levels: Dictionary = {}      # level → the preview of the floor beyond that level's door


## In a stairwell: the floors beyond the doors of the level you are on and the next one (StairView.refresh). level from the height.
func update_shaft_previews(height: float) -> void:
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
			continue
		var id := String(rooms_list[f])
		var model := _load_visual(id)
		var port := CampusPortals.stair_port(st, f, rooms, outside)
		if model == null or port.is_empty():
			continue
		var pp := CampusGeometry.to_scene(rooms[id] if id != "out" else null, port["p"])
		var theta := CampusPortals.stair_turn(port["n"])
		model.name = "ShaftPreview_%d" % f
		model.rotation.y = theta
		model.position = Vector3(-(cos(theta) * pp.x + sin(theta) * pp.y), float(f) * rise, -2.8 - (-sin(theta) * pp.x + cos(theta) * pp.y))
		add_child(model)
		_shaft_levels[f] = model


func _load_visual(id: String) -> Node3D:
	var path := CampusData.scene_path(id)
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			_to_multimesh(mesh)
	return model


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
			var model := _load_visual(rid)
			if model == null:
				continue
			var c := Vector2(float(r["cx"]), float(r["cy"])) + CampusGeometry.shift_of(r)
			model.name = "DoorPreview_" + rid
			model.position = Vector3(c.x * CampusGeometry.U2M, 0.0, c.y * CampusGeometry.U2M)
			add_child(model)
			door_previews.append(model)
		return
	for d: Dictionary in doors:
		if String(d["room"]) != scene_id:
			continue
		var model := _load_visual("out")
		if model == null:
			return
		var c := Vector2(float(layout["cx"]), float(layout["cy"])) + CampusGeometry.shift_of(layout)
		model.name = "DoorPreview_out"
		model.position = Vector3(-c.x * CampusGeometry.U2M, 0.0, -c.y * CampusGeometry.U2M)
		add_child(model)
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
		var shaft := (load(path) as PackedScene).instantiate() as Node3D
		shaft.name = "StairPreview_" + String(st["id"])
		for mesh: MeshInstance3D in shaft.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
				_to_multimesh(mesh)
		var pos := CampusGeometry.to_scene(layout if is_room() else null, port["p"])
		var n: Vector2 = port["n"]
		shaft.position = Vector3(pos.x + 2.8 * n.x, -float(level) * float(st["rise"]), pos.y + 2.8 * n.y)
		shaft.rotation.y = -CampusPortals.stair_turn(n)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#f2dcc0")
		lamp.omni_range = 9.0
		lamp.light_energy = 0.8
		lamp.position = Vector3(0, 2.4 + float(level) * float(st["rise"]), 0)
		shaft.add_child(lamp)
		add_child(shaft)
		stair_previews.append(shaft)


func _build_link_preview() -> void:
	var rooms := CampusData.rooms()
	var cfg: Dictionary = CampusData.campus().get("campus_link", {})
	for v: Dictionary in CampusPortals.link_ports(cfg, rooms, scene_id):
		var peer_id := String(v["peer"]["room"])
		if not rooms.has(peer_id) or not ResourceLoader.exists(CampusData.scene_path(peer_id)):
			continue
		var model := (load(CampusData.scene_path(peer_id)) as PackedScene).instantiate() as Node3D
		model.name = "LinkPreview_" + peer_id
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
				_to_multimesh(mesh)
		var t := CampusPortals.link_between(v["peer"], v["self"])
		var peer_room: Dictionary = rooms[peer_id]
		var phi := float(t["phi"])
		var c_there := Vector2(float(peer_room["cx"]), float(peer_room["cy"]))
		var c_here := Vector2(float(layout["cx"]), float(layout["cy"]))
		var p := (c_there.rotated(phi) + (t["t"] as Vector2) - c_here) * CampusGeometry.U2M
		model.rotation.y = -phi
		model.position = Vector3(p.x, 0.0, p.y)
		var pp: Dictionary = v["peer"]
		var inner: Vector2 = (pp["p"] as Vector2) - (pp["n"] as Vector2) * 3.0 / CampusGeometry.U2M
		var lamp := OmniLight3D.new()
		lamp.name = "LinkLamp"
		lamp.light_color = Color("#f2dcc0")
		lamp.omni_range = 14.0
		lamp.light_energy = 0.9
		lamp.shadow_enabled = false
		lamp.position = Vector3((inner.x - c_there.x) * CampusGeometry.U2M, 2.7, (inner.y - c_there.y) * CampusGeometry.U2M)
		model.add_child(lamp)
		add_child(model)
		link_previews.append(model)


# ---- model ----

func _build_model() -> void:
	var packed := load(CampusData.scene_path(scene_id)) as PackedScene
	if packed == null:
		push_error("校园模型缺失：%s" % scene_id)
		return
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			_to_multimesh(mesh)
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
			if mat != null:
				mat.vertex_color_use_as_albedo = true
	var node := MultiMeshInstance3D.new()
	node.name = source.name
	node.multimesh = mm
	node.transform = source.transform
	source.get_parent().add_child(node)
	source.get_parent().remove_child(source)
	source.free()


func set_door_open(key: String, open: bool) -> void:
	if _door_leaves.has(key):
		var leaves: Dictionary = _door_leaves[key]
		if leaves.has("closed"):
			(leaves["closed"] as Node3D).visible = not open
		if leaves.has("open"):
			(leaves["open"] as Node3D).visible = open
	if _door_bodies.has(key):
		(_door_bodies[key] as CollisionShape3D).set_deferred("disabled", open)


func apply_doors(open_doors: Dictionary) -> void:
	for key: String in _door_bodies:
		set_door_open(key, open_doors.has(key))
	for key: String in _door_leaves:
		if not _door_bodies.has(key):
			set_door_open(key, open_doors.has(key))


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
		for mi: Node in f.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m != null:
				m.albedo_color.a = alpha
		i += 1
	if _scatter_t >= SCATTER_SECONDS:
		_scatter.queue_free()
		_scatter = null


## Rebuild the leftovers when an anomaly has just left one (the list of AnomalyModule.traces).
func sync_traces(list: Array) -> void:
	if traces == null or list.size() == _traces_seen:
		return
	_traces_seen = list.size()
	traces.build(scene_id, layout if is_room() else null, list)


func scattering() -> bool:
	return _scatter != null and is_instance_valid(_scatter)


func show_silhouettes(points: Array, room: Variant, height: float) -> void:
	var key := str(points)
	if key == _silhouette_key:
		return
	_silhouette_key = key
	if is_instance_valid(_silhouettes):
		if points.is_empty() and not _scatter_dirs_of(_silhouettes, room).is_empty():
			# The check is over: they scatter instead of vanishing.
			if is_instance_valid(_scatter):
				_scatter.queue_free()
			_scatter = _silhouettes
			_scatter_t = 0.0
			_scatter_dirs = _scatter_dirs_of(_silhouettes, room)
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
		var fig := FigureModel.make("person", Color(0.02, 0.02, 0.025), false, 0.95)
		fig.position = Vector3(s.x, height, s.y)
		_silhouettes.add_child(fig)


## Directions (x, z) from the player to each figure; the player is where the camera looks from (the first person).
var _player_scene := Vector3.ZERO


func set_player_scene(p: Vector3) -> void:
	_player_scene = p


func _scatter_dirs_of(group: Node3D, _room: Variant) -> Array:
	var out: Array = []
	for f: Node3D in group.get_children():
		var dx := f.position.x - _player_scene.x
		var dz := f.position.z - _player_scene.z
		var len := maxf(0.001, sqrt(dx * dx + dz * dz))
		out.append(Vector2(dx / len, dz / len))
	return out


## The patroller's figure (patEnsureFig / patRender): the exported teacher figure scaled 1.12,
## black and unlit, turned to face the player. Position in scene metres, height in metres.
var _patrol_figure: Node3D


func show_patrol(visible_now: bool, scene_pos: Vector2, height: float, toward: Vector3) -> void:
	if not visible_now:
		if is_instance_valid(_patrol_figure):
			_patrol_figure.visible = false
		return
	if not is_instance_valid(_patrol_figure):
		var packed := load("res://assets/campus/patrol/patrol_figure.glb") as PackedScene
		if packed == null:
			return
		_patrol_figure = packed.instantiate() as Node3D
		_patrol_figure.name = "Patroller"
		add_child(_patrol_figure)
		for mi: MeshInstance3D in _patrol_figure.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if mat != null:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patrol_figure.visible = true
	_patrol_figure.position = Vector3(scene_pos.x, height, scene_pos.y)
	_patrol_figure.rotation.y = atan2(toward.x - scene_pos.x, toward.z - scene_pos.y)


## The thing in the garage driveway (systems.js ROAM): a tall dark figure, placeholder.
var _garage_shadow: Node3D


func show_garage_shadow(visible_now: bool, scene_pos: Vector2, height: float) -> void:
	if not visible_now:
		if is_instance_valid(_garage_shadow):
			_garage_shadow.visible = false
		return
	if not is_instance_valid(_garage_shadow):
		_garage_shadow = FigureModel.make("roam", Color(0.01, 0.01, 0.012), true)
		_garage_shadow.name = "GarageShadow"
		add_child(_garage_shadow)
	_garage_shadow.visible = true
	_garage_shadow.position = Vector3(scene_pos.x, height, scene_pos.y)


## The opened door of the portal route (portal.js): a ring of coloured light in front of the physics bench.
var _portal_ring: Node3D


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
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.91, 0.91, 0.89)
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.55, 0.58, 0.59)
		var box := func(size: Vector3, pos: Vector3, mat: Material) -> void:
			var m := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = size
			m.mesh = b
			m.material_override = mat
			m.position = pos
			_checkup.add_child(m)
		var rp: Vector3 = at.call(1.16, 15.45)
		box.call(Vector3(0.05, 2.0, 0.16), rp + Vector3(0, 1.0, 0), white)
		box.call(Vector3(0.26, 0.025, 0.12), rp + Vector3(0.14, 1.92, 0), metal)
		box.call(Vector3(0.34, 0.04, 0.36), rp + Vector3(0.17, 0.02, 0), metal)
		box.call(Vector3(0.34, 0.06, 0.4), at.call(2.7, 15.45) + Vector3(0, 0.03, 0), white)
		var chart := Label3D.new()
		chart.text = "E\nE  E\nE  E  E\nE  E  E  E\n\n" + line
		chart.font_size = 28
		chart.pixel_size = 0.0015
		chart.modulate = Color(0.08, 0.08, 0.08)
		chart.outline_size = 0
		var back := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.88)
		back.mesh = quad
		back.material_override = white
		var cp: Vector3 = at.call(8.84, 15.45)
		back.position = cp + Vector3(0, 1.45, 0)
		back.rotation.y = -PI * 0.5
		chart.position = cp + Vector3(-0.01, 1.45, 0)
		chart.rotation.y = -PI * 0.5
		_checkup.add_child(back)
		_checkup.add_child(chart)
		var sign := Label3D.new()
		sign.text = "医 务 室\n（体检）"
		sign.font_size = 40
		sign.pixel_size = 0.0012
		sign.position = at.call(7.0, 17.14) + Vector3(0, 1.55, 0)
		_checkup.add_child(sign)
		_checkup_queue = StaticBody3D.new()
		_checkup_queue.name = "Queue"
		_checkup_queue.collision_layer = 1
		_checkup_queue.collision_mask = 0
		_checkup.add_child(_checkup_queue)
		var k := 0
		for q: Vector2 in [Vector2(1.45, 17.32), Vector2(2.22, 17.32), Vector2(3.0, 17.32), Vector2(3.78, 17.32), Vector2(4.55, 17.32)]:
			var p: Vector3 = at.call(q.x, q.y)
			var fig := FigureModel.make("person", Color(0.29, 0.34, 0.41), false, (1.6 + 0.05 * float((k * 37) % 3)) / 1.85)
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
	paper.material_override = mat
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


func dread_note_text() -> String:
	if not is_instance_valid(_dread_note):
		return ""
	return (_dread_note.get_child(1) as Label3D).text


func show_portal(visible_now: bool) -> void:
	if not visible_now or scene_id != "lab1":
		if is_instance_valid(_portal_ring):
			_portal_ring.visible = false
		return
	if not is_instance_valid(_portal_ring):
		var room := CampusData.layout("lab1")
		var bench := Vector2.ZERO
		var n := 0
		var grid: Array = room["grid"]
		for r in grid.size():
			for c in String(grid[r]).length():
				if String(grid[r]).substr(c, 1) == "K":
					bench += CampusGeometry.tile_center(room, c, r)
					n += 1
		bench /= maxf(1.0, float(n))
		var mid := Vector2(float(room["cx"]), float(room["cy"]))
		var at := bench + (mid - bench).normalized() * 14.0
		var s := CampusGeometry.to_scene(room, at)
		_portal_ring = Node3D.new()
		_portal_ring.name = "PortalRing"
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 1.0
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.9, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.85, 1.0)
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
		ring.rotation.x = PI * 0.5
		_portal_ring.add_child(ring)
		var inside := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.86
		disc.bottom_radius = 0.86
		disc.height = 0.01
		inside.mesh = disc
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.95, 0.8, 0.5, 0.55)
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		inside.material_override = glow
		inside.rotation.x = PI * 0.5
		_portal_ring.add_child(inside)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.7, 0.9, 1.0)
		lamp.light_energy = 1.2
		lamp.omni_range = 5.0
		_portal_ring.add_child(lamp)
		_portal_ring.position = Vector3(s.x, 1.15, s.y)
		var face := (mid - bench)
		_portal_ring.rotation.y = atan2(face.x, face.y)
		add_child(_portal_ring)
	_portal_ring.visible = true


func portal_shown() -> bool:
	return is_instance_valid(_portal_ring) and _portal_ring.visible


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
	if rules.is_stairwell(scene_id):
		_build_stairwell(body, rules.stair_surfaces(scene_id))
		return
	_add_box(body, Rect2(extent.position - Vector2.ONE * 2, extent.size + Vector2.ONE * 4), -1.0, 0.0, "floor")
	if is_room():
		for b: Dictionary in layout["walls"] + layout["boxes"]:
			_add_rect(body, b)
		if layout["flags"].get("spiral", false):
			_build_spiral(body, CampusData.campus()["spiral"])
		var doorways := rules.stair_doorways(scene_id)
		for b: Dictionary in layout["stairs"]:
			for part: Rect2 in _cut_doorways(_rect_of(b), doorways):
				_add_box(body, part, WALL_BOTTOM, WALL_TOP, "stair")
		_room_boundary(body, extent)
		var doors := StaticBody3D.new()
		doors.name = "Doors"
		doors.collision_layer = 1
		doors.collision_mask = 0
		add_child(doors)
		for d: Dictionary in layout["doors"]:
			_door_bodies[String(d["key"])] = _add_rect(doors, d)
		for r: Rect2 in CampusData.lift_geometry().door_rects(scene_id):
			_lift_bodies.append(_add_box(doors, r, WALL_BOTTOM, WALL_TOP, "lift_door"))
	else:
		for b: Dictionary in layout["boxes"]:
			_add_rect(body, b)
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
	return _add_box(parent, _rect_of(b), WALL_BOTTOM, WALL_TOP, String(b["k"]))


## Old rule (collision.js + StairWorld.doorwayFree): a stair cell is solid except the 1.7 m doorway
## the body fits through; the shaft threshold is crossed in the middle of that cell.
func _cut_doorways(r: Rect2, doorways: Array[Dictionary]) -> Array[Rect2]:
	var parts: Array[Rect2] = [r]
	for d: Dictionary in doorways:
		var c: Vector2 = d["center"]
		var half := float(d["half"])
		if r.get_center().distance_to(c) > 2.0:
			continue
		var lateral_x := absf((d["lateral"] as Vector2).x) > 0.5
		var next: Array[Rect2] = []
		for q: Rect2 in parts:
			var lo := (c.x if lateral_x else c.y) - half
			var hi := (c.x if lateral_x else c.y) + half
			var a0 := q.position.x if lateral_x else q.position.y
			var a1 := q.end.x if lateral_x else q.end.y
			if hi <= a0 or lo >= a1:
				next.append(q)
				continue
			if lo > a0:
				next.append(Rect2(q.position, Vector2(lo - a0, q.size.y)) if lateral_x else Rect2(q.position, Vector2(q.size.x, lo - a0)))
			if hi < a1:
				next.append(Rect2(Vector2(hi, q.position.y), Vector2(a1 - hi, q.size.y)) if lateral_x else Rect2(Vector2(q.position.x, hi), Vector2(q.size.x, a1 - hi)))
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
	for r: Rect2 in [
		Rect2(-3.2, -1.2, 1.0, 8.4), Rect2(2.2, -1.2, 1.0, 8.4),          # outer side walls
		Rect2(-3.2, 7.2, 6.4, 1.0),                                        # back wall
		Rect2(-3.2, -2.2, 2.35, 1.0), Rect2(0.85, -2.2, 2.35, 1.0),       # front wall beside the corridor
		Rect2(-1.85, -4.5, 1.0, 3.3), Rect2(0.85, -4.5, 1.0, 3.3),        # corridor walls
		Rect2(-1.85, -4.5, 3.7, 1.0),                                      # corridor end
		Rect2(-0.3, 0.8, 0.6, 4.8),                                        # slot between the two flights
	]:
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
		_annex(body, p, n, half, depth)
	# The cabin behind a floor's elevator doors lies outside the grid (Elevator.annexAt); its walls are
	# exported props, so only the boundary opens there.
	var cabin := CampusData.lift_geometry().cabin_gap(scene_id)
	if not cabin.is_empty():
		gaps.append(cabin)
	# Corridor bridges (campus-link/link.js) open the same kind of gap.
	for g: Dictionary in CampusData.rules().link_doorways(scene_id):
		gaps.append(g)
		_annex(body, g["center"], g["normal"], float(g["half"]), float(g["depth"]) + CampusGeometry.PRAD * CampusGeometry.U2M)
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
	var t := BOUNDARY
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
		_add_box(body, rect, WALL_BOTTOM, WALL_TOP, "boundary")


# ---- lighting (lighting.js port in CampusLighting) ----

func _build_lighting() -> void:
	lighting = CampusLighting.new()
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
