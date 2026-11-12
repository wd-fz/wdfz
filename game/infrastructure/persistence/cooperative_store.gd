class_name CooperativeStore
extends RefCounted
## Isolated cooperative slot. Credentials are host-local and never part of snapshots.
var path := "user://cooperative/room.json"
var validator: Callable
const MAX_BYTES := 2 * 1024 * 1024


func write(data: Dictionary, credentials: Dictionary) -> String:
	if validator.is_valid():
		var why := String(validator.call(data))
		if not why.is_empty(): return why
	var envelope := {"save": data, "credentials": credentials}
	var bytes := JSON.stringify(envelope).to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return "合作存档超过大小限制。"
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return "无法建立合作存档目录。"
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "无法写入合作存档。"
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.get_file_as_bytes(path + ".tmp") != bytes: return "合作存档写入校验失败。"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"): DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK: return "无法备份合作存档。"
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return "无法完成合作存档替换。"
	return ""


func read() -> Dictionary:
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES: continue
		var data := LanProtocol.decode(file.get_buffer(file.get_length()), MAX_BYTES)
		if data.get("save") is Dictionary and data.get("credentials") is Dictionary:
			if validator.is_valid() and not String(validator.call(data["save"])).is_empty(): continue
			var valid := true
			for hash_value: Variant in data["credentials"]:
				if not hash_value is String or String(hash_value).length() != 64 or not data["save"].get("actors", {}).has(data["credentials"][hash_value]): valid = false
			if valid: return data
	return {"error": "没有有效的合作存档。"}


## Personal and team outcomes are intentionally isolated from single-player achievements.
func result(room: Dictionary, member: String, life: Dictionary) -> String:
	var destination := path.get_base_dir().path_join("results.json")
	var history: Array = []
	if FileAccess.file_exists(destination):
		var old := FileAccess.open(destination, FileAccess.READ)
		if old != null and old.get_length() < MAX_BYTES:
			var parsed: Variant = JSON.parse_string(old.get_as_text())
			if parsed is Array: history = parsed
	for entry: Variant in history:
		if entry is Dictionary and entry.get("epoch") == room["epoch"]: return ""
	history.append({"epoch": room["epoch"], "member": member, "members": room["members"], "ending": room["ending"], "personal": life, "debug": room["debug"]})
	while history.size() > 100: history.pop_front()
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null: return "合作结算记录写入失败。"
	file.store_string(JSON.stringify(history))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(destination + ".tmp", destination) != OK: return "合作结算记录替换失败。"
	return ""
