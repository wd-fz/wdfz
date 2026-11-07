class_name CampusData
extends RefCounted
## Adapter: reads the layout JSON exported from the Web version (tools/export_scenes)
## and hands plain dictionaries to the rules. Cached per process; the data is read-only.

const LAYOUT_DIR := "res://assets/campus/layout/"
const SCENE_DIR := "res://assets/campus/scenes/"

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
		_patrol_nav = PatrolNav.new(patrol_data(), rooms(), campus())
	return _patrol_nav


static func make_patrol() -> PatrolModule:
	return PatrolModule.new(patrol_nav(), rooms(), patrol_data())


## Drop the shared module/navigation instances (called when the app or a test run ends).
static func clear_caches() -> void:
	_rules = null
	_lift_geometry = null
	_patrol_nav = null
	_patrol_data = {}
	_cache.clear()


static func make_module() -> CampusModule:
	return CampusModule.new(rooms(), layout("out"), campus())
