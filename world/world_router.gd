class_name WorldRouter
extends Node3D

@export var worlds: Array[WorldDefinition] = []
var current: WorldDefinition
var _instance: Node3D


func world_instance() -> Node3D:
	return _instance


func known_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for definition: WorldDefinition in worlds:
		if definition != null and not definition.world_id.is_empty() and definition.scene != null:
			result.append(String(definition.world_id))
	return result


func switch_to(id: String) -> String:
	var matches: Array[WorldDefinition] = []
	for definition: WorldDefinition in worlds:
		if definition != null and String(definition.world_id) == id:
			matches.append(definition)
	if matches.size() != 1 or matches[0].scene == null:
		return "场景未登记、重复登记或未指定 PackedScene：%s" % id
	var candidate: Node = matches[0].scene.instantiate()
	if not candidate is Node3D:
		if candidate != null:
			candidate.free()
		return "世界场景根节点必须是 Node3D"
	for key: Variant in matches[0].properties:
		candidate.set(String(key), matches[0].properties[key])
	clear()
	current = matches[0]
	_instance = candidate
	add_child(_instance)
	return ""


func clear() -> void:
	if is_instance_valid(_instance):
		remove_child(_instance)
		_instance.queue_free()
	_instance = null
	current = null
