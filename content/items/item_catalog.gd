class_name ItemCatalog
extends Resource
## Authoring resources are converted to plain data at the composition boundary.

@export var items: Array[ItemDefinition] = []


func validate() -> String:
	var ids: Dictionary = {}
	for item: ItemDefinition in items:
		if item == null or item.item_id.is_empty() or item.display_name.is_empty():
			return "物品缺少 ID 或名称"
		if ids.has(item.item_id):
			return "物品 ID 重复：%s" % item.item_id
		ids[item.item_id] = true
	return ""


func to_data() -> Dictionary:
	var result: Dictionary = {}
	for item: ItemDefinition in items:
		result[String(item.item_id)] = {"name": item.display_name, "description": item.description}
	return result
