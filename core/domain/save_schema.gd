class_name SaveSchema
extends RefCounted
## JSON-only Godot schema. Web saves are deliberately not interpreted as v1.

const FORMAT := "wdfz-godot"
const VERSION := 1
const MAX_SECONDS := 315360000.0


static func number_in(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return number_in(value, minimum, maximum) and float(value) == floor(float(value))


static func is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value:
				if not is_json_value(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not is_json_value(value[key], depth + 1):
					return false
			return true
	return false


static func validate(data: Dictionary, known_worlds: PackedStringArray) -> String:
	if not is_json_value(data):
		return "存档只能包含有限数值、字符串、布尔值、数组与字典"
	if data.get("format") != FORMAT or not is_integer(data.get("version"), VERSION, VERSION):
		return "不支持的存档格式或版本；Web 版存档尚未提供转换器"
	if not data.get("world_id") is String or not known_worlds.has(data["world_id"]):
		return "存档引用了未登记的场景"
	if not data.get("clock") is Dictionary or not data.get("player") is Dictionary or not data.get("modules") is Dictionary:
		return "存档缺少时钟、玩家或模块状态"
	var clock: Dictionary = data["clock"]
	if not number_in(clock.get("active_seconds"), 0, MAX_SECONDS) or not number_in(clock.get("calendar_seconds"), 0, MAX_SECONDS):
		return "存档时钟无效"
	if float(clock["calendar_seconds"]) > float(clock["active_seconds"]) + 0.001:
		return "日历运行时间不能超过有效运行时间"
	var player: Dictionary = data["player"]
	var position: Variant = player.get("position")
	if not position is Array or position.size() != 3:
		return "玩家位置无效"
	for coordinate: Variant in position:
		if not number_in(coordinate, -10000, 10000):
			return "玩家位置超出有效范围"
	if not number_in(player.get("yaw"), -PI, PI) or not number_in(player.get("pitch"), -1.4, 1.4):
		return "玩家视角无效"
	return ""
