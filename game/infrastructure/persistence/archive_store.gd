class_name ArchiveStore
extends RefCounted
## Only the archive profile is written here; replay has no save-store dependency.
var path: String

func _init(file_path: String) -> void: path = file_path

func read(rules: ArchiveRules, old_log: Dictionary) -> void:
	rules.restore(JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null)
	rules.migrate(old_log)
	write(rules)

func write(rules: ArchiveRules) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(rules.state))
	return true
