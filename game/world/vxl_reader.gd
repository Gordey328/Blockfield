class_name VXLReader
extends RefCounted
## Ace of Spades/OpenSpades 512 x 512 x 64 span decoder.
## Source (x, y, z-down) maps to Godot (x, 63-z, y).
## Colors are 0x01RRGGBB, with 0 reserved for air.

const SIZE := Vector3i(512, 64, 512)
const DEFAULT_SOLID := 0x01674028

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
