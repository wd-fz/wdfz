class_name InvestigationModule
extends FeatureModule
## First migration slice: canonical clue text, office key and a reusable room lock.
## The compact scene is an acceptance fixture, not the finished campus layout.

signal changed

const ID := &"story.first_investigation"
const NOTES := {
	"desk": {"title": "课桌里的停车单", "text": "停车单背面写着：「钥匙又被收走了。讲台上的移交单还没撕。」"},
	"notice": {"title": "讲台移交单", "text": "钥匙移交：行政楼五楼校长办公室。保安岗留有停车记录和备用手电；车库位于校园西侧。"},
	"room_lock": {"title": "网络中心的门锁", "text": "机房门锁着，需要机房钥匙。校长办公室可能有。"},
	"key": {"title": "机房钥匙", "text": "在校长室抽屉取得一把铜钥匙。塑料标签上写着「机房」。钥匙可以重复使用。"},
	"door": {"title": "开门验证", "text": "机房钥匙与门锁相配。开门没有消耗钥匙，门后的空间已经可以进入。"},
}

var _inventory: InventoryModule
var _entries: Array[String] = []
var _key_taken := false
var _door_open := false


func _init(inventory: InventoryModule) -> void:
	_inventory = inventory


func module_id() -> StringName:
	return ID


func interaction_ids() -> PackedStringArray:
	return PackedStringArray(["investigation.desk", "investigation.notice", "investigation.cabinet", "investigation.door"])


func _record(id: String) -> bool:
	if _entries.has(id):
		return false
	_entries.append(id)
	return true


func interact(id: StringName) -> String:
	match id:
		&"investigation.desk":
			if _record("desk"):
				changed.emit()
			return NOTES["desk"]["text"] + " 可以在背包的「调查记录」中重读。"
		&"investigation.notice":
			if _record("notice"):
				changed.emit()
			return NOTES["notice"]["text"]
		&"investigation.cabinet":
			return _take_key()
		&"investigation.door":
			if not _inventory.has("roomkey"):
				if _record("room_lock"):
					changed.emit()
				return "门锁着。需要「机房钥匙」；如果已经拿过，请查看背包或地上的物品。"
			_door_open = not _door_open
			_record("door")
			changed.emit()
			return "门开了。机房钥匙仍在背包里。" if _door_open else "门关上了。"
	return ""


func _take_key() -> String:
	if _key_taken or _inventory.owns("roomkey"):
		return "抽屉里的机房钥匙已经拿走了。丢在地上的物品可以重新拾取。"
	var result := _inventory.try_add("roomkey")
	if result == InventoryModule.AddResult.FULL:
		return "背包装不下了。钥匙会留在抽屉里，先放下一件物品再来。"
	if result != InventoryModule.AddResult.ADDED:
		return "暂时无法拿起钥匙。"
	_key_taken = true
	_record("key")
	changed.emit()
	return "拿到了「机房钥匙」。铜钥匙上挂着写有「机房」的标签。"


func key_available() -> bool:
	return not _key_taken and not _inventory.owns("roomkey")


func door_open() -> bool:
	return _door_open


func notes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _entries:
		result.append(NOTES[id].duplicate(true))
	return result


func objective() -> String:
	if _door_open:
		return "机房门已打开，可以走进去查看。"
	if _inventory.has("roomkey"):
		return "找到标有「机房」的门，用铜钥匙开门。"
	if _inventory.owns("roomkey"):
		return "机房钥匙已放在地上；拾回后再开门。"
	if _entries.has("notice") or _entries.has("room_lock"):
		return "核对校长室抽屉里的钥匙。"
	if _entries.has("desk"):
		return "去讲台查看尚未撕掉的移交单。"
	return "查看自己课桌里的停车单。"


func capture() -> Dictionary:
	return {"entries": _entries.duplicate(), "key_taken": _key_taken, "door_open": _door_open}


func validate(data: Dictionary) -> String:
	if not data.get("entries") is Array or data["entries"].size() > NOTES.size():
		return "调查记录无效"
	var seen: Dictionary = {}
	for id: Variant in data["entries"]:
		if not id is String or not NOTES.has(id) or seen.has(id):
			return "调查记录包含未知或重复条目"
		seen[id] = true
	if not data.get("key_taken") is bool or not data.get("door_open") is bool:
		return "调查进度格式错误"
	if data["key_taken"] and not seen.has("key"):
		return "取得钥匙的记录缺失"
	if data["door_open"] and not seen.has("door"):
		return "开门记录缺失"
	return ""


func validate_snapshot(module_snapshots: Dictionary) -> String:
	var state: Dictionary = module_snapshots.get(String(ID), {}).get("data", {})
	if state.is_empty() or not state.get("key_taken", false):
		return ""
	var inventory_data: Dictionary = module_snapshots.get(String(InventoryModule.ID), {}).get("data", _inventory.initial_data())
	if not inventory_data["items"].has("roomkey") and not inventory_data["ground"].has("roomkey"):
		return "钥匙已被取走，但背包和地面都没有钥匙；当前会话未改变"
	return ""


func restore(data: Dictionary) -> void:
	_entries.assign(data["entries"])
	_key_taken = data["key_taken"]
	_door_open = data["door_open"]
	changed.emit()


func reset() -> void:
	_entries.clear()
	_key_taken = false
	_door_open = false
	changed.emit()
