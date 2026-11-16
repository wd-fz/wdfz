extends SceneTree
## The Android plugin is replaced at its API boundary; discovery and ENet are real.
class Device extends RefCounted:
	var session: LanSession
	var bound := false
	var denied := false
	var lost := false
	var restore_failed := false
	var preparations := 0
	var socket_order_ok := true
	func state() -> String:
		return JSON.stringify({"ok": not denied and not lost, "error": "VPN 策略禁止本地网络" if denied else "Wi-Fi 已断开" if lost else "", "vpn": true, "bound": bound, "mode": "wifi", "network": "102", "interface": "wlan0", "addresses": ["192.168.8.2"], "broadcasts": ["255.255.255.255", "192.168.9.255", "127.0.0.1"]})
	func prepareLocal(_target: String) -> String:
		socket_order_ok = socket_order_ok and session.transport.peer == null and session.discovery.socket == null
		preparations += 1
		bound = not denied
		return state()
	func routeStatus() -> String: return state()
	func releaseLocal() -> String:
		socket_order_ok = socket_order_ok and session.transport.peer == null and session.discovery.socket == null
		if restore_failed: return JSON.stringify({"ok": false, "error": "无法恢复系统网络"})
		bound = false
		return JSON.stringify({"ok": true, "error": ""})

var checks := 0
var failures := 0


func _initialize() -> void: call_deferred("run")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)


func free_port() -> int:
	var socket := PacketPeerUDP.new()
	socket.bind(0, "127.0.0.1")
	var result := socket.get_local_port()
	socket.close()
	return result


func device(session: LanSession) -> Device:
	var result := Device.new()
	result.session = session
	session.route.plugin = result
	root.add_child(session)
	return result


func run() -> void:
	var host := LanSession.new()
	var guest := LanSession.new()
	var host_device := device(host)
	var guest_device := device(guest)
	guest.discover()
	check(guest_device.bound and guest.discovery.socket != null, "scan binds Wi-Fi before creating the discovery socket")
	check(guest.discovery.targets == PackedStringArray(["255.255.255.255", "192.168.9.255", "127.0.0.1"]), "scan uses the selected network's real prefix, not VPN interfaces")
	check(guest.stop().is_empty() and not guest_device.bound, "closing scan restores routing")
	var port := free_port()
	check(host.host("test", "host", port).is_empty() and host_device.bound, "VPN host binds physical LAN before listening")
	check(host.route.addresses == PackedStringArray(["192.168.8.2"]), "host advertises selected physical addresses")
	check(guest.join("127.0.0.1:%d" % port, "guest").is_empty() and guest_device.bound, "VPN guest binds before ENet connect")
	var deadline := Time.get_ticks_msec() + 3000
	while guest.room == null and Time.get_ticks_msec() < deadline: await process_frame
	check(guest.room != null, "room handshake still completes through the scoped route adapter")
	check(host.connection_details().contains("网卡 wlan0") and guest.connection_details().contains("VPN true"), "both device diagnostics include selected interface and VPN state")
	check(guest.stop().is_empty() and not guest_device.bound, "guest closes sockets before restoring default routing")
	host_device.lost = true
	host.route._process(1.1)
	check(host.connection_stage == "failed" and host.transport.peer == null and host.discovery.socket == null and not host_device.bound, "lost Wi-Fi stops host ENet and discovery before restoring default routing")
	check(host.connection_details().contains("Wi-Fi 已断开"), "network loss reason survives cleanup")
	host.stop()
	host_device.lost = false
	host_device.denied = true
	check(not host.host("test", "host", port).is_empty() and host.transport.peer == null and host.discovery.socket == null, "denied VPN bypass never starts an unbound host")
	host_device.denied = false
	host.direct_lan = false
	var before := host_device.preparations
	check(host.host("remote", "host", port).is_empty() and not host_device.bound and host_device.preparations == before, "Terracotta host never acquires a physical-network binding")
	host.stop()
	guest_device.restore_failed = true
	check(not guest.join("127.0.0.1:%d" % port, "guest").is_empty() and guest.transport.peer == null, "failed route cleanup blocks a new connection")
	guest_device.restore_failed = false
	check(host_device.socket_order_ok and guest_device.socket_order_ok, "all acquisitions/restores occur outside live socket lifetimes")
	host.queue_free()
	guest.queue_free()
	await process_frame
	print("LAN ROUTING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
