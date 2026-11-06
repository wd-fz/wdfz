class_name DemoModule
extends FeatureModule
## Replaceable vertical slice: interaction -> rule state -> save -> restore.
## This is a migration example, not a canon quest or survival rule.

var _read_count := 0


func module_id() -> StringName:
	return &"demo.notice_board"


func interaction_ids() -> PackedStringArray:
	return PackedStringArray(["demo.read_board"])


func interact(_id: StringName) -> String:
	_read_count = mini(_read_count + 1, 1000000)
	return "接入示例：交互已交给功能模块。本局已查看 %d 次，可暂停存档后验证恢复。" % _read_count


func capture() -> Dictionary:
	return {"read_count": _read_count}


func validate(data: Dictionary) -> String:
	if not SaveSchema.is_integer(data.get("read_count"), 0, 1000000):
		return "查看次数无效"
	return ""


func restore(data: Dictionary) -> void:
	_read_count = int(data["read_count"])


func reset() -> void:
	_read_count = 0
