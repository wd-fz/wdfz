extends "res://tests/support/test_suite.gd"
const RSCC := preload("res://addons/package_optimizer/rscc.gd")


func test_containers() -> void:
	for length in [0, 1, 4095, 4096, 4097, RSCC.BLOCK, RSCC.BLOCK + 13]:
		var raw := PackedByteArray()
		raw.resize(length)
		raw.fill(37)
		for i in range(0, length, 251): raw[i] = i % 256
		var original := RSCC.pack(raw, 4096)
		var result := RSCC.compact(original)
		check(not result.has("error") and RSCC.unpack(result.data).data == raw, "RSCC round-trip preserves every byte at size %d, including empty final blocks" % length)
		check(result.data.size() <= original.size() and result.data.decode_u32(8) <= RSCC.BLOCK, "compaction never enlarges a resource or exceeds one MiB per read buffer")
	var truncated := RSCC.pack("fixture".to_utf8_buffer())
	truncated.resize(20)
	check(RSCC.unpack(truncated).has("error"), "truncated container is rejected")
	var invalid := RSCC.pack("fixture".to_utf8_buffer())
	invalid.encode_u32(8, 0)
	check(RSCC.unpack(invalid).has("error"), "zero-size compression blocks are rejected")
	invalid = RSCC.pack("fixture".to_utf8_buffer())
	invalid.encode_u32(16, 0xffffffff)
	check(RSCC.unpack(invalid).has("error"), "out-of-bounds compressed lengths are rejected")
	invalid = RSCC.pack("fixture".to_utf8_buffer())
	invalid.encode_u32(12, RSCC.MAX_RESOURCE + 1)
	check(RSCC.unpack(invalid).has("error"), "oversized advertised allocations are rejected before decoding")


func test_native_resource() -> void:
	var node := Node3D.new()
	node.name = "PreservedRoot"
	node.position = Vector3(1.25, -2.5, 7)
	var payload := "materials, nodes, geometry, transforms, metadata;".repeat(500)
	node.set_meta("content", payload)
	var child := Node3D.new()
	child.name = "Door"
	node.add_child(child)
	child.owner = node
	child.set_meta("door_key", "classroom-door")
	var scene := PackedScene.new()
	check(scene.pack(node) == OK, "native fixture packs")
	node.free()
	var folder := _test_path.get_base_dir() + "/package"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/original.scn"
	check(ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS) == OK, "native engine writes the original RSCC resource")
	var result := RSCC.compact(FileAccess.get_file_as_bytes(path))
	check(not result.has("error"), "engine-generated compression blocks are understood")
	var output := folder + "/compact.scn"
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_buffer(result.data)
	file.close()
	var loaded := load(output) as PackedScene
	check(loaded != null, "Godot reads the compacted native scene without a custom runtime loader")
	if loaded != null:
		var restored := loaded.instantiate() as Node3D
		check(restored.name == "PreservedRoot" and restored.position == Vector3(1.25,-2.5,7) and restored.get_meta("content") == payload and restored.get_node("Door").get_meta("door_key") == "classroom-door", "native loading preserves hierarchy, transform, metadata and dynamic-door identity")
		restored.free()
