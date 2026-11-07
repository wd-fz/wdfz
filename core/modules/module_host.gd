class_name ModuleHost
extends RefCounted
## Deterministic registration order. IDs and interaction ownership are unique.

var _modules: Dictionary[StringName, FeatureModule] = {}
var _interactions: Dictionary[StringName, FeatureModule] = {}
var _unloaded_state: Dictionary = {}


func register(feature: FeatureModule) -> String:
	var id := feature.module_id()
	if id.is_empty() or _modules.has(id):
		return "模块 ID 为空或重复：%s" % id
	var claims: Dictionary = {}
	for interaction_id: String in feature.interaction_ids():
		if interaction_id.is_empty() or _interactions.has(interaction_id) or claims.has(interaction_id):
			return "交互 ID 为空或重复：%s" % interaction_id
		claims[interaction_id] = true
	_modules[id] = feature
	for interaction_id: String in feature.interaction_ids():
		_interactions[StringName(interaction_id)] = feature
	return ""


func get_module(id: StringName) -> FeatureModule:
	return _modules.get(id)


func reset() -> void:
	_unloaded_state.clear()
	for feature: FeatureModule in _modules.values():
		feature.reset()


func advance(delta: float) -> void:
	for feature: FeatureModule in _modules.values():
		feature.advance(delta)


func interact(id: StringName) -> String:
	if not _interactions.has(id):
		return "此交互尚未接入：%s" % id
	return _interactions[id].interact(id)


func capture() -> Dictionary:
	var result := _unloaded_state.duplicate(true)
	for id: StringName in _modules:
		var feature := _modules[id]
		result[String(id)] = {"version": feature.state_version(), "data": feature.capture().duplicate(true)}
	return result


func validate(data: Dictionary) -> String:
	for id: Variant in data:
		if not id is String or not data[id] is Dictionary:
			return "模块存档格式错误"
		var entry: Dictionary = data[id]
		if not entry.get("data") is Dictionary or not SaveSchema.is_integer(entry.get("version"), 1, 100000):
			return "模块存档缺少有效版本或数据：%s" % id
		if not _modules.has(StringName(id)):
			continue # Preserve inactive modules; do not execute or load code from saves.
		var feature := _modules[StringName(id)]
		if int(entry["version"]) != feature.state_version():
			return "模块存档版本不兼容：%s" % id
		var error := feature.validate(entry["data"])
		if not error.is_empty():
			return "%s：%s" % [id, error]
	# Local payloads are already valid before checking cross-module invariants.
	for feature: FeatureModule in _modules.values():
		var error := feature.validate_snapshot(data)
		if not error.is_empty():
			return "%s：%s" % [feature.module_id(), error]
	return ""


func feature(id: StringName) -> FeatureModule:
	return _modules.get(id)


func restore(data: Dictionary) -> void:
	# The caller must validate the entire snapshot before entering this method.
	reset()
	_unloaded_state = data.duplicate(true)
	for id: StringName in _modules:
		if data.has(String(id)):
			_modules[id].restore(data[String(id)]["data"].duplicate(true))
		_unloaded_state.erase(String(id))


func stop() -> void:
	for feature: FeatureModule in _modules.values():
		feature.stop()
