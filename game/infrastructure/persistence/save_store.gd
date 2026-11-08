class_name SaveStore
extends RefCounted
## Storage adapter only. Validation belongs to GameSession, before world teardown.

const MAX_BYTES := 1024 * 1024
var path: String


func _init(save_path: String = "user://saves/slot_1.json") -> void:
	path = save_path


func exists() -> bool:
	return FileAccess.file_exists(path)


## story.js clearSave on a final death: the run cannot be loaded again (the .bak stays for recovery).
func clear() -> void:
	if exists():
		DirAccess.remove_absolute(path)


## Small JSON side files next to the save (e.g. the cross-run death log).
func side_path(name: String) -> String:
	return path.get_base_dir().path_join(name)


func write(data: Dictionary) -> String:
	if not SaveSchema.is_json_value(data):
		return "存档包含无法保存的临时对象或非有限数值"
	var payload := JSON.stringify(data, "\t", true, true)
	if payload.to_utf8_buffer().size() > MAX_BYTES:
		return "存档超过 1 MiB 限制"
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK:
		return "无法创建存档目录：%s" % error_string(directory_error)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入临时存档：%s" % error_string(FileAccess.get_open_error())
	file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "存档写入失败：%s" % error_string(write_error)
	if exists():
		var backup_error := DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return "未能保留旧档备份：%s" % error_string(backup_error)
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary)
		return "未能替换存档，旧档仍保留：%s" % error_string(replace_error)
	return ""


func read() -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取存档：%s" % error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"error": "存档超过 1 MiB 限制"}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "存档不是有效的 JSON 对象；当前会话未改变"}
	return {"data": json.data}
