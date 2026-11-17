class_name CooperativeConnectionHistory
extends RefCounted
## Device-local credentials, one recent room per connection mode.
var path := "user://cooperative/connection.json"
var entries: Dictionary = {}
const MAX_BYTES := 8192


func _init(destination: String = "user://cooperative/connection.json") -> void:
	path = destination


func load_file() -> void:
	entries.clear()
	for candidate: String in [path, path + ".bak"]:
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES: continue
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK: continue
		var raw: Variant = parser.data
		if not raw is Dictionary: continue
		var source: Dictionary = {}
		if raw.get("version") == 2 and raw.get("entries") is Dictionary: source = raw["entries"]
		elif raw.get("mode", "lan") is String: source[String(raw.get("mode", "lan"))] = raw
		for mode: String in ["lan", "remote"]:
			var value: Variant = source.get(mode)
			if value is Dictionary and valid(mode, value): entries[mode] = _record(mode, value)
		if not entries.is_empty(): return


static func valid(mode: String, data: Dictionary) -> bool:
	if mode not in ["lan", "remote"]: return false
	for key: String in ["name", "token", "address" if mode == "lan" else "code"]:
		if not data.get(key) is String or String(data[key]).is_empty() or String(data[key]).length() > 128: return false
	return mode == "remote" or not LanProtocol.address(data["address"]).is_empty()


static func _record(mode: String, data: Dictionary) -> Dictionary:
	var key := "address" if mode == "lan" else "code"
	return {"mode": mode, "name": String(data["name"]).left(24), "token": data["token"], key: String(data[key]).strip_edges()}


func get_entry(mode: String) -> Dictionary:
	return entries.get(mode, {}).duplicate()


func remember(mode: String, data: Dictionary) -> String:
	if not valid(mode, data): return ""
	var record := _record(mode, data)
	if entries.get(mode, {}) == record: return ""
	entries[mode] = record
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return "无法保存重连记录；本次游戏中仍可重连。"
	var bytes := JSON.stringify({"version": 2, "entries": entries}).to_utf8_buffer()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "无法保存重连记录；本次游戏中仍可重连。"
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.get_file_as_bytes(path + ".tmp") != bytes: return "重连记录写入校验失败。"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK: return "无法备份重连记录。"
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return "无法更新重连记录。"
	return ""
