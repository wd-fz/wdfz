class_name WorldRouter
extends Node3D

## Composition roots can configure presentation adapters before their _ready builds them.
signal world_preparing(world: Node3D)

@export var worlds: Array[WorldDefinition] = []
var current: WorldDefinition
var _instance: Node3D
var stream := CampusStream.new()


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
	# The cold path is only for initial loads, teleports or a request that outran prefetch.
	# Collect outstanding work before any synchronous mesh processing touches shared resources.
	if not stream.has(id):
		stream.finish()
	var candidate: Node = stream.take(id)
	if candidate == null:
		candidate = matches[0].scene.instantiate()
	if not candidate is Node3D:
		if candidate != null:
			candidate.free()
		return "世界场景根节点必须是 Node3D"
	for key: Variant in matches[0].properties:
		candidate.set(String(key), matches[0].properties[key])
	world_preparing.emit(candidate)
	if is_instance_valid(_instance):
		if _instance is CampusWorld and not _instance.collision_only:
			stream.keep(_instance.release_geometry())
		remove_child(_instance)
		_instance.queue_free()
	current = matches[0]
	_instance = candidate
	if _instance is CampusWorld and stream.automatic():
		_instance.preview_request = stream.request_preview
	add_child(_instance)
	return ""


func prepare(id: String) -> void:
	if (current != null and String(current.world_id) == id) or stream.has(id) or stream.pending(id):
		return
	for definition: WorldDefinition in worlds:
		if definition == null or String(definition.world_id) != id or definition.scene == null:
			continue
		var candidate := definition.scene.instantiate()
		if not candidate is CampusWorld:
			candidate.free()
			return
		for key: Variant in definition.properties:
			candidate.set(String(key), definition.properties[key])
		world_preparing.emit(candidate)
		# Warm data adapters on the main thread before detached workers read their caches.
		CampusData.rooms()
		CampusData.layout("out")
		CampusData.campus()
		CampusData.rules()
		CampusData.lift_geometry()
		var visuals := CampusWorld.visual_ids(id)
		if id != "out":
			candidate.entry_views.append("out")
		if _instance is CampusWorld:
			var here := _instance as CampusWorld
			if id == "out":
				candidate.entry_views.append(here.scene_id)
				visuals.append(here.scene_id)
			for stair: Dictionary in CampusData.campus().get("stair_layout", []):
				if id == String(stair["id"]) and (stair["rooms"] as Array).has(here.scene_id):
					candidate.entry_height = (stair["rooms"] as Array).find(here.scene_id) * float(stair["rise"])
					visuals.append(here.scene_id)
			if visuals.has(here.scene_id) and here.get_node_or_null("Model") != null:
				candidate.seed_visual(here.scene_id, here.get_node("Model"))
		for source_id: String in stream.cached:
			if visuals.has(source_id):
				candidate.seed_visual(source_id, (stream.cached[source_id] as CampusWorld).get_node("Model"))
		stream.prepare(candidate)
		return


func warm(id: String) -> bool:
	return stream.has(id) or (current != null and String(current.world_id) == id)


func prefetch(position: Vector3) -> void:
	if not stream.automatic() or not _instance is CampusWorld:
		return
	var ids := CampusConnections.nearby(_instance.scene_id, position)
	stream.want(ids)
	for id: String in ids:
		prepare(id)


func _process(_delta: float) -> void:
	stream.poll()


func _exit_tree() -> void:
	stream.clear()


func clear() -> void:
	stream.clear()
	if is_instance_valid(_instance):
		remove_child(_instance)
		_instance.queue_free()
	_instance = null
	current = null
