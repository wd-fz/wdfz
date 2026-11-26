@tool
extends EditorExportPlugin
const Exterior := preload("res://game/presentation/world/campus/baked_exterior.gd")
const RSCC := preload("rscc.gd")
const POLICY := {"version": 1, "model_tiers": [0, 1, 2, 3], "scene_block_max": 1048576, "lossless": true}
var _textures: Dictionary = {}
var _report: Dictionary = {}
var _output := ""


func _get_name() -> String:
	return "WdfzLosslessPackage"


func _export_begin(_features: PackedStringArray, _debug: bool, path: String, _flags: int) -> void:
	_textures.clear()
	_output = path
	_report = {"policy": POLICY, "output": path, "scenes": 0, "scene_bytes_before": 0, "scene_bytes_after": 0,
		"textures": 0, "unique_textures": 0, "texture_bytes_before": 0, "texture_bytes_after": 0, "lossless_verified": 0}
	add_file("res://assets/package_policy.json", JSON.stringify(POLICY).to_utf8_buffer(), false)
	_add_exteriors()


func _add_exteriors() -> void:
	var directory := "res://.godot/resident-exterior-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create temporary directory for the resident campus")
		return
	var output := []
	var code := OS.execute(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://addons/package_optimizer/bake_exterior.gd", "--", directory,
	], output, true)
	_report.exterior_bytes = 0
	_report.exterior_tiers = []
	if code != 0:
		push_error("Exterior bake failed (%d): %s" % [code, "\n".join(output)])
	else:
		for tier: int in POLICY.model_tiers:
			var destination := Exterior.PATH % tier
			var path := directory.path_join(destination.get_file())
			var result := RSCC.compact(FileAccess.get_file_as_bytes(path))
			if result.has("error"):
				push_error("Exterior bake: %s: %s" % [path, result.error])
				break
			add_file(destination, result.data, false)
			_report.exterior_bytes += result.data.size()
			_report.exterior_tiers.append(tier)
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	print("RESIDENT EXTERIORS: %.1f MiB" % (_report.exterior_bytes / 1048576.0))


func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	if not path.begins_with("res://assets/") or not FileAccess.file_exists(path + ".import"): return
	# Keep one directly decodable model per region and its shared PNGs on Android.
	# FileAccess can read these even if a device cannot instantiate an imported scene.
	if "android" in features:
		var entry_model := path.begins_with("res://assets/campus_q0/scenes/") or path.begins_with("res://assets/characters/") or path.begins_with("res://assets/campus/figures/otherworld/")
		if entry_model and path.ends_with(".glb"):
			add_file(path + ".source", FileAccess.get_file_as_bytes(path), false)
		elif path.begins_with("res://assets/campus_q0/textures/") and path.ends_with(".png"):
			add_file(path, FileAccess.get_file_as_bytes(path), false)
		elif path == "res://assets/ui/menu_panorama.jpg":
			add_file(path + ".source", FileAccess.get_file_as_bytes(path), false)
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK: return
	# Feature-specific GPU texture variants remain under the engine's exporter.
	for key in config.get_section_keys("remap"):
		if key.begins_with("path."): return
	var imported := String(config.get_value("remap", "path", ""))
	if imported.is_empty(): return
	if type == "PackedScene" and imported.ends_with(".scn"):
		var original := FileAccess.get_file_as_bytes(imported)
		# Unsupported future import formats keep the engine's normal export path.
		if original.size() < 4 or original.slice(0, 4) != RSCC.MAGIC: return
		var result := RSCC.compact(original)
		if result.has("error"):
			push_error("Package optimizer: %s: %s" % [path, result.error])
			return
		add_file(path + ".packed.scn", result.data, true)
		_report.scenes += 1
		_report.scene_bytes_before += original.size()
		_report.scene_bytes_after += result.data.size()
		_report.lossless_verified += 1
	elif imported.ends_with(".ctex"):
		var data := FileAccess.get_file_as_bytes(imported)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(data)
		var signature := hash.finish().hex_encode()
		var destination := "res://assets/packed_textures/" + signature + ".ctex"
		if not _textures.has(signature):
			_textures[signature] = destination
			add_file(destination, data, false)
			_report.unique_textures += 1
			_report.texture_bytes_after += data.size()
		# Preserve the import adapter: direct .remap -> .ctex fails when native
		# materials request the abstract Texture2D type (rather than CompressedTexture2D).
		config.set_value("remap", "path", destination)
		for section in ["deps", "params"]:
			if config.has_section(section): config.erase_section(section)
		add_file(path + ".import", config.encode_to_text().to_utf8_buffer(), false)
		skip()
		_report.textures += 1
		_report.texture_bytes_before += data.size()


func _export_end() -> void:
	var directory := "res://build/reports/package-size"
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join(_output.get_file() + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write package optimization report")
		return
	file.store_string(JSON.stringify(_report, "  ") + "\n")
	print("PACKAGE OPTIMIZER: %d scenes verified, %d/%d unique textures, %.1f MiB removed losslessly" % [
		_report.lossless_verified, _report.unique_textures, _report.textures,
		(_report.scene_bytes_before - _report.scene_bytes_after + _report.texture_bytes_before - _report.texture_bytes_after) / 1048576.0])
