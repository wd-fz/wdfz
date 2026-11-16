class_name LanNetworkRoute
extends Node
## Android's process binding must surround both discovery and ENet socket lifetimes.
signal unavailable(reason: String)
var plugin: Object
var active := false
var details := "系统默认网络（非 Android）"
var addresses: PackedStringArray = []
var broadcasts: PackedStringArray = []
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if plugin == null and OS.get_name() == "Android" and Engine.has_singleton("WdfzLanNetwork"):
		plugin = Engine.get_singleton("WdfzLanNetwork")


func acquire(target: String = "") -> String:
	if plugin == null:
		return "此 APK 缺少本地网络组件，请更新游戏。" if OS.get_name() == "Android" else ""
	var data := _read(plugin.call("prepareLocal", target))
	_describe(data)
	active = bool(data.get("ok", false))
	_timer = 0.0
	if not active:
		# Keep the error/selected interface for the copied report, but do not
		# leave a failed acquisition's callback or binding behind.
		plugin.call("releaseLocal")
	return String(data.get("error", ""))


func release() -> String:
	active = false
	addresses.clear()
	broadcasts.clear()
	if plugin == null: return ""
	var result := _read(plugin.call("releaseLocal"))
	return String(result.get("error", ""))


func _read(raw: Variant) -> Dictionary:
	var data: Variant = JSON.parse_string(raw) if raw is String else null
	if not data is Dictionary or not data.get("ok") is bool or not data.get("error") is String:
		return {"ok": false, "error": "本地网络组件没有返回有效状态，请更新游戏。"}
	if not data["ok"] and data["error"].is_empty(): data["error"] = "本地网络连接不可用。"
	return data


func _describe(data: Dictionary) -> void:
	addresses.clear()
	broadcasts.clear()
	for address: Variant in data.get("addresses", []):
		if address is String and address.is_valid_ip_address(): addresses.append(address)
	for target: Variant in data.get("broadcasts", []):
		if target is String and target.is_valid_ip_address() and not broadcasts.has(target): broadcasts.append(target)
	details = "本地选路 %s · 网卡 %s · 网络 %s · 已绑定 %s · VPN %s" % [data.get("mode", "unknown"), data.get("interface", ""), data.get("network", ""), str(data.get("bound", false)), str(data.get("vpn", false))]
	if not String(data.get("error", "")).is_empty(): details += "\n" + String(data["error"])


func _process(dt: float) -> void:
	if not active or plugin == null: return
	_timer += dt
	if _timer < 1.0: return
	_timer = 0.0
	var data := _read(plugin.call("routeStatus"))
	_describe(data)
	if not data["ok"]:
		active = false
		unavailable.emit(String(data["error"]))


func _exit_tree() -> void:
	# LanSession closes sockets and then releases us in stop(). The native
	# plugin also restores the prior binding when Android destroys the activity.
	active = false
