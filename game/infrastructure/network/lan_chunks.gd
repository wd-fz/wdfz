class_name LanChunks
extends RefCounted
## One bounded in-flight snapshot; atomic replacement only after hash/size validation.
var key := ""
var count := 0
var raw_size := 0
var digest := ""
var pieces: Dictionary = {}
var received := 0
var started := 0.0


static func split(data: Dictionary, id: String) -> Array:
	var raw := LanProtocol.encode(data)
	if raw.size() > LanProtocol.MAX_BASELINE: return []
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var result: Array = []
	var total := int(ceil(float(packed.size()) / LanProtocol.CHUNK))
	var hash_value := raw.hex_encode().sha256_text()
	for i in total:
		result.append({"key": id, "index": i, "count": total, "raw": raw.size(), "hash": hash_value,
			"bytes": Marshalls.raw_to_base64(packed.slice(i * LanProtocol.CHUNK, mini((i + 1) * LanProtocol.CHUNK, packed.size())))})
	return result


func accept(data: Dictionary, now: float) -> Dictionary:
	if not data.get("key") is String or not data.get("hash") is String or not data.get("bytes") is String: return {}
	if not SaveSchema.is_integer(data.get("count"), 1, 128) or not SaveSchema.is_integer(data.get("raw"), 1, LanProtocol.MAX_BASELINE): return {}
	if not SaveSchema.is_integer(data.get("index"), 0, int(data["count"]) - 1) or data["bytes"].length() > LanProtocol.CHUNK * 2: return {}
	if key != data["key"] or now - started > 15.0:
		clear()
		key = String(data["key"])
		count = int(data["count"])
		raw_size = int(data["raw"])
		digest = String(data["hash"])
		started = now
	if count != int(data["count"]) or raw_size != int(data["raw"]) or digest != data["hash"]: return {}
	var index := int(data["index"])
	var bytes := Marshalls.base64_to_raw(data["bytes"])
	if bytes.size() > LanProtocol.CHUNK or bytes.is_empty(): return {}
	if not pieces.has(index):
		received += bytes.size()
		pieces[index] = bytes
	if received > LanProtocol.MAX_BASELINE:
		clear()
		return {}
	if pieces.size() != count: return {}
	var packed := PackedByteArray()
	for i in count: packed.append_array(pieces[i])
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size or raw.hex_encode().sha256_text() != digest:
		clear()
		return {}
	var result := LanProtocol.decode(raw, LanProtocol.MAX_BASELINE)
	clear()
	return result


func clear() -> void:
	key = ""
	pieces.clear()
	received = 0
