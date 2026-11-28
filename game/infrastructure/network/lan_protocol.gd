class_name LanProtocol
extends RefCounted
## JSON-only wire format. Never decode objects or resource paths from a peer.
const VERSION := 3
const RULES := "coop-1"
const PORT := 24560
const DISCOVERY_PORT := 24561
const MAX_PACKET := 64 * 1024
const MAX_INPUT_PACKET := 1200
const MAX_BASELINE := 2 * 1024 * 1024
const CHUNK := 16 * 1024
const CHANNELS := 4
const MAX_DEPTH := 24
const INPUT_WINDOW := 12


static func encode(value: Dictionary) -> PackedByteArray:
	return JSON.stringify(value).to_utf8_buffer()


static func encode_input(data: Dictionary) -> PackedByteArray:
	var packet := encode(data)
	if packet.size() <= MAX_INPUT_PACKET: return packet
	var frames: Variant = data.get("frames")
	if not frames is Array or frames.size() > INPUT_WINDOW: return PackedByteArray()
	# Analog movement and look values can make the full JSON window exceed the datagram budget.
	# Keep a contiguous suffix anchored at seq so the host can acknowledge the newest sample.
	var payload := data.duplicate()
	for start in range(1, frames.size()):
		payload["frames"] = frames.slice(start)
		packet = encode(payload)
		if packet.size() <= MAX_INPUT_PACKET: return packet
	return PackedByteArray()


static func decode(bytes: PackedByteArray, limit: int = MAX_PACKET) -> Dictionary:
	if bytes.size() == 0 or bytes.size() > limit: return {}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not safe(parsed): return {}
	return parsed


static func safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL: return true
		TYPE_INT, TYPE_FLOAT: return is_finite(float(value))
		TYPE_STRING: return (value as String).length() <= MAX_BASELINE
		TYPE_ARRAY:
			if value.size() > 16384: return false
			for entry: Variant in value:
				if not safe(entry, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 4096: return false
			for key: Variant in value:
				if not (key is String or key is int) or str(key).length() > 256 or not safe(value[key], depth + 1): return false
			return true
	return false


## A packet repeats up to INPUT_WINDOW physics samples. Sequence numbers are implicit
## in the ordered window, and the sender never supplies a simulation duration.
static func inputs(data: Dictionary) -> Array:
	var frames: Variant = data.get("frames")
	if not frames is Array or frames.is_empty() or frames.size() > INPUT_WINDOW: return []
	if not SaveSchema.is_integer(data.get("seq"), frames.size() - 1, 2147483647) or not SaveSchema.is_integer(data.get("scene"), 0, 2147483647): return []
	var result := []
	var sequence: int = int(data["seq"]) - frames.size() + 1
	for frame: Variant in frames:
		if not frame is Array or frame.size() != 7: return []
		var sample := {"x": frame[0], "y": frame[1], "yaw": frame[2], "pitch": frame[3], "run": frame[4], "vault": frame[5], "steer": frame[6], "seq": sequence, "scene": data["scene"]}
		if not input_valid(sample): return []
		result.append(sample)
		sequence += 1
	return result


static func input_valid(data: Dictionary) -> bool:
	if not data.get("steer", {}) is Dictionary: return false
	for key: String in data.get("steer", {}):
		if key not in ["l", "r", "u", "d"] or not SaveSchema.number_in(data["steer"][key], 0, 1): return false
	return SaveSchema.is_integer(data.get("seq"), 0, 2147483647) and SaveSchema.is_integer(data.get("scene"), 0, 2147483647) and SaveSchema.number_in(data.get("x"), -1, 1) and SaveSchema.number_in(data.get("y"), -1, 1) and SaveSchema.number_in(data.get("yaw"), -PI, PI) and SaveSchema.number_in(data.get("pitch"), -1.4, 1.4) and data.get("run") is bool and data.get("vault", false) is bool


static func address(text: String) -> Dictionary:
	var parts := text.strip_edges().split(":")
	if parts.size() > 2 or not parts[0].is_valid_ip_address() or parts[0].contains(":"): return {}
	var port := PORT
	if parts.size() == 2:
		if not parts[1].is_valid_int(): return {}
		port = int(parts[1])
	if port < 1024 or port > 65535: return {}
	return {"ip": parts[0], "port": port}


static func token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()


static func patch(previous: Dictionary, current: Dictionary) -> Dictionary:
	var changed := {}
	for key: String in current:
		if not previous.has(key) or current[key] != previous[key]: changed[key] = current[key]
	return changed
