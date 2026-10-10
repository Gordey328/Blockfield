extends SceneTree
## Run with --path game --script absolute/path/tests/world/test_vxl_save.gd.
const WORLD = preload("res://world/voxel_world.gd")
const READER = preload("res://world/vxl_reader.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("VXL SAVE TEST: " + message)

func _run() -> void:
	var layered_span := PackedByteArray([3, 10, 10, 0, 7, 8, 9, 255, 10, 11, 12, 255, 0, 62, 62, 20, 1, 2, 3, 255])
	var bytes := PackedByteArray()
	bytes.resize(512 * 512 * layered_span.size())
	for column in range(512 * 512):
		for byte_index in range(layered_span.size()):
			bytes[column * layered_span.size() + byte_index] = layered_span[byte_index]
	var decoded: Dictionary = READER.decode(bytes)
	check(decoded.error == OK, "layered fixture must decode")
	var data: PackedInt32Array = decoded.blocks
	var center := 64 * (256 + 512 * 256)
	data[center + 53] = 0x01000000 # Repaint a visible surface solid black.
	data[center + 50] = 0x01040506 # Repaint and expose a previously hidden cell.
	data[center + 49] = 0
	data[center + 5] = 0x01112233 # Add a third non-contiguous span.
	var encoded: PackedByteArray = READER.encode(data, READER.SIZE)
	check(not encoded.is_empty(), "edited multi-span map must encode")
	var restored: Dictionary = READER.decode(encoded)
	check(restored.error == OK and restored.consumed == encoded.size(), "encoded multi-span data must decode fully")
	if restored.error == OK:
		var copy: PackedInt32Array = restored.blocks
		check(copy[center + 53] == 0x01000000, "solid black surface color must survive save")
		check(copy[center + 50] == 0x01040506 and copy[center + 49] == 0, "exposed interior recolor and excavated air must survive save")
		check(copy[center + 5] == 0x01112233 and copy[center + 6] == 0, "new isolated span and surrounding air must survive save")
		check(data == copy, "fixture solid geometry and all representable colors must round-trip exactly")
	check(READER.decode(encoded.slice(0, encoded.size() - 1)).error == ERR_FILE_CORRUPT, "truncated saved VXL must be rejected")
	check(READER.decode(PackedByteArray([0, 63, 61, 0, 1, 2, 3, 4])).error == ERR_FILE_CORRUPT, "invalid negative color count must be rejected")
	var world := WORLD.new()
	world.clear_world(Vector3i(16, 16, 16))
	root.add_child(world)
	world._fill_box(Vector3i.ZERO, Vector3i(16, 2, 16), 0x01665544)
	world.set_block(Vector3i(7, 2, 7), 0x01aabbcc)
	check(world.load_vxl_bytes(PackedByteArray([1, 2, 3])) == ERR_FILE_CORRUPT and world.get_block(Vector3i(7, 2, 7)) == 0x01aabbcc, "failed import must preserve edited world")
	var lab_bytes := world.encode_vxl()
	var lab: Dictionary = READER.decode(lab_bytes)
	check(lab.error == OK, "smaller lab must export as a native-sized VXL map")
	if lab.error == OK:
		var lab_data: PackedInt32Array = lab.blocks
		check(lab_data[64 * (7 + 512 * 7) + 2] == 0x01aabbcc, "lab voxel coordinates/heights and visible color must survive padding")
		check(lab_data[64 * (400 + 512 * 400) + 1] != 0 and lab_data[64 * (400 + 512 * 400) + 2] == 0, "padded map area must have only two safe floor layers")
	var save_path := "user://blockfield_world_test.vxl"
	check(world.save_vxl(save_path) == OK, "filesystem save must succeed")
	var file := FileAccess.open(save_path, FileAccess.READ)
	check(file != null and file.get_buffer(file.get_length()) == lab_bytes, "filesystem save must equal encoded map bytes")
	file = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	world.free()
	var source_path := "res://assets/openspades/maps/Title.vxl"
	check(FileAccess.file_exists(source_path), "committed original map fixture must be available without source cache")
	if FileAccess.file_exists(source_path):
		var original_file := FileAccess.open(source_path, FileAccess.READ)
		var original: Dictionary = READER.decode(original_file.get_buffer(original_file.get_length()))
		var original_bytes := READER.encode(original.blocks, original.size)
		var original_copy: Dictionary = READER.decode(original_bytes)
		check(original_copy.error == OK, "original Title.vxl must decode after native save")
		if original_copy.error == OK:
			_verify_native_roundtrip(original.blocks, original_copy.blocks)
	print("VXL SAVE TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _verify_native_roundtrip(before: PackedInt32Array, after: PackedInt32Array) -> void:
	var geometry_errors := 0
	var surface_errors := 0
	var surface_count := 0
	for z in range(512):
		for x in range(512):
			var base := 64 * (x + 512 * z)
			for y in range(64):
				var index := base + y
				if (before[index] == 0) != (after[index] == 0):
					geometry_errors += 1
				if before[index] == 0:
					continue
				var surface := y == 63 or (x > 0 and before[index - 64] == 0) or (x < 511 and before[index + 64] == 0) or (z > 0 and before[index - 32768] == 0) or (z < 511 and before[index + 32768] == 0) or (y < 63 and before[index + 1] == 0) or (y > 0 and before[index - 1] == 0)
				if surface:
					surface_count += 1
					if before[index] != after[index]:
						surface_errors += 1
	check(geometry_errors == 0, "original Title.vxl occupancy must round-trip at every cell (%d mismatches)" % geometry_errors)
	check(surface_count > 250000 and surface_errors == 0, "all native surface colors must round-trip (%d cells, %d mismatches)" % [surface_count, surface_errors])
