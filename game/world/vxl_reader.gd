class_name VXLReader
extends RefCounted
## Ace of Spades/OpenSpades 512 x 512 x 64 span decoder.
## Source (x, y, z-down) maps to Godot (x, 63-z, y).
## Colors are 0x01RRGGBB, with 0 reserved for air.

const SIZE := Vector3i(512, 64, 512)
const DEFAULT_SOLID := 0x01674028

## Jobs retain one private input version. A complete column is indivisible; the
## elapsed budget is checked between columns, never inside a VXL span.
static func begin_decode(bytes: PackedByteArray) -> DecodeJob:
	return DecodeJob.new(bytes)

static func begin_encode(data: RefCounted) -> EncodeJob:
	return EncodeJob.new(data)

class DecodeJob extends RefCounted:
	const TOTAL_COLUMNS: int = 512 * 512
	var done: bool = false
	var error: Error = OK
	var message: String = ""
	var columns_done: int = 0
	var total_columns: int = TOTAL_COLUMNS
	var result_data: Dictionary = {}
	var setup_usec: int = 0
	var progress: float:
		get:
			return float(columns_done) / TOTAL_COLUMNS
	var _bytes: PackedByteArray = PackedByteArray()
	var _blocks: PackedInt32Array = PackedInt32Array()
	var _offset: int = 0

	func _init(bytes: PackedByteArray) -> void:
		var started: int = Time.get_ticks_usec()
		_bytes = bytes.duplicate()
		_blocks.resize(512 * 64 * 512)
		setup_usec = Time.get_ticks_usec() - started

	func advance(max_columns: int = 1024, max_usec: int = 2000) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var processed: int = 0
		while not done and processed < maxi(0, max_columns) and max_usec > 0:
			if not _decode_column():
				break
			columns_done += 1
			processed += 1
			if columns_done == TOTAL_COLUMNS:
				result_data = {"error": OK, "blocks": _blocks, "size": VXLReader.SIZE, "consumed": _offset}
				done = true
				_bytes = PackedByteArray()
				_blocks = PackedInt32Array()
			if Time.get_ticks_usec() - started >= max_usec:
				break
		return {"processed_columns": processed, "elapsed_usec": Time.get_ticks_usec() - started,
			"columns_done": columns_done, "total_columns": TOTAL_COLUMNS, "done": done,
			"error": error, "progress": progress, "setup_usec": setup_usec,
			"retained_input_bytes": _bytes.size(), "retained_work_bytes": _blocks.size() * 4}

	func cancel() -> void:
		if done:
			return
		_fail(ERR_SKIP, "VXL decode cancelled", _offset)

	func _fail(value: Error, reason: String, at_offset: int) -> void:
		error = value
		message = reason
		done = true
		result_data = {"error": value, "message": reason, "offset": at_offset}
		_bytes = PackedByteArray()
		_blocks = PackedInt32Array()

	func _decode_column() -> bool:
		var last_air: int = 0
		var base: int = columns_done * 64
		while true:
			if _offset + 4 > _bytes.size():
				_fail(ERR_FILE_CORRUPT, "Truncated VXL span header", _offset)
				return false
			var span_words: int = _bytes[_offset]
			var top_start: int = _bytes[_offset + 1]
			var top_end: int = _bytes[_offset + 2]
			var air_start: int = _bytes[_offset + 3]
			if top_start > 63 or top_end > 63 or top_end < top_start - 1 or top_start < last_air or air_start > top_start:
				_fail(ERR_FILE_CORRUPT, "Invalid VXL span bounds", _offset)
				return false
			var top_count: int = top_end - top_start + 1
			var words: int = top_count + 1 if span_words == 0 else span_words
			var next_offset: int = _offset + words * 4
			if words < top_count + 1 or next_offset > _bytes.size():
				_fail(ERR_FILE_CORRUPT, "Truncated VXL color data", _offset)
				return false
			var bottom_count: int = words - top_count - 1
			var solid_end: int = 64
			if span_words != 0:
				if next_offset + 4 > _bytes.size():
					_fail(ERR_FILE_CORRUPT, "Missing VXL following span", next_offset)
					return false
				solid_end = _bytes[next_offset + 3]
				if solid_end <= top_end or solid_end > 63 or solid_end - bottom_count < top_end + 1:
					_fail(ERR_FILE_CORRUPT, "Invalid VXL lower surface", _offset)
					return false
			for source_z: int in range(top_start, solid_end):
				_blocks[base + 63 - source_z] = VXLReader.DEFAULT_SOLID
			var color_offset: int = _offset + 4
			for source_z: int in range(top_start, top_end + 1):
				_blocks[base + 63 - source_z] = VXLReader._read_color(_bytes, color_offset)
				color_offset += 4
			for source_z: int in range(solid_end - bottom_count, solid_end):
				_blocks[base + 63 - source_z] = VXLReader._read_color(_bytes, color_offset)
				color_offset += 4
			if top_end == 62 or solid_end == 63:
				_blocks[base] = _blocks[base + 1]
			_offset = next_offset
			if span_words == 0:
				return true
			last_air = solid_end
		return false

class EncodeJob extends RefCounted:
	const TOTAL_COLUMNS: int = 512 * 512
	var done: bool = false
	var error: Error = OK
	var message: String = ""
	var columns_done: int = 0
	var total_columns: int = TOTAL_COLUMNS
	var result_bytes: PackedByteArray = PackedByteArray()
	var setup_usec: int = 0
	var snapshot_bytes: int = 0
	var progress: float:
		get:
			return float(columns_done) / TOTAL_COLUMNS
	var _snapshot: RefCounted
	var _blocks: PackedInt32Array = PackedInt32Array()
	var _size: Vector3i = Vector3i.ZERO
	var _native: bool = false
	var _output: PackedByteArray = PackedByteArray()
	var _padding_column: PackedByteArray = PackedByteArray()

	func _init(data: RefCounted) -> void:
		var started: int = Time.get_ticks_usec()
		if data == null or not data.has_method("frozen_copy"):
			_fail(ERR_INVALID_PARAMETER, "VXL encode requires map data")
			return
		var size_value: Variant = data.get("dimensions")
		var blocks_value: Variant = data.get("blocks")
		if typeof(size_value) != TYPE_VECTOR3I or typeof(blocks_value) != TYPE_PACKED_INT32_ARRAY:
			_fail(ERR_INVALID_DATA, "Invalid VXL map data")
			return
		_size = size_value
		if _size.x <= 0 or _size.y <= 0 or _size.z <= 0 or _size.x > 512 or _size.y > 64 or _size.z > 512 or blocks_value.size() != _size.x * _size.y * _size.z:
			_fail(ERR_INVALID_DATA, "Invalid VXL map dimensions")
			return
		# Captured once, before any yield. Live edits never alias this version.
		_snapshot = data.call("frozen_copy")
		_blocks = _snapshot.get("blocks")
		_native = _size == VXLReader.SIZE
		_padding_column = PackedByteArray([0, 62, 62, 0])
		VXLReader._write_color(_padding_column, VXLReader.DEFAULT_SOLID)
		snapshot_bytes = _blocks.size() * 4
		setup_usec = Time.get_ticks_usec() - started

	func advance(max_columns: int = 1024, max_usec: int = 2000) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var processed: int = 0
		while not done and processed < maxi(0, max_columns) and max_usec > 0:
			if not _encode_column():
				break
			columns_done += 1
			processed += 1
			if columns_done == TOTAL_COLUMNS:
				result_bytes = _output
				_output = PackedByteArray()
				done = true
				_release_snapshot()
			if Time.get_ticks_usec() - started >= max_usec:
				break
		return {"processed_columns": processed, "elapsed_usec": Time.get_ticks_usec() - started,
			"columns_done": columns_done, "total_columns": TOTAL_COLUMNS, "done": done,
			"error": error, "progress": progress, "setup_usec": setup_usec,
			"snapshot_bytes": snapshot_bytes, "retained_snapshot_bytes": _blocks.size() * 4,
			"retained_output_bytes": _output.size()}

	func cancel() -> void:
		if not done:
			_fail(ERR_SKIP, "VXL encode cancelled")

	func _release_snapshot() -> void:
		_snapshot = null
		_blocks = PackedInt32Array()

	func _fail(value: Error, reason: String) -> void:
		error = value
		message = reason
		done = true
		_release_snapshot()
		_output = PackedByteArray()
		result_bytes = PackedByteArray()

	func _color(x: int, y: int, z: int) -> int:
		# Match _native_data without allocating a second 64 MiB padded map.
		if x < _size.x and y < _size.y and z < _size.z:
			return _blocks[y + _size.y * (x + _size.x * z)]
		return VXLReader.DEFAULT_SOLID if y < 2 else 0

	func _encode_column() -> bool:
		var x: int = columns_done % 512
		var z: int = columns_done / 512
		var base: int = columns_done * 64
		if not _native and (x >= _size.x or z >= _size.z):
			# Outside the source extent, _native_data has exactly two default
			# floor layers. y=1 is a surface because y=2 is air; y=0 cannot be
			# a surface in any valid map (every neighboring real floor is solid).
			# A missing real floor is still rejected when its own column is reached,
			# discarding every previously emitted byte as the synchronous path does.
			_output.append_array(_padding_column)
			return true
		if (_blocks[base] if _native else _color(x, 0, z)) == 0:
			_fail(ERR_INVALID_DATA, "VXL column has no immutable floor")
			return false
		var solid_mask: int = 0
		var surface_mask: int = 0
		# Above a small map's source height the virtual native column is air.
		# A one-layer source retains the default y=1 padding, hence max(height,2).
		var first_depth: int = 0 if _native else 64 - maxi(_size.y, 2)
		for source_z: int in range(first_depth, 64):
			var y: int = 63 - source_z
			var index: int = base + y
			var color: int = _blocks[index] if _native else _color(x, y, z)
			if color == 0:
				continue
			var bit: int = 1 << source_z
			solid_mask |= bit
			var surface: bool
			if _native:
				surface = source_z == 0 or (x > 0 and _blocks[index - 64] == 0) or (x < 511 and _blocks[index + 64] == 0) or (z > 0 and _blocks[index - 32768] == 0) or (z < 511 and _blocks[index + 32768] == 0) or (source_z > 0 and _blocks[index + 1] == 0) or (source_z < 63 and _blocks[index - 1] == 0)
			else:
				surface = source_z == 0 or (x > 0 and _color(x - 1, y, z) == 0) or (x < 511 and _color(x + 1, y, z) == 0) or (z > 0 and _color(x, y, z - 1) == 0) or (z < 511 and _color(x, y, z + 1) == 0) or (source_z > 0 and _color(x, y + 1, z) == 0) or (source_z < 63 and _color(x, y - 1, z) == 0)
			if surface:
				surface_mask |= bit
		var cursor: int = 0
		while cursor < 64:
			var air_start: int = cursor
			while cursor < 64 and (solid_mask & (1 << cursor)) == 0:
				cursor += 1
			var top_start: int = cursor
			while cursor < 64 and (surface_mask & (1 << cursor)) != 0:
				cursor += 1
			var top_end: int = cursor
			while cursor < 64 and (solid_mask & (1 << cursor)) != 0 and (surface_mask & (1 << cursor)) == 0:
				cursor += 1
			var bottom_start: int = cursor
			var bottom_end: int = cursor
			while bottom_end < 64 and (surface_mask & (1 << bottom_end)) != 0:
				bottom_end += 1
			if bottom_end != 64:
				cursor = bottom_end
			var color_count: int = top_end - top_start + cursor - bottom_start
			_output.append_array(PackedByteArray([0 if cursor == 64 else color_count + 1, top_start, top_end - 1, air_start]))
			for depth: int in range(top_start, top_end):
				VXLReader._write_color(_output, _blocks[base + 63 - depth] if _native else _color(x, 63 - depth, z))
			for depth: int in range(bottom_start, cursor):
				VXLReader._write_color(_output, _blocks[base + 63 - depth] if _native else _color(x, 63 - depth, z))
		return true

static func decode(bytes: PackedByteArray) -> Dictionary:
	var blocks := PackedInt32Array()
	blocks.resize(SIZE.x * SIZE.y * SIZE.z)
	var offset := 0
	for source_y in range(512):
		for source_x in range(512):
			var last_air := 0
			while true:
				if offset + 4 > bytes.size():
					return {"error": ERR_FILE_CORRUPT, "message": "Truncated VXL span header", "offset": offset}
				var span_words: int = bytes[offset]
				var top_start: int = bytes[offset + 1]
				var top_end: int = bytes[offset + 2]
				var air_start: int = bytes[offset + 3]
				# Save() can split a solid column at a horizontal surface patch.
				# The following span then has zero upper colors (end=start-1).
				if top_start > 63 or top_end > 63 or top_end < top_start - 1 or top_start < last_air or air_start > top_start:
					return {"error": ERR_FILE_CORRUPT, "message": "Invalid VXL span bounds", "offset": offset}
				var top_count := top_end - top_start + 1
				var words := top_count + 1 if span_words == 0 else span_words
				var next_offset := offset + words * 4
				if words < top_count + 1 or next_offset > bytes.size():
					return {"error": ERR_FILE_CORRUPT, "message": "Truncated VXL color data", "offset": offset}
				var bottom_count := words - top_count - 1
				var solid_end := 64
				if span_words != 0:
					if next_offset + 4 > bytes.size():
						return {"error": ERR_FILE_CORRUPT, "message": "Missing VXL following span", "offset": next_offset}
					solid_end = bytes[next_offset + 3]
					if solid_end <= top_end or solid_end > 63 or solid_end - bottom_count < top_end + 1:
						return {"error": ERR_FILE_CORRUPT, "message": "Invalid VXL lower surface", "offset": offset}
				var base := SIZE.y * (source_x + SIZE.x * source_y)
				# VXL stores colors only at surfaces, but the interior is solid too.
				for source_z in range(top_start, solid_end):
					blocks[base + 63 - source_z] = DEFAULT_SOLID
				var color_offset := offset + 4
				for source_z in range(top_start, top_end + 1):
					blocks[base + 63 - source_z] = _read_color(bytes, color_offset)
					color_offset += 4
				for source_z in range(solid_end - bottom_count, solid_end):
					blocks[base + 63 - source_z] = _read_color(bytes, color_offset)
					color_offset += 4
				# Original GameMap::Load duplicates z=62 onto the immutable floor.
				if top_end == 62 or solid_end == 63:
					blocks[base] = blocks[base + 1]
				offset = next_offset
				if span_words == 0:
					break
				last_air = solid_end
	return {"error": OK, "blocks": blocks, "size": SIZE, "consumed": offset}

static func _read_color(bytes: PackedByteArray, offset: int) -> int:
	# VXL colors are blue, green, red, unused/health in byte order.
	return 0x01000000 | (bytes[offset + 2] << 16) | (bytes[offset + 1] << 8) | bytes[offset]

static func encode(blocks: PackedInt32Array, size: Vector3i) -> PackedByteArray:
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x > SIZE.x or size.y > SIZE.y or size.z > SIZE.z or blocks.size() != size.x * size.y * size.z:
		return PackedByteArray()
	var data := _native_data(blocks, size)
	var output := PackedByteArray()
	for source_y in range(512):
		for source_x in range(512):
			var base := 64 * (source_x + 512 * source_y)
			# A valid native column always ends at a solid immutable floor.
			if data[base] == 0:
				return PackedByteArray()
			var solid_mask := 0
			var surface_mask := 0
			for source_z in range(64):
				var index := base + 63 - source_z
				if data[index] == 0:
					continue
				var bit := 1 << source_z
				solid_mask |= bit
				# Matches GameMap::IsSurface; the world edge is not an air neighbor.
				if source_z == 0 or (source_x > 0 and data[index - 64] == 0) or (source_x < 511 and data[index + 64] == 0) or (source_y > 0 and data[index - 32768] == 0) or (source_y < 511 and data[index + 32768] == 0) or (source_z > 0 and data[index + 1] == 0) or (source_z < 63 and data[index - 1] == 0):
					surface_mask |= bit
			var cursor := 0
			while cursor < 64:
				var air_start := cursor
				while cursor < 64 and (solid_mask & (1 << cursor)) == 0:
					cursor += 1
				var top_start := cursor
				while cursor < 64 and (surface_mask & (1 << cursor)) != 0:
					cursor += 1
				var top_end := cursor
				while cursor < 64 and (solid_mask & (1 << cursor)) != 0 and (surface_mask & (1 << cursor)) == 0:
					cursor += 1
				var bottom_start := cursor
				var bottom_end := cursor
				while bottom_end < 64 and (surface_mask & (1 << bottom_end)) != 0:
					bottom_end += 1
				# Native terminal spans omit the hidden floor's lower colors.
				if bottom_end != 64:
					cursor = bottom_end
				var color_count := top_end - top_start + cursor - bottom_start
				output.append_array(PackedByteArray([0 if cursor == 64 else color_count + 1, top_start, top_end - 1, air_start]))
				for source_z in range(top_start, top_end):
					_write_color(output, data[base + 63 - source_z])
				for source_z in range(bottom_start, cursor):
					_write_color(output, data[base + 63 - source_z])
	return output

static func _native_data(blocks: PackedInt32Array, size: Vector3i) -> PackedInt32Array:
	if size == SIZE:
		return blocks
	# Lab export stays at its existing origin/heights within a native map.
	var data := PackedInt32Array()
	data.resize(512 * 512 * 64)
	for z in range(512):
		for x in range(512):
			var base := 64 * (x + 512 * z)
			data[base] = DEFAULT_SOLID
			data[base + 1] = DEFAULT_SOLID
	for z in range(size.z):
		for x in range(size.x):
			var target_base := 64 * (x + 512 * z)
			var source_base := size.y * (x + size.x * z)
			for y in range(size.y):
				data[target_base + y] = blocks[source_base + y]
	return data

static func _write_color(output: PackedByteArray, packed: int) -> void:
	output.append(packed & 255)
	output.append((packed >> 8) & 255)
	output.append((packed >> 16) & 255)
	output.append(100)
