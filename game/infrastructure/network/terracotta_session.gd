class_name TerracottaSession
extends Node
## Owns the tunnel lifecycle only; LanSession remains the authoritative game session.
signal status_changed(text: String)
signal connected(address: String, code: String)
signal failed(reason: String)
signal stopped
var gateway := TerracottaGateway.new()
var bridge := TerracottaBridge.new()
var code := ""
var phase := "idle"
var hosting := false
var available := false
var _nick := ""
var _owned := false
var _cancel := false
var _poll := 0.0
var _deadline := 0
var _index := -1
var _scaffolding := 13448
var _failures := 0
var _error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(gateway)
	add_child(bridge)
	gateway.booted.connect(_booted)
	gateway.replied.connect(_reply)
	gateway.released.connect(_released)
	bridge.verified.connect(func(ok: bool) -> void:
		if _cancel: return
		if not ok:
			_fail("Terracotta 未转发本游戏端口。请关闭其他游戏的联机房间，或释放本地 13448 端口后重试。")
			return
		phase = "connected"
		available = true
		status_changed.emit("远程房间已就绪。仅把邀请码交给可信的朋友。")
		connected.emit("", code))


func begin(host: bool, nickname: String, room_code: String = "", port: int = LanProtocol.PORT) -> String:
	if phase != "idle": return "请等待上一次远程连接完全关闭。"
	var normalized := TerracottaProtocol.normalize(room_code)
	if not host and not TerracottaProtocol.valid_code(normalized): return "邀请码格式或校验不正确，请粘贴完整的 U/… 邀请码。"
	if host:
		var error := bridge.start(port)
		if error != "": return error
	hosting = host
	code = TerracottaProtocol.new_code() if host else normalized
	_nick = nickname.strip_edges().left(24)
	_owned = false
	_cancel = false
	_error = ""
	_index = -1
	_failures = 0
	available = false
	phase = "boot"
	_deadline = Time.get_ticks_msec() + 120000
	status_changed.emit("正在准备远程联机；Android 首次使用需允许系统 VPN 请求。")
	gateway.boot()
	return ""


func stop() -> void:
	if phase in ["idle", "release"]: return
	_cancel = true
	available = false
	bridge.stop()
	status_changed.emit("正在关闭远程连接……")
	# Do not abort an in-flight mutation: its late completion must still be reset.
	if not gateway.busy and phase != "boot": _cleanup()


func _booted(error: String) -> void:
	if phase != "boot": return
	if error != "":
		_fail(error)
		_finish()
	elif _cancel: _finish()
	else:
		phase = "meta"
		gateway.request("/meta")


func _reply(path: String, status: int, data: Dictionary) -> void:
	if phase == "idle": return
	if path == "/state/ide":
		if status != 200 and _failures < 2:
			_failures += 1
			gateway.request("/state/ide")
			return
		if status != 200: _error = "远程接口无响应，未能确认房间关闭；请在 Terracotta 中手动结束房间。"
		_finish()
		return
	if path.begins_with("/state/scanning") or path.begins_with("/state/guesting"):
		# A lost HTTP response may still have performed the request. Inspect before cleanup.
		_owned = status == 200 or status == 0
		phase = "connecting"
		if status != 200: _fail("Terracotta 未接受连接请求，请重试。")
		elif _cancel: _cleanup()
		else: _poll = 0.0
		return
	if _cancel:
		if phase == "cleanup" and path == "/state":
			if status == 200 and _ours(data): gateway.request("/state/ide")
			else: _finish()
		else: _cleanup()
		return
	if status != 200:
		_failures += 1
		if phase != "connected" or _failures >= 3: _fail("远程联机组件无响应，请检查网络后重新连接。")
		return
	_failures = 0
	if path == "/meta":
		if String(data.get("version", "")) != "0.4.2":
			_fail("Terracotta 版本不兼容，请关闭旧版程序并使用游戏附带的 0.4.2。")
			return
		_scaffolding = int(data.get("yggdrasil_port", 13448))
		if _scaffolding < 1 or _scaffolding > 65535:
			_fail("远程组件端口无效。")
			return
		phase = "inspect"
		gateway.request("/state")
		return
	if phase == "inspect":
		if data.get("state") != "waiting":
			_fail("Terracotta 正在服务另一个房间。请先在原应用结束该房间，再重试。")
			return
		phase = "command"
		gateway.request(("/state/scanning" if hosting else "/state/guesting") + "?room=" + code.uri_encode() + "&player=" + _nick.uri_encode())
		return
	var state := String(data.get("state", ""))
	if state in ["exception", "waiting"]:
		_fail("远程连接中断。房主须保持游戏运行；可检查网络后重连。" if state == "exception" else "远程房间已经关闭。")
		return
	if not _ours(data):
		_owned = false
		_fail("Terracotta 已切换到其他房间，本游戏已断开。")
		return
	var index := int(data.get("index", -1))
	if index <= _index: return
	_index = index
	if state == "host-ok" and phase == "connecting":
		phase = "verify"
		status_changed.emit("已建立远程网络，正在验证游戏端口……")
		bridge.verify_port(_scaffolding)
	elif state == "guest-ok" and phase == "connecting":
		var target := TerracottaProtocol.endpoint(String(data.get("url", "")))
		if target == "":
			_fail("Terracotta 返回了无效的本地游戏地址。")
			return
		phase = "connected"
		available = true
		status_changed.emit("远程通道已建立，正在加入好友的校园……")
		connected.emit(target, code)
	elif phase == "connecting":
		status_changed.emit("正在建立远程连接（最长 120 秒），可返回取消。" + ("双方网络限制较严格，建议切换网络后重试。" if data.get("difficulty") == "TOUGH" else ""))


func _ours(data: Dictionary) -> bool:
	if data.has("room"): return data.room == code
	return _owned and data.get("state") in (["host-scanning", "exception"] if hosting else ["guest-ok", "exception"])


func _cleanup() -> void:
	if gateway.busy: return
	if _owned:
		phase = "cleanup"
		gateway.request("/state")
	else: _finish()


func _fail(reason: String) -> void:
	_error = reason
	stop()


func _finish() -> void:
	if phase == "release": return
	bridge.stop()
	phase = "release"
	gateway.release()


func _released() -> void:
	if phase != "release": return
	phase = "idle"
	_owned = false
	available = false
	var error := _error
	_error = ""
	stopped.emit()
	if error != "": failed.emit(error)


func _process(dt: float) -> void:
	if _cancel or phase in ["idle", "boot", "meta", "inspect", "command", "cleanup", "release"]: return
	if not available and Time.get_ticks_msec() > _deadline:
		_fail("远程连接超时。请确认房主在线，允许游戏通过防火墙，或尝试更换网络。")
		return
	_poll -= dt
	if _poll <= 0 and not gateway.busy:
		_poll = 1.0 if available else 0.5
		gateway.request("/state")
