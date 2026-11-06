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


static func make_module() -> CampusModule:
	return CampusModule.new(rooms(), layout("out"), campus())
