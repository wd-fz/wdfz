extends SceneTree
var checks := 0
var failures := 0

class FakeGateway extends TerracottaGateway:
	var calls: Array[String] = []
	var boot_delay := false
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func boot() -> void:
		if not boot_delay: booted.emit.call_deferred("")
	func request(path: String) -> void:
		assert(not busy)
		busy = true
		calls.append(path)
	func answer(data: Dictionary, status: int = 200) -> void:
		var path: String = calls.back()
		busy = false
		replied.emit(path, status, data)
	func release() -> void: released.emit.call_deferred()


func _initialize() -> void: run.call_deferred()


func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", text)


func setup() -> TerracottaSession:
	var session := TerracottaSession.new()
	session.gateway.free()
	session.gateway = FakeGateway.new()
	root.add_child(session)
	session.set_process(false)
	return session


func accept(session: TerracottaSession) -> void:
	await process_frame
	var gateway := session.gateway as FakeGateway
	gateway.answer({"version": "0.4.2", "yggdrasil_port": 13448})
	gateway.answer({"state": "waiting", "index": 0})
	check(gateway.calls.back().begins_with("/state/guesting?room="), "guest submits validated code")
	gateway.answer({})


func run() -> void:
	const CODE := "U/YNZE-U61D-2206-HXRG"
	check(TerracottaProtocol.valid_code(CODE), "upstream example validates")
	for value: String in ["", "../../", CODE + "&player=x", "U/YNZE-U61D-2206-HXR0", "U/YNZE-I61D-2206-HXRG"]:
		check(not TerracottaProtocol.valid_code(value), "malformed invitation rejected")
	for _i in 64: check(TerracottaProtocol.valid_code(TerracottaProtocol.new_code()), "new code validates")
	check(TerracottaProtocol.endpoint("127.0.0.1") == "127.0.0.1:25565", "upstream default is Minecraft's port, not ENet's")
	check(TerracottaProtocol.endpoint("127.0.0.1:31000") == "127.0.0.1:31000", "dynamic forwarded port")
	for value: String in ["localhost", "1.2.3.4:24560", "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:12/a", "127.0.0.1:01", "127.0.0.1:1:2"]:
		check(TerracottaProtocol.endpoint(value) == "", "non-loopback/malformed endpoint rejected")
	var session := setup()
	var gateway := session.gateway as FakeGateway
	check(session.begin(false, "同学 & nickname", CODE) == "", "starts asynchronously")
	await accept(session)
	check(gateway.calls.back().contains("%26"), "query nickname is escaped")
	session._process(1.0)
	gateway.answer({"state": "guest-starting", "room": CODE, "index": 2})
	session._process(1.0)
	var endpoints: Array = []
	session.connected.connect(func(address: String, _code: String) -> void: endpoints.append(address))
	gateway.answer({"state": "guest-ok", "url": "127.0.0.1:31000", "index": 3})
	check(session.available and endpoints == ["127.0.0.1:31000"], "only validated endpoint reaches ENet")
	session._process(1.0)
	gateway.answer({"state": "guest-ok", "url": "127.0.0.1:31001", "index": 3})
	check(endpoints.size() == 1, "duplicate state does not rejoin")
	session.stop()
	gateway.answer({"state": "guest-ok", "index": 3})
	check(gateway.calls.back() == "/state/ide", "own room is reset before release")
	gateway.answer({})
	await process_frame
	# 2026-11-14 CI flake: a busy local component can miss one status poll while a guest is still connecting.
	var slow := setup()
	var slow_gateway := slow.gateway as FakeGateway
	var slow_errors: Array = []
	slow.failed.connect(func(text: String) -> void: slow_errors.append(text))
	check(slow.begin(false, "同学", CODE) == "", "a second guest starts")
	await accept(slow)
	slow._process(1.0)
	slow_gateway.answer({}, 0)
	check(slow_errors.is_empty() and slow.phase == "connecting", "one missed poll while connecting does not abandon the join")
	slow._process(1.0)
	slow_gateway.answer({"state": "guest-starting", "room": CODE, "index": 2})
	slow._process(1.0)
	slow_gateway.answer({}, 0)
	slow._process(1.0)
	slow_gateway.answer({}, 0)
	slow._process(1.0)
	slow_gateway.answer({}, 0)
	check(slow._error.contains("无响应") and slow._cancel, "three misses in a row still fail with the component message")
	await process_frame
	var refused := setup()
	var refused_gateway := refused.gateway as FakeGateway
	var refused_errors: Array = []
	refused.failed.connect(func(text: String) -> void: refused_errors.append(text))
	refused.begin(false, "同学", CODE)
	await accept(refused)
	refused._process(1.0)
	refused_gateway.answer({}, 404)
	check(refused._error.contains("无响应") and refused._cancel, "a definite refusal while connecting fails at once")
	await process_frame
	check(session.phase == "idle", "cleanup finishes")
	session.queue_free()

	session = setup()
	gateway = session.gateway as FakeGateway
	session.begin(false, "name", CODE)
	await process_frame
	gateway.answer({"version": "0.4.2"})
	gateway.answer({"state": "host-ok", "room": "another-room", "index": 8})
	await process_frame
	check(session.phase == "idle" and not gateway.calls.has("/state/ide"), "another application's room is untouched")
	session.queue_free()

	session = setup()
	gateway = session.gateway as FakeGateway
	session.begin(false, "name", CODE)
	await process_frame
	gateway.answer({"version": "0.4.2"})
	gateway.answer({"state": "waiting", "index": 0})
	session.stop()
	check(gateway.busy, "cancel waits for in-flight mutation")
	gateway.answer({})
	check(gateway.calls.back() == "/state", "late command is inspected")
	gateway.answer({"state": "guest-connecting", "room": CODE, "index": 1})
	check(gateway.calls.back() == "/state/ide", "late command is cleaned")
	gateway.answer({})
	await process_frame
	check(session.phase == "idle", "cancel permits new connection")
	session.queue_free()

	session = setup()
	gateway = session.gateway as FakeGateway
	gateway.boot_delay = true
	session.begin(false, "name", CODE)
	session.stop()
	gateway.booted.emit("")
	await process_frame
	check(session.phase == "idle" and gateway.calls.is_empty(), "cancel before boot never creates a room")
	session.queue_free()

	session = setup()
	gateway = session.gateway as FakeGateway
	session.begin(false, "name", CODE)
	await accept(session)
	session._process(1.0)
	gateway.answer({"state": "guest-ok", "url": "10.0.0.3:80", "index": 2})
	check(not session.available and session._cancel, "bad endpoint fails closed")
	gateway.answer({"state": "guest-ok", "index": 2})
	gateway.answer({})
	await process_frame
	session.queue_free()
	await process_frame
	print("TERRACOTTA UNIT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
