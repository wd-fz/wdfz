class_name InventoryModule
extends FeatureModule
## Eight unique items, two quick slots, and persistent dropped items.
## Item/world definitions are injected plain data, never loaded from a save.

signal changed

const ID := &"player.inventory"
const CAPACITY := 8
enum AddResult { ADDED, INVALID, DUPLICATE, FULL }

var _definitions: Dictionary
var _worlds: PackedStringArray
var _initial: PackedStringArray
var _items: Array[String] = []
var _quick: Array = ["", ""]
var _selected := 0
var _ground: Dictionary = {}


func _init(definitions: Dictionary, worlds: PackedStringArray, initial: PackedStringArray = PackedStringArray(["card"])) -> void:
	_definitions = definitions.duplicate(true)
	_worlds = worlds.duplicate()
	_initial = initial.duplicate()
	reset()


func module_id() -> StringName:
	return ID


func interaction_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id: String in _definitions:
		result.append("inventory.pickup." + id)
	return result


func interact(id: StringName) -> String:
	return pickup(String(id).trim_prefix("inventory.pickup."))


func details(id: String) -> Dictionary:
	return _definitions.get(id, {}).duplicate(true)


func has(id: String) -> bool:
	return _items.has(id)


func owns(id: String) -> bool:
	return has(id) or _ground.has(id)


func items() -> Array[String]:
	return _items.duplicate()


func quick_slots() -> Array:
	return _quick.duplicate()


func selected_id() -> String:
	return _items[_selected] if _selected < _items.size() else ""


func selected_index() -> int:
	return _selected


func try_add(id: String) -> AddResult:
	if not _definitions.has(id):
		return AddResult.INVALID
	if owns(id):
		return AddResult.DUPLICATE
	if _items.size() >= CAPACITY:
		return AddResult.FULL
	_items.append(id)
	changed.emit()
	return AddResult.ADDED


func select(index: int) -> bool:
	if index < 0 or index >= CAPACITY:
		return false
	_selected = index
	changed.emit()
	return true


func set_quick(index: int, id: String) -> bool:
	if index not in [0, 1] or (not id.is_empty() and not has(id)):
		return false
	_quick[index] = id
	changed.emit()
	return true


func _remove(id: String) -> void:
	_items.erase(id)
	for index in 2:
		if _quick[index] == id:
			_quick[index] = ""
	_selected = mini(_selected, maxi(0, _items.size() - 1))


func drop(id: String, world_id: String, position: Array) -> String:
	if not has(id):
		return "背包里没有这件物品。"
	var record := {"world_id": world_id, "position": position.duplicate()}
	if not _valid_ground_record(record):
		return "这里无法放下物品。"
	_remove(id)
	_ground[id] = record
	changed.emit()
	return "已放下「%s」，可以在脚边重新拾取。" % _definitions[id]["name"]


func pickup(id: String) -> String:
	if not _ground.has(id):
		return "物品已经不在这里了。"
	if _items.size() >= CAPACITY:
		return "背包装不下了，物品会留在地上。"
	_ground.erase(id)
	_items.append(id)
	changed.emit()
	return "拿回了「%s」。" % _definitions[id]["name"]


func dropped_in(world_id: String) -> Dictionary:
	var result: Dictionary = {}
	for id: String in _ground:
		if _ground[id]["world_id"] == world_id:
			result[id] = _ground[id].duplicate(true)
	return result


func capture() -> Dictionary:
	return {"items": _items.duplicate(), "quick": _quick.duplicate(), "selected": _selected, "ground": _ground.duplicate(true)}


func initial_data() -> Dictionary:
	return {"items": Array(_initial), "quick": ["", ""], "selected": 0, "ground": {}}


func _valid_ground_record(record: Dictionary) -> bool:
	if not record.get("world_id") is String or not _worlds.has(record["world_id"]):
		return false
	var position: Variant = record.get("position")
	if not position is Array or position.size() != 3:
		return false
	for value: Variant in position:
		if not SaveSchema.number_in(value, -10000, 10000):
			return false
	return true


func validate(data: Dictionary) -> String:
	if not data.get("items") is Array or data["items"].size() > CAPACITY:
		return "背包物品数量无效"
	var seen: Dictionary = {}
	for id: Variant in data["items"]:
		if not id is String or not _definitions.has(id) or seen.has(id):
			return "背包含未知或重复物品"
		seen[id] = true
	if not data.get("quick") is Array or data["quick"].size() != 2:
		return "快捷栏格式无效"
	for id: Variant in data["quick"]:
		if not id is String or (not id.is_empty() and not seen.has(id)):
			return "快捷栏引用了未持有的物品"
	if not SaveSchema.is_integer(data.get("selected"), 0, CAPACITY - 1):
		return "背包选中位置无效"
	if not data.get("ground") is Dictionary:
		return "地面物品格式无效"
	for id: Variant in data["ground"]:
		if not id is String or not _definitions.has(id) or seen.has(id):
			return "地面物品与背包重复或未定义"
		if not data["ground"][id] is Dictionary or not _valid_ground_record(data["ground"][id]):
			return "地面物品的位置无效"
	return ""


func restore(data: Dictionary) -> void:
	_items.assign(data["items"])
	_quick = data["quick"].duplicate()
	_selected = int(data["selected"])
	_ground = data["ground"].duplicate(true)
	changed.emit()


func reset() -> void:
	_items.assign(_initial)
	_quick = ["", ""]
	_selected = 0
	_ground.clear()
	changed.emit()
