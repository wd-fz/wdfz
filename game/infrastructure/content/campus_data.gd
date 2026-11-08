class_name CampusData
extends RefCounted
## Adapter: reads the layout JSON exported from the Web version (tools/export_scenes)
## and hands plain dictionaries to the rules. Cached per process; the data is read-only.

const LAYOUT_DIR := "res://assets/campus/layout/"
const SCENE_DIR := "res://assets/campus/scenes/"
## The model tier the player chose (GameSettings quality 0–4; the default tier is 2, the one in SCENE_DIR). A tier's exports live in
## res://assets/campus_q<N>/scenes/ (tools/export_scenes/export_scenes.py --quality N --out assets/campus_qN); a scene missing there falls
## back to the default tier, so tiers can be added one by one. Only the models change: the layout and the collision are the same.
const DEFAULT_TIER := 2
static var tier := DEFAULT_TIER


static func scene_path(id: String) -> String:
	if tier != DEFAULT_TIER:
		var alt := "res://assets/campus_q%d/scenes/%s.glb" % [tier, id]
		if ResourceLoader.exists(alt):
			return alt
	return SCENE_DIR + id + ".glb"


static func tiers_available() -> Array:
	var out: Array = [DEFAULT_TIER]
	for q in 5:
		if q != DEFAULT_TIER and DirAccess.dir_exists_absolute("res://assets/campus_q%d/scenes" % q):
			out.append(q)
	out.sort()
	return out

static var _cache: Dictionary = {}


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
	var result := PackedStringArray()
	for file: String in DirAccess.get_files_at(LAYOUT_DIR):
		if not file.ends_with(".json"):
			continue
		var id := file.get_basename()
		if id in ["campus", "out"]:
			continue
		if ResourceLoader.exists(SCENE_DIR + id + ".glb"):
			result.append(id)
	result.sort()
	return result


static func rooms() -> Dictionary:
	var result := {}
	for id: String in room_ids():
		result[id] = layout(id)
	return result


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
	_rules = null
	_lift_geometry = null
	_maze_geometry = null
	_patrol_nav = null
	_patrol_data = {}
	_cache.clear()


static func make_module() -> CampusModule:
	return CampusModule.new(rooms(), layout("out"), campus())
