class_name TerracottaGateway
extends Node
## Desktop loopback HTTP or the packaged Android JNI plugin. One request at a time.
signal booted(error: String)
signal replied(path: String, status: int, data: Dictionary)
signal released
var busy := false
var api_port := 0
var _http: HTTPRequest
var _plugin: Object
var _path := ""
var _file := ""
var _deadline := 0
var _serial := 0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	_http.max_redirects = 0
	_http.body_size_limit = 65536
	add_child(_http)
	_http.request_completed.connect(_http_reply)
	if OS.get_name() == "Android" and Engine.has_singleton("WdfzTerracotta"):
		_plugin = Engine.get_singleton("WdfzTerracotta")
		_plugin.connect("response", _android_reply)
		_plugin.connect("prepared", func(error: String) -> void: booted.emit(error))
		_plugin.connect("released", func() -> void: released.emit())


func boot() -> void:
	if OS.get_name() == "Android":
		if _plugin == null: booted.emit("此 APK 未包含远程联机组件，请安装完整测试包。")
		else: _plugin.call("prepare")
		return
	if OS.get_name() not in ["Linux", "Windows"]:
		booted.emit("当前平台尚未提供 Terracotta 组件。")
		return
	var filename := "terracotta.exe" if OS.get_name() == "Windows" else "terracotta"
	var platform := "windows" if OS.get_name() == "Windows" else "linux"
	var binary := OS.get_executable_path().get_base_dir().path_join("terracotta/" + filename)
	if OS.has_feature("editor"):
		binary = ProjectSettings.globalize_path("res://build/deps/terracotta/%s/%s" % [platform, filename])
	if not FileAccess.file_exists(binary):
		booted.emit("缺少 Terracotta 组件。开发环境请运行 tools/terracotta.py --platform " + platform + "；玩家请重新解压完整安装包。")
		return
	DirAccess.make_dir_recursive_absolute("user://remote")
	_file = ProjectSettings.globalize_path("user://remote/api-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json")
	_deadline = Time.get_ticks_msec() + 12000
	if OS.create_process(binary, PackedStringArray(["--hmcl", _file])) == -1:
		_file = ""
		booted.emit("无法启动 Terracotta，请检查安装目录的执行权限。")


func _process(_dt: float) -> void:
	if _file == "": return
	if FileAccess.file_exists(_file):
		var file := FileAccess.open(_file, FileAccess.READ)
		var data: Variant = JSON.parse_string(file.get_as_text()) if file != null and file.get_length() <= 128 else null
		DirAccess.remove_absolute(_file)
		_file = ""
		if data is Dictionary and data.get("port") is float and int(data.port) > 0 and int(data.port) <= 65535:
			api_port = int(data.port)
			booted.emit("")
		else: booted.emit("Terracotta 返回了无效的本地接口。")
	elif Time.get_ticks_msec() >= _deadline:
		_file = ""
		booted.emit("Terracotta 启动超时，请重试。")


func request(path: String) -> void:
	assert(not busy)
	busy = true
	_path = path
	_serial += 1
	if _plugin != null:
		_plugin.call("request", _serial, path)
	else:
		var error := _http.request("http://127.0.0.1:%d%s" % [api_port, path])
		if error != OK: _finish.call_deferred(0, {})


func _http_reply(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else {}
	_finish(status if result == HTTPRequest.RESULT_SUCCESS and parsed is Dictionary else 0, parsed if parsed is Dictionary else {})


func _android_reply(id: int, status: int, body: String) -> void:
	if id != _serial or not busy: return
	var data: Variant = JSON.parse_string(body)
	_finish(status if data is Dictionary else 0, data if data is Dictionary else {})


func _finish(status: int, data: Dictionary) -> void:
	var path := _path
	busy = false
	replied.emit(path, status, data)


func release() -> void:
	if _plugin != null: _plugin.call("release")
	else: released.emit.call_deferred()
	# Desktop instances may be shared with another application; never kill or /panic them.


func _exit_tree() -> void:
	if _file != "": DirAccess.remove_absolute(_file)
