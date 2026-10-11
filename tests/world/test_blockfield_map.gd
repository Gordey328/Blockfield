extends SceneTree
## Run with --path game --script absolute/path/tests/world/test_blockfield_map.gd.
## Optional arguments after -- are real .bfm packages to validate as well.

const MAP = preload("res://world/blockfield_map.gd")
const DATA = preload("res://world/voxel_data.gd")
const PYTHON_ZLIB_HEX: String = "789c6364606060cccfcf67c0014072a3f2402ca8643c98dd372a3f2a3f2a3f2a3f2a3f2a4f8a3c005eb8a61b"
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("BLOCKFIELD MAP TEST: " + message)

func fixture() -> VoxelData:
	var data: VoxelData = DATA.new()
	check(data.clear(Vector3i(8, 8, 8), 7) == OK, "fixture allocation")
	data.seed_box(Vector3i.ZERO, Vector3i(8, 2, 8), 0x016f6f6f)
	data.blocks[0] = 0x01000000
	data.blocks[data.index(Vector3i(1, 2, 1))] = 0x01112233
	return data

func metadata() -> Dictionary:
	return {"format":1, "dimensions":[8, 8, 8], "title":"Python fixture — карта",
			"spawn":[3.5, 2.01, 3.5], "provenance":{"source":"fixture.blend"},
			"gameplay":{"mode":"exploration"}}

func frame(document: Variant, raw: PackedByteArray, payload: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var text: PackedByteArray = JSON.stringify(document).to_utf8_buffer()
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE) if payload.is_empty() else payload
	return frame_text(text, raw.size(), compressed)

func frame_text(text: PackedByteArray, raw_size: int, compressed: PackedByteArray) -> PackedByteArray:
	var output: PackedByteArray = MAP.MAGIC.to_utf8_buffer()
	output.resize(MAP.HEADER_BYTES)
	output.encode_u32(4, text.size())
	output.encode_u32(8, raw_size)
	output.encode_u32(12, compressed.size())
	output.append_array(text)
	output.append_array(compressed)
	return output

func reject(bytes: PackedByteArray, label: String, expected_zlib_error: bool = false) -> void:
	# Native zlib reports malformed streams on stderr. Only expected corruption
	# fixtures suppress that diagnostic; assertion errors remain visible.
	var previous: bool = Engine.print_error_messages
	if expected_zlib_error:
		Engine.print_error_messages = false
	var result: Dictionary = MAP.load_bytes(bytes)
	Engine.print_error_messages = previous
	check(result.error != OK and result.data == null and result.metadata.is_empty()
			and not result.message.is_empty(), label)

func success_checks(data: VoxelData, raw: PackedByteArray) -> void:
	var document: Dictionary = metadata()
	var json_document: Dictionary = JSON.parse_string(JSON.stringify(document))
	var python: PackedByteArray = frame(document, raw, PYTHON_ZLIB_HEX.hex_decode())
	var decoded: Dictionary = MAP.load_bytes(python, 23)
	check(decoded.error == OK, "Python standard-library zlib payload decodes")
	if decoded.error != OK:
		return
	var copy: VoxelData = decoded.data
	check(copy.dimensions == Vector3i(8, 8, 8) and copy.blocks == data.blocks, "all cells preserve Y-fast positions and complete RGB")
	check(copy.get_block(Vector3i.ZERO) == 0x01000000, "solid black survives canonical package")
	check(copy.get_block(Vector3i(1, 2, 1)) == 0x01112233
			and copy.get_block(Vector3i(1, 3, 1)) == 0, "colored cell and adjacent air survive")
	check(copy.epoch == 23 and copy.map_sequence == 0 and copy.last_tick == 0
			and copy.get_journal_stats().transactions == 0, "requested authority epoch and clean journal")
	check(decoded.metadata == json_document and decoded.metadata.provenance.source == "fixture.blend", "UTF-8 metadata, spawn and provenance survive")
	var encoded: PackedByteArray = MAP.encode(copy, document)
	check(not encoded.is_empty(), "valid compact map encodes")
	var restored: Dictionary = MAP.load_bytes(encoded, 31)
	check(restored.error == OK and restored.data.snapshot_bytes() == raw
			and restored.metadata == json_document and restored.data.epoch == 31, "full encode/decode roundtrip")
	check(copy.set_block(Vector3i(6, 2, 6), 0x01ffffff).ok
			and data.snapshot_bytes() == raw, "loaded candidate never aliases source cells")
	check(document == metadata(), "encoder never mutates caller metadata")
	var inferred: Dictionary = {"title":"Minimal fixture", "spawn":[3.5, 2.01, 3.5]}
	var inferred_package: Dictionary = MAP.load_bytes(MAP.encode(data, inferred))
	check(inferred_package.error == OK and inferred_package.metadata.format == 1
			and MAP._dimensions(inferred_package.metadata) == Vector3i(8, 8, 8)
			and not inferred.has("format"), "encoder supplies format and dimensions without mutating caller")
	var invalid_epoch: Dictionary = MAP.load_bytes(python, 0)
	check(invalid_epoch.error == ERR_INVALID_PARAMETER and invalid_epoch.data == null, "zero epoch rejected")
	invalid_epoch = MAP.load_bytes(python, DATA.MAX_UINT32 + 1)
	check(invalid_epoch.error == ERR_INVALID_PARAMETER, "overflow epoch rejected")
	check(MAP.load_bytes(python, DATA.MAX_UINT32).error == OK, "maximum epoch accepted")
	var path: String = "user://blockfield_map_test.bfm"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "fixture file opens")
	if file != null:
		file.store_buffer(encoded)
		file.close()
		var from_file: Dictionary = MAP.load(path, 41)
		check(from_file.error == OK and from_file.data.snapshot_bytes() == raw
				and from_file.data.epoch == 41, "filesystem package loading")
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "fixture file removed")
	check(MAP.load("user://missing_blockfield_map_test.bfm").error != OK, "missing package rejected")

func framing_checks(raw: PackedByteArray) -> void:
	var valid: PackedByteArray = frame(metadata(), raw)
	for length: int in [0, 1, 4, 15, 16, valid.size() - 1]:
		reject(valid.slice(0, length), "truncated frame at %d bytes" % length)
	var bad: PackedByteArray = valid.duplicate()
	bad[0] = 0
	reject(bad, "wrong magic")
	bad = valid.duplicate()
	bad.append(0)
	reject(bad, "trailing bytes outside frame")
	for entry: Vector2i in [Vector2i(4, 0), Vector2i(4, MAP.MAX_METADATA_BYTES + 1),
			Vector2i(8, 0), Vector2i(8, 3), Vector2i(8, MAP.MAX_CELL_BYTES + 4),
			Vector2i(12, 0), Vector2i(12, 5), Vector2i(12, MAP.MAX_CELL_BYTES + 1)]:
		bad = valid.duplicate()
		bad.encode_u32(entry.x, entry.y)
		reject(bad, "bounded header field %s" % entry)
	for offset: int in [4, 8, 12]:
		bad = valid.duplicate()
		bad.encode_u32(offset, 0xffffffff)
		reject(bad, "unsigned oversized length at %d" % offset)
	var payload_start: int = MAP.HEADER_BYTES + valid.decode_u32(4)
	bad = valid.duplicate()
	bad[payload_start] = 0
	reject(bad, "invalid zlib header")
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	reject(frame(metadata(), raw, compressed.slice(0, compressed.size() - 1)), "truncated zlib payload", true)
	compressed[compressed.size() - 1] ^= 1
	reject(frame(metadata(), raw, compressed), "invalid zlib checksum", true)
	reject(frame(metadata(), raw, raw.slice(0, 4).compress(FileAccess.COMPRESSION_DEFLATE)), "wrong decompressed size")
	reject(frame_text("{invalid json".to_utf8_buffer(), raw.size(), raw.compress(FileAccess.COMPRESSION_DEFLATE)), "malformed JSON")
	reject(frame([], raw), "metadata must be an object")
	var utf8: PackedByteArray = JSON.stringify(metadata()).to_utf8_buffer()
	utf8[utf8.size() - 2] = 255
	reject(frame_text(utf8, raw.size(), raw.compress(FileAccess.COMPRESSION_DEFLATE)), "invalid metadata UTF-8")

func metadata_checks(raw: PackedByteArray) -> void:
	var variants: Array[Dictionary] = [
		{"format":0}, {"format":2}, {"format":true}, {"format":1.5},
		{"dimensions":null}, {"dimensions":[8, 8]}, {"dimensions":[0, 8, 8]},
		{"dimensions":[513, 8, 8]}, {"dimensions":[8, 65, 8]}, {"dimensions":[8, 8, 513]},
		{"dimensions":[8.5, 8, 8]}, {"dimensions":[true, 8, 8]}, {"dimensions":[8, 8, 7]},
		{"title":""}, {"title":"   "}, {"title":42}, {"title":"x".repeat(513)},
		{"spawn":null}, {"spawn":[3.5, 2.01]}, {"spawn":[true, 2.01, 3.5]},
		{"spawn":["3.5", 2.01, 3.5]}, {"spawn":[-1, 2.01, 3.5]},
		{"spawn":[3.5, 6, 3.5]}, {"spawn":[3.5, 3, 3.5]}, {"spawn":[3.5, 1, 3.5]}]
	for replacement: Dictionary in variants:
		var document: Dictionary = metadata()
		document.merge(replacement, true)
		reject(frame(document, raw), "invalid metadata: %s" % replacement)
	for required: String in ["format", "dimensions", "title", "spawn"]:
		var document: Dictionary = metadata()
		document.erase(required)
		reject(frame(document, raw), "missing required metadata field %s" % required)
	var integral: Dictionary = metadata()
	integral.dimensions = [8.0, 8.0, 8.0]
	check(MAP.load_bytes(frame(integral, raw)).error == OK, "exact integral JSON numbers accepted")
	for first_byte: int in [0, 2, 255]:
		var corrupt: PackedByteArray = raw.duplicate()
		corrupt[0] = first_byte
		corrupt[3] = 1
		reject(frame(metadata(), corrupt), "noncanonical packed voxel marker %d" % first_byte)

func spawn_checks(data: VoxelData) -> void:
	check(MAP.is_valid_spawn(data, Vector3(3.5, 2, 3.5)), "exact floor contact accepts clear standing spawn")
	check(MAP.is_valid_spawn(data, Vector3(3.5, 2.01, 3.5)), "source spawn clearance lift accepts solid support")
	check(not MAP.is_valid_spawn(data, Vector3(NAN, 2, 3.5))
			and not MAP.is_valid_spawn(data, Vector3(INF, 2, 3.5)), "nonfinite spawn rejected")
	check(not MAP.is_valid_spawn(data, Vector3(0.2, 2, 3.5))
			and not MAP.is_valid_spawn(data, Vector3(7.8, 2, 3.5)), "full horizontal footprint is bounded")
	var blocked: VoxelData = fixture()
	blocked.blocks[blocked.index(Vector3i(3, 4, 3))] = 0x01000000
	check(not MAP.is_valid_spawn(blocked, Vector3(3.5, 2, 3.5)), "solid black ceiling obstructs standing body")
	reject(frame(metadata(), blocked.snapshot_bytes()), "package with obstructed spawn rejected")
	var corner: VoxelData = fixture()
	corner.blocks[corner.index(Vector3i(3, 1, 3))] = 0
	check(not MAP.is_valid_spawn(corner, Vector3(4.0, 2.01, 4.0)), "unsupported corner rejected even with supported center")
	check(MAP.encode(blocked, metadata()).is_empty(), "encoder rejects unsafe spawn")
	check(MAP.encode(null, metadata()).is_empty(), "encoder rejects missing data")
	var invalid: VoxelData = fixture()
	invalid.blocks[0] = 0xffffff
	check(MAP.encode(invalid, metadata()).is_empty(), "encoder rejects invalid canonical colors")
	var oversized: Dictionary = metadata()
	oversized.provenance = {"note":"a".repeat(MAP.MAX_METADATA_BYTES)}
	check(MAP.encode(data, oversized).is_empty(), "encoder bounds metadata bytes")

func _run() -> void:
	var data: VoxelData = fixture()
	var raw: PackedByteArray = data.snapshot_bytes()
	success_checks(data, raw)
	framing_checks(raw)
	metadata_checks(raw)
	spawn_checks(data)
	check(data.snapshot_bytes() == raw and data.epoch == 7
			and data.map_sequence == 0, "all malformed loads preserve existing caller data")
	for path: String in OS.get_cmdline_user_args():
		var actual: Dictionary = MAP.load(path, 73)
		check(actual.error == OK, "real converted package %s: %s" % [path, actual.message])
		if actual.error == OK:
			var value: VoxelData = actual.data
			check(MAP.is_valid_spawn(value, MAP._spawn(actual.metadata)), "real converted package standing spawn")
			print("REAL MAP: %s dimensions=%s spawn=%s cells=%d" % [actual.metadata.title,
					value.dimensions, actual.metadata.spawn, value.blocks.size()])
	print("BLOCKFIELD MAP TEST: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)
