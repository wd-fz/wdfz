class_name CampusData
extends RefCounted
## Adapter: reads the layout JSON exported from the Web version (tools/export_scenes)
## and hands plain dictionaries to the rules. Cached per process; the data is read-only.

const LAYOUT_DIR := "res://assets/campus/layout/"
const SCENE_DIR := "res://assets/campus/scenes/"
## The model tier the player chose (GameSettings model_detail 0–3; the default tier is 2, the one in SCENE_DIR). A tier's exports live in
## res://assets/campus_q<N>/scenes/ (tools/export_scenes/export_scenes.py --quality N --out assets/campus_qN); a scene missing there falls
## back to the default tier, so tiers can be added one by one. Only the models change: the layout and the collision are the same.
const MOBILE_SCENE_DIR := "res://assets/campus_q0/scenes/"
const DEFAULT_TIER := 2
const MODEL_TIERS := [0, 1, 2, 3]
static var tier := DEFAULT_TIER


static func scene_path(id: String) -> String:
	var selected := clampi(tier, 0, 3)
	if selected != DEFAULT_TIER:
		var alt := "res://assets/campus_q%d/scenes/%s.glb" % [selected, id]
		if ResourceLoader.exists(alt):
			return alt
	return SCENE_DIR + id + ".glb"


static func _has_mesh(scene: PackedScene) -> bool:
	if scene == null or not scene.can_instantiate(): return false
	var state := scene.get_state()
	for i in state.get_node_count():
		if state.get_node_type(i) != &"MeshInstance3D": continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"mesh" and state.get_node_property_value(i, j) is Mesh: return true
	return false


static func load_scene(id: String) -> PackedScene:
	var path := scene_path(id)
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if _has_mesh(packed): return packed
	var base := SCENE_DIR + id + ".glb"
	if path == base: return null
	packed = ResourceLoader.load(base, "PackedScene") as PackedScene
	return packed if _has_mesh(packed) else null


static func instantiate_model(id: String) -> Node3D:
	var packed := load_scene(id)
	if packed != null:
		var root := packed.instantiate()
		if root is Node3D:
			return root
		if root != null:
			root.free()
	var source := MOBILE_SCENE_DIR + id + ".glb.source"
	if not FileAccess.file_exists(source):
		CampusEntryLog.resource_issue("模型 %s · 导入模型未能实例化，备用文件不存在 · %s" % [id, scene_path(id)])
		return null
	var bytes := FileAccess.get_file_as_bytes(source)
	var recovered := decode_model(bytes, source)
	var selected := scene_path(id)
	var remap := ConfigFile.new()
	var native := selected if remap.load(selected + ".remap") != OK else String(remap.get_value("remap", "path", selected))
	var file := FileAccess.open(native, FileAccess.READ)
	var evidence := "%s (%s)" % [native, "%d B" % file.get_length() if file != null else error_string(FileAccess.get_open_error())]
	CampusEntryLog.resource_issue("模型 %s · 原生 %s · 备用 glTF %d B · %s" % [id, evidence, bytes.size(), "已恢复" if recovered != null else "读取失败"])
	return recovered


## The opening uses actors immediately after the world is ready. Keep a successfully
## decoded fallback scene so a classroom of pupils does not decode the same rig repeatedly.
static var _recovered_actors: Dictionary = {}


static func actor_scene(path: String) -> PackedScene:
	if _recovered_actors.has(path): return _recovered_actors[path]
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if _has_mesh(scene): return scene
	var source := path + ".source"
	if FileAccess.file_exists(source):
		scene = decode_actor(FileAccess.get_file_as_bytes(source), source)
		if scene != null:
			_recovered_actors[path] = scene
			CampusEntryLog.resource_issue("开场人物已从原始 glTF 恢复 · " + path)
			return scene
	CampusEntryLog.resource_issue("开场人物读取失败 · " + path)
	return null


static func decode_actor(bytes: PackedByteArray, path: String) -> PackedScene:
	var model := decode_model(bytes, path)
	if model == null: return null
	# The editor importer strips the _loop suffix and enables looping. Match it
	# so existing game calls to read, sit and walk work on either loading path.
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		for library_id in player.get_animation_library_list():
			var library := player.get_animation_library(library_id)
			for clip in library.get_animation_list():
				if String(clip).ends_with("_loop"):
					library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					library.rename_animation(clip, String(clip).trim_suffix("_loop"))
	var packed := PackedScene.new()
	var result := packed.pack(model)
	model.free()
	return packed if result == OK else null


## Use the original low-detail geometry, extras and materials through Godot's runtime glTF loader.
static func decode_model(bytes: PackedByteArray, source: String) -> Node3D:
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if bytes.is_empty() or document.append_from_buffer(bytes, source, state) != OK:
		return null
	var root := document.generate_scene(state)
	if root is Node3D:
		return root
	if root != null:
		root.free()
	return null


static func tiers_available() -> Array:
	var out: Array = [DEFAULT_TIER]
	for q in MODEL_TIERS:
		if q != DEFAULT_TIER and DirAccess.dir_exists_absolute("res://assets/campus_q%d/scenes" % q):
			out.append(q)
	out.sort()
	return out

static var _cache: Dictionary = {}
static var _room_ids: PackedStringArray = []
static var _rooms: Dictionary = {}


static func layout(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := LAYOUT_DIR + id + ".json"
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary:
		push_error("校园布局缺失或损坏：%s" % path)
		return {}
	_cache[id] = data
	return data


static func campus() -> Dictionary:
	return layout("campus")


static func campus_map() -> Dictionary:
	if not _cache.has("campus_map"):
		_cache["campus_map"] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/map.json"))
	return _cache["campus_map"]


static func rules_dlc() -> Dictionary:
	if not _cache.has("rules_dlc"):
		_cache["rules_dlc"]=JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/rules_dlc.json"))
	return _cache["rules_dlc"]


static func archive() -> Dictionary:
	if not _cache.has("archive"):
		_cache["archive"] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/archive.json"))
	return _cache["archive"]


## Every room id that has both a layout and an exported model.
static func room_ids() -> PackedStringArray:
	if not _room_ids.is_empty(): return _room_ids
	var result := PackedStringArray()
	for file: String in DirAccess.get_files_at(LAYOUT_DIR):
		if not file.ends_with(".json"):
			continue
		var id := file.get_basename()
		if id in ["campus", "out"]:
			continue
		if ResourceLoader.exists(SCENE_DIR + id + ".glb") or FileAccess.file_exists(MOBILE_SCENE_DIR + id + ".glb.source"):
			result.append(id)
	result.sort()
	_room_ids = result
	return result


static func rooms() -> Dictionary:
	if _rooms.is_empty():
		for id: String in room_ids(): _rooms[id] = layout(id)
	return _rooms


static var _rules: CampusModule


## Shared read-only rules for geometry queries from scene adapters (no per-run state is read).
static func rules() -> CampusModule:
	if _rules == null:
		_rules = make_module()
	return _rules


static var _lift_geometry: ElevatorModule
static var _maze_geometry: MazeGeometry


static func maze_data() -> Dictionary:
	if not _cache.has("maze_data"):
		_cache["maze_data"] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/maze/maze.json"))
	return _cache["maze_data"]


static func maze_geometry() -> MazeGeometry:
	if _maze_geometry == null:
		_maze_geometry = MazeGeometry.new(maze_data())
	return _maze_geometry


## Read-only elevator geometry (frames, door rectangles, cabin gaps) for scene adapters.
static func lift_geometry() -> ElevatorModule:
	if _lift_geometry == null:
		_lift_geometry = ElevatorModule.new(rooms())
		_lift_geometry.reset()
	return _lift_geometry


static var _patrol_data: Dictionary = {}
static var _patrol_nav: PatrolNav


## Exported patrol data (grids, connection graph, route, zones) and the shared navigation caches.
static func patrol_data() -> Dictionary:
	if _patrol_data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/patrol/patrol_data.json"))
		_patrol_data = parsed if parsed is Dictionary else {}
	return _patrol_data


static func patrol_nav() -> PatrolNav:
	if _patrol_nav == null:
		_patrol_nav = PatrolNav.new(patrol_data(), rooms(), campus(), maze_geometry())
	return _patrol_nav


static func make_anomaly() -> AnomalyModule:
	return AnomalyModule.new(rooms(), layout("out"), campus())


static func make_patrol() -> PatrolModule:
	return PatrolModule.new(patrol_nav(), rooms(), patrol_data())


## Drop the shared module/navigation instances (called when the app or a test run ends).
static func clear_caches() -> void:
	_room_ids = []
	_rooms = {}
	_rules = null
	_lift_geometry = null
	_maze_geometry = null
	_patrol_nav = null
	_patrol_data = {}
	_cache.clear()


static func make_module() -> CampusModule:
	return CampusModule.new(rooms(), layout("out"), campus())
