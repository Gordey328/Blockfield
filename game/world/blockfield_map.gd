class_name BlockfieldMap
extends RefCounted
## Offline map package. Header lengths are little-endian; canonical voxel cells
## are big-endian 0x01RRGGBB (air=0) in VoxelData's Y-fast Godot coordinates.
## Decoding stages an independent VoxelData; callers adopt only a successful result.

const DATA = preload("res://world/voxel_data.gd")
const MAGIC: String = "BFM1"
const HEADER_BYTES: int = 16
const MAX_METADATA_BYTES: int = 1024 * 1024
const MAX_CELL_BYTES: int = 64 * 1024 * 1024
const MAX_FILE_BYTES: int = HEADER_BYTES + MAX_METADATA_BYTES + MAX_CELL_BYTES
const PLAYER_HALF_WIDTH: float = 0.45
const PLAYER_HEIGHT: float = 2.7
const CONTACT_EPSILON: float = 0.0001

static func _failure(message: String, error: Error = ERR_FILE_CORRUPT) -> Dictionary:
	return {"error":error, "message":message, "data":null, "metadata":{}}

static func load(path: String, match_epoch: int = 1) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Cannot open map package", FileAccess.get_open_error())
	var length: int = file.get_length()
	if length < HEADER_BYTES or length > MAX_FILE_BYTES:
		file.close()
		return _failure("Map package size is outside the supported limit")
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return _failure("Map package read was truncated")
	return load_bytes(bytes, match_epoch)

static func load_bytes(bytes: PackedByteArray, match_epoch: int = 1) -> Dictionary:
	if match_epoch < 1 or match_epoch > DATA.MAX_UINT32:
		return _failure("Map epoch must be a positive uint32", ERR_INVALID_PARAMETER)
	if bytes.size() < HEADER_BYTES or bytes.size() > MAX_FILE_BYTES:
		return _failure("Map package size is outside the supported limit")
	if bytes.slice(0, 4) != MAGIC.to_utf8_buffer():
		return _failure("Unsupported map package signature")
	var metadata_length: int = bytes.decode_u32(4)
	var raw_length: int = bytes.decode_u32(8)
	var compressed_length: int = bytes.decode_u32(12)
	if metadata_length < 1 or metadata_length > MAX_METADATA_BYTES:
		return _failure("Map metadata size is outside the supported limit")
	if raw_length < 4 or raw_length > MAX_CELL_BYTES or raw_length % 4 != 0:
		return _failure("Map cell size is outside the supported limit")
	if compressed_length < 6 or compressed_length > MAX_CELL_BYTES:
		return _failure("Compressed map size is outside the supported limit")
	if HEADER_BYTES + metadata_length + compressed_length != bytes.size():
		return _failure("Map package lengths do not match its framing")
	var metadata_bytes: PackedByteArray = bytes.slice(HEADER_BYTES, HEADER_BYTES + metadata_length)
	var metadata_text: String = metadata_bytes.get_string_from_utf8()
	if metadata_text.to_utf8_buffer() != metadata_bytes:
		return _failure("Map metadata must be valid UTF-8")
	var json: JSON = JSON.new()
	if json.parse(metadata_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _failure("Map metadata must be a JSON object")
	var metadata: Dictionary = json.data
	var metadata_error: String = _metadata_error(metadata)
	if not metadata_error.is_empty():
		return _failure(metadata_error)
	var size: Vector3i = _dimensions(metadata)
	if size.x * size.y * size.z * 4 != raw_length:
		return _failure("Map dimensions do not match its cell size")
	var compressed: PackedByteArray = bytes.slice(HEADER_BYTES + metadata_length)
	# Godot's DEFLATE mode uses an RFC1950 zlib wrapper, matching Python zlib.
	# Reject unsupported dictionary streams and invalid headers before allocation.
	var zlib_header: int = (compressed[0] << 8) | compressed[1]
	if (compressed[0] & 15) != 8 or (compressed[0] >> 4) > 7 \
			or zlib_header % 31 != 0 or (compressed[1] & 32) != 0:
		return _failure("Map payload must be a zlib DEFLATE stream")
	var raw: PackedByteArray = compressed.decompress(raw_length, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_length:
		return _failure("Map payload is corrupt or has an invalid decompressed size")
	var candidate: VoxelData = DATA.new()
	if candidate.load_snapshot_bytes(raw, size, match_epoch, 0) != OK:
		return _failure("Map payload contains invalid voxel colors")
	if not is_valid_spawn(candidate, _spawn(metadata)):
		return _failure("Map spawn needs clear standing space and solid support")
	return {"error":OK, "message":"", "data":candidate, "metadata":metadata}

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _finite_number(value) and float(value) >= minimum \
			and float(value) <= maximum and float(value) == floorf(float(value))

static func _metadata_error(metadata: Dictionary) -> String:
	if not _bounded_integer(metadata.get("format"), 1, 1):
		return "Unsupported map metadata format"
	var size: Variant = metadata.get("dimensions")
	if typeof(size) != TYPE_ARRAY or size.size() != 3:
		return "Map dimensions must contain width, height and depth"
	if not _bounded_integer(size[0], 1, 512) or not _bounded_integer(size[1], 1, 64) \
			or not _bounded_integer(size[2], 1, 512):
		return "Map dimensions are outside the supported limit"
	var title: Variant = metadata.get("title")
	if typeof(title) != TYPE_STRING or title.strip_edges().is_empty() or title.length() > 512:
		return "Map title must be a nonempty string of at most 512 characters"
	var point: Variant = metadata.get("spawn")
	if typeof(point) != TYPE_ARRAY or point.size() != 3:
		return "Map spawn must contain three feet coordinates"
	for axis: int in range(3):
		if not _finite_number(point[axis]):
			return "Map spawn coordinates must be finite numbers"
	return ""

static func _dimensions(metadata: Dictionary) -> Vector3i:
	var size: Array = metadata.dimensions
	return Vector3i(int(size[0]), int(size[1]), int(size[2]))

static func _spawn(metadata: Dictionary) -> Vector3:
	var point: Array = metadata.spawn
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func is_valid_spawn(data: VoxelData, feet: Vector3) -> bool:
	if data == null or not feet.is_finite() or not DATA.valid_dimensions(data.dimensions) \
			or data.blocks.size() != data.dimensions.x * data.dimensions.y * data.dimensions.z:
		return false
	var lower: Vector3 = feet - Vector3(PLAYER_HALF_WIDTH, 0.0, PLAYER_HALF_WIDTH)
	var upper: Vector3 = feet + Vector3(PLAYER_HALF_WIDTH, PLAYER_HEIGHT, PLAYER_HALF_WIDTH)
	if lower.x < 0.0 or lower.z < 0.0 or lower.y < 1.0 \
			or upper.x > data.dimensions.x or upper.z > data.dimensions.z or upper.y > data.dimensions.y:
		return false
	var minimum: Vector3i = Vector3i((lower + Vector3.ONE * CONTACT_EPSILON).floor())
	var maximum: Vector3i = Vector3i((upper - Vector3.ONE * CONTACT_EPSILON).floor())
	for z: int in range(minimum.z, maximum.z + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			for y: int in range(minimum.y, maximum.y + 1):
				if data.get_block(Vector3i(x, y, z)) != 0:
					return false
	# The same footprint must remain supported; checking only the center can
	# accept a spawn straddling a hole. A 0.05 probe accepts the game's 0.01 lift.
	for dx: float in [-PLAYER_HALF_WIDTH + CONTACT_EPSILON, PLAYER_HALF_WIDTH - CONTACT_EPSILON]:
		for dz: float in [-PLAYER_HALF_WIDTH + CONTACT_EPSILON, PLAYER_HALF_WIDTH - CONTACT_EPSILON]:
			if data.get_block(Vector3i((feet + Vector3(dx, -0.05, dz)).floor())) == 0:
				return false
	return true

static func encode(data: VoxelData, metadata: Dictionary) -> PackedByteArray:
	if data == null or not DATA.valid_dimensions(data.dimensions):
		return PackedByteArray()
	var document: Dictionary = metadata.duplicate(true)
	document.format = 1
	document.dimensions = [data.dimensions.x, data.dimensions.y, data.dimensions.z]
	if not _metadata_error(document).is_empty() or not is_valid_spawn(data, _spawn(document)):
		return PackedByteArray()
	var metadata_bytes: PackedByteArray = JSON.stringify(document).to_utf8_buffer()
	if metadata_bytes.size() < 1 or metadata_bytes.size() > MAX_METADATA_BYTES:
		return PackedByteArray()
	var raw: PackedByteArray = data.snapshot_bytes()
	if raw.is_empty() or raw.size() > MAX_CELL_BYTES:
		return PackedByteArray()
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	if compressed.is_empty() or compressed.size() > MAX_CELL_BYTES:
		return PackedByteArray()
	var output: PackedByteArray = MAGIC.to_utf8_buffer()
	output.resize(HEADER_BYTES)
	output.encode_u32(4, metadata_bytes.size())
	output.encode_u32(8, raw.size())
	output.encode_u32(12, compressed.size())
	output.append_array(metadata_bytes)
	output.append_array(compressed)
	return output
