@abstract
class_name FeatureModule
extends RefCounted
## Session-owned rules. No Node, input polling, scene paths or file I/O here.
## A renderer/UI adapter may subscribe to signals on a concrete module.

@abstract func module_id() -> StringName
@abstract func capture() -> Dictionary
@abstract func validate(data: Dictionary) -> String
@abstract func restore(data: Dictionary) -> void
@abstract func reset() -> void


func state_version() -> int:
	return 1


func validate_snapshot(_module_snapshots: Dictionary) -> String:
	return ""


func interaction_ids() -> PackedStringArray:
	return PackedStringArray()


func interact(_interaction_id: StringName) -> String:
	return ""


func advance(_delta: float) -> void:
	pass


func stop() -> void:
	pass
