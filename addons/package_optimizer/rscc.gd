@tool
extends RefCounted
## Godot 4.6 FileAccessCompressed container. Only the block layout changes;
## the complete decompressed native resource must remain byte-identical.
## Format: godotengine/godot@4.6.3-stable core/io/file_access_compressed.cpp.
static var MAGIC := PackedByteArray([82, 83, 67, 67])
static var EMPTY_ZSTD := PackedByteArray([40, 181, 47, 253, 32, 0, 1, 0, 0])
const BLOCK := 1024 * 1024
const MAX_RESOURCE := 512 * 1024 * 1024


static func unpack(data: PackedByteArray) -> Dictionary:
	if data.size() < 24 or data.slice(0, 4) != MAGIC or data.slice(data.size() - 4) != MAGIC:
		return {"error": "Invalid RSCC header/trailer"}
	var mode := data.decode_u32(4)
	var block := data.decode_u32(8)
	var length := data.decode_u32(12)
	if mode != FileAccess.COMPRESSION_ZSTD or block < 1 or block > MAX_RESOURCE or length > MAX_RESOURCE:
		return {"error": "Unsupported RSCC parameters"}
	var count := length / block + 1
	var offset := 16 + count * 4
	if offset > data.size() - 4:
		return {"error": "Truncated block table"}
	var raw := PackedByteArray()
	for i in count:
		var size := data.decode_u32(16 + i * 4)
		if size < 1 or size > data.size() - 4 - offset:
			return {"error": "Truncated compressed block"}
		var chunk := data.slice(offset, offset + size)
		offset += size
		var expected := mini(block, length - i * block)
		if expected == 0:
			if chunk != EMPTY_ZSTD:
				return {"error": "Invalid empty final block"}
			continue
		var decoded := chunk.decompress(expected, FileAccess.COMPRESSION_ZSTD)
		if decoded.size() != expected:
			return {"error": "Invalid decompressed block length"}
		raw.append_array(decoded)
	if offset != data.size() - 4 or raw.size() != length:
		return {"error": "Invalid resource length"}
	return {"data": raw, "block": block}


static func pack(raw: PackedByteArray, block: int = BLOCK) -> PackedByteArray:
	if block < 1 or block > BLOCK or raw.size() > MAX_RESOURCE: return PackedByteArray()
	# Small resources do not need a one-megabyte decompression buffer.
	block = mini(block, maxi(1, raw.size() + 1))
	var count := raw.size() / block + 1
	var result := PackedByteArray()
	result.resize(16 + count * 4)
	for i in 4: result[i] = MAGIC[i]
	result.encode_u32(4, FileAccess.COMPRESSION_ZSTD)
	result.encode_u32(8, block)
	result.encode_u32(12, raw.size())
	for i in count:
		var chunk := raw.slice(i * block, mini(raw.size(), (i + 1) * block))
		var encoded := EMPTY_ZSTD if chunk.is_empty() else chunk.compress(FileAccess.COMPRESSION_ZSTD)
		result.encode_u32(16 + i * 4, encoded.size())
		result.append_array(encoded)
	result.append_array(MAGIC)
	return result


static func compact(original: PackedByteArray) -> Dictionary:
	var unpacked := unpack(original)
	if unpacked.has("error"): return unpacked
	var raw: PackedByteArray = unpacked.data
	var encoded := pack(raw)
	var verified := unpack(encoded)
	if verified.has("error") or verified.data != raw:
		return {"error": "Lossless verification failed"}
	return {"data": encoded if encoded.size() < original.size() else original, "raw_bytes": raw.size()}
